# 76_AHB_sd_host控制器设计15

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：进入 `SDIF` RTL，理解 SD Host 的 AHB slave 寄存器接口如何把 CPU 配置转成 DMA、command FSM、data FSM、中断和 response 寄存器的控制信号。
- 核心概念：AHB slave、`HREADYOUT=1`、`HRESP=OKAY`、写地址相位/写数据相位、`write_register_en`、`read_register_en`、寄存器 bank、`dma_en` latch、`HRDATA` read mux。
- 逻辑主线：`SDIF` 只负责寄存器读写和控制状态，不直接等待 SD 卡数据；所以它的 AHB ready 必须保持寄存器接口的单周期特性，数据慢的问题交给 DMA/FIFO。
- 最小主线：
  - 先按端口分组识别 `SDIF` 的边界。
  - 再解释为什么 `HREADYOUT` 一直为 1。
  - 然后区分 AHB 写寄存器和读寄存器的对齐方式。
  - 最后看普通寄存器、`dma_en` 特殊 latch、`HRDATA` 读 mux 和 interrupt status 拼接。

### 2. 概念地图

| 概念层级 | 信号/逻辑 | 输入来自 | 输出去向 | 关键约束 |
|---|---|---|---|---|
| AHB 接口 | `HSEL/HWRITE/HTRANS/HADDR/HWDATA/HRDATA/HREADYOUT/HRESP` | AHB bus | CPU/总线 | `SDIF` 寄存器访问不能等待 SD 数据路径 |
| 写使能 | delayed `HSEL/HWRITE/HTRANS/HADDR` | AHB 地址相位 | register bank | 写数据相位要和打一拍后的地址对齐 |
| 读使能 | current `HSEL/HWRITE/HADDR` | AHB 地址相位 | `HRDATA` mux | 读数据下一拍返回，地址不再额外打一拍 |
| 配置输出 | clock、argument、command、block、direction、timeout | register bank | clock/command/data FSM | 大部分配置写入后保持 |
| DMA 控制 | `dma_en/dma_direction/transfer_size/dma_addr` | CPU 写 DMA 寄存器 | DMA module | `dma_en` 需要硬件 clear |
| 状态输入 | response、FIFO、timeout、CRC、DMA finish | 后级模块 | status register/read mux | 硬件事件进入软件可读状态 |

### 3. 最短学习路径

1. 把 `SDIF` 定位成“寄存器 bank + AHB slave”，不要把它当成 SD 卡数据通路。
2. 写路径记一句：写寄存器用打一拍后的地址和控制，因为 `HWDATA` 晚一拍到。
3. 读路径记一句：读 mux 用当前地址相位选择，下一拍给 `HRDATA`。
4. `HREADYOUT` 保持 1 的理由是 SD 卡数据不从 `SDIF` 直接返回。

### 4. 全讲结构地图

| 阶段 | 画面/代码主线 | 必须学会的判断 |
|---|---|---|
| 00:00-03:30 | 架构图与 `SDIF` 文件 | `SDIF` 是配置接口，不是 SD data path |
| 03:30-12:30 | 端口分组 | 端口就是模块职责边界 |
| 12:30-22:00 | `HREADYOUT/HRESP` | 只有寄存器读写，不应反压 AHB 总线 |
| 22:00-31:30 | AHB 控制信号采样、写读 enable | 写用 delayed，读用 current |
| 31:30-40:30 | 寄存器写入和 `dma_en` | 普通配置保持，启动类 bit 需硬件清除 |
| 40:30-46:38 | read mux 和 interrupt status 拼接 | `HRDATA` 只能集中驱动，状态位序要稳定 |

## 1. `SDIF` 是 SD Host 的软件控制面

`SDIF` 位于 AHB slave 和 SD Host 内部模块之间。CPU 通过它写配置、读状态；command FSM、data FSM、DMA 和 clock 模块通过它获得控制参数。它不直接把 SD 卡数据通过 `HRDATA` 送给 CPU。

![SD Host architecture](<./screenshots/任务076_AHB_sd_host控制器设计15/task76_docx_001.jpeg>)

打开 `SDIF` 文件后，先看端口而不是马上钻 always 块。端口分组直接给出模块边界：

![SDIF module and port list](<./screenshots/任务076_AHB_sd_host控制器设计15/task76_docx_003.jpeg>)

| 端口组 | 典型信号 | 设计含义 |
|---|---|---|
| AHB slave | `HCLK`、`HRESETn`、`HSEL`、`HWRITE`、`HTRANS`、`HADDR`、`HWDATA`、`HRDATA` | CPU 配置和读取寄存器 |
| DMA 输出 | `dma_en`、`dma_direction`、`transfer_size`、`dma_addr` | 让 DMA 知道是否启动、搬多少、往哪边搬 |
| 中断控制 | mask、clear、FIFO interrupt enable、DMA finish interrupt enable | 控制哪些事件上报 CPU |
| 状态输入 | FIFO full/empty、DMA finish、CRC error、timeout、response | 后级模块把结果回写给 `SDIF` |
| 命令/数据配置 | argument、command index、response type、block size/count、direction、width、timeout | 送给 command/data FSM |

端口分组的工程价值是快速定位问题：写寄存器失败查 AHB 和写 enable；命令不启动查 command ready；读数据链路不走查 data ready 和 DMA/FIFO；中断不来查 status、mask 和 interrupt enable。

一条 CPU 命令从 AHB 写入到硬件执行，完整链条是：

```text
CPU 写寄存器
  -> AHB 地址相位被 SDIF 识别
  -> 写数据相位更新 register bank
  -> 普通配置字段保持为 level
  -> start/ready 类字段转成后级可消费的握手
  -> command/data/DMA/clock 模块执行
  -> 状态事件回到 SDIF，被锁存进 status
  -> CPU 读 status 或收到 irq
```

`SDIF` 像控制台，不像数据传送带。控制台上的旋钮要保持，启动按钮要能被设备确认后复位，指示灯要把设备事件保持到操作员看见。

## 2. `HREADYOUT=1` 是架构边界，不是偷懒写法

本讲明确强调：`SDIF` 的 `HREADYOUT` 一直为 1，`HRESP` 一直返回 OKAY。原因是 `SDIF` 只做寄存器读写，SD 卡数据传输不经过它直接返回给 AHB master。

![HREADYOUT and HRESP code](<./screenshots/任务076_AHB_sd_host控制器设计15/task76_docx_012.jpeg>)

对比三个控制器更清楚：

| 控制器 | AHB 访问目标 | ready 行为 | 原因 |
|---|---|---|---|
| AHB SRAM | 直接读写 SRAM | 通常单周期 ready | 存储体可在固定短时序内返回 |
| AHB eFlash read | AHB read 等 flash 数据 | 可能拉低 ready | read 数据必须当场返回，flash 慢 |
| SDIF | AHB 只访问寄存器 | 保持 ready | SD 数据由 DMA/FIFO 搬运，不从 `HRDATA` 直接返回 |

如果 `SDIF` 因为“SD 卡正在读数据”而拉低 `HREADYOUT`，会造成两个错误：

1. CPU 写读寄存器被无意义阻塞。
2. AHB 总线 `HREADYIN` 可能影响其他 slave 或 DMA master，反而让 DMA 无法及时搬 FIFO。

所以 `HREADYOUT=1` 的真正含义是：SD Host 把“配置面”和“数据面”分离。配置面单周期响应，数据面通过状态/中断/DMA 异步完成。

## 3. AHB 写寄存器必须用 delayed 控制信号对齐 `HWDATA`

AHB 写传输有地址相位和数据相位。地址相位给出 `HADDR/HWRITE/HTRANS`，下一拍数据相位给出 `HWDATA`。因此 `SDIF` 不能用当前拍地址直接写当前拍数据，而要把地址和控制打一拍。

![AHB control sampling](<./screenshots/任务076_AHB_sd_host控制器设计15/task76_docx_013.jpeg>)

写使能的本质条件：

```verilog
write_register_en =
    hsel_d &&
    hreadyin_d &&
    hwrite_d &&
    (htrans_d == NONSEQ || htrans_d == SEQ);
```

画面里的代码把 `HSEL/HREADYIN/HWRITE/HTRANS/HADDR` 采样后用于写寄存器，目的就是和 `HWDATA` 对齐。

![write register enable](<./screenshots/任务076_AHB_sd_host控制器设计15/task76_docx_014.jpeg>)

如果不用 delayed 地址，连续写寄存器时会出现典型错配：

```text
cycle N:   HADDR = COMMAND_ADDR
cycle N+1: HWDATA = command_data, HADDR = DMA_CTRL_ADDR
错误写法：用 N+1 的 HADDR 配 N+1 的 HWDATA
结果：command_data 被写进 DMA_CTRL_ADDR
```

这类 bug 在单次写仿真中不一定出现，连续寄存器配置时才暴露。

## 4. AHB 读寄存器不能再多打一拍地址

读路径和写路径相反：AHB read 的地址相位给出地址，slave 下一拍返回 `HRDATA`。因此读 mux 使用当前地址相位选择寄存器值即可。如果把读地址再打一拍，`HRDATA` 会比协议要求晚两拍。

![read register path](<./screenshots/任务076_AHB_sd_host控制器设计15/task76_docx_025.jpeg>)

读路径可以理解为：

```text
cycle N:   CPU 给 HADDR，HWRITE=0，HTRANS=NONSEQ/SEQ
cycle N+1: SDIF 在 HRDATA 上返回对应寄存器
```

所以：

| 路径 | 地址选择 | 原因 |
|---|---|---|
| write | delayed address | 对齐晚一拍到达的 `HWDATA` |
| read | current address | 为下一拍 `HRDATA` 准备数据 |

这个差别是 `SDIF` 代码最重要的协议点。很多初学者把读写都打一拍，或者都不打一拍，都会在连续访问时错。

## 5. 普通配置寄存器只由 AHB 写改变，`dma_en` 还要由硬件 clear

`argument`、`command index`、`block_size`、`block_count`、`direction`、`read_timeout`、`dma_addr` 这类寄存器通常是 CPU 写什么就保持什么，直到下一次 CPU 覆盖。

![register write examples](<./screenshots/任务076_AHB_sd_host控制器设计15/task76_docx_017.jpeg>)

`dma_en` 不同。它是启动请求，不应只打一拍就消失。CPU 写 1 后，硬件需要保持它，直到 DMA 逻辑通过 `clear_dma_en` 表示已经接收或完成本次请求。

![dma enable latch](<./screenshots/任务076_AHB_sd_host控制器设计15/task76_docx_018.jpeg>)

对比：

| 寄存器字段 | 行为 | 清除来源 |
|---|---|---|
| `dma_direction` | 写入后保持 | 下一次 CPU 写 |
| `transfer_size` | 写入后保持 | 下一次 CPU 写 |
| `dma_addr` | 写入后保持 | 下一次 CPU 写 |
| `dma_en` | 写 1 后 latch | DMA/控制逻辑发 `clear_dma_en` |

这类启动位如果只按普通寄存器处理，DMA 可能漏掉请求；如果永远不清，下一次传输又会误触发。

寄存器字段可以分成四类：

| 字段类型 | 例子 | 正确行为 | 错误后果 |
|---|---|---|---|
| 保持配置 | block size、direction、timeout、DMA address | CPU 写后保持到下一次覆盖 | 事务中途漂移 |
| 启动请求 | `dma_en`、command ready 类信号 | 写 1 后保持到后级确认/清除 | 脉冲太短被漏采，或永远重复启动 |
| 硬件清除 | `clear_dma_en` 后的 `dma_en` | 后级消费后撤销请求 | 新旧请求无法区分 |
| 只读状态 | response、timeout、CRC、finish | 硬件置位，CPU 读/clear | 软件看不到真实事件 |

这张表比单看寄存器名更重要，因为 RTL 写法取决于字段行为，而不是取决于字段是否在同一个 address 下。

这张 `dma_en` 图要看保持语义：它不是单拍 start 脉冲，而是被 AHB 写置位、被 `clear_dma_en` 清零的握手保持位。这样的字段像门铃旁的“待处理”灯，按下后要亮到屋里的人确认，而不是响一瞬间就消失。

## 6. command ready 的生成假设软件最后写 argument

课程里提到 `command_ready` 的产生和 argument 写入相关：软件配置命令时通常先写 command index/response/data_present 等字段，再写 argument；写完 argument 后，`SDIF` 认为本次命令参数齐备，延迟产生 command FSM ready。

![command ready generation](<./screenshots/任务076_AHB_sd_host控制器设计15/task76_docx_019.jpeg>)

这个设计隐含一个软件约束：寄存器写顺序要稳定。若软件先写 argument，再改 command index，就可能提前触发 command FSM，导致命令帧使用旧 index 或不完整配置。正式驱动必须把“最后写哪个寄存器触发事务”写进编程规范。

更稳妥的思路是单独使用 `command_enable` 作为明确启动位；但既有 RTL 如果使用 argument 写入触发 ready，笔记必须把这个隐含顺序写清。

## 7. `HRDATA` 必须由集中 read mux 驱动

所有寄存器读值最后都要进入 `HRDATA`。正确实现方式是集中一个 mux，根据地址选择返回值。不要在多个 always 块分别写 `HRDATA`，否则会形成多驱动或优先级不明。

![read mux and HRDATA](<./screenshots/任务076_AHB_sd_host控制器设计15/task76_docx_032.jpeg>)

典型 read mux：

```verilog
case (HADDR)
  CLK_REG:      HRDATA = {clock fields};
  ARG_REG:      HRDATA = argument;
  CMD_REG:      HRDATA = {response_type, data_present, command_enable, command_index};
  RESP0_REG:    HRDATA = response0;
  INT_STATUS:   HRDATA = {status bits};
  default:      HRDATA = 32'h0;
endcase
```

`INT_STATUS` 是最复杂的读值，因为它由多个模块事件拼接而来：

![interrupt status read mux](<./screenshots/任务076_AHB_sd_host控制器设计15/task76_docx_034.jpeg>)

状态位序必须和寄存器文档稳定对应。软件驱动不会知道 RTL 内部变量名，只会按 bit 号读；如果 RTL 拼接顺序和文档不一致，软件会把 CRC 错误、timeout、DMA finish 等状态解释错。

集中 read mux 的反模式是“每个寄存器块自己觉得该返回什么就写一次 `HRDATA`”。这像多个窗口同时往同一张回执上盖章：仿真里可能因为最后赋值顺序看似稳定，综合后却变成不可维护的优先级网。寄存器读口应当只有一个最终裁判。

## 工程检查清单

- `SDIF` 是否只处理寄存器读写，SD 数据是否确实通过 DMA/FIFO。
- `HREADYOUT` 是否保持 1，`HRESP` 是否返回 OKAY；若要拉低 ready，必须有寄存器访问层面的真实等待理由。
- 写寄存器是否使用 delayed `HADDR/HWRITE/HTRANS/HSEL/HREADYIN`。
- 读寄存器是否使用 current `HADDR`，没有额外打一拍导致 `HRDATA` 晚两拍。
- `dma_en` 是否能被 CPU 写 1 后保持，并由 `clear_dma_en` 清除。
- command ready 的触发寄存器是否和软件写入顺序一致。
- `HRDATA` 是否集中驱动，interrupt status 拼接位序是否和文档一致。

## 最后速记

- `SDIF` 是寄存器接口，不是 SD 数据通路。
- `HREADYOUT=1` 是因为数据慢的问题在 DMA/FIFO，不在 AHB slave read。
- AHB 写：地址控制打一拍，对齐 `HWDATA`。
- AHB 读：当前地址选 mux，下一拍出 `HRDATA`。
- `dma_en` 是启动请求，必须 latch 到硬件 clear。
- `HRDATA` read mux 要集中，尤其是 interrupt status 位序不能乱。

## 复习与自测

1. 为什么 `SDIF` 不能因为 SD 卡读数据慢就拉低 `HREADYOUT`？  
   答：`SDIF` 只负责寄存器访问，SD 数据通过 DMA/FIFO 搬运。拉低 ready 会阻塞 AHB 总线，甚至让 DMA master 无法工作。

2. AHB 写寄存器为什么要延迟地址和控制信号？  
   答：写地址相位先到，写数据 `HWDATA` 下一拍到。延迟后的地址和控制才能与对应数据对齐。

3. AHB 读路径为什么不能使用延迟后的地址？  
   答：读数据本来就在地址相位后一拍返回；再延迟地址会让 `HRDATA` 晚两拍，不符合预期时序。

4. `dma_en` 和 `dma_addr` 的保持逻辑有什么不同？  
   答：`dma_addr` 是普通配置，只由 CPU 下一次写覆盖；`dma_en` 是启动请求，CPU 写 1 后要保持到硬件 `clear_dma_en` 清除。

5. 如果软件写 argument 会触发 command ready，驱动写寄存器顺序应如何安排？  
   答：应先写 command index、response type、data_present、block 等配置，最后写 argument 或明确启动位，避免提前启动命令 FSM。

6. interrupt status 拼接位序错误会造成什么后果？  
   答：软件按文档 bit 号解释状态，位序错会把真实错误解释成别的事件，例如把 CRC 错看成 DMA finish 或 timeout。


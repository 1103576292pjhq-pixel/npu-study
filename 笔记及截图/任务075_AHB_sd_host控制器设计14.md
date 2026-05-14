# 75_AHB_sd_host控制器设计14

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：补全 SD Host 寄存器表，把软件可写的配置寄存器、硬件可写的状态寄存器、中断控制寄存器和内嵌 DMA 寄存器串成一条可执行的数据传输链路。
- 核心概念：`CLK_EN_SPEED_UP_ADDR`、`SOFTWARE_RESET_REGISTER_ADDR`、`ARGUMENT_REGISTER_ADDR`、`COMMAND_REGISTER_ADDR`、`BLOCK_SIZE_REGISTER_ADDR`、`BLOCK_COUNT_REGISTER_ADDR`、`TRANSFER_MODE_REGISTER_ADDR`、`RESPONSE0-3`、`READ_TIMEOUT_CONTROL_REGISTER_ADDR`、`INTERRUPT_STATUS_REGISTER_ADDR`、`INTERRUPT_STATUS_MASK_REGISTER_ADDR`、`INT_GEN_REG_ADDR`、`DMA_CTRL_ADDR`、`DMA_ADDR`。
- 逻辑主线：软件不是直接操纵 CMD/DAT 线，而是先写寄存器描述一笔事务；SD Host RTL 再把这些寄存器值转成命令帧、数据块边界、FIFO/DMA 搬运和中断状态。
- 最小主线：
  - 时钟和软复位寄存器决定 Host 是否能工作、是否需要停钟和高速模式。
  - `argument + command` 决定发什么 SD 命令、是否需要响应、是否带数据阶段。
  - `block_size + block_count + transfer_mode` 决定数据搬运的粒度、总量、方向和 DAT 位宽。
  - `response + timeout + interrupt status/mask/clear` 让软件能判断命令和数据事务是否成功。
  - `DMA_CTRL + DMA_ADDR` 把 SD FIFO 和 AHB 内存连接起来；这里只配置一个 AHB 地址，另一侧固定是 FIFO。

### 2. 概念地图

| 概念层级 | 寄存器/字段 | 谁写 | 谁用 | 关键判断 |
|---|---|---|---|---|
| 工作环境 | clock enable、high speed、hardware stop clock、soft reset | CPU | clock/reset/control | 没有稳定时钟和复位释放，后面的命令寄存器写了也不能安全启动 |
| 命令描述 | argument、response type、data present、command enable、command index | CPU | command FSM、command shift | `command` 寄存器是命令事务入口，不只是命令号 |
| 数据描述 | block size、block count、data direction、data width | CPU | data FSM、DMA、FIFO | 单块/多块、读/写、1-bit/4-bit 都在这里定边界 |
| 响应保存 | response0-3 | 硬件 | CPU | 普通短响应看 response0，长响应才用 response1-3 |
| 错误/完成 | response timeout、read timeout、CRC error、end command、transfer complete、DMA finish | 硬件 | CPU/interrupt | 状态必须锁存成软件能读到的 bit |
| 中断控制 | status mask、interrupt enable、interrupt clear | CPU/硬件 | interrupt output | mask 只决定是否报中断，不等于状态没发生 |
| DMA 搬运 | dma enable、direction、transfer size、dma address | CPU/硬件 | DMA master、FIFO | 一个地址加方向位替代普通 DMA 的 source/destination 双地址 |

### 3. 最短学习路径

1. 先把寄存器按功能分组：命令组、数据组、响应组、中断组、DMA 组。
2. 再看一次读卡事务：写 argument/command，等 response，等 DAT 数据，FIFO 满后 DMA 搬走，最后中断通知 CPU。
3. 最后抓住本章最容易混的点：SD Host DMA 只有一侧是 AHB 地址，FIFO 侧是固定硬件端口，所以必须用 direction 表达搬运方向。

### 4. 全讲结构地图

| 阶段 | 画面主线 | 必须学会的判断 |
|---|---|---|
| 00:00-03:40 | clock、soft reset、argument | argument 是 SD 命令帧字段，不是 Host 私有配置 |
| 03:40-08:30 | command、block size、block count、transfer mode | 命令寄存器同时启动 command FSM 和数据 FSM |
| 08:30-12:20 | response0-3、read timeout | response 是只读结果，timeout 是数据等待边界 |
| 12:20-24:30 | interrupt status、FIFO full/empty | 状态寄存器承接 command/data/DMA/FIFO 多个模块的事件 |
| 24:30-34:30 | mask、clear、DMA control | 中断控制分成状态、屏蔽、清除和产生使能 |
| 34:30-45:36 | DMA address 和普通 DMA 对比 | SD Host DMA 少一组地址，多一个方向位 |

## 1. 时钟与复位寄存器先定义 Host 能不能安全工作

SD Host 的寄存器链路从时钟和复位开始。`CLK_EN_SPEED_UP_ADDR` 里不仅有 SD clock enable，还包含 `hw_stop_clk_en` 和 `high_speed_clk_mode`。这说明 Host 时钟既要能被软件打开，也要能被硬件在 FIFO/DMA 反压场景下暂停。

![clock enable register](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_001.jpeg>)

`hw_stop_clk_en` 的意义是允许硬件在读数据路径中临时停 SD clock。读卡时数据由 DAT 线进入 FIFO，如果 DMA 没及时把 FIFO 搬空，继续给卡提供 clock 会让新数据继续进入，造成 FIFO 溢出。这个字段要和后面任务 77、78 的 `stop_clock` 逻辑连起来看：寄存器表里的 bit 最后会变成 clock 模块里的控制条件。

`SOFTWARE_RESET_REGISTER_ADDR` 提供软件软复位入口，通常用于把 SD Host 内部控制状态拉回初始状态。它不是系统级 `HRESETn` 的替代，而是让驱动在一次事务失败后能复位 Host 内部 FSM、状态寄存器或局部控制逻辑。

![software reset register](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_002.jpeg>)

工程判断：

| 场景 | 应检查的寄存器 | 失败信号 |
|---|---|---|
| 写命令后没有任何动作 | clock enable、soft reset、command enable | command FSM 不离开 idle/stop |
| 读数据一块后卡住 | hardware stop clock、DMA finish clear stop | FIFO 中有数据但 SD clock 未恢复 |
| 高速模式不稳定 | high speed mode、clock divide、卡端配置 | 响应 CRC 或数据 CRC 偶发错误 |

## 2. `argument + command` 把软件命令翻译成 SD CMD 线事务

`ARGUMENT_REGISTER_ADDR` 对应 SD 命令帧中的 32-bit argument。它的语义由 command index 决定：读块命令里可能是地址，初始化命令里可能是 OCR/RCA 相关参数。RTL 的职责是把它按位送进 command shift，而不是重新解释所有协议语义。

![argument register and command frame](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_01_argument_field_02m58s.jpg>)

`COMMAND_REGISTER_ADDR` 是本章最关键的控制寄存器。它只用低 11 bit，字段大致分为 response type、data present、command enable 和 command index。

![command register fields](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_003.jpeg>)

| 字段 | 作用 | RTL 直接影响 |
|---|---|---|
| `response_type` | 说明命令是否需要 response，以及是否为 long response | command receive FSM 的等待与接收计数 |
| `data_present` | 说明命令后是否有 DAT 数据阶段 | data FSM 是否启动 |
| `command_enable` | 表示本次命令有效 | 生成 command ready / start |
| `command_index[5:0]` | SD 命令号 | command shift 中的 index 字段 |

这里最容易犯的错是只记 `command_index`。例如 `CMD17` 不是“写 17 就够了”，还必须同时配置 argument、response type、data present、block size、transfer mode 和 DMA 参数。否则命令可能发出去了，但数据 FSM 或 DMA 不会跟上。

## 3. block size、block count、transfer mode 决定数据事务边界

`BLOCK_SIZE_REGISTER_ADDR` 给出每个数据块的大小，单位是 byte。高容量 SD 卡常见块大小是 512 Byte，但 Host 不能在 RTL 里写死全部行为，因为软件和协议流程仍需要通过寄存器描述当前事务。

![block size register](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_004.jpeg>)

`BLOCK_COUNT_REGISTER_ADDR` 给出本次要读写多少个 block。它对多块传输尤其关键：硬件只有知道总块数，才能判断什么时候传输完成，什么时候需要配合停止命令 `CMD12`。

![block count register](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_005.jpeg>)

`TRANSFER_MODE_REGISTER_ADDR` 至少包含数据方向和 DAT 位宽。

![transfer mode register](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_006.jpeg>)

| 字段 | 典型含义 | 错配后果 |
|---|---|---|
| `data_direction` | Host 读卡 / Host 写卡 | DMA 方向、FIFO 读写方向全部反掉 |
| `data_width` | 1-bit / 4-bit | 数据拼接错位或无效线被当成有效数据 |

一笔读卡事务可以按下面的硬件动作理解：

```text
CPU 写 argument 和 command
  -> command FSM 发 CMD17/CMD18
  -> command receive FSM 收 R1 response
  -> data FSM 按 block_size 等 DAT start bit 和数据
  -> FIFO 满或一块结束后触发 DMA 搬运
  -> block_count 归零或停止命令完成后置 transfer_complete
```

如果 `block_count` 没写对，单块逻辑可能能跑，多块读写会无法判断结束边界。这个问题在仿真中常被简化模型掩盖，但在真实 SD 卡上会表现为多读、少读或停止命令时机错误。

寄存器组不是“目录页”，而是一块事务参数面板。软件每写一个字段，都是给后面的 command FSM、data FSM、DMA 或 status 逻辑拨一个开关；开关组合不一致，硬件不会自动猜软件本意。

一笔 `CMD17` 单块读可以这样配置：

| 配置组 | 典型值/动作 | 驱动的硬件链路 |
|---|---|---|
| `argument` | 目标块地址或字节地址 | command frame 的 32-bit argument |
| `command` | index=17，需短响应，`data_present=1` | command FSM 发 CMD17，随后允许 data FSM |
| `block_size` | 512 Byte | data receive 的 block 内计数边界 |
| `block_count` | 1 | 单块完成后置 transfer complete |
| `transfer_mode` | read，1-bit/4-bit 按卡配置 | DAT 方向、lane 数、FIFO 写方向 |
| `DMA_ADDR` | 目标内存地址 | DMA 把 FIFO 数据写入系统内存 |
| `DMA_CTRL` | enable，FIFO->AHB，size=512 | 启动 DMA master 搬运 |

一笔 `CMD24` 单块写则方向相反：`argument` 仍描述卡侧块地址，`command` 改成 index=24，`transfer_mode` 改成 write，`DMA_CTRL` 指向 AHB->FIFO。也就是说，命令号只决定“卡端动作”，direction 和 DMA 字段决定“Host 内部数据往哪边流”。

## 4. response0-3 和 read timeout 是软件判断命令结果的依据

SD response 寄存器是只读寄存器，由硬件在命令响应接收完成后写入。普通短响应通常放在 `response0`，长响应需要 `response0-3` 一起保存。

![response registers](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_007.jpeg>)

![response1 and response2 registers](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_008.jpeg>)

短响应和长响应的差别不是“保存多几个寄存器”这么简单。长响应涉及 136-bit 接收边界，后面任务 79 会看到 command FSM 里 `need_to_receive_bit` 的 off-by-one 风险。任务 75 这里先建立寄存器视角：软件最终只能从 response 寄存器读到硬件保存后的结果。

`READ_TIMEOUT_CONTROL_REGISTER_ADDR` 给数据接收等待设置周期边界。它针对的是 DAT 线上等待读数据 start bit 或数据块的超时，不是 CMD 线上等 response 的 64-cycle timeout。

![read timeout register](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_009.jpeg>)

两个 timeout 要分清：

| 超时类型 | 发生位置 | 典型触发 |
|---|---|---|
| response timeout | CMD 线 | 命令发完后规定周期内没有 response start bit |
| read timeout | DAT 线 | 读命令响应后，等待数据块开始超过配置值 |

如果读卡失败只看到“timeout”，调试时必须先确认是哪条线超时：CMD 超时优先查命令、卡状态、时钟、CMD 线；DAT 超时优先查 block 参数、卡 busy、数据 FSM 和 DAT 线。

## 5. interrupt status 是多个硬件模块汇总给软件的事务报告

`INTERRUPT_STATUS_REGISTER_ADDR` 是只读状态寄存器，来源不是 CPU 写入，而是 SD Host 内部模块产生的事件。它把 response timeout、CRC error、FIFO 状态、data transfer complete、end command、end command response 和 DMA finish 等事件集中到一个软件可读入口。

![interrupt status register overview](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_010.jpeg>)

![interrupt status field details](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_011.jpeg>)

关键状态位可以按来源分组：

| 来源模块 | 状态 | 含义 |
|---|---|---|
| command FSM | `response_timeout`、`end_command`、`end_command_response` | 命令是否发完、响应是否收完、是否超时 |
| data FSM | `read_timeout_error`、`receive_data_crc_error`、`transfer_complete` | DAT 线读写是否正常完成 |
| write/CRC path | `send_data_crc_error` | 写数据后卡返回 CRC status fail |
| FIFO/DMA 协同 | FIFO full/empty、DMA-side FIFO status、`dma_finish_interrupt` | FIFO 需要搬运或 DMA 已搬运完成 |

FIFO full/empty 的命名尤其容易混。它不是单一 FIFO 只有一组 full/empty，而是 SD 侧和 DMA 侧都可能关心 FIFO 的空满状态。读卡时，SD 侧把 FIFO 写满后需要 DMA 搬走；写卡时，DMA 把 FIFO 写满后 SD 侧才能继续发送。笔记里必须保留这个“双端协同”视角，否则后面看 data FSM ready 会断。

状态位来源矩阵更适合这样读：

| 状态位类别 | 置位来源 | 软件看到后应查什么 |
|---|---|---|
| command done / response done | command FSM | CMD 是否发完、response 是否完整保存 |
| response timeout | command FSM wait-response 计数 | CMD 线、卡状态、clock、命令合法性 |
| read timeout | data receive 等 DAT start | DAT 线、block 参数、卡 busy、data FSM |
| receive/send CRC error | data shift / CRC path | DAT lane 顺序、CRC16、byte swap、卡返回 status |
| FIFO full/empty interrupt | FIFO 状态与方向组合 | DMA 是否及时搬运、方向是否配反 |
| DMA finish | DMA master | AHB grant、HREADY/HRESP、地址递增 |

这张矩阵的作用是把“一个 status bit”追回“哪个硬件模块说话”。如果调试只停在寄存器表，读到 timeout 也不知道该查 CMD 线还是 DAT 线。

![interrupt generate register](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_012.jpeg>)

这张图要区分四层：status 记录事件，generate/enable 决定哪些事件进入中断产生链，mask 决定是否屏蔽输出，clear 负责复用状态位。它们不是四个同义寄存器。

## 6. mask、generate enable、clear 共同决定一次中断如何产生和复用

中断不是事件线直接接 CPU。至少有三层逻辑：

| 层 | 寄存器 | 作用 |
|---|---|---|
| 状态层 | interrupt status | 记录发生过什么 |
| 屏蔽层 | interrupt mask | 决定某个状态是否允许产生中断输出 |
| 清除层 | interrupt clear | 软件处理后清状态，为下一次事件腾出空间 |

`INTERRUPT_STATUS_MASK_REGISTER_ADDR` 允许软件屏蔽不关心的中断。mask 不应阻止 status 位被置位；它只是不让该状态进一步拉起 interrupt 输出。这样软件仍可轮询状态寄存器，只是不被打断。

![interrupt mask register](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_03_interrupt_status_12m01s.jpg>)

`INT_CLEAR_ADDR` 或同类 clear 寄存器用于清除已经处理过的中断状态。中断状态如果不清，下一次同类事件到来时软件无法区分新旧；如果清得太早，又可能丢掉尚未处理的错误原因。

## 7. SD Host DMA 的特殊点是“一端固定 FIFO，一端可配置 AHB 地址”

普通 DMA 需要 source address、destination address、size、start/status/interrupt。SD Host 里的 DMA 控制寄存器嵌在 SDIF 里，因为它服务的是 SD Host 数据路径。

![DMA control register](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_013.jpeg>)

![DMA control with direction reasoning](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_014.jpeg>)

`DMA_CTRL_ADDR` 中的字段可以这样看：

| 字段 | 含义 | 作用 |
|---|---|---|
| `dma_en` | 启动或允许 DMA | 让 DMA 开始参与本次搬运 |
| `data_direction` / `dma_direction` | AHB 到 FIFO 或 FIFO 到 AHB | 替代普通 DMA 的双地址方向判断 |
| `transfer_size` | 本次搬运字节数 | 决定 DMA 搬多少数据 |

`DMA_ADDR` 只有一个地址。原因是 SD/FIFO 侧固定在 Host 内部，不是可编程地址空间；可配置的只有 AHB 系统内存侧。

![DMA address register](<./screenshots/任务075_AHB_sd_host控制器设计14/task75_docx_015.jpeg>)

对比关系如下：

| DMA 类型 | 可配地址 | 方向表达 | 适用场景 |
|---|---|---|---|
| 普通 memory-to-memory DMA | source + destination | 两个地址天然表达方向 | 内存块复制、外设到内存等通用搬运 |
| SD Host 内嵌 DMA | 一个 AHB address | direction bit 决定 FIFO 到 AHB 或 AHB 到 FIFO | SD 卡数据块和系统内存之间搬运 |

读卡时：DAT 线数据进入 SD FIFO，DMA 从 FIFO 取数据写入 `DMA_ADDR` 指向的内存。写卡时：DMA 从 `DMA_ADDR` 指向的内存读数据，写入 SD FIFO，再由 data send 逻辑发到 DAT 线。

| 方向 | AHB 地址代表 | FIFO 行为 | DMA master 事务 |
|---|---|---|---|
| 读卡 Host receive | 目的内存地址 | FIFO 被 SD receive 写入，被 DMA 读出 | AHB write，把 FIFO 数据写到内存 |
| 写卡 Host transmit | 源内存地址 | FIFO 被 DMA 写入，被 SD send 读出 | AHB read，把内存数据读入 FIFO |

所以“只有一个地址仍然足够”的根本原因是另一端不是地址空间，而是固定硬件端口。方向位就是把这一个地址解释成源或目的的钥匙。

这也是面试中常问的点：不要机械背“DMA 有源地址和目的地址”，要能解释为什么某些外设内嵌 DMA 只有一个系统地址，因为另一端是固定硬件 FIFO 或寄存器端口。

## 工程检查清单

- 写 command 之前：clock enable、soft reset、argument、response type、command index 是否已配置。
- 带数据命令：`data_present`、block size、block count、direction、DAT width 是否一致。
- 读卡失败：先区分 response timeout 和 read timeout，再看 CMD/DAT 对应链路。
- FIFO 中断：判断是 SD 侧触发还是 DMA 侧触发，不要只按 full/empty 字面理解。
- 中断调试：status、mask、clear 三个寄存器一起看；mask 掉不代表 status 不置位。
- DMA 调试：确认 `DMA_ADDR` 是 AHB 侧地址，direction 决定 FIFO 与 AHB 的搬运方向。
- 多块传输：block count 必须和 `CMD18/CMD25` 以及停止命令策略匹配。

## 最后速记

- `argument` 是命令帧字段，`command` 是命令事务控制。
- `data_present` 是 command FSM 和 data FSM 的连接开关。
- `block_size` 管一块多大，`block_count` 管本次多少块。
- response0 保存普通短响应，response0-3 才能覆盖长响应。
- response timeout 看 CMD 线，read timeout 看 DAT 线。
- interrupt status 记录事件，mask 控制上报，clear 负责复用。
- SD Host DMA 只有一个 AHB 地址，FIFO 侧是固定硬件端口。

## 复习与自测

1. 为什么 `COMMAND_REGISTER_ADDR` 不能只保存 command index？  
   答：一次命令事务还需要 response 类型、是否有数据阶段、命令使能等控制信息；只保存 index 无法决定 command FSM 是否等响应，也无法启动 data FSM。

2. `block_size` 和 `block_count` 分别解决什么问题？  
   答：`block_size` 定义块内字节边界，驱动数据块计数；`block_count` 定义本次事务的块数，驱动多块传输结束和停止命令策略。

3. response timeout 和 read timeout 的区别是什么？  
   答：response timeout 发生在 CMD 线上，表示命令响应没按时到；read timeout 发生在 DAT 线上，表示读数据块没按配置周期开始或到达。

4. mask 位为 1 后，对应 status 事件还应不应该被记录？  
   答：应该。mask 只决定是否产生中断输出，不应阻止 status 位记录事件；否则软件轮询也看不到真实状态。

5. 为什么 SD Host DMA 不需要 source address 和 destination address 两个寄存器？  
   答：因为一端固定连接 SD Host 内部 FIFO，只有 AHB 内存侧地址可配置；方向位说明是 FIFO 到 AHB，还是 AHB 到 FIFO。

6. 如果写卡时 direction 配反，会发生什么？  
   答：DMA 会按错误方向访问 AHB/FIFO，可能导致 FIFO 没被填入待发送数据，或把无效 FIFO 数据写回内存，最终表现为数据传输失败、CRC 错或 timeout。


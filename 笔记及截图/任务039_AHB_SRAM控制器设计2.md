# 任务39：AHB SRAM 控制器设计2

## 本章知识全景图

### 一眼看懂这讲在讲什么

- **本章主题**：把 AHB SRAM controller 从系统需求推进到微架构实现，重点是 SRAM 端控制信号生成和 AHB/SRAM 时序对齐。
- **核心概念**：`sramc_top`、`ahb_slave_if`、`sram_core`、`8K x 8`、`bank*_csn`、`sram_w_en`、`sram_addr_out`、AHB 地址阶段、AHB 数据阶段、write pipeline、read latency、`HREADYOUT`。
- **逻辑主线**：AHB 给的是流水线式地址阶段和数据阶段，SRAM macro 要的是同拍地址、片选、写使能和数据；控制器的真正工作，是把协议阶段转成宏端口时序。
- **最短学习路径**：先看顶层模块边界，再计算 SRAM 宏地址和 bank/byte lane，最后分别处理写路径打一拍和读路径单周期返回的时序压力。

| 概念层级 | 核心概念 | 前置知识 | 延伸应用 |
|---|---|---|---|
| 顶层边界 | `ahb_slave_if`、`sram_core` | module instance、端口连接 | controller 微架构划分 |
| 存储组织 | 8 个 `8K x 8` | 地址位宽、byte lane | bank select、容量计算 |
| SRAM 控制 | `csn`、`wen`、address、data | active low、读写方向 | 片选生成、低功耗 |
| AHB 有效访问 | `HSEL/HREADYIN/HTRANS/HWRITE/HSIZE` | AHB 地址/数据阶段 | write/read enable |
| 写路径 | 地址/control 打一拍 | `HWDATA` 数据阶段 | pipeline register |
| 读路径 | SRAM access time | `HRDATA` 数据阶段 | 单周期读、wait state |
| 文档化 | 架构/微架构/集成文档 | 规格拆解 | 评审、交付、debug |

**写 SRAM 的核心是让上一拍 AHB 地址/control 对齐当前拍 `HWDATA`；读 SRAM 的核心是判断 SRAM 数据能不能在 AHB 下一数据阶段前稳定。**

## 1. 顶层架构先分清自己写什么

AHB-SRAMC 顶层通常包含 `ahb_slave_if.v` 和 `sram_core.v`。前者是本项目要设计的协议转换逻辑，后者代表 SRAM 宏模型或宏封装；`sramc_top.v` 把两者连接起来。

![AHB-SRAMC 设计架构](<./screenshots/任务039_AHB_SRAM控制器设计2/task39_00_controller_arch_00m20s.jpg>)

🔍 视觉核验：视频 00:20-04:00（controller 架构图：应看到 `ahb_slave_if.v` 与 `sram_core.v` 的边界。）
- **教学职责**：这张图负责划清本轮 RTL 的责任边界：`ahb_slave_if` 做协议转换，`sram_core` 做 SRAM 宏封装。
- **看图要点**：沿 `HADDR/HWRITE/HSIZE/HWDATA` 进入 `ahb_slave_if`，再沿 `bank*_csn/sram_w_en/sram_addr_out/sram_wdata` 到 `sram_core`。
- **看不懂会漏什么**：debug 时会直接钻进 SRAM 模型，忽略真正可能出错的是 AHB 有效访问、地址切片或写数据对齐。

主功能链：

```text
AHB 输入控制 + HADDR + HWDATA
  -> ahb_slave_if.v
  -> SRAM control signals generator
  -> bank0_csn / bank1_csn / sram_w_en / sram_addr_out / sram_wdata
  -> sram_core.v
  -> sram_q0 ... sram_q7
  -> HRDATA
```

第一遍不要把 BIST、低功耗模式和所有测试信号一起塞进脑子。先证明正常读写路径闭合，再扩展测试和低功耗路径。

## 2. `8K x 8` 决定地址位宽和容量

`8K x 8` 的第一个数是深度，第二个数是数据宽度。8K = 8192 = `2^13`，所以每个宏内部至少需要 13 位地址；每个地址 8 bit，表示一个 byte。

![8K x 8 的含义](<./screenshots/任务039_AHB_SRAM控制器设计2/task39_02_8kx8_meaning_08m53s.jpg>)

🔍 视觉核验：视频 08:53-13:00（`8K x 8` 解释页：应看到 depth 和 width 被分开说明。）
- **教学职责**：这张图负责把 SRAM 宏规格翻译成地址位宽和 byte lane 数量。
- **看图要点**：`8K` 是深度，决定 13 位地址；`8` 是宽度，说明一个宏一次只提供 1 个 byte。
- **看不懂会漏什么**：会把 8 个宏的组织关系算错，进而导致 `sram_addr_out` 位宽、bank select 和数据拼接全错。

容量链：

```text
单个 macro: 8K x 8 bit = 8KB
8 个 macro: 8 x 8KB = 64KB
```

地址切片的原则：

```text
高位：决定是否命中 SRAM 窗口和选择 bank
中间位：进入 8K 深度的 SRAM 宏地址
低位：选择 byte lane 或 halfword lane
```

具体位号要以系统 base address、数据宽度和宏封装为准。不能只记某个图上的 `HADDR[14:2]`；要能从容量和访问粒度推出来。

## 3. bank select 是低有效片选

SRAM 宏常用低有效片选，`CSN` 里的 `N` 表示 active low。图里的 `bank0_csn[3:0]` 和 `bank1_csn[3:0]` 对应两个 bank，每个 bank 内 4 个 byte lane。

![bank 选择信号](<./screenshots/任务039_AHB_SRAM控制器设计2/task39_01_bank_select_signals_04m12s.jpg>)

🔍 视觉核验：视频 04:12-08:30（bank select 信号页：应看到 `bank0_csn/bank1_csn` 以及低有效片选关系。）
- **教学职责**：这张图负责让 `bank*_csn[3:0]` 和 4 个 byte lane 对上号。
- **看图要点**：`csn` 里的 `n` 表示低有效；`4'b0000` 是四个 lane 都选中，`4'b1111` 是全不选。
- **看不懂会漏什么**：最常见错误是把低有效当高有效，仿真表现为读全 X、写不进去或未命中 bank 被误打开。

32-bit 写入一个 bank：

```text
bank0_csn = 4'b0000   // bank0 四个 byte lane 都选中
bank1_csn = 4'b1111   // bank1 全不选
```

8-bit 写入只选一个 lane：

```text
HADDR[1:0] = 2'b00 -> byte0
HADDR[1:0] = 2'b01 -> byte1
HADDR[1:0] = 2'b10 -> byte2
HADDR[1:0] = 2'b11 -> byte3
```

16-bit 写入选两个相邻 byte lane，并且通常要求 halfword 对齐。未对齐访问是“上游保证不会来”，还是“本模块返回错误”，必须写进规格；否则验证用例和 RTL 会各按各的理解走。

## 4. AHB slave 侧要裁剪主功能信号

SRAM controller 不需要把每个 AHB 信号都做成复杂逻辑。主功能路径通常关心有效访问、方向、宽度、地址和写数据；burst、lock、master 编号等可能接端口，但本设计未必使用。

![AHB slave 接口](<./screenshots/任务039_AHB_SRAM控制器设计2/task39_03_ahb_slave_interface_13m11s.jpg>)

🔍 视觉核验：视频 13:11-17:00（AHB slave 接口页：应看到主功能相关信号与协议完整性信号的区别。）
- **教学职责**：这张图负责区分“必须驱动主功能”的 AHB 信号和“需要声明处理策略”的协议信号。
- **看图要点**：先圈出 `HSEL/HREADYIN/HTRANS/HWRITE/HSIZE/HADDR/HWDATA`，再看 `HREADYOUT/HRESP` 如何反馈完成和错误。
- **看不懂会漏什么**：会只写内部 SRAM 控制，不写 AHB 完成条件；系统 master 可能在数据还没稳定时就采样。

| 信号 | 是否主功能必看 | 原因 |
|---|---|---|
| `HSEL` | 是 | 是否命中本 slave |
| `HREADYIN` | 是 | 地址阶段是否被总线承认 |
| `HTRANS` | 是 | 排除 `IDLE/BUSY` |
| `HWRITE` | 是 | 读写方向 |
| `HSIZE` | 是 | 生成 byte/halfword/word lane |
| `HADDR` | 是 | bank、宏地址、byte lane |
| `HWDATA` | 写路径 | 数据阶段写入 SRAM |
| `HBURST` | 常可忽略 | 本 SRAM 单周期响应，不靠 burst 优化内部访问 |
| `HRESP/HREADYOUT` | 输出策略 | 简单设计可固定，但要有单周期成立的前提 |

有效访问条件常写成：

```systemverilog
valid_ahb = hsel && hreadyin && htrans[1];
```

`htrans[1]` 为 1 通常覆盖 `NONSEQ/SEQ`，排除 `IDLE/BUSY`。如果 `HREADYIN=0` 时仍采样地址/control，后面数据阶段会错位。

把这个条件落到 RTL 时，建议拆成三层判断：

```systemverilog
addr_phase_valid = hsel && hreadyin && htrans[1];
addr_phase_write = addr_phase_valid && hwrite;
addr_phase_read  = addr_phase_valid && !hwrite;
```

第一层只判断“这拍地址阶段是否被总线接受”，第二层再分读写。这样写的好处是波形 debug 很直接：如果 `addr_phase_valid=0`，后面所有 bank select、write delay、read return 都不应该被触发；如果仍然触发，说明控制器把无效拍当成了事务。

`HREADYOUT` 和 `HRESP` 要和有效访问一起定义。最小可接受策略是：

```text
合法单周期访问:
  HREADYOUT = 1
  HRESP     = OKAY

SRAM 读数据一个周期内不稳定:
  HREADYOUT = 0，保持数据阶段
  数据稳定后 HREADYOUT = 1，HRESP = OKAY

不支持的 HSIZE / 未对齐 / 非法访问:
  若规格选择报错，最终完成拍给 HRESP = ERROR
  若规格选择上游保证不发生，TB 也必须禁止这类激励
```

把 `HREADYOUT` 看成“这笔交易的完成闸门”，把 `HRESP` 看成“完成时的判决章”。闸门不开，master 不应采样或推进依赖事务；闸门打开但判决为 ERROR，说明这笔访问完成了但不是成功访问。

## 5. 写路径必须对齐 AHB 数据阶段

AHB 写传输中，地址阶段先给 `HADDR/HWRITE/HSIZE/HTRANS`，下一拍数据阶段才给对应 `HWDATA`。SRAM 写宏通常希望地址、片选、写使能和写数据同拍有效，所以控制器必须把地址/control 保存一拍。

![SRAM 写时序](<./screenshots/任务039_AHB_SRAM控制器设计2/task39_04_sram_write_timing_17m16s.jpg>)

🔍 视觉核验：视频 17:16-21:00（SRAM 写时序图：应看到 AHB 地址阶段与 `HWDATA` 数据阶段错一拍。）
- **教学职责**：这张图负责证明写路径为什么必须保存上一拍地址/control。
- **看图要点**：在波形上找地址阶段的 `HADDR/HWRITE/HSIZE`，再找下一拍才出现的对应 `HWDATA`。
- **看不懂会漏什么**：会用当前拍地址配当前拍写数据；back-to-back 写入时，A 的数据会写到 B 的地址。

写路径时间线：

```text
T0 AHB 地址阶段：
  valid_ahb=1, HWRITE=1
  保存 HADDR/HSIZE/HWRITE

T1 AHB 数据阶段：
  HWDATA 到达
  用上一拍地址/control 生成 bank_csn、sram_w_en、sram_addr_out
  写入 SRAM macro
```

RTL 骨架：

```systemverilog
always_ff @(posedge hclk or negedge hreset_n) begin
    if (!hreset_n) begin
        wr_valid_d <= 1'b0;
    end else if (hreadyin) begin
        wr_valid_d <= hsel && htrans[1] && hwrite;
        wr_addr_d  <= haddr;
        wr_size_d  <= hsize;
    end
end
```

关键不是“打一拍”这个动作，而是打一拍的条件。只有当前地址阶段被 `HREADYIN` 承认，保存下来的地址/control 才能和下一拍 `HWDATA` 对上。

写 lane 也必须用打一拍后的地址和宽度生成，而不是用当前拍 `HADDR/HSIZE`。因为当前拍可能已经是下一笔访问的地址阶段：

```text
T0: 写 A 地址阶段，保存 A 的 addr/size
T1: A 的 HWDATA 到达，同时总线上可能出现 B 地址阶段
    SRAM 写入必须使用 A 的 addr/size + A 的 HWDATA
```

最小 byte enable 规则：

```text
word  write: HSIZE=010, HADDR[1:0]=00 -> 4 个 lane 全选
half  write: HSIZE=001, HADDR[1]=0    -> lane[1:0]
half  write: HSIZE=001, HADDR[1]=1    -> lane[3:2]
byte  write: HSIZE=000, HADDR[1:0]    -> 只选对应 1 个 lane
```

如果规格不支持未对齐 halfword/word，RTL 和 TB 都要明确：是上游保证不会发，还是本 slave 返回错误响应。没有这个约定，byte lane bug 会在系统集成时才暴露。

一个准确的比喻是“订单先到，货物后一拍到”：AHB 地址阶段像订单，写数据阶段像货物。SRAM 仓库入库时要求订单和货物同一拍交给它，所以 controller 必须夹住上一拍订单，等货物到达时一起交给 SRAM。这个比喻的边界也要清楚：真实 RTL 不是排队系统，能不能连续接单取决于 `HREADYIN/HREADYOUT` 和寄存器是否覆盖了 back-to-back 场景。

## 6. 读路径比写路径更容易卡时序

读操作也有地址阶段和数据阶段，但读路径没有 `HWDATA` 后来对齐的问题；它的问题是时间更紧。AHB master 希望下一数据阶段拿到 `HRDATA`，SRAM 宏读出数据需要 access time，controller 还要 mux 和返回。

![读延迟问题](<./screenshots/任务039_AHB_SRAM控制器设计2/task39_05_read_latency_problem_21m16s.jpg>)

🔍 视觉核验：视频 21:16-24:30（读延迟问题页：应看到 AHB 下一数据阶段要求读数据返回的时序压力。）
- **教学职责**：这张图负责把读路径的难点从“会不会读”提升到“什么时候能被 master 采样”。
- **看图要点**：确认 AHB 读地址阶段后，下一数据阶段就是 `HRDATA` 的被采样窗口；SRAM access time 必须落在这个窗口前。
- **看不懂会漏什么**：会把 `HRDATA` 晚一拍更新但仍保持 `HREADYOUT=1`，master 实际采样到的是旧数据或 X。

两种设计口径：

```text
单周期读成立：
SRAM read access time + mux + HRDATA path <= 一个周期可用预算
HREADYOUT 可保持高

单周期读不成立：
拉低 HREADYOUT 插入 wait state
等数据稳定后再让 master 采样
```

因此，读路径不能随手再打一拍。如果你把 `HRDATA` 晚一拍返回，却没有拉低 `HREADYOUT`，AHB master 会在错误时间采样旧值或 X。

读路径的检查口径可以写成一个时序不等式：

```text
Tclk 可用预算
  >= SRAM tAA / tCO
   + bank output mux
   + controller HRDATA mux/register setup
   + SoC interconnect 返回路径裕量
```

如果这个不等式成立，`HREADYOUT` 可以保持 1，读数据在下一数据阶段被采样；如果不成立，必须插入 wait state。wait state 不是“让仿真慢一点”，而是告诉 AHB master：这笔数据阶段尚未完成，请不要采样、不要推进下一笔依赖访问。

最小读控制可以抽象为三态：

```text
IDLE:
  等待 addr_phase_read

READ_ACCESS:
  打开命中 bank，给出 SRAM 地址，等待 q 数据稳定

READ_RESP:
  HRDATA 有效，HREADYOUT=1，HRESP=OKAY
```

如果 SRAM 宏足够快，`READ_ACCESS` 和 `READ_RESP` 可以压在一个周期内完成；如果不够快，就用 `HREADYOUT=0` 把数据阶段保持住。失败信号不是“仿真变慢”，而是 `HREADYOUT` 永远不回 1、`HRDATA` 在完成拍仍为 X、或连续读时前一笔数据串到后一笔地址。

## 7. bank 数量是功耗和复杂度的取舍

把 64KB 切成两个 bank，每次访问打开 32KB 范围；切成四个 bank，每次打开 16KB 范围，动态功耗可能更低，但译码和控制更复杂。

![bank 划分扩展](<./screenshots/任务039_AHB_SRAM控制器设计2/task39_07_bank_split_29m49s.jpg>)

🔍 视觉核验：视频 29:49-36:00（bank 扩展图：应看到用高位地址选择不同 bank 的思路。）
- **教学职责**：这张图负责说明 bank 切分既是低功耗手段，也是地址译码复杂度来源。
- **看图要点**：比较 2 bank 和 4 bank 时，每次被打开的容量变小，但片选译码和验证组合数变多。
- **看不懂会漏什么**：会盲目追求更多 bank，却低估 filelist、宏规格、时序 mux 和 byte lane 验证的成本。

| 方案 | 选择位 | 每次打开范围 | 代价 |
|---|---|---|---|
| 2 bank | 1 位高地址 | 32KB | 简单 |
| 4 bank | 2 位高地址 | 16KB | 译码、片选、验证更复杂 |

实际工程还受 memory compiler 限制。想要某种深度/宽度/端口的宏，不代表库里一定有合适版本。前端方案必须和可用 SRAM macro 对齐。

## 8. SRAM 宏时序决定单周期是否真实成立

SRAM macro 的 truth table 和 timing table 会定义 `CEN/CSN/WEN/OEN` 等控制信号在读写时的组合，以及地址到数据稳定需要多久。

![SRAM 读时序](<./screenshots/任务039_AHB_SRAM控制器设计2/task39_08_sram_read_timing_37m59s.jpg>)

🔍 视觉核验：视频 37:59-42:39（SRAM read timing 页：应看到读模式下地址和使能有效后，数据经过访问时间才稳定。）
- **教学职责**：这张图负责把 SRAM 宏手册里的 timing table 连接到 AHB `HREADYOUT` 决策。
- **看图要点**：读模式下先有地址和使能，再经过 access time 才有稳定 Q；不要把 Q 当组合零延迟信号。
- **看不懂会漏什么**：会在 RTL 中过度乐观地组合返回 `HRDATA`，综合后 slow corner 或布线延迟下单周期读失败。

读路径判断：

```text
SRAM read access time
  + controller mux
  + HRDATA 返回路径
  <= 一个 AHB cycle 的可用时序预算
```

写路径判断：

```text
地址/control/write enable/write data
在 SRAM 采样边界满足 setup/hold
```

这就是任务39的价值：它把协议知识变成 RTL 决策。某个信号要不要寄存、某条路径能不能组合、是否需要 `HREADYOUT` 等待，都不是风格问题，而是协议时序和 SRAM 宏规格共同决定的。

结合 SRAM logic table 看，读写模式还要守住 `CEN/WEN/OEN` 的组合语义：

```text
standby: CEN=H，地址输入无效，存储内容保持
write  : CEN=L, WEN=L，D 输入写入指定地址
read   : CEN=L, WEN=H, OEN=L，Q 输出指定地址数据
high-Z : OEN=H，输出不驱动
```

因此 `csn/wen/oen` 不是随便命名的控制线。片选低有效、写使能低有效、输出使能低有效这些约定如果搞反，功能仿真可能表现为全 X、读不到新值，或者未访问 bank 也在翻转。

## 9. 微架构文档先于 coding

课程讲架构文档、微架构文档和集成文档，不是流程装饰。SRAM controller 这种接口转换模块，如果不先写清时序策略，代码很容易边写边猜。

![设计文档类型](<./screenshots/任务039_AHB_SRAM控制器设计2/task39_06_design_docs_24m37s.jpg>)

🔍 视觉核验：视频 24:37-29:00（设计文档页：应看到架构、微架构、集成文档的粒度区别。）
- **教学职责**：这张图负责说明文档不是交付装饰，而是把时序策略和不支持行为提前固定。
- **看图要点**：架构文档回答做什么，微架构文档回答怎么分阶段和怎么打拍，集成文档回答怎么接到 SoC 和 SRAM 宏。
- **看不懂会漏什么**：会在 coding 时临时决定 wait state、未对齐访问和 BIST 优先级，导致 RTL、TB 和集成方口径不一致。

| 文档 | 内容重点 | SRAM controller 中要写清 |
|---|---|---|
| 架构设计 | 做什么、系统位置、软硬件分工 | SRAM 是 AHB slave，提供 64KB 存储 |
| 微架构设计 | 怎么做、模块划分、内部信号、时序 | `ahb_slave_if` 如何生成 bank/csn/wen/hrdata |
| 集成文档 | 怎么接、时钟复位、端口、约束 | AHB 端口接 SoC bus，SRAM 端口接 macro |

微架构文档至少要回答：有效访问条件是什么？写地址/control 为什么打一拍？读路径是否插 wait？8/16/32-bit 怎么生成 byte enable？非法/未对齐访问怎么处理？

## 最小闭环：从 AHB 写到 SRAM

```text
T0:
  HSEL=1, HREADYIN=1, HTRANS=NONSEQ/SEQ, HWRITE=1
  HADDR/HSIZE 有效
  controller 保存地址、宽度、写方向

T1:
  HWDATA 到达
  controller 用上一拍地址选择 bank 和 byte lane
  拉低对应 bank_csn 和写使能
  把 HWDATA 写入 SRAM macro

读回:
  AHB read 命中同一地址
  SRAM q0-q7 拼成 HRDATA
  master 在数据阶段采样
```

## 可复现检查：手推一笔 back-to-back 写读

用下面的事务检查控制器有没有真正对齐 AHB 两阶段：

```text
T0: 写 A 地址阶段，HADDR=0x0040_0000, HSIZE=word, HWRITE=1
T1: A 的 HWDATA=0x1122_3344 到达，同时写 B 地址阶段 HADDR=0x0040_0004
T2: B 的 HWDATA=0x5566_7788 到达
T3: 读 A 地址阶段
T4: HRDATA 应返回 0x1122_3344，除非 HREADYOUT 插入 wait
```

判定口径：

```text
通过：
  T1 写 SRAM 时使用 A 的 addr/size + A 的 HWDATA
  T2 写 SRAM 时使用 B 的 addr/size + B 的 HWDATA
  读 A 返回 A 的数据，读 B 返回 B 的数据
  完成拍 HREADYOUT=1 且 HRESP=OKAY

失败：
  T1 使用了 B 的地址
  HREADYIN=0 时仍更新 wr_addr_d
  HRDATA 晚到但 HREADYOUT 没有拉低
  未对齐或不支持访问没有按规格报错或屏蔽
```

这组检查比单笔写读更有价值，因为它会暴露“当前拍地址误配当前拍数据”的隐藏 bug。

## 常见误区和失败信号

- 把 `8K x 8` 当 8K bit，容量和地址位宽都错。
- 忘记 `csn` 低有效，导致波形上“选中”其实宏没工作。
- 写路径不保存地址/control，`HWDATA` 写到错误地址。
- `HREADYIN=0` 时仍更新寄存器，wait state 下地址数据错位。
- 读路径晚一拍但不拉低 `HREADYOUT`，master 采样旧数据。
- 只测 32-bit，不测 byte/halfword，lane 选择问题漏掉。
- 文档没有声明不支持的 AHB feature，集成方按完整协议使用后行为不匹配。

## 和 AI+IC / NPU 学习的连接

NPU buffer、DMA buffer、weight SRAM 都会遇到同样的微架构问题：地址/control 与数据是否同拍，bank 是否低功耗选择，byte enable 是否正确，读路径是否满足单周期，不能满足时是否用 ready/valid 或 wait state 背压。

最小练习：写出一个 32-bit AHB 写入 4 个 8-bit SRAM lane 的控制条件，分别覆盖 byte、halfword、word 三种宽度。

## 复习与自测

1. **解释题**：`ahb_slave_if.v` 和 `sram_core.v` 分别负责什么？  
   **答案**：`ahb_slave_if.v` 把 AHB 访问翻译成 SRAM 控制和 AHB 返回；`sram_core.v` 封装 SRAM 宏模型，执行实际存储读写。

2. **计算题**：为什么 `8K x 8` 宏内部地址需要 13 位？  
   **答案**：8K = 8192 = `2^13`，所以需要 13 位地址选择宏内部位置。

3. **判断题**：AHB 写 SRAM 时可以直接用当前拍 `HADDR` 和当前拍 `HWDATA` 写宏。  
   **答案**：错。AHB 写数据比地址晚一拍，必须保存上一拍地址/control 去对齐当前 `HWDATA`。

4. **工程题**：如果 SRAM 读路径一个周期内不能稳定，协议上怎么处理？  
   **答案要点**：拉低 `HREADYOUT` 插入 wait state，等 `HRDATA` 稳定后再拉高 ready 让 master 完成采样。

5. **波形题**：back-to-back 写 A、写 B 时，为什么 T1 不能用当前拍 `HADDR` 生成 SRAM 写地址？  
   **答案要点**：T1 当前拍 `HADDR` 可能已经是 B 的地址阶段，而 T1 的 `HWDATA` 属于 A；SRAM 写入必须使用上一拍锁存的 A 地址/control。

6. **判断题**：`HREADYOUT=0` 的作用是让 SRAM 多等一会儿，所以 master 是否采样不受影响。  
   **答案**：错。`HREADYOUT=0` 表示当前数据阶段没有完成，master 不能认为返回数据有效，也不能推进依赖这笔访问的后续动作。

7. **工程题**：`HRESP=ERROR` 应该在什么情况下出现？  
   **答案要点**：取决于规格。常见候选包括不支持的 `HSIZE`、未对齐访问、保留地址或内部错误；如果规格规定上游保证这些情况不发生，TB 要禁止对应激励，而不是随意期待 ERROR。



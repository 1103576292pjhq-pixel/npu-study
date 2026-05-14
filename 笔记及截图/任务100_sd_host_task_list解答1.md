# 任务100：SD host task list 解答 1

## 本章知识全景图

这一讲复盘 SD host 作业题，核心不是背 SD 卡名词，而是把串行协议、command 格式、data bit 顺序、响应间隔、停 clock 条件、buffer/DMA 设计和 CRC 校验连成一个硬件控制器的设计口径。SD host 的难点在于：外部卡按自己的协议节奏吐数据，内部 SoC 侧又受 FIFO、DMA、AHB 仲裁和时序收敛约束。

| 层级 | 核心概念 | 本讲必须掌握的判断 |
|---|---|---|
| 背景指标 | SD 2.0 容量、speed class | 容量越大，持续吞吐越重要；class 是最低持续写入速度口径。 |
| 接口信号 | CLK、CMD、DAT[3:0] | SD 是同步串行接口，CMD 串行传命令，DAT 支持 1-bit/4-bit 数据。 |
| Command 格式 | 48 bit、start、transmit、index、argument、CRC7、end | start bit 负责对齐，index 表示命令号，argument 补充命令参数。 |
| Data 顺序 | 1-bit / 4-bit | 4-bit 模式按 nibble 并行传输，发送和接收必须采用同一 bit 顺序。 |
| 协议间隔 | NCR、NID、NAC、NRC、NCC、NWR | command/response/data 之间有最小和最大 cycle 约束。 |
| 停 clock | FIFO 溢出保护、功耗、尾部 8 clocks | 当前设计靠停 SD clock 防止 host FIFO 被卡继续写爆。 |
| 更优架构 | ping-pong buffer + DMA | 一边收 SD 数据，一边让 DMA 搬走上一块，提高吞吐，但仍需保留 backpressure。 |
| CRC | CRC7、CRC16 | command/response 用 CRC7，data block 用 CRC16，硬件上常用移位寄存器实现。 |

最短学习路径：

```text
先认 SD 接口：CLK/CMD/DAT[3:0]
  -> command 48 bit 如何串行对齐
  -> data 1-bit/4-bit 顺序如何恢复成 byte/block
  -> command/response/data 之间有哪些等待区间
  -> 为什么当前设计要停 SD clock
  -> ping-pong buffer + DMA 为什么更合理
  -> busy 和 CRC 如何判断事务可靠结束
```

## 全视频地图

| 时间段 | 视频块 | 视觉证据 | 学习目标 |
|---|---|---|---|
| 00:33-02:07 | SD 2.0 容量和 class | `task100_00_sd_capacity_class_00m33s.jpg`、`task100_01_sd_interface_pins_02m07s.jpg` | 建立容量、速度等级和接口线的基本背景。 |
| 03:41-10:40 | CMD 48 bit 与 data bit 顺序 | `task100_02_cmd_format_03m41s.jpg`、`task100_03_data_bit_order_10m40s.jpg` | 理解串行 start bit、command 字段和 4-bit 数据发送顺序。 |
| 11:42-17:43 | 协议时序间隔 | `task100_04_timing_intervals_11m42s.jpg` | 分清 NCR、NID、NAC、NRC、NCC、NWR。 |
| 17:43-20:04 | 当前设计为什么停 SD clock | `task100_05_stop_sd_clock_17m43s.jpg` | 用停 clock 避免 FIFO overflow。 |
| 20:04-31:46 | ping-pong buffer 与 DMA | `task100_06_pingpong_buffer_20m04s.jpg` | 理解更高吞吐架构，以及何时仍要停 clock。 |
| 31:46-36:15 | 停 clock 尾部 8 cycles 与 busy | `task100_07_busy_crc_34m46s.jpg` | 事务结束后不能立刻停 clock；写入 busy 可由 DAT0 或 CMD13 判断。 |
| 36:15-40:41 | CRC7 / CRC16 | `task100_08_crc7_crc16_36m15s.jpg` | 说明 CRC 的作用和硬件实现思路。 |

## 视觉证据与截图说明

| 截图 | 教学职责 |
|---|---|
| ![SD 容量与速度等级](<./screenshots/任务100_sd_host_task_list解答1/task100_00_sd_capacity_class_00m33s.jpg>) | 说明 SD 2.0 容量等级和 speed class 的背景。 |
| ![SD 接口信号](<./screenshots/任务100_sd_host_task_list解答1/task100_01_sd_interface_pins_02m07s.jpg>) | 对齐 CLK、CMD、DAT[3:0] 这组 host 控制器接口。 |
| ![CMD 48 bit 格式](<./screenshots/任务100_sd_host_task_list解答1/task100_02_cmd_format_03m41s.jpg>) | 展示 command 固定长度和字段分布。 |
| ![data bit order](<./screenshots/任务100_sd_host_task_list解答1/task100_03_data_bit_order_10m40s.jpg>) | 说明 1-bit/4-bit 模式下 bit 顺序不同。 |
| ![协议间隔](<./screenshots/任务100_sd_host_task_list解答1/task100_04_timing_intervals_11m42s.jpg>) | 对齐 command、response、data 之间的 cycle 约束。 |
| ![停 SD clock](<./screenshots/任务100_sd_host_task_list解答1/task100_05_stop_sd_clock_17m43s.jpg>) | 说明当前设计靠停 clock 防止 FIFO overflow。 |
| ![ping-pong buffer](<./screenshots/任务100_sd_host_task_list解答1/task100_06_pingpong_buffer_20m04s.jpg>) | 展示更高效的双 buffer + DMA 思路。 |
| ![busy 与 CRC](<./screenshots/任务100_sd_host_task_list解答1/task100_07_busy_crc_34m46s.jpg>) | 对齐 DAT0 busy、CMD13 状态查询和 CRC 场景。 |
| ![CRC7 / CRC16](<./screenshots/任务100_sd_host_task_list解答1/task100_08_crc7_crc16_36m15s.jpg>) | 说明 command/response 与 data block 使用不同 CRC 宽度。 |

## 1. SD 容量和速度等级只是背景，吞吐设计才是硬问题

SD 2.0 中普通容量卡最高到 2GB，高容量卡到 32GB；课程中提到 class 0/2/4/6 这类速度等级，表示最低持续写入速度要求。例如 class 2 至少 2MB/s，class 6 至少 6MB/s。

这些数字本身不是 RTL 难点。真正的硬件问题是：卡容量越大，用户越在乎持续吞吐；持续吞吐又取决于 SD clock、数据位宽、内部 FIFO、DMA 搬运和总线仲裁。一个 SD host 不能只会“把一个 command 发出去”，还要能持续收发 block，并处理 SoC 内部来不及搬走数据的情况。

## 2. SD 接口是同步串行接口

SD host 基本信号可以压成三类：

| 信号 | 方向/作用 | 设计含义 |
|---|---|---|
| `SD_CLK` | host 输出 | 卡和 host 都按这个时钟推进协议状态。 |
| `CMD` | 双向串行命令线 | host 发 command，card 回 response。 |
| `DAT[3:0]` | 数据线 | 可用 1-bit 或 4-bit 模式传输 data block，也承载 busy。 |

同步串行接口的关键约束是：没有 clock，卡内部状态也不能继续按协议推进。因此停 clock 可以成为 backpressure 手段，但停错时机会让卡内部事务卡住或协议尾部不完整。

## 3. 48-bit command 靠 start bit 完成串行对齐

SD command 固定为 48 bit。字段可以概括为：

```text
start bit      : 1 bit，通常为 0，用来标记帧开始
transmission bit: 1 bit，区分 host->card command 或 card->host response
command index  : 6 bit，表示 CMD0、CMD8、CMD17 等命令号
argument       : 32 bit，命令参数，例如 RCA、地址、block number
CRC7           : 7 bit，保护前面字段
end bit        : 1 bit，通常为 1，表示帧结束
```

串行协议最怕错位。start bit 的教学价值就在这里：CMD 线 idle 时通常为高，帧开始时出现低电平 start bit，接收端据此进入状态机并按固定 bit 计数接收后续字段。如果接收端把第二个 bit 当成第一个 bit，后面的 command index、argument、CRC 全部错位。

命令号和参数缺一不可。比如选择某张卡时，CMD7 表示“select/deselect card”，argument 中的 RCA 指出选择哪一张卡。只有 CMD7 没有 RCA，卡不知道选谁；只有 RCA 没有 CMD7，卡不知道要执行什么动作。

## 4. 4-bit data 模式不是简单“快四倍”，还要求 bit 顺序一致

1-bit 模式下，data byte 按高位到低位依次从一根 DAT 线上串行传。4-bit 模式下，一个 clock 可以通过 DAT[3:0] 传 4 个 bit，但发送端和接收端必须使用同一拆分顺序。

可理解为：

```text
1-bit:
  B7 -> B6 -> B5 -> B4 -> B3 -> B2 -> B1 -> B0

4-bit:
  cycle0: DAT3=B7, DAT2=B6, DAT1=B5, DAT0=B4
  cycle1: DAT3=B3, DAT2=B2, DAT1=B1, DAT0=B0
```

如果发送端把 B7 放在 DAT0，而接收端按 DAT3 取最高位，恢复出的 byte 会完全错误。4-bit 模式提高吞吐的前提是双方对 bit lane 和 bit order 的定义一致。

## 5. 协议间隔是状态机等待条件，不是注释

SD 协议里 command、response、data 之间存在多个间隔名词。它们在 RTL 中通常会变成 counter 和 timeout 条件。

| 名词 | 含义 | 控制器要做什么 |
|---|---|---|
| NCR | command 结束到 response start 之间的等待 | 等待 response start bit，超过最大值报 timeout。 |
| NID | command 到 identification 相关响应/数据的固定等待 | 按协议固定等待，不能随意少等。 |
| NAC | read command 到 data block start 的等待 | 等待 data start token 或 data start bit。 |
| NRC | response 结束到下一 command 的最小间隔 | 不要刚收完 response 就立刻发下一帧。 |
| NCC | 不需要 response 的 command 到下一 command 的间隔 | 给卡内部解析和状态推进时间。 |
| NWR | write command 后 host 开始写 data 的等待 | 写数据前保留协议规定空隙。 |

这些间隔不是文档装饰。RTL 状态机必须把它们落成“进入某状态后计数多少 cycle、什么时候允许跳转、什么时候 timeout”的逻辑。

## 6. 当前设计停 SD clock 是为了防止 FIFO overflow

视频中复盘的当前设计比较直接：读一个 block，host FIFO 里收到数据；如果 AHB/DMA 侧还没把这块数据搬走，SD card 又继续吐下一块，FIFO 就可能 overflow。因此当前设计在收完一个 block 后停 SD clock，等内部把数据搬走，再打开 clock 继续下一块。

这个方案的优点是控制简单，能保护 FIFO。缺点是吞吐不高，因为每个 block 后都可能暂停外部卡。

可以把它写成硬件条件：

```text
stop_sd_clk when:
  read path has received one block
  and internal FIFO/buffer is full
  and DMA/AHB side has not consumed it yet

restart_sd_clk when:
  at least one buffer slot becomes empty
  and protocol tail clocks have been satisfied
```

这里的停 clock 不是低功耗优先，而是 backpressure 优先。它解决的是“外部源头继续给数据，而内部暂时接不住”的问题。

## 7. 更好的吞吐架构是 ping-pong buffer + DMA

更合理的设计是双 buffer，也叫 ping-pong buffer：

```text
buffer A:
  正在接收 SD card 的 block N

buffer B:
  DMA 正在搬运 block N-1 到 AHB/memory

下一轮:
  A/B 角色交换
```

这样 SD 接收和 DMA 搬运可以并行，吞吐由较慢的一侧决定。若 DMA 搬运通常比 SD 接收快，就很少需要停 SD clock。

但 ping-pong buffer 不能取消停 clock 功能。极端情况下，AHB 总线可能一直拿不到 grant，DMA 搬不走数据；如果 A、B 两个 buffer 都满，host 仍然必须停 SD clock，否则第三个 block 来了没有地方放。

可靠策略是：

| 情况 | 动作 |
|---|---|
| A 正在收，B 正在被 DMA 搬走 | 正常运行。 |
| 当前 buffer 满，另一个 buffer 已空 | 切换 buffer，继续收。 |
| 两个 buffer 都满 | 停 SD clock，等待 DMA 释放至少一个 buffer。 |
| DMA 获得 grant 并搬空一个 buffer | 重新打开 SD clock。 |

这就是数字设计里的 backpressure：不要假设下游永远够快，要给“下游暂时接不住”留硬件路径。

## 8. 停 clock 前要给协议尾部时钟

不能在一个动作刚结束的同一拍立刻停 SD clock。原因是卡内部也依赖 SD clock 推进状态，command、response、data、CRC status、program busy 等尾部动作都可能需要额外 clock。

课程中强调一个保守规则：事务结束后至少再给 8 个 SD clock，再停 clock。

可归纳为：

```text
无响应 command:
  command end 后再给至少 8 clocks

有响应 command:
  response end 后再给至少 8 clocks

read:
  最后一个 data block / CRC 结束后再给至少 8 clocks

write:
  CRC status / busy 处理完成后再给至少 8 clocks
```

这个规则的设计含义是：停 clock 是合法 backpressure，但必须停在协议安全点。

## 9. 写入 busy 可以用 DAT0 或 CMD13 判断

SD card 写入 data block 后，内部还要把数据 program 到非易失存储。这个阶段卡可能进入 busy。

两种常见判断方式：

| 方法 | 含义 | 使用场景 |
|---|---|---|
| DAT0 busy | 卡把 DAT0 拉低表示 busy，释放为高表示可继续。 | 写入后等待卡内部 program 完成。 |
| CMD13 SEND_STATUS | host 主动查询卡状态。 | 需要软件/硬件明确读取状态寄存器口径。 |

DAT0 busy 更像硬件握手，CMD13 更像显式状态查询。实际控制器可根据设计复杂度和协议阶段选择其一或组合使用。

## 10. CRC 是传输可靠性的硬件检查

SD 线上传的是电信号，可能因干扰、走线、封装、采样边界等原因发生 bit 错误。CRC 的作用是让接收端检查“收到的数据很可能就是发送端发出的数据”。

本讲涉及两类：

| CRC | 用途 | 宽度 |
|---|---|---|
| CRC7 | command 和 response | 7 bit |
| CRC16 | data block | 16 bit |

硬件实现通常是移位寄存器 + XOR 反馈。发送端一边移入原始 bit 一边计算 CRC，把 CRC 附在帧尾；接收端用同样规则重新计算，与收到的 CRC 比较。若不一致，说明传输过程中很可能出现 bit 错误，应上报 CRC error 或拒绝本次数据。

CRC 不能证明数据“语义正确”。它只能证明传输链路上出现随机错误的概率很低。比如 host 原本就发错 argument，CRC 仍可能完全正确，因为 CRC 保护的是“这个错误帧有没有在传输中被改坏”，不是“命令是不是你想发的命令”。

## 11. SD host RTL 的最终设计口径

把本讲合并成一个控制器设计检查表：

```text
Command path:
  48-bit frame packing
  start/end bit
  command index
  argument
  CRC7
  response wait / timeout

Data path:
  1-bit / 4-bit lane mapping
  block receive/send
  CRC16
  DAT0 busy
  buffer full/empty

Backpressure:
  FIFO or ping-pong buffer
  DMA/AHB grant
  stop/restart SD clock
  tail 8 clocks before stop

Software-visible state:
  status
  error
  interrupt
  command done / data done / crc error / timeout
```

只会发 command 的 host 不是完整 host。完整 host 必须能处理协议等待、数据搬运、错误状态、下游 backpressure 和软件可见结果。

## 深层理解：SD Host 是同步传送带，不是普通串口

SD 协议看起来只有 CMD、CLK、DAT 几根线，但真正难点是这些线共同组成一条同步传送带。`sd_clk` 是传送带节拍，CMD 是调度单，DAT[3:0] 是四条并行货道，CRC 是每批货的封条，busy 是卡内部还没入库的信号。Host 的任务不是“把 bit 推出去”，而是让调度单、货道、封条、等待和后端仓库同时对齐。

这个模型解释了本讲几个关键问题：

| 协议点 | 传送带直觉 | RTL 后果 |
|---|---|---|
| 48-bit command | 一张固定格式调度单 | start/transmission/index/argument/CRC/end 必须按位发 |
| 4-bit DAT | 四条货道并行装货 | bit lane 顺序错会整块数据错位 |
| Ncr/Nrc/Ncc 间隔 | 调度单之间的安全距离 | 状态机必须等待，不能连续猛发 |
| stop SD clock | 后端仓库满时踩刹车 | 停太早断协议，停太晚 FIFO overflow |
| ping-pong buffer | 两个装卸月台轮换 | DMA 慢时仍需 backpressure |
| DAT0 busy/CMD13 | 卡内部入库状态 | response OK 后仍可能不能立刻发下一笔写 |

Ping-pong buffer 不是魔法，它只是把一个月台变成两个：一个接 SD 数据，一个给 AHB/DMA 搬走。若 DMA 长时间拿不到总线，两个 buffer 都会满，此时必须停传送带。这里和 NPU 数据搬运完全同构：外部数据源、片上 buffer、DMA/NoC、计算单元之间，只要生产者快于消费者，就必须有水位、停顿和恢复机制。

## AI+IC 连接

SD host 的 buffer/DMA/backpressure 思路和 NPU 数据搬运高度相似。NPU 从外部 memory 读 feature map、weights、instructions 时，也会遇到“上游产生数据、下游暂时接不住、总线 grant 不稳定、buffer 满了怎么办”的问题。ping-pong buffer、FIFO 水位、clock gating/backpressure、DMA 仲裁，都是 AI 芯片数据通路设计的基础能力。

## 工程练习

1. 写出 48-bit CMD 帧的 bit 字段表，并说明每个字段的用途。
2. 给一个 byte `8'b1011_0010`，分别写出 1-bit 和 4-bit 模式下发送顺序。
3. 用状态机画出 CMD 发出后等待 response 的 NCR timeout 逻辑。
4. 设计一个 ping-pong buffer 的 full/empty 和 role-swap 条件。
5. 写出 `stop_sd_clk` 和 `restart_sd_clk` 的伪代码，必须包含“两个 buffer 都满”和“至少 8 个尾部 clock”。
6. 解释 CRC7 和 CRC16 分别保护什么，不能证明什么。

## 常见误区和失败信号

| 误区 | 正确判断 |
|---|---|
| 4-bit 模式就是简单并行，顺序无所谓。 | DAT[3:0] 的 bit lane 顺序必须和协议一致。 |
| command 发完马上可以发下一条。 | response、data 或 no-response 间隔都可能要求等待。 |
| 停 SD clock 只为省电。 | 本设计中主要是 backpressure，防止 FIFO/buffer overflow。 |
| 有 ping-pong buffer 就永远不用停 clock。 | AHB/DMA 可能拿不到 grant，两个 buffer 都满时仍要停。 |
| CRC 能证明命令语义正确。 | CRC 只能检查传输错误，不能判断 argument 是否符合软件意图。 |
| 写入后 response OK 就说明卡不 busy。 | 写 block 后卡可能仍在内部 program，需要 DAT0 busy 或 CMD13 状态判断。 |

## 复习与自测

1. SD command 为什么需要 start bit？  
   答案：CMD 是串行线，start bit 让接收端知道帧从哪里开始，避免 bit 计数错位。

2. 48-bit command 的主要字段有哪些？  
   答案：start bit、transmission bit、6-bit command index、32-bit argument、7-bit CRC7、end bit。

3. 4-bit 模式下一个 byte `B7..B0` 通常如何传？  
   答案：第一个 clock 传 B7/B6/B5/B4 到 DAT3/DAT2/DAT1/DAT0，第二个 clock 传 B3/B2/B1/B0。

4. 当前设计为什么要停 SD clock？  
   答案：防止 SD card 继续吐数据导致 host FIFO/buffer overflow，属于 backpressure 机制。

5. ping-pong buffer 为什么仍需保留停 clock？  
   答案：如果 AHB/DMA 长时间拿不到 grant，两个 buffer 都可能满；此时必须停 SD clock 等待至少一个 buffer 被搬空。

6. 停 clock 前为什么要再给 8 个 clock？  
   答案：给卡内部协议尾部、response/data/CRC/busy 等状态推进留安全周期，避免刚结束就把卡停在不完整状态。

7. CRC7 和 CRC16 的用途分别是什么？  
   答案：CRC7 用于 command/response，CRC16 用于 data block。它们检查传输错误，不检查命令语义是否正确。

## 工程核对口径

评审 SD Host 方案时，把设计拆成六个可检查对象：

1. CMD 帧：48 bit 字段、CRC7、response 类型、timeout 是否完整。
2. DAT 线：1-bit/4-bit lane 顺序、payload/CRC16/busy 边界是否正确。
3. 时钟：初始化低速、传输高速、停钟尾部 clock、恢复条件是否明确。
4. Buffer：FIFO 或 ping-pong buffer 的 full/empty、role swap、水位中断是否可验证。
5. DMA：AHB grant 不稳定时是否能持续服务，不能服务时是否 backpressure。
6. 软件状态：done/error/interrupt/status 是否能让驱动区分成功、CRC 错、timeout、busy 和 overflow。

如果一个设计只说明“能发命令、能收数据”，但回答不了这六项，它还只是 demo，不是可交付 Host。完整 Host 要像一条有刹车、有仓库、有质检、有调度反馈的传送线。


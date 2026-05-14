# 80_AHB_sd_host控制器设计19

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：从 `sd_command_fsm` 往下走，进入 `command send shift register`，把并行的 command 字段拆成串行 CMD 线输出，同时在发送过程中生成 CRC7。
- 核心概念：`command send shift register`、`in_has_send_bit`、`in_command_index`、`in_command_argument`、`command_for_send`、`command_direction_pos/neg`、`high_speed_clock`、CRC7。
- 逻辑主线：command FSM 只决定什么时候发送；真正把 `start + transmit + index + argument + crc7 + end` 逐 bit 推到 CMD 线的是 send shift 模块。
- 最小主线：
  - `sd_command_fsm` 负责让 `in_has_send_bit` 从 0 数到 47。
  - send shift 模块按每 8 bit 一组装载数据，再逐拍左移输出最高位。
  - 前 40 bit 参与 CRC7 计算。
  - `high_speed_clock` 通过 posedge/negedge 选择，把 CMD 输出相位平移半拍，解决板级采样时序。

这讲可以把 48-bit command frame 想成一张要从并行表格卷成一条纸带的通关单：前 40 bit 是正文信息，CRC7 是防伪章，end bit 是纸带尾标。FSM 只喊“开始卷纸带”和“卷到第几格”，send shift 才是真正把纸带一格一格送到 CMD 线的人。

### 2. 概念地图

| 层级 | 对象 | 作用 | 易错点 |
|---|---|---|---|
| 控制输入 | `in_current_state`、`in_has_send_bit` | 指示当前是否处于 `STATE_SEND`、已发到第几 bit | 不要把状态机和 shift 输出混为一体 |
| 并行命令字段 | `in_command_index`、`in_command_argument` | 构造 40-bit 命令主体 | `start/transmit` 已包含在拼装里，不要重复算 |
| 串行输出 | `out_sd_command`、`out_command_direction` | 驱动双向 CMD pad 的数据与输出使能 | direction 既是输出使能，又决定 pad 是否回到输入态 |
| CRC7 | send-side CRC 计算 | 给 bit[40:46] 提供 CRC7 | 只对前 40 bit 计算 |
| 时序相位 | posedge/negedge 选择 | 半拍平移 CMD 输出 | 这是板级 timing 修正，不是协议逻辑变化 |

### 3. 最短学习路径

1. 先记住 command frame 是 48 bit，其中前 40 bit 是 `start + transmit + index + argument`。
2. 再看 send shift 如何每 8 bit 装载一次、逐拍左移输出。
3. 最后看 CRC7 和 `high_speed_clock`，这两个是本模块真正有工程价值的地方。

### 4. 全讲结构地图

| 阶段 | 内容 | 关键判断 |
|---|---|---|
| 00:00-09:30 | 回顾 command FSM 与 send/receive 两个 shift 模块的分工 | 状态机控制节奏，shift 模块真正发 bit |
| 09:30-16:00 | `command_direction_pos/neg` 与 `high_speed_clock` | 输出相位可切换半拍 |
| 16:00-33:30 | `command_for_send` 拼装与每 8 bit 装载/移位 | 串并转换的主路径 |
| 33:30-44:30 | CRC7 生成 | 前 40 bit 参与计算 |
| 44:30-48:30 | 为什么要切 posedge/negedge | 解决板级 setup/hold 问题 |

## 1. send shift 模块的职责是把 48-bit command frame 串行化

`sd_command_fsm` 在任务 79 里已经决定了 `STATE_SEND` 的生命周期和 `send_bit_count`。本讲的 `command send shift register` 只做一件事：根据 `in_has_send_bit` 当前值，决定 CMD 线上这一拍该输出哪个 bit。

画面核对：01:40-03:28，课程先回顾 command FSM，再明确 send/receive 两个 shift 模块分别承担发送和接收的串并转换。

![command send overview](<./screenshots/任务080_AHB_sd_host控制器设计19/task80_00_command_send_overview_01m10s.jpg>)

模块输入的本质分三类：

| 输入组 | 典型信号 | 含义 |
|---|---|---|
| 状态控制 | `in_current_state`、`in_has_send_bit` | 当前是不是 `STATE_SEND`，已经发到第几 bit |
| 命令内容 | `in_command_index`、`in_command_argument` | 要发的 index 和 32-bit argument |
| 时序选择 | `in_high_speed_clock`、`sd_clock` | 选择输出相位 |

输出只有两个真正关键：

| 输出 | 作用 |
|---|---|
| `out_sd_command` | CMD 线上当前 bit 的值 |
| `out_command_direction` | CMD pad 的输出使能 |

48-bit 帧的 bit 编号可以固定成：

| bit 区间 | 内容 | 说明 |
|---|---|---|
| 0 | start bit = 0 | Host 发起命令帧 |
| 1 | transmission bit = 1 | 表示 Host-to-card |
| 2..7 | command index[5:0] | 6-bit 命令号 |
| 8..39 | argument[31:0] | 命令参数 |
| 40..46 | CRC7[6:0] | 对前 40 bit 的校验 |
| 47 | end bit = 1 | 帧结束 |

有了这张表，后面每 8 bit 分组才不会变成机械记忆。

## 2. `out_command_direction` 本质上是 CMD pad 的 OEN

CMD pad 是双向的。Host 发送命令时，它要作为输出；等待 card response 时，它要回到输入态。因此 `out_command_direction` 本质上就是 command pad 的输出使能。

课程把它拆成 posedge 和 negedge 两套方向信号，再用 `high_speed_clock` 选择最终输出相位。直接理由不是协议要求，而是板级 timing 修正。

高层逻辑：

```text
if current_state == STATE_SEND:
    direction = 1
else:
    direction = 0
```

但实现上它分成：

- `command_direction_pos`
- `command_direction_neg`
- `high_speed_clock ? pos : neg`

这样做的原因是：对端 SD 卡永远按时钟边沿采样。如果 PCB 走线或 IO delay 让某一边沿不满足 setup/hold，可以把输出相位整体平移半拍。

## 3. `high_speed_clock` 选择正沿还是负沿输出，不改变协议，只改变采样窗口

课程后半段专门解释为什么要在 `high_speed_clock` 下选择 posedge 或 negedge 输出。

![command send shift and timing choice](<./screenshots/任务080_AHB_sd_host控制器设计19/task80_01_command_send_shift_05m20s.jpg>)

这个选择的本质是：

| 模式 | 输出变化时刻 | 作用 |
|---|---|---|
| `pos` | SD clock 上升沿 | 默认相位 |
| `neg` | SD clock 下降沿 | 相比对端采样边沿平移半个周期 |

它不是“高速模式必须用 pos，低速模式必须用 neg”的硬编码规则，而是一个 timing 修正开关。课程提到的真实动机是板级 setup/hold：

- 如果对端在上升沿采样而当前输出过晚，可能 setup 不满足。
- 把输出改到下降沿，等价于提前半拍准备数据。
- 这样常能把原本踩不住的时序拉回安全范围。

这是典型的工程细节：协议逻辑看上去没变，真正问题出在芯片 pad 到卡座之间的物理延迟。

第一次看这张图，重点是相位选择：posedge/negedge 两套寄存输出改变的是卡端采样窗口，不改变 command frame 的 bit 内容。

## 4. 发送数据按“每 8 bit 装载一次，再逐拍移位”实现

课程里最核心的代码路径是 `command_for_send` 和后面的 shift register。实现不是直接写 48 路 mux，而是：

1. 先按 `in_has_send_bit` 所在区间，决定当前该装哪一个 8-bit 分组。
2. 每到一个 8-bit 边界，就把这一组装进 8-bit shift register。
3. 中间 7 拍持续左移，每拍把最高位送到 `out_sd_command`。

![command send grouping](<./screenshots/任务080_AHB_sd_host控制器设计19/task80_01_command_send_shift_05m20s_2.jpg>)

第二次复用同一张图时，不是重复看整体结构，而是只看 8-bit 分组如何把 `start/transmission/index/argument/CRC7/end` 映射到移位窗口。也就是说，同一张图第一次服务“什么时候输出”，第二次服务“输出哪 8 bit”。

课程解释的 bit 分组可以压成：

| bit 区间 | 内容 |
|---|---|
| 0..7 | `start + transmit + index[5:0]` |
| 8..39 | `argument[31:0]`，每 8 bit 一组 |
| 40..46 | CRC7 |
| 47 | end bit = 1 |

这里一个关键点是：`start bit` 和 `transmit bit` 已经被包含在最前 8 bit 里，所以前 40 bit 并不是“index + argument 38 bit”，而是“2 个协议头位 + 6 个 index + 32 个 argument”。

## 5. `command_for_send` 的存在既服务串行装载，也服务 CRC7 计算

课程特别指出 `command_for_send` 看起来和最终发送内容有一点重复，但它的价值很明确：既给 shift register 分组装载，也给 CRC7 提供稳定的输入序列。

这一点要看懂，否则会误以为代码“多绕了一层”。实际上这层中间表示有两个收益：

- 发送路径按 8-bit group 处理更规整。
- CRC7 直接复用同一套 bit 序列，不必重复从 index/argument 拆。

## 6. CRC7 只对前 40 bit 计算

本讲 CRC7 的结论很清楚：发送 command 时，前 40 bit 参与 CRC7 计算，后 7 bit 是计算结果，最后 1 bit 是 end bit。

![CRC7 logic](<./screenshots/任务080_AHB_sd_host控制器设计19/task80_02_crc7_logic_13m40s.jpg>)

所以：

| 区段 | 是否参与 CRC7 |
|---|---|
| `start bit` | 参与 |
| `transmit bit` | 参与 |
| `command index[5:0]` | 参与 |
| `argument[31:0]` | 参与 |
| CRC7 自身 | 不参与 |
| end bit | 不参与 |

课程里从代码和 PPT 两边都核了一遍，确认这是 40 bit，而不是有人容易误记的 38 bit 或 39 bit。

对 CRC7 的工程理解不需要走到数学证明，只要抓住：

- 它是一个线性反馈式移位寄存器结构。
- 输入每来 1 bit，寄存器更新一次。
- 最终 7 个寄存器位就是发给卡的 CRC7。

一个最小移位例子是：假设前 40 bit 的某一拍输入为 `din`，CRC7 寄存器不是简单左移，而是用最高位反馈和 `din` 做异或，再按多项式更新若干位。学习时不必背完整多项式，但要知道“每发出一个主体 bit，CRC7 同步更新一次”；如果只在最后对 40-bit bus 做组合计算，时序和面积会完全不同。

## 7. 串行发送时，最高位先出，后续通过左移逐 bit 推出

send shift 的工作节奏是：

```text
装载 8-bit group
  -> 当前最高位送到 out_sd_command
  -> 左移 1 位，低位补 0
  -> 下一拍继续送当前最高位
  -> 直到这 8 bit 发完
```

![command receive shift relation](<./screenshots/任务080_AHB_sd_host控制器设计19/task80_03_command_receive_shift_22m00s.jpg>)

课程里特别解释了“为什么每组要补一个 0”：因为本地 shift register 定成了固定 8 bit，发完最后一位后补 0 不会影响已经决定的输出窗口。

要点不是这个 0 本身，而是：本模块把 48-bit frame 切成了可管理的 8-bit 小块，降低了组合路径复杂度。

## 8. 本讲和任务81的关系是：这里发 bit，下一讲收 response

本讲的 send shift 结束后，CMD 线进入 card 驱动阶段，任务81的 receive shift 就开始从串行 CMD 上还原 response。

![long response capture preview](<./screenshots/任务080_AHB_sd_host控制器设计19/task80_04_long_response_capture_31m30s.jpg>)

![end command response path preview](<./screenshots/任务080_AHB_sd_host控制器设计19/task80_05_end_command_response_path_40m00s.jpg>)

所以这两讲必须连着看：

- 任务80解决“Host 怎么把命令发出去”。
- 任务81解决“Host 怎么把 response 收回来，并做 CRC 比对”。

## 工程检查清单

- `STATE_SEND` 期间 `out_command_direction` 必须有效，离开后必须回到输入态。
- 发送 bit 计数要和 `send_bit_count 0..47` 对齐，不能多发或少发。
- `start/transmit/index/argument` 的 40 bit 组成要和 CRC7 输入完全一致。
- `high_speed_clock` 的相位选择是 board timing 开关，不是协议逻辑开关。
- shift register 每 8 bit 装载一次，组边界不能和 `in_has_send_bit` 错位。
- CRC7 结果必须只占 bit[40:46]，end bit 单独保持 1。

## 最后速记

- command FSM 只决定节奏，send shift 才真正把 bit 推到 CMD 线上。
- `out_command_direction` 本质是 CMD pad 的 OEN。
- 48-bit command frame = 40-bit 主体 + 7-bit CRC7 + 1-bit end。
- 前 40 bit 参与 CRC7。
- `high_speed_clock` 用于半拍相位平移，修正板级 setup/hold。

## 复习与自测

1. send shift 模块和 command FSM 的分工是什么？  
   答：command FSM 决定何时进入发送状态、发送多少 bit；send shift 模块根据当前 bit 计数，把并行命令字段逐 bit 推到 CMD 线上。

2. 为什么 `out_command_direction` 必须和状态机联动？  
   答：CMD pad 是双向的。发送命令时要输出，等待 response 时要回到高阻输入态，否则会和 card 驱动冲突。

3. command frame 的前 40 bit 是什么？  
   答：`start bit + transmit bit + 6-bit command index + 32-bit argument`。

4. `high_speed_clock` 的作用是什么？  
   答：控制 CMD 输出相位选上升沿还是下降沿，相当于平移半拍，解决板级采样 setup/hold 问题。

5. CRC7 为什么只算前 40 bit？  
   答：CRC7 本身和 end bit 是命令帧尾部，计算时只覆盖 command 主体字段。


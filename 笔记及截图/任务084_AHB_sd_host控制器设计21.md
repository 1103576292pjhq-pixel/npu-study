# 84_AHB_sd_host控制器设计21

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：进入 `SD data FSM`，先把它的状态图、输入来源和上半段 RTL 跳转逻辑讲清楚，重点覆盖 `STOP/IDLE/WAIT_RECEIVE/RECEIVE` 这条读路径和 `WAIT_SEND` 的入口条件。
- 核心概念：`data_ready`、`data_direction`、`need_to_receive_bit`、`need_to_send_bit`、`need_to_receive_block`、`read_timeout`、`has_receive_bit`、`has_receive_block`、`transfer_complete`、`one_block_read_end`。
- 逻辑主线：data FSM 是数据面的总调度器，它不自己搬数据、不自己算 CRC，它只决定“现在该收数据、收 CRC、发数据、发 CRC、等下一块、还是整笔事务结束”。
- 最小主线：
  - `data_ready` 拉起 FSM，从 `STOP` 进入 `IDLE`。
  - `data_direction=0` 走读路径：`WAIT_RECEIVE -> RECEIVE -> RECEIVE_CRC -> ...`
  - `data_direction=1` 走写路径入口：`WAIT_SEND`。
  - 读路径在 `WAIT_RECEIVE` 里既要等 start bit，也要防 read timeout。
  - bit 计数和 block 计数是两个层次，不能混。

### 2. 概念地图

| 层级 | 对象 | 作用 | 易错点 |
|---|---|---|---|
| 启动条件 | `data_ready` | 让 data FSM 离开 `STOP` | 不是只要命令发了就一定 ready |
| 路径选择 | `data_direction` | 决定读路径还是写路径 | 读写对 `data0` 的解释不同 |
| bit 边界 | `need_to_receive_bit`、`need_to_send_bit` | 控制一块数据内部收/发多少 bit | 1-bit 和 4-bit 总线计数不同 |
| block 边界 | `need_to_receive_block` | 控制整笔事务有多少块 | 完成一个 block 不等于整笔传输结束 |
| 等待逻辑 | `WAIT_RECEIVE`、`read_timeout_count` | 等 start bit 或报 timeout | start bit 检测和 timeout 要并行存在 |
| 结束标志 | `transfer_complete`、`one_block_read_end` | 告诉外部一个 block 或整笔事务结束 | 两者作用不同，不能互换 |

### 3. 最短学习路径

1. 先把 data FSM 当作 command FSM 的数据侧版本，但它比 command FSM 多一层 block 概念。
2. 再明确两个计数器层次：bit counter 管一块内部，block counter 管整笔事务。
3. 最后抓住 `data_ready` 的来源和 `WAIT_RECEIVE` 的 timeout 行为。

## 全视频地图

| 阶段 | 内容 | 关键判断 |
|---|---|---|
| 00:00-10:00 | 回顾 data FSM 状态图 | 数据路径比 command 路径更复杂，因为有 block 与 CRC |
| 10:00-18:30 | 读路径状态：`WAIT_RECEIVE -> RECEIVE -> RECEIVE_CRC` | 收到 start bit 才进入正式接收 |
| 18:30-24:30 | 写路径入口和图中已知错误 | `WAIT_SEND` 条件图上有手误，代码为准 |
| 24:30-33:30 | 接口输入来源：`data_ready/data_direction/need_to_*` | 大多数来自 SDIF 配置或 FIFO 状态 |
| 33:30-43:30 | `data_ready` 来源与读写入口条件 | `data_ready` 不是固定一拍逻辑，而是条件组合 |

## 1. data FSM 是数据面的总调度器，不直接搬数据

课程一开始就把 data FSM 的定位说清楚了：它不直接发送数据、不直接接收数据，也不直接计算 CRC；真正做这些事的是 data send shift、data receive shift 和各自的 CRC 逻辑。data FSM 负责给它们分配状态窗口。

画面核对：01:10-03:36，课程从状态图回顾 data FSM 的整体跳转。

![data fsm overview](<./screenshots/任务084_AHB_sd_host控制器设计21/task84_00_data_fsm_code_01m30s.jpg>)

可以把 data FSM 理解成“数据面的时序和阶段经理”：

| 状态机负责 | 小弟模块负责 |
|---|---|
| 现在该收还是该发 | 真正从 DAT 线收 bit 或往 DAT 线发 bit |
| 什么时候开始计 bit | 真正移位、拼并行数据 |
| 什么时候进入 CRC 阶段 | 真正计算或接收 CRC16 |
| 什么时候一个 block 结束 | 真正完成该 block 的数据位处理 |

## 2. `data_ready` 是 data FSM 的启动条件，不是固定脉冲

`data_ready` 不是写死的一拍 start，而是由 `SDIF` 输出的组合条件。课程明确追溯了来源：

- 如果是读方向：command 已结束，可以开始等卡在 DAT 线上回数据。
- 如果是写方向：FIFO 已经存满一个 block，才允许开始发。

也就是：

```text
data_ready =
    data_present &&
    (
      (direction == read  && end_command) ||
      (direction == write && sd_fifo_full)
    )
```

这是本讲最关键的输入之一。它解释了为什么 data FSM 不能简单跟着 command FSM 同步启动。

## 3. `STOP -> IDLE` 只取决于 `data_ready`

在 RTL 上半段，`STOP` 状态几乎只做一件事：把各种使能和 flag 复位为 0，并等待 `data_ready`。

一旦 `data_ready=1`：

- 进入 `IDLE`
- 再由 `data_direction` 决定是走读路径还是写路径

这个结构的价值是把“是否有数据事务”与“具体怎么收/发”分离开。

## 4. 读路径先进入 `WAIT_RECEIVE`，等 DAT start bit

当 `data_direction=0` 时，FSM 从 `IDLE` 进入 `WAIT_RECEIVE`。这时还没有真正开始收数据，它做的是等待 DAT0 上的 start bit。

课程里的解释和 command response 很像：

- 对端还没开始发 block，DAT0 保持 idle 高。
- 一旦 DAT0 拉成 0，就认作 data start bit 到来。
- 这时 FSM 才真正进入 `RECEIVE`。

![data receive path](<./screenshots/任务084_AHB_sd_host控制器设计21/task84_02_receive_count_logic_18m10s.jpg>)

这个设计避免了“命令一结束就盲收数据”的错误。读数据的延迟不像 command response 是固定 64 cycle；它可能更长，所以要有独立的等待状态。

## 5. `WAIT_RECEIVE` 里有两个并行判断：block 是否已收完、是否 timeout

`WAIT_RECEIVE` 的代码里有一组优先级判断：

1. 是否已经达到 `need_to_receive_block`
2. 是否 read timeout
3. 是否检测到 start bit
4. 否则继续 wait，并拉起 timeout counter enable

这说明它不是简单等待一个条件，而是“边等边裁决”。

如果 `need_to_receive_block=0`，它会立刻把这笔事务视为完成并回到 `STOP`。课程把这当成极端配置错误场景：软件如果把要收的 block 数配成 0，那么 data FSM 再怎么启动也不会真正去收数据。

如果 timeout 先到，就拉起 `out_read_timeout_error`，并结束事务。

## 6. `read_timeout` 是可配的，不像 command response timeout 固定 64 cycle

这点课程强调得很明确：

- command 等 response 的 timeout 是固定 64 cycle
- data 等 block start 的 timeout 来自寄存器配置

这很合理，因为数据面等待时间受 card 内部准备、block 长度、模式等影响，比 command response 更适合做软件可配。

![crc timeout relation](<./screenshots/任务084_AHB_sd_host控制器设计21/task84_03_crc_compare_27m50s.jpg>)

但是课程还指出一个值得注意的问题：当前实现里 timeout counter 不会在每次成功收到一个 block 后自动清零，而是可能跨多个 block 累加，直到整笔读传输结束或真正 timeout 才清掉。这意味着它更像“本次事务累计等待时间”，而不是“每块独立等待时间”。

这未必一定错，但必须知道它的语义，否则软件配置 timeout 时会误判余量。

## 7. `RECEIVE` 状态里，1-bit 和 4-bit 总线的 bit 计数完全不同

进入 `RECEIVE` 后，data FSM 会根据 `data_width` 判断使用哪个计数边界：

| 总线宽度 | 每拍接收 bit 数 | 对 `has_receive_bit` 的要求 |
|---|---|---|
| 1-bit | 1 | 计满 `need_to_receive_bit` |
| 4-bit | 4 | 计满 `need_to_receive_bit/4` |

课程举的例子很直观：如果一块是 `100 byte`，那么：

- 总 bit 数是 `800`
- 1-bit 总线需要 `800 cycle`
- 4-bit 总线只需要 `200 cycle`

![receive count logic](<./screenshots/任务084_AHB_sd_host控制器设计21/task84_02_receive_count_logic_18m10s_2.jpg>)

这就是为什么模块里同时存在 `need_to_receive_bit` 和类似“四分之一”计数路径。不是重复定义，而是为了适配不同总线宽度下的节拍数。

## 8. bit 计数和 block 计数是两个层次

读路径里有两个完全不同的“完成”：

| 完成对象 | 对应计数 | 作用 |
|---|---|---|
| 一个 block 内的数据位收完 | `has_receive_bit` | 进入 `RECEIVE_CRC` |
| 本次事务所有 block 收完 | `has_receive_block` | 回到 `STOP`，置 `transfer_complete` |

如果把两者混起来，就会犯典型错误：

- 收完一块就误以为整笔事务结束
- 多块传输里没法决定是否继续回到 `WAIT_RECEIVE`

## 9. 课程图里有两个需要以代码为准的点

本讲明确提了两个图和代码不完全一致的点：

1. 写路径图上 `WAIT_SEND` 的判断条件里有手误，代码为准。
2. 图里没有把 `SD FIFO FULL` 的判断明确画进 `WAIT_SEND`，但代码里这是必须条件。

所以这一批笔记里要保留一个原则：PPT 先帮助理解，最终以 RTL 为准，尤其是状态边界和具体条件判断。

## 工程检查清单

- `data_ready` 的来源是否正确区分了读方向和写方向。
- `STOP -> IDLE` 是否只在 `data_ready=1` 时发生。
- 读路径是否只有在检测到 DAT start bit 后才进入 `RECEIVE`。
- `read_timeout` 是否是可配寄存器值，而不是硬编码。
- timeout counter 是否按设计意图在每块后清零，还是跨 block 累加。
- `has_receive_bit` 和 `has_receive_block` 是否分别控制 block 内完成和整笔事务完成。
- 1-bit 与 4-bit 总线下的计数边界是否一致换算。

## 最后速记

- data FSM 负责阶段调度，不直接搬数据。
- `data_ready` 是数据事务入口，来自 SDIF 配置和 FIFO/command 条件。
- 读路径先 `WAIT_RECEIVE`，再 `RECEIVE`。
- `read_timeout` 是可配的，和 command response timeout 不一样。
- bit 计数管单块，block 计数管整笔事务。

## 复习与自测

1. 为什么 data FSM 不能在 command 一结束就直接开始收数据？  
   答：因为 card 还没一定在 DAT 线上给出 start bit。必须先进入 `WAIT_RECEIVE`，检测到 DAT start bit 后才能进入正式接收。

2. `data_ready` 在读和写方向分别代表什么？  
   答：读方向表示 command 已完成，可以开始等 card 回数据；写方向表示 FIFO 已经存满一个 block，可以开始发数据。

3. `read_timeout` 和 command response timeout 的区别是什么？  
   答：command response timeout 固定 64 cycle；`read_timeout` 是数据面等待 block start 的可配超时。

4. 为什么需要同时有 bit 计数和 block 计数？  
   答：bit 计数决定一个 block 内部何时收完数据并转到 CRC 阶段；block 计数决定整笔多块事务何时真正结束。

5. 4-bit 总线为什么能明显缩短接收时间？  
   答：每拍收 4 bit，而不是 1 bit，所以达到同样总 bit 数所需 cycle 约为 1-bit 模式的四分之一。


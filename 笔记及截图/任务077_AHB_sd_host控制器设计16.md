# 77_AHB_sd_host控制器设计16

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：继续阅读 `SDIF`，把任务 76 的寄存器读写推进到“寄存器值如何真正驱动后级 FSM、DMA、中断和 response 保存”。
- 核心概念：block size 两拍同步、`data_fsm_ready`、`dma_en` clear、DMA finish 边沿检测、`one_block_read_end`、`stop_clock`、`command_state_send`、interrupt status latch、status clear、response capture。
- 逻辑主线：一个控制器的可靠性不在于寄存器能写进去，而在于跨域配置、一次性事件、level 状态、中断屏蔽和清除时机都能形成闭环。
- 最小主线：
  - HCLK 域配置要稳定送到 SD clock 域。
  - data FSM ready 必须按方向、命令阶段和 FIFO 条件生成。
  - DMA finish、one block read end、command send 都要转成可靠脉冲。
  - 中断状态要从短脉冲锁存成软件可读 level。
  - 新事务启动前清掉旧事务状态，response 完成后才更新 response 寄存器。

### 2. 概念地图

| 概念层级 | 信号/逻辑 | 来源 | 作用 | 易错点 |
|---|---|---|---|---|
| 跨域配置 | `block_size -> block_length`、`block_number` | AHB/HCLK 写寄存器 | SD clock 域 data FSM 计数 | 不能随意在事务中改配置 |
| 数据启动 | `data_fsm_ready` | `data_present`、direction、FIFO/command 状态 | 启动 data FSM | 无数据命令不能启动 data FSM |
| DMA 闭环 | `dma_finish_interrupt`、`clear_dma_en`、`stop_clock` clear | DMA module | 表示搬运完成并恢复读路径 | level 不转 pulse 会重复触发 |
| FIFO 反压 | `one_block_read_end`、`stop_clock` set | data receive path | 一块读完后等待 DMA 搬走 | 不停钟可能 FIFO 溢出 |
| 命令握手 | `command_state_send` 清 `command_ready_pre` | command FSM state | 防止一次配置重复发命令 | ready 粘住会重复驱动 FSM |
| 状态锁存 | end/timeout/CRC/complete | 后级事件 pulse | 软件可读 status | pulse 不锁存 CPU 可能读不到 |
| 响应保存 | response0-3 capture | `end_command_response` | CPU 读 response | 未完成响应不能提前保存 |

### 3. 最短学习路径

1. 先看配置如何从寄存器变成后级输出，不要停在“寄存器写入成功”。
2. 再抓三类脉冲：DMA finish、one block read end、command state send。
3. 最后理解中断状态：事件可以是一拍，status 必须保持到软件可读或新事务清除。

### 4. 全讲结构地图

| 阶段 | 代码/画面主线 | 必须学会的判断 |
|---|---|---|
| 00:00-05:30 | block size/block number 同步 | 分频时钟也要按跨域/稳定性处理 |
| 05:30-10:30 | `data_fsm_ready` | 读写方向决定 ready 条件完全不同 |
| 10:30-17:30 | DMA finish interrupt 与 `stop_clock` clear | DMA 搬完后才能恢复被暂停的数据流 |
| 17:30-23:00 | `one_block_read_end` 和 command send pulse | 一块读完要停钟；命令开始发送要清 ready |
| 23:00-34:00 | interrupt mask、end command/response latch | status 由脉冲变 level，mask 决定是否上报 |
| 34:00-46:00 | CRC/timeout/transfer complete、response capture | 错误和响应必须保持到 CPU 可读 |

## 1. HCLK 写入的 block 参数要稳定进入 SD clock 域

`block_size` 是 CPU 通过 AHB 写入的寄存器，处在 HCLK 域；数据接收/发送计数依赖 SD clock。课程里能看到 RTL 用 SD clock 打两拍，把 `block_size` 变成 `block_length`。

![block size sync code](<./screenshots/任务077_AHB_sd_host控制器设计16/task77_docx_001.jpeg>)

这里的重点不是“两个名字其实一样”，而是工程上不能让 SD clock 域直接使用一个可能在 HCLK 域变化的配置。虽然 SD clock 往往由 HCLK 分频而来，不是完全异步，但数据路径仍需要在事务开始前看到稳定值。

同类参数还包括 block number。block size 决定一块内部收多少 byte，block number 决定本次多块事务有多少块。没有 block number，后级就不知道什么时候生成停止命令或 transfer complete。

这些参数必须在事务启动前冻结。否则会出现“尺子在量布时突然变长”的问题：data FSM 按旧 block size 收到一半，软件又写入新 block size，计数边界就不再对应本块数据。驱动规范应要求先配置 block 参数，再触发 command/data ready；RTL 侧至少要保证 data FSM 使用的是进入事务时稳定采样的值。

## 2. `data_fsm_ready` 是数据链路启动门，不能只看 command 寄存器

`data_fsm_ready` 只有在 `data_present=1` 时才可能有效。无数据命令即使 command 结束，也不能启动 data FSM。

![data fsm ready code](<./screenshots/任务077_AHB_sd_host控制器设计16/task77_docx_004.jpeg>)

读写方向的 ready 条件不同：

| 方向 | ready 依赖 | 原因 |
|---|---|---|
| Host 写 SD 卡 | FIFO 已被 DMA 写入可发送数据 | data send 需要从 FIFO 取数据推到 DAT 线 |
| Host 读 SD 卡 | command 已发完，DAT 线可等待数据 start bit | data receive 要在命令响应阶段后启动 |
| 无数据命令 | ready 必须为 0 | 只有 CMD 阶段，没有 DAT 阶段 |

课程里强调：如果 `data_present` 为 0，状态机 ready 永远不应起来；否则整条 SD 数据读写路径会在没有数据事务时误启动。

`data_fsm_ready` 的分支可以这样判断：

```text
if data_present == 0:
    data_fsm_ready = 0
elif direction == write_to_card:
    wait FIFO has data and command phase permits data
elif direction == read_from_card:
    wait command phase reaches data window
```

这里的 ready 不是 command ready 的影子。它是 command 阶段、方向和 FIFO 条件共同打开的一扇门；门没开时，后级 data FSM 不应靠猜测启动。

## 3. `dma_en` 被 clear 是一次 DMA 请求完成闭环

`dma_en` 在任务 76 中已经说明是启动请求。任务 77 继续强调：普通 DMA 字段只由 AHB 写改变，而 `dma_en` 会同时被 AHB 写置位、被 `clear_dma_en` 清零。

![dma en clear logic](<./screenshots/任务077_AHB_sd_host控制器设计16/task77_docx_008.jpeg>)

这个结构形成一次请求闭环：

```text
CPU 写 dma_en=1
  -> DMA 接收请求并开始搬运
  -> DMA 或控制逻辑产生 clear_dma_en
  -> SDIF 清 dma_en，等待下一次软件请求
```

若没有 clear，下一次 DMA 请求和上一次请求无法区分；若只打一拍 enable，DMA 可能没采到启动信号。

## 4. DMA finish 要做边沿检测，并清除 `stop_clock`

DMA finish interrupt 从 DMA 模块返回。课程中看到它被打多拍，再做上升沿检测，生成当前模块使用的脉冲。

![dma finish edge detect](<./screenshots/任务077_AHB_sd_host控制器设计16/task77_docx_010.jpeg>)

脉冲化的原因有两个：

1. 中断状态只需要记录一次事件，不应因为输入 level 保持而反复触发。
2. `stop_clock` 这类控制需要在 DMA 完成那一刻清除，而不是被一个长 level 多次覆盖。

读卡链路的闭环是：

```text
SD data receive 写满 FIFO 或读完一块
  -> SDIF 置 stop_clock，暂停 SD clock
  -> DMA 把 FIFO 数据搬到 AHB 内存
  -> dma_finish_interrupt pulse
  -> SDIF 清 stop_clock，SD clock 恢复
```

![dma finish interrupt and stop clock](<./screenshots/任务077_AHB_sd_host控制器设计16/task77_02_dma_finish_interrupt_11m30s.jpg>)

如果 DMA finish 没有清 `stop_clock`，读多块数据会在第一块之后停住；如果没有 stop clock，FIFO 可能在 DMA 没搬完前继续被写入。

把这个闭环看成“蓄水池和水泵”更直观：SD 卡侧 clock 是进水阀，FIFO 是水池，DMA 是水泵。水池满时先关进水阀，水泵继续抽水；水位降下来再开阀。错误设计要么忘关阀导致溢出，要么把水泵也关掉导致永远排不空。

## 5. `one_block_read_end` 负责把数据块边界转成 FIFO 反压

`one_block_read_end` 是 data receive 侧来的输入，表示一个 block 已经读完。SDIF 对它做多拍延迟和边沿检测，然后设置 `stop_clock`。

![one block read end logic](<./screenshots/任务077_AHB_sd_host控制器设计16/task77_docx_016.jpeg>)

这条逻辑把“协议上的一个 block 结束”转成“内部数据通路的反压动作”。读卡时，数据块已经进入 FIFO，但系统内存还没拿到这块数据；停 clock 给 DMA 时间搬运。

要注意，`one_block_read_end` 不是整笔传输完成。多块读里它每块都会出现，真正的整笔完成还要看 block count、停止命令和 transfer complete。

## 6. command FSM 开始发送后必须清掉 `command_ready_pre`

软件写完命令配置后，`SDIF` 给 command FSM 一个 ready/start 信号。这个信号不能一直保持高，否则一条命令会被重复驱动。课程里通过 `command_state_send` 打拍和边沿检测产生脉冲，用来清 `command_ready_pre`。

![command ready clear](<./screenshots/任务077_AHB_sd_host控制器设计16/task77_docx_020.jpeg>)

握手关系如下：

```text
CPU 配置命令
  -> SDIF 置 command_ready_pre
  -> command FSM 进入 SEND
  -> SDIF 检测 command_state_send pulse
  -> 清 command_ready_pre
  -> 等下一次 CPU 配置命令
```

这个点和任务 76 的“写 argument 触发 command ready”要一起看：软件触发一次，FSM 消费一次，SDIF 撤销一次。三步缺一，都会出现重复发命令或命令不发。

## 7. 中断输出是 status 与 mask 的组合，status 本身必须锁存

中断输出通常可表达为：

```verilog
interrupt = |(interrupt_status & ~interrupt_mask);
```

mask 为 1 表示屏蔽，不产生 interrupt 输出；但 status 仍应置位，软件轮询时仍能看到。

![interrupt status and mask](<./screenshots/任务077_AHB_sd_host控制器设计16/task77_docx_024.jpeg>)

课程中把多个 status 放在一起讲：`end_command_response`、`end_command`、`transfer_complete`、`read_timeout_error`、`send_crc_error`、`receive_crc_error`、`response_timeout` 等。它们有共同模式：输入可能是脉冲，SDIF 内部锁存为 level；新命令准备开始时清掉旧状态。

这里要看 mask 的边界：mask 只屏蔽中断输出，不屏蔽 status 置位。软件即使关闭某个中断，也应能轮询看到事件；否则 mask 会从“勿打扰开关”变成“抹掉监控记录”。

状态输出可以分三层：

| 层 | 例子 | 行为 |
|---|---|---|
| 事件脉冲 | `end_command_response_pulse`、`dma_finish_edge` | 后级一拍事件 |
| 粘性状态 | interrupt status bit | 保持到 clear 或下一事务 |
| 中断输出 | `status & ~mask` 汇总 | 只决定是否打断 CPU |

## 8. 状态清除时机是“下一次命令准备开始”，不是随便清

`end_command_response` 的处理很典型：后级输入来一个完成事件，SDIF 把它锁存为 status bit；等下一次 `command_ready_pre` 到来时，清掉上一次状态。

![end command response latch](<./screenshots/任务077_AHB_sd_host控制器设计16/task77_docx_026.jpeg>)

清除时机的含义：

| 时机 | 作用 | 风险 |
|---|---|---|
| 事件一来就清 | 不合格 | CPU 可能读不到 |
| 软件 clear 或下一次命令开始清 | 合格 | 旧状态不会污染新事务 |
| 永远不清 | 不合格 | 新旧事务无法区分 |

`end_command`、`transfer_complete`、CRC error、timeout 都遵循类似逻辑。

![transfer complete and status latch](<./screenshots/任务077_AHB_sd_host控制器设计16/task77_docx_030.jpeg>)

错误状态尤其要保持。例如 response timeout 只在 64-cycle 计数到边界时出现一个事件，但 CPU 可能很多拍之后才读状态寄存器；没有锁存，驱动无法知道失败原因。

![timeout and crc latch](<./screenshots/任务077_AHB_sd_host控制器设计16/task77_docx_041.jpeg>)

## 9. response 寄存器只在命令响应完整后更新

`response0-3` 不应在命令发完时更新，而应在 `end_command_response` 后锁存输入 response。课程中能看到 response capture 逻辑：完成事件到来后，把 response 输入写进寄存器，之后保持到下一次响应覆盖。

![response capture logic](<./screenshots/任务077_AHB_sd_host控制器设计16/task77_docx_055.jpeg>)

这保证软件任何时候读 response 寄存器，都读到最近一次完整响应，而不是 CMD 线移位中的半成品。

## 工程检查清单

- block size / block number 是否在 SD clock 域稳定使用，软件是否避免事务中途改配置。
- `data_fsm_ready` 是否只有 `data_present=1` 时才可能有效。
- 读方向和写方向的 ready 条件是否分别对应 command end、FIFO full/empty。
- `dma_en` 是否写 1 后保持，并由 `clear_dma_en` 清掉。
- DMA finish、one block read end、command state send 是否做边沿检测。
- `stop_clock` 是否由 block read end 置位，由 DMA finish 清除。
- 中断 status 是否锁存，mask 是否只控制输出。
- 旧 status 是否在下一次命令准备开始或软件 clear 时清除。
- response 是否只在 `end_command_response` 后保存。

## 最后速记

- 任务 77 的核心是“事件变状态，状态可读，下一次事务前清除”。
- `data_fsm_ready` 不是命令写入的影子，它是方向、FIFO 和命令阶段的组合条件。
- `stop_clock` 是读 FIFO 反压机制，和 DMA finish 构成闭环。
- `command_ready_pre` 必须被 command send 消费后清掉。
- 中断 mask 不等于 status 不发生。
- response 寄存器保存完整响应，不保存移位过程。

## 复习与自测

1. 为什么 `one_block_read_end` 会置 `stop_clock`？  
   答：一块数据进入 FIFO 后，需要给 DMA 时间把 FIFO 数据搬到内存；停 SD clock 可以阻止卡继续按 clock 输出数据，避免 FIFO 溢出。

2. `dma_finish_interrupt` 为什么要做边沿检测？  
   答：它可能是 level 或持续多拍信号；边沿检测可生成一次性 pulse，用于置状态、清 stop_clock 或产生中断，避免重复触发。

3. `command_ready_pre` 不清会造成什么问题？  
   答：command FSM 会持续看到 ready，高概率重复发送同一条命令，或无法区分下一次软件配置。

4. 为什么 status 要保持到下一次命令开始才清？  
   答：CPU 需要时间读取上一次事务结果；下一次命令开始前清掉旧状态，能避免旧结果污染新事务。

5. `end_command` 和 `transfer_complete` 为什么不是同一个状态？  
   答：`end_command` 只表示命令阶段结束；带数据命令还要等 DAT 数据传输和 DMA/FIFO 处理完成，才能置 `transfer_complete`。

6. response 寄存器为什么不能在 `end_command` 时更新？  
   答：`end_command` 只代表命令发完，若命令需要 response，此时响应还没有完整接收；必须等 `end_command_response`。


# 85_AHB_sd_host控制器设计22

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：继续 `SD data FSM` 的 RTL，下半段重点落在 `WAIT_SEND/SEND/SEND_CRC/SEND_END_BIT/RECEIVE_CRC_STATUS/SEND_BUSY`，也就是完整写路径和块间循环逻辑。
- 核心概念：`need_to_send_bit`、左移三位替代乘 8、`WAIT_SEND` 依赖 `SD FIFO FULL`、`SEND_Z/SEND_P/SEND_START_BIT`、`SEND_CRC`、`RECEIVE_CRC_STATUS`、`SEND_BUSY`、`has_send_block`、`transfer_complete`。
- 逻辑主线：写路径不是命令一发完就往 DAT 线上推数据，它必须先等 FIFO 存满一块、再连续发完整 block、接着发 CRC16、再收 card 返回的 CRC status，最后判断是否还有下一块。
- 最小主线：
  - byte 数先扩成 bit 数，避免乘法器。
  - `WAIT_SEND` 的前提是 FIFO 已经满一块，并且 card 不 busy。
  - 一旦开始发，一个 block 必须连续发完。
  - 发完数据后再发 CRC16，再收 CRC status。
  - `SEND_BUSY` 决定是整个事务完成，还是回去发下一块。

### 2. 概念地图

| 层级 | 对象 | 作用 | 易错点 |
|---|---|---|---|
| 位宽扩展 | `need_to_send_bit = byte_count << 3` | 把 byte 数转成 bit 数 | 不要在 RTL 里无谓上乘法 |
| 发起条件 | `SD FIFO FULL`、`data0 ready` | 判断能否开始发一整块 | 没有满一块就不能开送 |
| 发包阶段 | `SEND_Z/SEND_P/SEND_START_BIT/SEND` | 发送 start 和 block 数据 | 不是每个阶段波形都明显不同，但状态上必须保留 |
| CRC 阶段 | `SEND_CRC`、CRC count | 发 16-bit CRC16 | CRC16 是固定长度，不依赖配置 |
| 回执阶段 | `RECEIVE_CRC_STATUS` | 收 card 返回的 3-bit/4-bit status | 图上少了等待 start bit 的状态，代码实现有风险 |
| 块循环 | `SEND_BUSY`、`has_send_block` | 判断回 stop 还是回 `WAIT_SEND` | 每完成一个 block 只能加一次 block 计数 |

### 3. 最短学习路径

1. 先把写路径和上一讲读路径完全分开看。
2. 再抓住 `WAIT_SEND` 的两个前提：FIFO 满一块，card 不 busy。
3. 最后看 block 间循环：发完一块后不是立刻结束，而是先收 CRC status，再判断是否还有下一块。

## 全视频地图

| 阶段 | 内容 | 关键判断 |
|---|---|---|
| 00:00-03:00 | byte 转 bit、状态机框架 | 左移三位是资源友好的设计 |
| 03:00-16:00 | `STOP/IDLE/WAIT_RECEIVE/RECEIVE` 回顾 | 为下半段写路径做衔接 |
| 16:00-31:30 | `WAIT_SEND -> SEND_Z -> SEND_P -> SEND_START_BIT -> SEND` | 开始发之前必须保证 FIFO 满和 card ready |
| 31:30-40:30 | `SEND_CRC` | CRC16 固定 16 cycle |
| 40:30-45:30 | `RECEIVE_CRC_STATUS` 与 `SEND_BUSY` | 块结束后判断状态和是否继续发下一块 |
| 45:30-48:40 | `one_block_read_end`、`flop out` 等收尾 | 单拍脉冲和模块输出时序意识 |

## 1. `need_to_send_bit` 用左移三位，而不是乘 8

课程开头先讲了一个很工程化的点：`need_to_send_bit` 来自 byte 数乘 8，但实现写成左移三位，而不是乘法。

```text
need_to_send_bit = need_to_send_byte << 3
```

理由很直接：

- 乘法器资源更重
- 左移基本不花额外逻辑
- 这里是固定乘 8，没有必要依赖综合器再优化

这类小选择在控制器 RTL 里非常常见：功能一样，但资源和时序更稳。

## 2. `WAIT_SEND` 的核心前提是 FIFO 已经存满一个 block

写路径和读路径最大的不同，是写数据不能边取边等等看。SD 协议一旦开始在 DAT 线上发一个 block，中间不能停顿去等 FIFO 补数据。

所以 `WAIT_SEND` 的第一前提不是 card ready，而是：

```text
SD FIFO FULL == 1
```

课程明确指出：

- 图上没有把这个条件画清楚
- 代码里它是真正存在且必须存在的判断

![data send path](<./screenshots/任务085_AHB_sd_host控制器设计22/task85_02_dma_read_write_flow_16m40s.jpg>)

如果 FIFO 还没满一块就启动发送，会出现两个问题：

1. data send shift 中途没数据可取
2. DAT 线协议要求连续发送一个 block，中途停顿会直接破坏协议

## 3. `WAIT_SEND` 还要看 card 端 `data0` 是否 ready

FIFO 满一块只是 host 这一侧准备好了，还不够。card 这一侧还可能 busy，因此课程继续强调 `data0` 必须等于 1，才能真正进入发送。

也就是：

```text
if fifo_full && data0_ready:
    next_state = SEND_Z
else:
    stay WAIT_SEND
```

这里和上一讲读路径刚好对称：

- 读路径：等对方发 start bit 0
- 写路径：等对方从 busy 释放成可接收状态

## 4. `SEND_Z/SEND_P/SEND_START_BIT` 是写路径前导阶段

课程图里保留了 `SEND_Z`、`SEND_P`、`SEND_START_BIT` 这些前导状态。波形上看，它们未必每个都特别显眼，但状态机里保留它们能明确协议边界：

- `SEND_Z` / `SEND_P`：写路径开始前的过渡
- `SEND_START_BIT`：正式把 data start bit 拉下去
- `SEND`：真正连续推出 block 数据

![fifo full empty handshake](<./screenshots/任务085_AHB_sd_host控制器设计22/task85_03_full_empty_handshake_26m20s.jpg>)

课程也说明了一个现实点：这些阶段在代码里有时只是很短的 1-cycle 过渡，并不是每个都需要很复杂的逻辑，但它们把状态语义讲清楚了。

## 5. `SEND` 状态里，1-bit 和 4-bit 总线的计数和上一讲完全对称

写路径的 bit 计数和读路径一模一样，只是方向反过来：

| 总线宽度 | 每拍发 bit 数 | 完成条件 |
|---|---|---|
| 1-bit | 1 | `has_send_bit == need_to_send_bit` |
| 4-bit | 4 | `has_send_bit == need_to_send_bit/4` |

课程再次用了“100 byte 例子”来帮助理解：

- 总 bit 数是 800
- 1-bit 模式需要 800 cycle
- 4-bit 模式需要 200 cycle

本讲真正要记住的不是数字，而是：宽度变化影响的是 bit counter 终点，不影响 block counter 的意义。

## 6. `SEND_CRC` 是固定 16 cycle，因为 data CRC 是 CRC16

command 路径的 CRC 是 7 bit；data 路径这里是 CRC16。所以 `SEND_CRC` 状态不需要从寄存器读取长度，直接固定 16 cycle 即可。

![dma finish interrupt? used as later stage marker](<./screenshots/任务085_AHB_sd_host控制器设计22/task85_04_dma_finish_interrupt_36m20s.jpg>)

逻辑上可以压成：

```text
enter SEND_CRC
  -> crc_count_en = 1
  -> count 0..15
  -> next_state = SEND_END_BIT / RECEIVE_CRC_STATUS
```

这和上一讲 `RECEIVE_CRC` 的结构是对称的，只是方向换成发送。

## 7. `RECEIVE_CRC_STATUS` 是当前实现里最需要警惕的点

课程直接指出一个设计风险：图和代码里，写路径在发完 end bit 之后，直接靠固定 interval count 去接收对方的 CRC status，没有额外插入“等待对方 start bit”的状态。

这意味着实现默认假设：

- card 会在固定若干 cycle 后返回 CRC status
- host 这边的计数刚好和对方返回节拍对齐

这个假设并不稳。更保险的做法应该是：

1. 先进入 `WAIT_CRC_STATUS`
2. 等对方 status start bit 到来
3. 再进入 `RECEIVE_CRC_STATUS`

课程给出的判断很明确：现在这种“只靠 interval count”的写法，规范性和鲁棒性都不如显式等待 start bit。

## 8. `SEND_BUSY` 决定整笔写事务是否结束

发完数据、发完 CRC、收完 status 后，不代表整笔写事务一定结束，只能说明“这一块已经处理完”。

`SEND_BUSY` 的职责是判断：

| 条件 | 结果 |
|---|---|
| `has_send_block == need_to_send_block - 1` | 整笔事务结束，回 `STOP`，拉 `transfer_complete` |
| 否则 | 还有下一块，回 `WAIT_SEND`，继续等 FIFO 满下一块 |

![end to end path](<./screenshots/任务085_AHB_sd_host控制器设计22/task85_05_end_to_end_path_45m20s.jpg>)

这里的 `-1` 很自然，因为 block counter 从 0 开始。

## 9. `has_send_block` 只能在一个 block 真正结束时加一次

课程特别强调：一个 block 结束后，`has_send_block_count_en` 只能给一拍，使 `has_send_block` 只加 1 次。

如果多给几拍，会出现：

- 明明只发完 1 个 block
- block counter 却加了 2 或 3
- 多块写事务提前结束

这也是状态机里“单拍脉冲”和“持续 level”必须严格区分的典型例子。

## 10. `one_block_read_end` 和 flop out 的收尾提醒

本讲最后还有两个值得保留的工程点：

1. `one_block_read_end` 之类信号本来就是单拍，打一拍更多是为了模块边界稳定和时序友好，不一定是为了重新造脉冲。
2. 大模块输出最好 `flop out`，避免超长组合路径直接跨模块外送。

这两个提醒都很实用：

- 前者是“什么时候需要脉冲整形，什么时候只是边界寄存”。
- 后者是“模块边界也要考虑时序，不是只看功能”。

## 工程检查清单

- `need_to_send_bit` 是否用移位而不是不必要的乘法器。
- `WAIT_SEND` 是否同时检查 FIFO 满一块和 card ready。
- 写路径一旦进入 `SEND`，一个 block 是否连续发完，没有中途停顿。
- `SEND_CRC` 是否固定 16 cycle，对应 CRC16。
- `RECEIVE_CRC_STATUS` 是否存在固定 interval 对齐风险，是否需要显式等待 start bit。
- `has_send_block` 是否每块只加一次。
- `SEND_BUSY` 是否正确区分“整笔事务结束”和“还有下一块”。
- 输出信号是否有必要 `flop out`，避免长组合路径跨模块传播。

## 最后速记

- 写路径的真正前提是 FIFO 已经满一块，不只是 command 发完。
- `WAIT_SEND` 同时受 FIFO 和 card busy 状态约束。
- `SEND` 发完整块，`SEND_CRC` 再发 CRC16。
- `RECEIVE_CRC_STATUS` 当前实现依赖固定对齐，鲁棒性不如显式等 start bit。
- `SEND_BUSY` 决定是整笔结束还是继续发下一块。

## 复习与自测

1. 为什么 `need_to_send_bit` 要用左移三位实现？  
   答：因为 byte 转 bit 本质是乘 8，左移三位资源更轻、更直接，不需要无谓引入乘法逻辑。

2. 写路径为什么必须先等 `SD FIFO FULL`？  
   答：因为一个 block 的数据在 DAT 线上必须连续发送；如果 FIFO 还没满，中途没数据会直接破坏协议。

3. `SEND_CRC` 为什么固定 16 cycle？  
   答：data CRC 使用的是 CRC16，长度固定，不像 block 数据长度那样由配置决定。

4. 当前 `RECEIVE_CRC_STATUS` 的风险是什么？  
   答：它依赖固定 interval count 去对齐 card 返回的 CRC status，没有显式等待对方 start bit，鲁棒性较差。

5. 为什么 `has_send_block` 只能在每块结束时加一次？  
   答：因为它表示已经完成的 block 数，多加一次就会把多块事务提前结束，破坏整笔传输边界。


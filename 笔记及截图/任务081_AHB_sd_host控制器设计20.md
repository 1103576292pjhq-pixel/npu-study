# 81_AHB_sd_host控制器设计20

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：进入 `command receive shift register`，把 card 从 CMD 线串行返回的 response 收成并行寄存器，并同时接收 CRC7、在本地重算 CRC7，再比较是否出错。
- 核心概念：`in_serial_command`、`in_has_receive_bit`、`in_long_response`、`response0-3`、`receive_crc`、`generate_crc`、`command_receive_crc_error`。
- 逻辑主线：任务80负责把 command 发出去，任务81负责把 response 收回来；它的本质是串并转换加 CRC 校验。
- 最小主线：
  - 短 response 收 32-bit status 到 `response0`。
  - 长 response 收 120-bit payload 到 `response0-3`，高位空出的部分补 0。
  - `receive_crc` 收 card 发回的 7-bit CRC7。
  - `generate_crc` 用收到的有效 response bit 本地重算 CRC7。
  - 两者比较后给出 `command_receive_crc_error`。

### 2. 概念地图

| 层级 | 对象 | 作用 | 易错点 |
|---|---|---|---|
| 状态输入 | `in_current_state`、`in_has_receive_bit` | 指示当前是否处于 `STATE_RECEIVE`、已收到第几 bit | start bit 已在进入 `STATE_RECEIVE` 前被用来判定 |
| 串行输入 | `in_serial_command` | 实际收到的 CMD line response bit | 这里收的是 response，不是命令 |
| response 缓冲 | `response0-3` | 还原短/长 response 内容 | 长 response 只用到 120 bit，不是 128 bit 全满 |
| CRC 接收 | `receive_crc` | 保存 card 回送的 7-bit CRC7 | 接收窗口必须和 response 末尾对齐 |
| CRC 重算 | `generate_crc` | 用收到的有效 bit 本地重算 | 是否包含 start bit 要说清 |
| 错误输出 | `command_receive_crc_error` | 告诉 SDIF 本次 response CRC 是否错误 | 判定时机必须在 CRC 全收完之后 |

### 3. 最短学习路径

1. 先分短 response 和长 response 两条收包路径。
2. 再看 CRC：先收对方发来的 CRC，再本地重算 CRC。
3. 最后看 off-by-one：start bit 是否已经在进入 `STATE_RECEIVE` 前被消费。

## 全视频地图

| 阶段 | 内容 | 关键判断 |
|---|---|---|
| 00:00-10:00 | 回顾 receive 模块角色与接口 | 这里收的是 response，不是 command |
| 10:00-24:30 | 短 response/长 response 收包窗口 | 短 response 取 32 bit，长 response 取 120 bit |
| 24:30-29:30 | `receive_crc` 接收对方 CRC7 | 接收窗口要和 response 结束后对齐 |
| 29:30-39:30 | `generate_crc` 本地重算 | 解释为什么最高位 start bit 没单独再加也不会影响结果 |
| 39:30-44:30 | CRC 比较与 long response 边界讨论 | long response 多一拍不会影响最终寄存器值和 CRC 判断 |

## 1. receive 模块的工作是把串行 response 还原成并行寄存器

课程一开始就重新界定了 receive shift 的位置：任务80发 command，本讲收 response。CMD pad 在 host 发完命令后回到输入态，receive 模块开始从 `in_serial_command` 一拍一拍接 bit。

画面核对：02:04-05:06，课程从架构位置和接口开始，强调这里收的是 `response in`。

![data fsm preview? no, response receive path](<./screenshots/任务081_AHB_sd_host控制器设计20/task81_00_data_fsm_ppt_01m00s.jpg>)

它的核心输出是：

| 输出 | 作用 |
|---|---|
| `response0-3` | 给 SDIF/CPU 读的并行 response |
| `receive_crc` | 保存 card 发来的 CRC7 |
| `generate_crc` | 本地重算出来的 CRC7 |
| `command_receive_crc_error` | 两者不相等时拉高 |

## 2. start bit 已经被 command FSM 用来判定进入 `STATE_RECEIVE`

这个前提非常关键。任务79里 command FSM 在 `WAIT_RECEIVE` 状态下，就是靠 `sd_command=0` 的 start bit 才跳进 `STATE_RECEIVE`。所以本模块开始计数时，并不是从最开始的 start bit 重新开始，而是从后续 bit 开始。

这也是为什么课程里一再解释“为什么是从第 7 个开始收 32 bit”“为什么 long response 的边界看起来像少了一位”。如果不先承认 start bit 已经被前级状态机消耗，后面的窗口就会全部看错。

## 3. 短 response 只把 32-bit payload 收进 `response0`

普通 48-bit response 的结构可以粗略看成：

```text
start(0) + transmit(0) + command index(6) + status/data(32) + crc7(7) + end(1)
```

本模块真正关心的是中间的 32-bit 有效 payload，最后保存到 `response0`。

![data receive path as response parser](<./screenshots/任务081_AHB_sd_host控制器设计20/task81_02_data_receive_path_16m00s.jpg>)

课程的窗口判断是：在 `STATE_RECEIVE` 里，当 `has_receive_bit` 落在有效区间时，把 `in_serial_command` 左移灌进 `response0`。这本质上是一个串并转换窗口，而不是把整帧 48 bit 原样缓存。

为什么从第 7 个开始？

- 因为前面的 start bit 已被前级消耗。
- 后面 transmit bit 和 index 对 CPU 读 response 寄存器价值不高。
- 真正要读的是 32-bit status/payload。

## 4. 长 response 实际只收 120-bit payload，`response3` 高位自然补 0

课程里把 long response 讲得很清楚：虽然常说是 136-bit response，但对寄存器有意义的主体不是 128 个全有效 bit，而是 120-bit payload。写回四个 32-bit response 寄存器时：

- `response0/1/2` 可以各装满 32 bit
- `response3` 只会被写入其中一部分
- 多出来的高位自然保持 0

![block boundary style preview for long response windows](<./screenshots/任务081_AHB_sd_host控制器设计20/task81_04_block_boundary_34m10s.jpg>)

这个点的意义是：CPU 读长 response 时，不能机械认为四个寄存器都被“等长有效填满”。最高寄存器里有些位只是容器，不是协议有效字段。

## 5. `receive_crc` 收的是 card 发回来的 7-bit CRC7

在 response payload 收完之后，模块进入 CRC 接收窗口，把随 response 尾部而来的 7-bit CRC7 收进 `receive_crc`。

![crc and timeout discussion reused for CRC receive](<./screenshots/任务081_AHB_sd_host控制器设计20/task81_03_crc16_and_timeout_25m40s.jpg>)

它的本质和任务80发 CRC7 很像，区别只是方向相反：

- 发送端：本地生成 CRC7，再逐 bit 发出
- 接收端：先把对方发来的 7 bit 串行收下来，拼成并行寄存器

一旦窗口错位，例如提前一拍或晚一拍开始接 CRC，就会把 end bit 或 payload 最后一位混进 CRC，导致固定报错。

## 6. `generate_crc` 用收到的有效 payload 重新计算 CRC7

课程里有一个很值得保留的解释：发送 command 时，Host 会把前 40 bit 都纳入 CRC7，包括 start bit；接收 response 时，本地重算 CRC7 的实现没有单独再把 start bit 当作显式输入，但由于它是 0，这样处理不会改变最终 CRC 结果。

这段解释的价值不是“背结论”，而是学会判断：

- 某个 bit 没显式送进 CRC 计算器
- 如果这个 bit 恒为 0
- 那么它是否真的会改变线性反馈寄存器最终值

课程给出的结论是：这里不会造成结果差异，因此实现仍然可工作。

## 7. CRC 比较在接收完整个 CRC7 之后进行

`command_receive_crc_error` 不能在 payload 一收完就判，而必须在 `receive_crc` 七位都到齐以后再比较：

```text
receive_crc == generate_crc ? OK : CRC error
```

![transfer complete style end judgment](<./screenshots/任务081_AHB_sd_host控制器设计20/task81_05_transfer_complete_42m20s.jpg>)

这条规则很直接，但在 RTL 里常见 bug 是比较时机早一拍，导致最后一位 CRC 还没移入，就误判错误。

## 8. long response 多一拍不会改变最终有效结果

课程延续了任务79的疑问：long response 在状态机里可能比短 response 多停留一拍。这里的判断是，这一拍不会影响最终 `response0-3` 和 CRC 错误判定，因为：

- 有效 payload 已经全部写完
- `receive_crc` 已经收完
- `generate_crc` 已经算完

因此就算状态上多停一拍，也只是控制层面冗余，不会污染最终软件可读值。

## 工程检查清单

- 进入 `STATE_RECEIVE` 前的 start bit 是否已由 command FSM 消耗。
- 短 response 的 32-bit payload 窗口是否对齐到 `response0`。
- 长 response 的 120-bit payload 是否正确映射到 `response0-3`，`response3` 高位是否自然为 0。
- `receive_crc` 的 7-bit 接收窗口是否和 response 尾部对齐。
- `generate_crc` 的输入位序是否和协议一致。
- CRC 比较时机是否在 7 位 `receive_crc` 全到齐之后。
- 多一拍 long response 状态停留是否会影响寄存器值或错误位。

## 最后速记

- 任务81的本质是“串行 response -> 并行寄存器 + CRC 校验”。
- start bit 已经被前级状态机消耗，收包窗口从后续有效位开始。
- 短 response 重点是 32-bit `response0`。
- 长 response 真正有效主体是 120 bit，不是四个寄存器都满有效。
- `receive_crc` 收对方 CRC7，`generate_crc` 本地重算，再比较。

## 复习与自测

1. 为什么 receive 模块开始工作时，不会重新从 start bit 开始收？  
   答：因为 start bit 已在 command FSM 的 `WAIT_RECEIVE` 状态被用来判定 response 到来；进入 `STATE_RECEIVE` 时，这一位已经被前级消耗。

2. 短 response 最终为什么只需要重点保存 `response0`？  
   答：对 CPU 有价值的是中间 32-bit payload/status；其余协议头、CRC 和 end bit 不需要以同样形式暴露给软件。

3. 长 response 为什么会让 `response3` 的一部分高位保持 0？  
   答：因为有效 payload 只有 120 bit，分布到四个 32-bit 容器里时最高寄存器不会被完全填满。

4. `receive_crc` 和 `generate_crc` 的关系是什么？  
   答：`receive_crc` 是从 CMD 线上收下来的 card 端 CRC7；`generate_crc` 是 Host 根据收到的有效 response 数据本地重算的 CRC7。

5. long response 多一拍为什么通常不影响最终结果？  
   答：因为有效 payload 和 CRC 在前一拍已经收齐并比较完成，后续多停留一拍不会再写坏 `response0-3` 或改变 CRC 错误结果。


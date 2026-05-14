# 79_AHB_sd_host控制器设计18

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：阅读 `sd_command_fsm`，理解 SD Host 如何从 `command_ready` 开始，等待卡不 busy，发送 48-bit command frame，等待 response start bit，处理 64-cycle timeout，并接收短/长响应。
- 核心概念：`STATE_STOP`、`STATE_WAIT_SEND`、`STATE_SEND`、`STATE_WAIT_RECEIVE`、`STATE_RECEIVE`、DAT0 busy、CMD start bit、`send_bit_count`、`receive_bit_count`、`response_time_count`、`need_to_receive_bit`、R2 long response。
- 逻辑主线：command FSM 是 CMD 线事务的裁判；它不解释 response 内容，但必须严格控制何时发、发多少 bit、何时等、等多久、收多少 bit、什么时候告诉 `SDIF` 事务结束或超时。
- 最小主线：
  - `STOP` 等待 `in_command_ready`。
  - `WAIT_SEND` 用 DAT0 判断卡是否 busy。
  - `SEND` 发送 0..47 共 48 bit 命令帧。
  - 无 response 命令在发送结束后直接完成。
  - 有 response 命令进入 `WAIT_RECEIVE`，等 CMD 线 start bit 0。
  - 64 cycle 内没有 start bit，返回 timeout。
  - 进入 `RECEIVE` 后按短/长响应长度计数，完成后置 `end_command_response`。

完整时间线可以像接力赛一样看：SDIF 把 `command_ready` 交给 command FSM；FSM 先等 DAT0 这条“跑道”空出来；SEND 阶段把 48-bit 指挥棒推出去；WAIT_RECEIVE 阶段松开 CMD 线等卡接棒；RECEIVE 阶段再把卡回传的 response 收完整。接力棒掉在哪一段，status 就应该指向哪一段，而不是统一说“命令失败”。

### 2. 概念地图

| 概念层级 | 信号/状态 | 来源 | 作用 | 关键边界 |
|---|---|---|---|---|
| 命令请求 | `in_command_ready` | SDIF | 启动 command FSM | 请求被消费后要清 ready |
| 卡 busy | `sd_data[0]` | DAT0 | 判断能否发命令 | DAT0=0 时保持 wait |
| 命令发送 | `STATE_SEND`、`send_bit_count` | FSM | 控制 command shift 发 48 bit | 0..47 共 48 个 SD clock |
| 响应等待 | `STATE_WAIT_RECEIVE`、`sd_command`、`response_time_count` | CMD line | 等 start bit 或 timeout | 0..63 共 64 cycle |
| 响应接收 | `STATE_RECEIVE`、`receive_bit_count`、`need_to_receive_bit` | CMD line | 收短/长响应 | long response off-by-one 需核对 |
| 状态回报 | `end_command`、`end_command_response`、`response_timeout` | FSM | 回到 SDIF status/interrupt | 三者不能混用 |

### 3. 最短学习路径

1. 先背状态顺序：`STOP -> WAIT_SEND -> SEND -> WAIT_RECEIVE -> RECEIVE -> STOP`。
2. 再为每个等待状态写出退出条件：ready、DAT0、CMD start bit、timeout、receive count。
3. 最后检查输出语义：`end_command` 是发完命令，`end_command_response` 是整笔命令含响应完成，`response_timeout` 是等响应失败。

### 4. 全讲结构地图

| 阶段 | 画面/代码主线 | 必须学会的判断 |
|---|---|---|
| 00:00-04:30 | PPT 状态图、打开 `sd_command_fsm` | command FSM 由 ready、busy、send、wait、receive 串起 |
| 04:30-10:30 | 输入输出、send/receive 计数器 | 发最多 48 bit，收最多 136 bit |
| 10:30-16:00 | `need_to_receive_bit` | 短响应/长响应边界需要和 start bit 消耗核对 |
| 16:00-24:30 | 三段式 FSM、STOP、WAIT_SEND、SEND | 三段式状态机当前状态至少保持一个 cycle |
| 24:30-36:00 | WAIT_RECEIVE、response timeout | 64 cycle 内没有 start bit 要退出 |
| 36:00-46:15 | RECEIVE、R2 响应表、long response 边界 | 长响应多收一位可能不影响现有 TB，但应被验证 |

## 1. command FSM 的输入输出决定它只做 CMD 线控制

`sd_command_fsm` 的 `sd_clock` 来自任务 78 的 `out_sd_clock_dft`。它接收 `soft_reset`、`in_long_response`、`in_response`、`in_command_ready`，并观察 `sd_data[0]` 和 `sd_command`。它输出 current state、send/receive bit count、`end_command`、`end_command_response`、`response_timeout`。

![command FSM PPT](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_docx_002.jpeg>)

![sd command fsm port list](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_docx_004.jpeg>)

这说明 command FSM 不负责解析 R1/R2 具体字段，也不保存 response 寄存器。它负责时序和边界；response shift/capture 逻辑负责拼位，`SDIF` 负责把完整 response 保存给软件。

## 2. 三段式 FSM：当前状态只在 SD clock 边沿更新

课程强调三段式 FSM 写法：第一段时序逻辑保存 current state，第二段组合逻辑计算 next state 和控制输出，第三段或相关时序逻辑处理计数器。

![three block fsm state register](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_docx_006.jpeg>)

复位和 soft reset 都让状态回到 `STATE_STOP`。next state 在组合逻辑里可以变化，但 current state 只有下一个 SD clock 上升沿才更新。因此每个状态至少保持一个 cycle。

这点影响 bit counter 解释：当 next state 已经准备离开 `SEND` 时，current state 当前拍仍是 `SEND`，发送逻辑仍按 current state 工作。

## 3. `STOP` 等 command ready，`WAIT_SEND` 等 DAT0 释放 busy

`STATE_STOP` 是空闲状态，不是错误状态。只有 `in_command_ready=1`，FSM 才进入 `STATE_WAIT_SEND`。

![STOP state logic](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_docx_012.jpeg>)

`STATE_WAIT_SEND` 检查 `sd_data[0]`。DAT0=0 表示卡 busy，DAT0=1 表示卡 ready。卡 busy 时不能发新命令，否则真实卡可能无法接收或不会按预期响应。

![WAIT_SEND DAT0 logic](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_docx_018.jpeg>)

这一步是任务 69 的 SD timing/card busy 概念在 RTL 中落地。不要把 command ready 理解成“马上发送”，它只是软件侧准备好；卡侧准备好还要看 DAT0。

## 4. `SEND` 状态发 48-bit command frame

进入 `STATE_SEND` 后，FSM 置 `send_bit_count_en=1`，驱动 command send shift 模块。send counter 从 0 数到 47，共 48 个 SD clock，对应 SD command frame 的长度。

![SEND state logic](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_docx_021.jpeg>)

![send bit counter](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_docx_024.jpeg>)

发送结束后分两种：

| `in_response` | 下一状态 | 输出 |
|---|---|---|
| 0 | `STATE_STOP` | `end_command=1`，`end_command_response=1` |
| 1 | `STATE_WAIT_RECEIVE` | `end_command=1`，`end_command_response=0` |

`end_command` 和 `end_command_response` 的区别必须严格保留。对无响应命令，发送完命令就是事务结束；对有响应命令，发送完只是 CMD host-to-card 阶段结束，还要等 card-to-host response。

三类命令的分支要固定成验证表：

| 类型 | `in_response` | `in_long_response` | receive 目标 | 验证重点 |
|---|---|---|---|---|
| 无响应命令 | 0 | 无关 | 不进入 RECEIVE | 不能误报 timeout |
| 短响应命令 | 1 | 0 | 48-bit 类响应 | response0、CRC、timeout |
| 长响应命令 | 1 | 1 | 136-bit 类响应 | response0-3、start bit 边界 |

## 5. `WAIT_RECEIVE` 监听 CMD start bit，并用 64 cycle timeout 退出

有响应的命令进入 `STATE_WAIT_RECEIVE`。FSM 等 `sd_command=0`，因为 SD response 的 start bit 是 0。若在 64 个 SD clock 内没看到 start bit，就置 `response_timeout` 并回到 `STOP`。

![WAIT_RECEIVE timeout logic](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_docx_026.jpeg>)

响应等待逻辑：

```text
if response_time_count == 63:
    response_timeout = 1
    next_state = STOP
elif sd_command == 0:
    next_state = RECEIVE
else:
    response_time_count_en = 1
    next_state = WAIT_RECEIVE
```

![response timeout counter](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_docx_027.jpeg>)

这里的 `63` 对应 0..63 共 64 cycle。这个 timeout 只针对 CMD response start bit，不是 DAT 线 read timeout。任务 75 和任务 77 里已经把两个 timeout 分开，本章在 FSM 中看到 response timeout 的真实实现。

## 6. `RECEIVE` 状态按 `need_to_receive_bit` 收完整响应

进入 `STATE_RECEIVE` 后，FSM 置 `receive_bit_count_en=1`，驱动 command receive shift 模块。接收计数达到边界后，回到 `STOP` 并置 `end_command_response=1`。

![RECEIVE state logic](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_docx_031.jpeg>)

`need_to_receive_bit` 根据 `in_long_response` 选择。短响应和长响应的理论长度分别是 48 bit 和 136 bit。

![need to receive bit code](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_02_need_receive_bit_12m46s.jpg>)

但课程指出一个重要边界：FSM 在 `WAIT_RECEIVE` 中已经用 `sd_command=0` 检测到了 start bit。如果这个 start bit 已经被接收逻辑消费，则后续还按完整 136 bit 接收可能会多收 1 bit；短响应代码中使用 47 的边界，暗示已经考虑了 start bit 消耗。长响应如果写 136，需要用波形证明不会影响 response 保存。

这张图要核对的是“start bit 所有权”：它到底属于 WAIT_RECEIVE 的检测拍，还是属于 RECEIVE shift 的第 0 拍。边界差一拍，普通短响应可能因为代码特判没有暴露，R2 长响应却可能多收 1 bit。这个 bug 像尺子的 0 刻度被算了两次，量短物体时不明显，量长物体时误差就会累计到寄存器拼接里。

## 7. R2 long response 边界要用真实采样点验证

PPT 中 R2 是 long response，长度 136 bit，用于 CID/CSD 等寄存器类返回。课程后半段打开响应表，用它回到 `need_to_receive_bit` 代码判断。

![R2 response table](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_docx_029.jpeg>)

![R2 response table detail](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_docx_033.jpeg>)

课程的结论不是简单断言 RTL 一定错，而是提出 review 风险：`long response = 136` 可能多收一个 end bit 后的额外 bit；现有阉割版 TB 不一定会对 interface 做 bit-level 对比，所以可能测不出来。更严谨的验证应这样做：

| 检查点 | 应观察什么 |
|---|---|
| `WAIT_RECEIVE -> RECEIVE` 切换拍 | start bit 是否已经被 shift register 采样 |
| `receive_bit_count` 起点 | 第一次计数对应 response 的第几位 |
| `need_to_receive_bit` | 短响应 47 与长响应 136 是否采用同一逻辑口径 |
| response register capture | response0-3 是否恰好保存 136 bit 有效字段 |
| 改成 135 的试验 | long response 输出是否变化，TB 是否能检查出差异 |

这就是高质量 RTL 学习要保留的点：不是背状态机，而是能指出边界条件和验证缺口。

断言可以写成口径：

```text
进入 RECEIVE 后，shift register 捕获的第一位必须和设计定义一致；
receive_bit_count 到终点时，response0-3 中保存的有效 136 bit 不得左移或右移一位；
end bit 后的 idle 高电平不得被拼入 response。
```

如果现有 testbench 只检查 `end_command_response` 是否拉起，而不检查 response bit 内容，它只能证明状态机走完，不能证明长响应收对。

## 8. 状态输出如何回到任务 77 的 SDIF status

`end_command`、`end_command_response`、`response_timeout` 会回到 `SDIF`，在那里被边沿检测或锁存进 interrupt status。任务 79 讲的是事件生成，任务 77 讲的是事件保存。

![end command response path](<./screenshots/任务079_AHB_sd_host控制器设计18/task79_docx_032.jpeg>)

三者语义：

| 输出 | 何时出现 | SDIF 中用途 |
|---|---|---|
| `end_command` | 48-bit command frame 发完 | 命令阶段完成状态，可产生中断 |
| `end_command_response` | 无响应命令发完，或有响应命令收完 response | 表示命令事务完整结束，触发 response capture |
| `response_timeout` | 等 response start bit 超过 64 cycle | 锁存错误状态，通知软件失败 |

如果这三个混用，软件会出现典型误判：命令刚发完就读 response、响应超时仍当成功、无响应命令永远等 response。

## 9. command FSM 调试顺序

调 command FSM 不要先看 response 寄存器，要先看状态链：

```text
in_command_ready
  -> current_state: STOP -> WAIT_SEND
  -> sd_data[0] 是否为 1
  -> current_state: SEND
  -> send_bit_count 0..47
  -> in_response 决定 STOP 或 WAIT_RECEIVE
  -> sd_command 是否出现 0 start bit
  -> response_time_count 是否到 63
  -> receive_bit_count 是否到边界
  -> end_command_response / response_timeout
```

这个顺序能把问题定位到软件配置、卡 busy、发送 shift、响应等待、接收计数或状态回报。

## 工程检查清单

- reset 和 soft reset 是否都让 FSM 回到 `STATE_STOP`。
- `in_command_ready` 被消费后，任务 77 的 `command_ready_pre` 是否会被清掉。
- DAT0=0 时是否留在 `WAIT_SEND`，DAT0=1 时是否进入 `SEND`。
- `send_bit_count` 是否覆盖 0..47 共 48 bit。
- 无 response 命令是否直接产生 `end_command_response`。
- 有 response 命令是否只在 response 收完后产生 `end_command_response`。
- `response_time_count` 是否实现 64-cycle timeout。
- `receive_bit_count` 和 `need_to_receive_bit` 是否与 response shift 采样点一致。
- long response 是否有 bit-level 验证，不只靠简化 TB 通过。

## 最后速记

- command FSM 控制 CMD 线时序，不解析 response 内容。
- `STOP` 等软件请求，`WAIT_SEND` 等卡不 busy。
- `SEND` 固定发 48 bit。
- `WAIT_RECEIVE` 等 CMD start bit，64 cycle 未到就 timeout。
- `RECEIVE` 按短/长响应计数，结束后置 `end_command_response`。
- 长响应 136/135 的差异取决于 start bit 是否已被消费，必须看 shift 采样点。

## 复习与自测

1. DAT0=0 时 command FSM 为什么不能发命令？  
   答：DAT0=0 表示卡 busy；此时发命令可能被卡忽略或导致响应异常，FSM 应保持 `WAIT_SEND`。

2. `SEND` 状态为什么用 0..47？  
   答：SD command frame 是 48 bit，从计数 0 到 47 正好覆盖 48 个 SD clock 发送位。

3. 无响应命令为什么可以同时置 `end_command` 和 `end_command_response`？  
   答：无响应命令没有 card-to-host response 阶段，命令帧发完就表示整笔命令事务结束。

4. response timeout 的 64 cycle 是怎么来的？  
   答：计数器从 0 数到 63，共等待 64 个 SD clock；若期间 CMD 线没有 start bit 0，就判定响应超时。

5. long response 计数为什么有 off-by-one 风险？  
   答：`WAIT_RECEIVE` 已经检测到 start bit，如果接收模块从下一位开始采样，后续应收剩余 bit；若仍按完整 136 bit 收，可能多收一位。

6. 如何验证 long response 计数是否正确？  
   答：在波形中同时观察 `sd_command`、状态跳转、receive enable、receive count、shift register 和 response0-3 capture，确认 136 bit 有效字段恰好保存。


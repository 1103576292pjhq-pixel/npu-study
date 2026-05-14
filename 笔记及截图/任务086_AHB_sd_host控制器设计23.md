# 任务86：AHB sd host控制器设计23

## 本章知识全景图

本节完成 SD data receive shift register 的阅读。`sd_data_receive_shift` 的职责是把 DATA 线上收到的 1 bit 或 4 bit 串行数据重新拼成 32 bit，按节奏写入 SD FIFO，同时接收卡端 CRC16、自己重新生成 CRC16，并把 CRC mismatch 转成可被 SDIF/CPU 锁存的错误状态。

| 学习块 | 核心问题 | 结论 |
|---|---|---|
| CRC status 回顾 | 上一节为什么建议加 wait start 状态 | 现有代码按固定 4 cycle 接收 status，要求对端间隔固定；更稳妥是等 start bit |
| receive shift 定位 | data receive 模块到底干什么 | 收 DATA 线、拼 32 bit、写 FIFO、比 CRC16 |
| FIFO 写入 | 为什么每 32 bit 产生一次 write enable | FIFO 数据宽度是 32 bit，1 bit 模式 32 拍写一次，4 bit 模式 8 拍写一次 |
| byte 重排 | 为什么 `shift_r` 要重排 byte 顺序 | SD 卡按低地址 byte 先传，FIFO/总线按 32 bit word 组织，需要调整端序 |
| CRC 接收 | 1 bit 和 4 bit 模式怎么收 CRC16 | 1 bit 只收 DAT0 的一组 CRC16；4 bit 四根 DAT 线各收一组 CRC16 |
| CRC 生成 | 本地 CRC16 怎么产生 | 收 payload 时同步更新 CRC16 LFSR，收完 payload 后值保持 |
| 错误锁存 | 短脉冲 error 如何让 CPU 读到 | data receive 模块产生短错误脉冲，SDIF 跨域打拍并锁存成状态位 |

最短学习路径：先看 data receive 模块接口，再看 payload shift 和 FIFO write enable，最后把 received CRC、generated CRC 和 error latch 串成完整校验闭环。

![CRC status 固定间隔问题回顾](<./screenshots/任务086_AHB_sd_host控制器设计23/task86_01_crc_status_gap_recap.jpg>)

视频核对：00:01-06:27，截图用于核对“CRC status 固定间隔问题回顾”这个知识点。

## 全视频地图

| 时间 | 视频内容 | 学习任务 |
|---|---|---|
| 00:01-06:27 | 回顾 data FSM 中 CRC status 直接固定计数的问题 | 明确固定间隔接收 status 的前提和风险 |
| 06:27-11:09 | 打开 data receive shift register，分析接口 | 建立模块输入输出职责 |
| 11:48-15:51 | 解释 byte 重排和 FIFO write enable | 理解 32 bit word 写入边界 |
| 16:03-23:21 | 解释 1 bit/4 bit payload shift | 掌握串转并过程 |
| 23:21-27:44 | 接收对端 CRC16 | 理解 received CRC register |
| 27:44-36:39 | 生成本地 CRC16 | 理解 CRC16 LFSR 和多 lane 计算 |
| 36:39-44:49 | CRC error 比较、跨域锁存、上升沿触发写法 | 把短错误脉冲变成 CPU 可见状态 |

## 二轮重读：本节真正要抓住的三条线

这一节不是“又一个 shift register”，而是 SD 读数据链路的收口模块：它把 DATA 线上的串行电平变成 FIFO 可用的 32 bit word，同时在同一条时序链上完成 CRC16 生成、CRC16 接收、错误比较和错误上报。

| 线索 | 关键截图 | 必须看懂什么 |
|---|---|---|
| 数据线 | `task86_03`、`task86_04`、`task86_05` | `shift_reg` 怎么按 1 bit/4 bit 推进，何时凑满 32 bit，为什么写 FIFO 前要 byte reorder |
| CRC 线 | `task86_06`、`task86_07`、`task86_08` | received CRC 和 generated CRC 是两套寄存器；一个从卡端移入，一个由本端 LFSR 生成 |
| 事件线 | `task86_08`、`task86_09` | CRC error 原始信号是短事件，CPU 看到的是 SDIF 锁存后的状态；普通信号不能当 clock |

读这段 RTL 时不要把 300 行平均阅读。先确认 `out_write_receive_fifo` 与 `out_sd_fifo_wdata` 的对齐，再确认 CRC 寄存器只在正确状态更新，最后看 `out_receive_data_crc_error` 在哪一拍产生、谁负责把它锁住。

## 截图证据链：每张图在证明什么

| 截图 | 证据职责 | 如果这张图看不懂，会漏掉什么 |
|---|---|---|
| `task86_01` | 单块写时序里 CRC status 的位置 | 固定 interval 接收 status 为什么有错位风险 |
| `task86_02` | receive shift 的接口全貌 | `current_state`、`data_width`、`has_receive_bit` 分别控制什么 |
| `task86_03` | FIFO 写数据的 byte reorder | 数据值没丢但 word 内 byte 顺序颠倒的典型 bug |
| `task86_04` | FIFO write enable 的生成 | 早写/晚写一拍都会造成 32 bit word 边界错 |
| `task86_05` | payload shift 的 1 bit/4 bit 分支 | 宽度改变的是每拍吞吐，不是 block 总 bit 数 |
| `task86_06` | received CRC16 的收集 | 4 bit 模式必须有四组 lane CRC |
| `task86_07` | generated CRC16 的 LFSR 更新 | 只在 payload 接收阶段计算，收 CRC 阶段不能继续更新 |
| `task86_08` | CRC 比较和 error 输出 | 比较发生在 end bit 附近，error 是短脉冲 |
| `task86_09` | 边沿检测写法 | 用打拍取边沿，而不是把 error 当成时钟 |


## 1. CRC status 的遗留问题：固定间隔能对上，但条件很硬

上节 data FSM 中提到一个设计疑点：写数据后，卡返回 CRC status。现有代码在 `send_end` 后用固定 interval count 进入 `receive_crc_status`，并在这个状态里收 4 个 cycle。这个实现能对上的前提是对端总在固定位置返回 status。

视频开头重新核对了这个尾巴：代码里 `send_end_bit` 维持 4 个 cycle，`receive_crc_status` 也维持 4 个 cycle，表面上和 status + end bit 的长度能对上。但如果卡端 status 晚一个 cycle 或中间插入空闲，Host 就会错位采样。

![CRC status 需要固定间隔才能对上](<./screenshots/任务086_AHB_sd_host控制器设计23/task86_01_crc_status_gap_recap_2.jpg>)

视频核对：00:01-06:27，截图用于核对“CRC status 需要固定间隔才能对上”这个知识点。

更稳妥的控制方式是增加一个 wait state，明确等 DATA0 出现 status start bit 后再收 status。这个判断会在后面做波形或 RTL 修正时继续使用。

## 2. data receive shift 的接口：收数据、写 FIFO、报 CRC error

`sd_data_receive_shift` 的输入输出很集中：

| 类别 | 信号 | 含义 |
|---|---|---|
| 时钟复位 | `sd_clk`、`hreset_n`、`soft_reset_n` | SD clock 域逻辑 |
| 状态控制 | `in_current_state` | 来自 data FSM，决定当前是在 receive、receive_crc 还是 end |
| 数据输入 | `in_serial_data[3:0]` | DATA0-DATA3 输入；1 bit 模式只用 DATA0 |
| 传输配置 | `in_data_width` | 0 表示 1 bit，1 表示 4 bit |
| 计数输入 | `in_has_receive_bit` | 当前 payload 接收计数 |
| FIFO 输出 | `out_fifo_write_data`、`out_fifo_wen` | 每收满 32 bit 写一次 FIFO |
| 错误输出 | `out_receive_data_crc_error` | 本地 CRC 与接收 CRC 不一致 |

![data receive shift 接口](<./screenshots/任务086_AHB_sd_host控制器设计23/task86_02_receive_shift_interface.jpg>)

视频核对：07:26-11:09，截图用于核对“data receive shift 接口”这个知识点。

这类模块不要从 CRC 开始读。先读 FIFO 写口，因为它定义了 payload 数据最终流向；再读 shift register，因为它定义了串并转换；最后读 CRC，因为 CRC 只是对 payload 接收正确性的验证。

## 3. byte 重排：低地址 byte 先到，32 bit FIFO word 需要重新排

视频中专门解释了一个 byte reorder。原因是 SD 卡按地址递增顺序传 byte，低地址 byte 先到；而 FIFO 以 32 bit word 存储，软件/总线侧通常期望 word 内 byte 顺序固定。

![receive 数据 byte 重排](<./screenshots/任务086_AHB_sd_host控制器设计23/task86_03_byte_reorder.jpg>)

视频核对：11:48-13:37，截图用于核对“receive 数据 byte 重排”这个知识点。

假设 SD 卡从地址 `A` 开始返回 4 个 byte：

```text
先到：mem[A]
再到：mem[A+1]
再到：mem[A+2]
最后：mem[A+3]
```

shift register 连续接收 32 bit 后，先到的 byte 会落在某一端。为了让 FIFO 中的 32 bit word 与系统端预期一致，RTL 把 `shift_r[7:0]`、`shift_r[15:8]`、`shift_r[23:16]`、`shift_r[31:24]` 重新排列。

这个动作不是算法优化，而是端序匹配。读写 data path 时，byte order 错误会表现为数据整体存在但每个 word 内 byte 颠倒，调试时很容易误判成 DMA 地址或软件解析问题。

## 4. FIFO write enable：1 bit 模式 32 拍一次，4 bit 模式 8 拍一次

FIFO 宽度是 32 bit，所以 receive shift 每凑满一个 32 bit word 才能写一次。

![FIFO 写使能生成](<./screenshots/任务086_AHB_sd_host控制器设计23/task86_04_fifo_write_enable.jpg>)

视频核对：14:02-15:51，截图用于核对“FIFO 写使能生成”这个知识点。

| 模式 | 每拍接收 | 写 FIFO 周期 | 判断方式 |
|---|---:|---:|---|
| 1 bit | 1 bit | 32 拍一次 | `has_receive_bit[4:0] == 31` |
| 4 bit | 4 bit | 8 拍一次 | `has_receive_bit[2:0] == 7` |

这个 write enable 必须和 `out_fifo_write_data` 对齐。早一拍会写入未收满的数据，晚一拍会让 shift register 被后续 bit 覆盖，造成 word 边界错位。

## 5. payload shift：1 bit 和 4 bit 的差异只是每拍推进宽度

进入 `DATA_STATE_RECEIVE` 后，payload shift 开始工作。

![payload shift register](<./screenshots/任务086_AHB_sd_host控制器设计23/task86_05_shift_register_receive.jpg>)

视频核对：16:03-23:21，截图用于核对“payload shift register”这个知识点。

1 bit 模式可以理解为：

```verilog
shift_r <= {shift_r[30:0], in_serial_data[0]};
```

4 bit 模式可以理解为：

```verilog
shift_r <= {shift_r[27:0], in_serial_data[3:0]};
```

两者都是左移并把新数据塞到低位。差别只在每个 cycle 推进 1 bit 还是 4 bit。收满 32 bit 后，写 FIFO 并继续接收下一组 32 bit。

## 6. 接收 CRC16：1 bit 一组，4 bit 四组

SD data block 的 CRC 是 CRC16。1 bit 模式只通过 DATA0 传数据，因此只需要收一组 CRC16。4 bit 模式下，DATA0-DATA3 四根线并行传输，每根线都有自己的 CRC16，因此要收四组 CRC16。

![接收端 CRC16 寄存器](<./screenshots/任务086_AHB_sd_host控制器设计23/task86_06_receive_crc_register.jpg>)

视频核对：23:21-27:44，截图用于核对“接收端 CRC16 寄存器”这个知识点。

| 模式 | CRC 寄存器数量 | 原因 |
|---|---:|---|
| 1 bit | 1 组 | 只有 DAT0 承载 payload |
| 4 bit | 4 组 | DAT0-DAT3 各自承载一条 bit lane，每条 lane 独立校验 |

`receive_crc_reg` 在 `DATA_STATE_RECEIVE_CRC` 中移入。进入这个状态时 payload shift 已经停止，所以 payload 数据寄存器不会再被 CRC bit 污染。

## 7. 生成 CRC16：收 payload 时同步算，收 CRC 时只比较

本地生成 CRC16 的时机是 `DATA_STATE_RECEIVE`，也就是接收 payload 的同时计算。跳出 receive 状态后，generated CRC 保持不变，等待对端 CRC16 收完后比较。

![本地生成 CRC16](<./screenshots/任务086_AHB_sd_host控制器设计23/task86_07_generate_crc16.jpg>)

视频核对：27:44-36:39，截图用于核对“本地生成 CRC16”这个知识点。

CRC16 LFSR 的结构仍然是“移位 + 异或反馈”。1 bit 模式用 `in_serial_data[0]` 更新一组 CRC；4 bit 模式用 `in_serial_data[0]..[3]` 分别更新四组 CRC。

判断 CRC 代码是否合理，检查四个点：

1. reset/soft reset 是否清零。
2. 新 block 开始前是否清零。
3. 只有 payload 状态更新 generated CRC。
4. compare 发生时 generated CRC 和 received CRC 都已经稳定。

## 8. CRC error 短脉冲如何变成 CPU 可读状态

receive shift 在 `receive_end_bit` 附近比较 generated CRC 与 received CRC。如果不相等，就产生 `receive_data_crc_error`。这个信号在本模块里可能只维持很短时间。

![CRC error 锁存到 SDIF](<./screenshots/任务086_AHB_sd_host控制器设计23/task86_08_crc_error_latch.jpg>)

视频核对：36:39-41:30，截图用于核对“CRC error 锁存到 SDIF”这个知识点。

短脉冲不适合直接给 CPU 读。SDIF 会把它跨到 HCLK 域并锁存成状态位，直到下一次 command/data 操作或软件清除。这样 CPU 即使晚很多 cycle 来读，也能看到“上一次 data receive CRC 错误”。

这是一种常见硬件事件处理模式：

```text
事件源：短脉冲 error
跨域：双拍同步或边沿检测
状态寄存器：置 1 后保持
清除条件：软件 clear 或下一次事务开始
```

## 9. 不要用普通数据信号当 clock

视频最后强调：不要直接写 `always @(posedge some_error_signal)` 来捕获普通信号的边沿。普通信号不是时钟，拿它当 clock 会制造不可控时钟树、毛刺风险和 STA 约束问题。

![用打拍检测上升沿](<./screenshots/任务086_AHB_sd_host控制器设计23/task86_09_edge_trigger_style.jpg>)

视频核对：42:17-44:49，截图用于核对“用打拍检测上升沿”这个知识点。

正确做法是在目标 clock 域打拍，再做边沿检测：

```verilog
sig_d1 <= sig;
sig_d2 <= sig_d1;
sig_rise = sig_d1 & ~sig_d2;
```

这同时解决两个问题：跨域同步和上升沿脉冲提取。对数字 IC 工程来说，这是基础规范，不是写法偏好。

## 工程验证闭环

这一节的验证重点不是“仿真能跑完”，而是四个边界必须逐拍对齐：payload word 边界、FIFO 写边界、CRC 计算边界、错误锁存边界。

| 验证对象 | 波形上应看到的正确结果 | 常见失败信号 | 定位方向 |
|---|---|---|---|
| `shift_reg` | 1 bit 模式每拍左移 1 bit，4 bit 模式每拍左移 4 bit | 数据总量正确但 word 内部位序错 | 查 `in_data_width` 分支和拼接方向 |
| `out_write_receive_fifo` | 1 bit 模式每 32 拍一次，4 bit 模式每 8 拍一次 | FIFO 多写、少写、写入未满 word | 查 `has_receive_bit` 低位比较条件 |
| `out_sd_fifo_wdata` | 写入前完成 byte reorder，系统端按预期 endian 读出 | 每个 32 bit word 的四个 byte 颠倒 | 查 `{shift_reg[7:0], ...}` 排列 |
| `receive_crc_reg*` | 只在 `RECEIVE_CRC` 状态接收卡端 CRC | CRC bit 污染 payload shift | 查状态条件和寄存器清零 |
| `generate_crc_reg*` | 只在 `RECEIVE` 状态随 payload 更新 | 进入 CRC 状态后 generated CRC 还在变化 | 查 LFSR 更新 enable |
| `out_receive_data_crc_error` | CRC mismatch 后在 end 附近产生短脉冲，并被 SDIF 锁存 | 波形有 error，CPU 状态寄存器读不到 | 查跨域同步、边沿检测和状态寄存器 clear |

最小实验：构造一个 32 bit payload 和一组故意错误的 CRC16。先跑 1 bit 模式，确认 32 拍写一次 FIFO；再跑 4 bit 模式，确认 8 拍写一次 FIFO；最后把 CRC 改错，确认 SDIF 状态位能保持到软件清除。


## 自测题

1. data receive shift 写 FIFO 的最小单位是什么？
2. 为什么 receive 数据要做 byte reorder？
3. 4 bit 模式为什么有四组 CRC16？
4. generated CRC 和 received CRC 分别什么时候产生？
5. data CRC error 为什么可以是短脉冲？
6. 为什么不建议对普通 error 信号用 `posedge`？

## 自测参考答案与判分点

1. 答：32 bit。1 bit 模式每 32 拍写一次，4 bit 模式每 8 拍写一次。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

2. 答：SD 卡按低地址 byte 先传，FIFO/总线侧按 32 bit word 使用；需要重新排列 word 内 byte 顺序。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

3. 答：DAT0-DAT3 四根线各自传一条 bit lane，每条 lane 独立计算 CRC16。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

4. 答：generated CRC 在接收 payload 时同步计算；received CRC 在后续 receive_crc 状态从 DATA 线收进来。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

5. 答：SDIF 会把短脉冲跨域并锁存成状态位，CPU 读的是锁存后的状态，不要求原始脉冲一直保持。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

6. 答：普通信号不是 clock，可能有毛刺和不可控时钟路径；应在目标 clock 域打拍并做边沿检测。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。


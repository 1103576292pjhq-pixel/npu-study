# 任务87：AHB sd host控制器设计24

## 本章知识全景图

本节讲 SD data send shift register。它从 SD FIFO 读出 32 bit 并行数据，按 1 bit 或 4 bit 模式串行送到 DATA 线，同时生成 CRC16 并发送；发送完后还要接收卡返回的 CRC status，并在 status 异常时把错误报给 SDIF。

| 学习块 | 核心问题 | 结论 |
|---|---|---|
| 模块定位 | send shift 和 receive shift 的对称关系 | receive 是串转并写 FIFO，send 是读 FIFO 并转串 |
| 接口 | 为什么 send 模块还需要 `in_sd_data` | 发送完 data/CRC 后要从 DATA0 接收卡返回的 CRC status |
| half delay | `out_serial_data_half_delay` 有什么用 | 用下降沿打一拍，提供半周期相位选择，改善 IO timing |
| direction | data direction 什么时候打开 | send_p、send_start、send、send_crc、send_end 等输出阶段打开 |
| payload shift | 1 bit/4 bit 如何把 32 bit 推出 | 1 bit 每 32 拍装载，4 bit 每 8 拍装载 |
| CRC16 | 发送端如何生成和发送 CRC | payload 发送时同步算，send_crc 状态按 lane 输出 |
| CRC status | 当前 status decode 有什么疑点 | 代码按 `0010` 比较，视频认为可能应看高 3 bit `010`，需波形验证 |
| FIFO read enable | 为什么读使能时刻严格 | FIFO read data 下一拍到，必须提前一拍发 read enable |

最短学习路径：先把 FIFO read enable 的时序看懂，再看 1 bit/4 bit 的并转串，最后把 CRC16 生成、CRC status 接收和 half-delay 输出相位连起来。

![data send shift 模块定位](<./screenshots/任务087_AHB_sd_host控制器设计24/task87_01_send_shift_role.jpg>)

视频核对：00:00-03:18，截图用于核对“data send shift 模块定位”这个知识点。

## 全视频地图

| 时间 | 视频内容 | 学习任务 |
|---|---|---|
| 00:00-03:18 | 回顾 receive shift，引出 send shift 功能 | 明确读 FIFO、发 DATA、收 CRC status |
| 03:18-12:12 | 分析 send shift interface | 建立输入输出职责 |
| 13:05-18:26 | half delay 与 data direction/OEN | 理解高速相位和输出使能对齐 |
| 19:14-24:19 | 1 bit 模式 start/data shift 与 byte 顺序 | 理解并转串输出 |
| 24:19-31:58 | CRC16 生成与发送 | 理解 1 bit/4 bit CRC lane 计算 |
| 31:58-35:57 | 接收 CRC status 与疑点 | 记录 status decode 可能错误 |
| 36:19-40:24 | 4 bit 数据和 CRC 输出 | 理解四线并行发送 |
| 43:17-47:15 | FIFO read enable 时序 | 掌握提前一拍读 FIFO 的必要性 |

## 二轮重读：send shift 的难点在“提前”和“释放”

`sd_data_send_shift_register` 看起来是 receive shift 的反方向，但写路径多了两个容易出错的动作：第一，FIFO read enable 必须提前一拍，因为 FIFO read data 不是同拍有效；第二，发完 data/CRC/end 后要释放 DATA 线，等卡返回 CRC status。

| 线索 | 关键截图 | 必须看懂什么 |
|---|---|---|
| 输出相位 | `task87_04`、`task87_05` | data 和 direction 都有 pos/neg 版本，不能只延迟数据不延迟 OEN |
| 并转串 | `task87_06`、`task87_07` | idle 为 1、start 拉 0，随后按 1 bit/4 bit 推 payload |
| CRC/status | `task87_08`、`task87_09` | 发送端生成 CRC16，随后短暂转为接收方读取 DATA0 status |
| FIFO 时序 | `task87_10` | read enable 是“为下一拍装载准备数据”，不是当前拍想读就读 |

本节最容易被误读的代码是 `out_fifo_read_en`。它不是在 FIFO 空闲时随便拉高，而是在当前 32 bit word 将要发完、且下一状态仍是 send 时提前拉高。如果不看 `in_next_state`，会错过“最后一个 word 不应再读下一 word”的边界。

## 截图证据链：每张图在证明什么

| 截图 | 证据职责 | 如果这张图看不懂，会漏掉什么 |
|---|---|---|
| `task87_01` | SD Host 架构中 send shift 的位置 | send shift 为什么既连 FIFO 又连 DATA pad |
| `task87_02` | 模块接口 | `in_next_state`、`in_send_crc_counter`、`in_sd_data` 的真实用途 |
| `task87_03` | CRC status 输入 | 写路径末尾 Host 需要从 DATA0 接收卡状态 |
| `task87_04` | half delay 输出 | half-cycle 相位选择是 IO timing 设计，不是功能装饰 |
| `task87_05` | data direction/OEN | 数据线何时由 Host 驱动，何时释放给卡 |
| `task87_06` | idle/start bit | idle 高电平和 start 低电平给 block 边界 |
| `task87_07` | 1 bit payload shift | 32 bit FIFO word 如何一位一位推出 |
| `task87_08` | 4 lane CRC | 4 bit 模式四根线各有独立 CRC16 |
| `task87_09` | CRC status decode 疑点 | status 字段与 end bit 的对齐要靠波形确认 |
| `task87_10` | FIFO read enable | 提前一拍读 FIFO 是整个发送链路的时序关键点 |


## 1. send shift 的职责：从 FIFO word 到 SD DATA bit lane

写 SD 卡时，DMA 先把一个 block 的数据写进 SD FIFO。`sd_data_send_shift` 再从 FIFO 读 32 bit word，把它们转换成 DATA 线上的串行 bit。

![send shift interface](<./screenshots/任务087_AHB_sd_host控制器设计24/task87_02_send_shift_interface.jpg>)

视频核对：03:18-12:12，截图用于核对“send shift interface”这个知识点。

主要接口可以分为四组：

| 类别 | 信号 | 含义 |
|---|---|---|
| FIFO 侧 | `in_fifo_read_data`、`out_fifo_read_en` | 从 FIFO 取 32 bit word |
| FSM 侧 | `in_current_state`、`in_next_state`、`in_has_send_bit`、`in_send_crc_count` | 状态和计数窗口来自 data FSM |
| SD 侧 | `out_serial_data[3:0]`、`out_data_direction`、`in_sd_data[3:0]` | 输出 DATA bit，同时接收 CRC status |
| 配置侧 | `in_data_width`、`in_high_speed_clock` | 选择 1 bit/4 bit 和输出相位 |

这里 `in_next_state` 很关键：FIFO read enable 需要提前一拍发出，只看 current state 不够，必须知道下一拍是否仍在 send。

## 2. 发送模块为什么还要读 `in_sd_data`

send 模块不仅发数据，还要在发完 block 后接收卡返回的 CRC status。这个 status 通过 DATA0 返回，因此发送模块需要 `in_sd_data`。

![CRC status 输入](<./screenshots/任务087_AHB_sd_host控制器设计24/task87_03_crc_status_input.jpg>)

视频核对：07:55-12:12，截图用于核对“CRC status 输入”这个知识点。

写 data block 的闭环是：

```text
Host 从 FIFO 读 payload
  -> DATA 线发送 start + payload + CRC16 + end
  -> 卡检查 payload CRC
  -> 卡通过 DATA0 返回 CRC status
  -> Host 判断 status，必要时报错给 CPU
```

所以 send shift 不是单纯“只输出不输入”的模块。它在 data write 协议尾部会短暂转成接收方。

## 3. half delay：数据和输出使能都要一起偏移半周期

`out_serial_data_half_delay` 由 `out_serial_data` 在 SD clock 下降沿打一拍得到，相比上升沿版本延后半个周期。

![DATA 输出 half delay](<./screenshots/任务087_AHB_sd_host控制器设计24/task87_04_half_delay_data.jpg>)

视频核对：13:05-18:26，截图用于核对“DATA 输出 half delay”这个知识点。

输出选择类似 command send：

```text
high_speed = 1 -> 用原始 posedge 输出
high_speed = 0 -> 用下降沿 half-delay 输出
```

这个选择服务 IO 时序。DATA 线走到 SD 卡需要 pad、封装、PCB、卡端输入延迟；半周期相位选择能让卡端采样点避开数据变化窗口。

`out_data_direction` 也有 pos/neg 版本，必须和 data 输出相位一致。若数据延迟半周期而输出使能不延迟，可能出现“数据已经准备好但 pad 未使能”或“pad 使能时数据仍是旧值”的边界问题。

![DATA direction/OEN](<./screenshots/任务087_AHB_sd_host控制器设计24/task87_05_data_direction_oen.jpg>)

视频核对：14:40-18:26，截图用于核对“DATA direction/OEN”这个知识点。

## 4. direction 打开的状态：只在真正发 DATA 时驱动总线

DATA 线也是双向的。Host 写卡时驱动 DATA；卡返回 busy/status 或 Host 读卡时，Host 不能驱动。

| 状态 | direction |
|---|---|
| `send_p` | 1 |
| `send_start_bit` | 1 |
| `send` | 1 |
| `send_crc` | 1 |
| `send_end_bit` | 1 |
| `receive_crc_status` / wait / stop | 0 |

4 bit 模式下 DATA1-DATA3 的 direction 还要受 `in_data_width` 控制；1 bit 模式只驱动 DATA0，其余线保持不驱动或 idle。

## 5. reset 为 1，start bit 拉 0：协议边界靠高到低跳变

DATA 线 idle 态为高。reset 后 `out_serial_data` 置 1，进入 `send_start_bit` 时拉 0，卡端才能看到一个明确 start bit。

![idle 到 start bit](<./screenshots/任务087_AHB_sd_host控制器设计24/task87_06_idle_start_bit.jpg>)

视频核对：19:14-20:33，截图用于核对“idle 到 start bit”这个知识点。

如果 reset 默认就是 0，start bit 就没有边界；如果 output enable 异常打开，也更容易造成假 start。置 1 是协议安全默认值。

## 6. 1 bit 模式：每 32 bit 装载一次，然后逐位推出

1 bit 模式下，每个 FIFO word 需要 32 个 SD clock cycle 发完。

![1 bit 模式并转串](<./screenshots/任务087_AHB_sd_host控制器设计24/task87_07_one_bit_shift_send.jpg>)

视频核对：20:33-24:19，截图用于核对“1 bit 模式并转串”这个知识点。

流程是：

1. 在 32 bit 窗口起点装载 `data_for_send` 到 shift register。
2. 每拍把最高位送到 `out_serial_data[0]`。
3. shift register 左移一位。
4. 32 拍后发出下一次 FIFO read enable，下一拍拿到新 word。

这里也有 byte 顺序调整。FIFO 中的 32 bit word 以总线视角组织；SD 卡按低地址 byte 先接收，所以发送前需要把 byte 顺序调整成 SD 期望的输出顺序。

## 7. CRC16：payload 发出去的同时生成，send_crc 状态再推出

发送端生成 CRC16 的时机是 `DATA_STATE_SEND`。payload 每输出一拍，对应 lane 的 CRC register 更新一拍。进入 `send_crc` 后，CRC 值已经稳定，模块把它按 bit lane 推出去。

![4 bit CRC lane 计算](<./screenshots/任务087_AHB_sd_host控制器设计24/task87_08_four_bit_crc_lanes.jpg>)

视频核对：24:19-31:58，截图用于核对“4 bit CRC lane 计算”这个知识点。

1 bit 模式只有一组 CRC16。4 bit 模式有四组 CRC16：

| DATA lane | CRC 输入 |
|---|---|
| DAT3 | payload 的第 0、4、8... bit 位置对应 lane |
| DAT2 | payload 的第 1、5、9... bit 位置对应 lane |
| DAT1 | payload 的第 2、6、10... bit 位置对应 lane |
| DAT0 | payload 的第 3、7、11... bit 位置对应 lane |

具体 lane 对应要以 RTL bit order 为准。视频指出代码通过 `4N + offset` 的方式从 `data_for_send` 中抽取各 lane 输入，用来分别更新四组 CRC。

## 8. CRC status decode 疑点：`0010` 还是高三位 `010`

发送完 CRC 和 end bit 后，卡返回 CRC status。视频指出当前代码可能用 `0010` 判断 OK，但从 SD status 格式看，真正有效状态可能是高三位 `010`，末尾还有 end bit。

![CRC status decode 疑点](<./screenshots/任务087_AHB_sd_host控制器设计24/task87_09_crc_status_decode_issue.jpg>)

视频核对：31:58-35:57，截图用于核对“CRC status decode 疑点”这个知识点。

当前应把它作为待波形验证点记录：

| 观察点 | 判断 |
|---|---|
| 如果 shift 后 status register 为 `0010` 正好表示 OK | 代码可工作 |
| 如果协议有效字段是高三位 `010`，低位是 end bit | 应改成比较高三位 |
| 若固定 interval 导致 start/status/end 错位 | 需要增加 wait status start 状态 |

这是典型 RTL review 口径：不要凭感觉直接改，先把协议字段、采样窗口和波形对齐，再决定是否修代码。

## 9. FIFO read enable：必须提前一拍，不能早也不能晚

FIFO read data 通常在 read enable 下一拍有效。send shift 要在当前 32 bit word 即将发完时，提前一拍发 `out_fifo_read_en`，让下一拍新 word 刚好到达装载点。

![FIFO read enable 时序](<./screenshots/任务087_AHB_sd_host控制器设计24/task87_10_fifo_read_enable_timing.jpg>)

视频核对：43:17-47:15，截图用于核对“FIFO read enable 时序”这个知识点。

1 bit 模式：

```text
has_send_bit[4:0] == 31 且下一状态仍是 send
  -> 发 FIFO read enable
下一拍 has_send_bit[4:0] == 0
  -> 新 FIFO word 到达并装载
```

4 bit 模式：

```text
has_send_bit[2:0] == 7 且下一状态仍是 send
  -> 发 FIFO read enable
下一拍 has_send_bit[2:0] == 0
  -> 新 FIFO word 到达并装载
```

如果 read enable 早一拍，会覆盖当前还没发完的数据；晚一拍，装载点没有新数据，会重复或漏发 word。这个时序点是本节最重要的工程细节。

## 工程验证闭环

写路径的失败通常不会表现为“完全没波形”，而是表现为多一拍、少一拍、总线释放晚一拍或 CRC status 采样错一拍。验证要围绕边界拍展开。

| 验证对象 | 波形上应看到的正确结果 | 常见失败信号 | 定位方向 |
|---|---|---|---|
| `out_serial_data` | reset/idle 为高，`SEND_START_BIT` 拉低，payload 连续输出 | 卡端看不到 start bit 或 block 边界不稳 | 查 reset 默认值和 direction 使能 |
| `out_data_dir` | send_p/start/send/send_crc/send_end 驱动，status/busy 阶段释放 | Host 和卡同时驱动 DATA0 | 查 direction 状态枚举和 pos/neg 相位 |
| `out_data_half_delay` | 与 `out_data_dir` 使用同一相位策略 | 数据与 OEN 错半拍 | 查 high-speed mux 选择 |
| `out_fifo_read_en` | 32 bit word 发完前一拍拉高，最后一个 word 不多读 | 重复发送旧 word 或漏发新 word | 查 `in_next_state` 和 `has_send_bit` 低位比较 |
| CRC16 lane | 1 bit 一组 CRC，4 bit 四组 CRC 同步更新 | 4 bit 模式 CRC status 错 | 查 lane 映射和 LFSR 输入 bit |
| CRC status | send_end 后采样 DATA0 的 status 字段并识别 OK/error | status `010` 被误判，或 start/end 错位 | 查 interval count、wait start 缺失和 status bit 位置 |

最小实验：准备两个 FIFO word，跑 1 bit 和 4 bit 两种模式；在波形上标出“读 FIFO 的拍、FIFO data 有效的拍、shift 装载的拍、DATA 第一个 bit 输出的拍”。四个拍点只要错一个，板上就会出现偶发写卡失败。


## 自测题

1. data send shift 的核心输入数据来自哪里？
2. send 模块为什么需要 `in_next_state`？
3. half delay 的作用是什么？
4. 4 bit 模式为什么要生成四组 CRC16？
5. FIFO read enable 早一拍或晚一拍分别会怎样？
6. CRC status decode 为什么需要波形验证？

## 自测参考答案与判分点

1. 答：来自 SD FIFO 的 32 bit read data。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

2. 答：FIFO read enable 要提前一拍产生，并且只有下一拍仍在 send 时才需要读下一组数据。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

3. 答：用下降沿打一拍得到半周期延迟版本，给 DATA 输出和 direction 提供相位选择以满足 IO timing。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

4. 答：四根 DATA lane 并行承载数据，每根 lane 都需要独立 CRC16 校验。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

5. 答：早一拍会覆盖当前 shift 数据，晚一拍会在装载点拿不到新 word，导致漏发或重复。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

6. 答：要确认采样窗口是否对齐，以及 status 有效字段到底对应整个 4 bit register 还是其中高三位。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。


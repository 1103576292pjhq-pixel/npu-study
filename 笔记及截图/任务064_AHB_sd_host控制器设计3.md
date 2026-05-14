# 任务64：AHB SD Host 控制器设计3

## 本章知识全景图

**这一讲把 SD Host 从“能发命令、能收数据”推进到“能按卡状态和卡能力合法工作”。**SD Host 不能只会把 AHB 寄存器写成 CMD 线波形；它还必须完成初始化、识别、能力读取、RCA 保存、时钟切换和选卡。只有这些前置契约成立，后面的 block read/write 才是合法事务。

| 层级 | 核心概念 | 本章要形成的判断 | RTL 设计落点 |
|---|---|---|---|
| 协议版本 | SD 1.1、SD 2.0、SD 3.0 | Host 要知道自己按哪个能力范围设计 | capability、兼容性分支 |
| operation mode | inactive、card identification、data transfer | 不同模式允许不同命令和频率 | 初始化 FSM、命令合法性 |
| 信息寄存器 | CID、RCA、DSR、CSD、SCR、OCR、SSR、CSR | 每个寄存器回答不同问题：身份、地址、能力、电压、状态 | response/data 解析寄存器 |
| 频率切换 | `fOD` 到 `fPP` | 识别阶段低速，进入传输阶段后才提速 | clock divider 控制 |
| 卡选择 | CMD7、RCA | 只有被选中的卡进入 Transfer State | selected card tracking |

最短学习路径：

```text
先区分 SD 版本和 Host 能力边界
  -> 再用 card state 表理解初始化和传输两大阶段
  -> 再记信息寄存器各自回答什么问题
  -> 最后把 CMD9/CMD4/CMD7、fOD/fPP 和 RCA 映射到初始化 FSM
```

可以把初始化理解成“给卡办入网手续”：先确认这张卡能不能在当前电压和版本下工作，再给它分配本地地址 RCA，读取它的能力档案 CSD/SCR/OCR，最后用 CMD7 选中它进入可交易状态。这个比喻的边界是，SD 卡不是人，所有手续都必须落成可计数的命令、响应字段、状态位和超时处理。
这套“手续”在 RTL 里不能写成一条固定延迟流水线，因为每一步都可能失败或分支：`CMD8/R7` 可能说明电压或 check pattern 不匹配，`ACMD41/OCR` 可能长时间未 ready，`CMD3/R6` 可能没有发布可用 RCA，`CMD7/R1b` 可能返回 busy。初始化 FSM 的质量取决于每个手续是否有退出口，而不是能不能在理想模型里一路跑到 `tran`。

## 1. 协议版本决定 Host 设计的能力边界

课程开头列出 SD 1.1、SD 2.0、SD 3.0，并把本课程的 SD Host 学习放在 AHB/AMBA 外设设计语境里。对初学者来说，不需要一开始背完所有版本差异，但必须知道版本不是装饰：版本决定支持的容量、速度模式、命令扩展和能力寄存器字段。

![SD 协议版本与 AHB 外设语境](<./screenshots/任务064_AHB_sd_host控制器设计3/task64_01m00s.jpg>)

视觉核验：
- 教学职责：这张图负责说明 SD Host 是 AHB 外设设计和 SD 协议设计的交叉点，不是单纯的串行线控制器。
- 看图要点：看 SD 版本列表，再看手写标注如何把 AHB/AMBA 2.0 和 SD 协议学习连起来；这意味着 Host 一边要响应软件寄存器访问，一边要遵守卡协议版本。
- 漏看后果：设计会把所有 SD 功能当成必选，或者把高版本能力误加进低版本 Host，造成软件配置、卡能力和 RTL 支持范围不一致。

在 RTL/验证中，版本意识通常体现为：

| 设计点 | 为什么和版本有关 |
|---|---|
| 容量类型 | 标准容量和高容量可能影响地址解释 |
| 速度模式 | 默认、高速以及更高版本模式对应不同 clock 配置 |
| 命令集合 | 某些命令或 ACMD 在不同版本/卡类型下可用性不同 |
| 能力字段 | CSD、SCR、OCR 等寄存器字段解释依赖规范版本 |

最稳的学习方式是先实现课程锁定版本下的最小 Host，再逐步扩展能力。否则很容易把 SD 3.0 的概念误塞进只支持 SD 2.0 的控制器里。

## 2. card state 和 operation mode 是命令合法性的边界

SD 卡不是一直处在“可读写”状态。它从上电后的 Idle/Ready/Identification 逐步进入 Stand-by，再被 CMD7 选中进入 Transfer State。只有在合适状态下，Host 才能执行对应命令。

![SD 卡初始化状态路径](<./screenshots/任务064_AHB_sd_host控制器设计3/task64_25m00s.jpg>)

视觉核验：
- 教学职责：这张图负责把初始化 FSM 的大路径固定下来：上电后不是直接读写，而是先经过电压确认、识别、分配 RCA、选卡。
- 看图要点：沿 Power on/Idle State 看 CMD8、ACMD41、CMD2、CMD3 到 Stand-by；再看 CMD7 如何把卡选入 Transfer State；不兼容电压或 CMD15 会进入 Inactive State。
- 漏看后果：Host 会在未发布 RCA、未选卡或卡已 inactive 时发读写命令，波形看起来有 CMD 活动，但卡不会按数据传输模式响应。

可以把状态理解成三层：

| 大阶段 | 典型状态 | Host 主要任务 |
|---|---|---|
| inactive | Inactive | 卡不可用或被置为不可参与 |
| card identification mode | Idle、Ready、Identification | 低速时钟下识别卡、确认电压、读取 CID、分配 RCA |
| data transfer mode | Stand-by、Transfer、Sending-data、Receive-data、Programming、Disconnect | 选中卡、读写数据、等待 busy、处理停止和断开 |

Host 如果不维护 card state，软件可能在识别未完成时启动数据传输；或者在卡 busy/programming 时又发下一条数据命令。实际控制器通常会把状态作为 status register 或内部 FSM 条件暴露出来。

## 3. 信息寄存器不是一张表，而是初始化和传输的输入

SD 卡有一组信息寄存器：CID、RCA、DSR、CSD、SCR、OCR、SSR、CSR。它们的宽度不同、读取方式不同、用途也不同。Host 初始化不是“发几条固定命令”就结束，而是要把这些寄存器中的关键信息读出来，写入内部寄存器或交给软件。

![SD 信息寄存器表](<./screenshots/任务064_AHB_sd_host控制器设计3/task64_15m00s.jpg>)

视觉核验：
- 教学职责：这张图负责把一堆缩写转成初始化需要保存的设计对象，避免只背 CID/CSD/SCR 名字。
- 看图要点：看每个寄存器的宽度、mandatory/optional 属性和用途；尤其关注 RCA、CSD、SCR、OCR、CSR 这些会直接影响命令、容量、位宽、状态和错误处理的字段。
- 漏看后果：Host 只能把 response 原样丢给软件，内部 FSM 无法知道卡是否 ready、是否支持宽总线、地址和块长应该怎样解释。

这张信息寄存器表的读法不是“缩写背诵”，而是“字段去向追踪”：OCR 去初始化 ready 和电压判断，RCA 去 addressed command 的 argument，高容量/块长能力去地址解释，SCR 去 1-bit/4-bit 和版本能力，CSR 去错误恢复。每个字段都应该能回答“被谁读、驱动哪个决策、错了会报什么”。
寄存器用途要这样记：

| 寄存器 | 宽度 | 作用 | Host 侧怎么用 |
|---|---:|---|---|
| CID | 128 | 卡身份识别信息 | 初始化阶段识别卡，不直接决定普通读写地址 |
| RCA | 16 | Relative Card Address | 多卡或选卡时的本地地址，CMD7 选择卡要用 |
| DSR | 16 | Driver Stage Register，可选 | 配置输出驱动能力，课程中可先作为可选项 |
| CSD | 128 | Card Specific Data | 读取容量、block length、操作条件等核心能力 |
| SCR | 64 | SD Configuration Register | 读取 SD 特性和总线宽度等配置能力 |
| OCR | 32 | Operation Conditions Register | 电压窗口、上电 ready、容量类型等 |
| SSR | 512 | SD Status | 获取卡的更详细状态或厂商相关特性 |
| CSR | 32 | Card Status | 命令响应里的状态判断和错误标志 |

设计 SD Host 时，不能把 response register 只当作临时显示值。对 CSD、SCR、OCR、RCA 这类关键字段，Host 或软件必须解析并保存，否则后续无法正确配置容量、位宽、时钟和命令目标。

## 4. `fOD` 到 `fPP` 的切换体现初始化和传输的分界

识别阶段 Host 应保持在较低的 `fOD` 频率，因为不同卡上电后可能有操作频率限制。进入 Data Transfer Mode 后，Host 才可以在 `fPP` 范围内提高频率。课程中特别标出：clock rate 会在某个点从 `fOD` 切换到 `fPP`。

![数据传输阶段与时钟切换](<./screenshots/任务064_AHB_sd_host控制器设计3/task64_35m00s.jpg>)

视觉核验：
- 教学职责：这张图负责把“初始化低速、传输提速”变成 clock divider 的设计边界。
- 看图要点：看识别阶段保持 `fOD`，Data Transfer Mode 可运行在 `fPP`；同一页还提示 CMD9 读 CSD、CMD4 可选、CMD7 选卡进入 Transfer State。
- 漏看后果：Host 可能过早切高速导致卡无响应，或者进入传输阶段后仍用初始化低速，功能看似正确但吞吐严重不足。

这对 RTL 是一个实际 clock divider 问题：

```text
上电/识别阶段：
  sd_clk = low frequency fOD
  发送初始化、识别、电压确认、RCA/CSD 等命令

进入传输阶段：
  确认卡能力和状态
  切换 clock divider 到 fPP
  执行 block read/write
```

通过标准不是“寄存器里有个 clock_sel”，而是波形上能证明：初始化命令在低速时钟下完成，`CMD7` 选中后才允许进入高速传输配置；如果后续命令失败，错误寄存器能区分 clock/timeout、CRC、illegal state。

## 5. CMD9、CMD4、CMD7 是初始化链路里的关键节点

课程提到三个典型命令：

| 命令 | 作用 | 是否关键 |
|---|---|---|
| CMD9 `SEND_CSD` | 读取 CSD，获得 block length、容量等 card specific data | 关键 |
| CMD4 `SET_DSR` | 配置 DSR，和驱动级相关 | 可选，host/card 可不支持 |
| CMD7 | 选择一张卡进入 Transfer State；RCA 为 0 时可用于取消选择 | 关键 |

这三个命令说明初始化 FSM 不是线性“发完就完”，而是有条件分支：

```text
识别和地址分配完成
  -> 读取 CSD / CID / OCR 等能力信息
  -> 可选配置 DSR
  -> 用 RCA 通过 CMD7 选择目标卡
  -> 进入 Transfer State
  -> 切换时钟并允许数据命令
```

如果 Host 没有保存 RCA，就无法正确选择指定卡；如果没有读 CSD/SCR，就不知道 block、容量和位宽能力；如果没有状态跟踪，就可能在 Stand-by 和 Transfer 的边界上发错命令。

## 6. 信息寄存器映射到 AHB 侧时，要区分原始响应和解析字段

一个工程化 SD Host 通常会同时提供两类软件可见信息：

| 字段类型 | 更适合谁使用 | 示例 |
|---|---|---|
| 原始寄存器 | 软件驱动、调试 | CSD[127:0]、CID[127:0]、SCR[63:0] |
| 解析字段 | 硬件 FSM 或快速状态 | card_ready、high_capacity、selected、crc_error |
| 中断/状态位 | 软件事件处理 | command_done、transfer_done、timeout、data_crc_error |

原始值方便软件或驱动按规范解析；解析字段方便硬件 FSM 快速判断。课程阶段可以先记住最小要求：RCA、OCR ready/voltage、CSD capacity/block 信息、SCR bus width 能力、CSR error/status 都不能丢。

## 7. 最小闭环：CMD3/R6 到 CMD13 的复现链

初始化能不能闭合，最适合用 `CMD3/R6 -> CMD7 -> CMD13` 这一条链来复现。它把“卡给 Host 一个 RCA”“Host 用 RCA 选中卡”“Host 再查询卡是否真的进入可传输状态”串成闭环。

```text
CMD3:
  expect R6
  -> parse response[39:24] as RCA
  -> rca_valid = 1

CMD7:
  argument[31:16] = rca_reg
  -> expect R1/R1b
  -> selected = 1 only after response ok and busy done

CMD13:
  argument[31:16] = rca_reg
  -> expect R1
  -> check CURRENT_STATE=tran and READY_FOR_DATA=1
```

| 阶段 | AHB/Host 输入 | SD 响应 | Host 内部结果 | 失败信号 |
|---|---|---|---|---|
| `CMD3` | command index 3 | `R6` | `rca_reg` 锁存，`rca_valid=1` | RCA 为 0、R6 CRC/index 错 |
| `CMD7` | argument 高 16 bit = `rca_reg` | `R1/R1b` | `selected=1`，允许进入 transfer 检查 | RCA 位域错、busy 未等完 |
| `CMD13` | argument 高 16 bit = `rca_reg` | `R1 card status` | `current_state=tran`，`READY_FOR_DATA=1` | 状态不是 `tran`、错误位未清 |

这条链像“拿到号码牌、叫到窗口、再让窗口确认已开始服务”。号码牌是 RCA，`CMD7` 是选中，`CMD13` 是验收。只做前两步不够，因为选卡响应通过不等于后续读写已经合法；最终要让 card status 自己证明当前状态可传输。

可写断言口径：

```systemverilog
assert property (@(posedge sd_clk) cmd7_start |-> rca_valid);
assert property (@(posedge sd_clk) transfer_cmd_start |-> selected && current_state_tran);
assert property (@(posedge sd_clk) high_speed_req |-> selected && capability_high_speed_known);
```

这些断言能防住三类初始化错：没有 RCA 就选卡、未进入 `tran` 就发数据命令、未确认能力就切高速。

## 8. 最小闭环：SD 卡初始化到可读写状态

```text
1. 复位 Host，设置低速 sd_clk = fOD。
2. 发送初始化相关命令，让卡从 Idle 进入识别流程。
3. 读取/确认 OCR，判断电压窗口和 ready。
4. 获取或保存 RCA。
5. 读取 CID/CSD，至少保存 CSD 供容量和 block 参数使用。
6. 必要时读取 SCR，确认总线宽度能力。
7. 用 CMD7 选择目标卡，进入 Transfer State。
8. 根据能力切换到 fPP，允许 block read/write。
```

通过标准：

| 检查项 | 通过标准 |
|---|---|
| 频率 | 识别阶段低速，传输阶段可切换高速 |
| RCA | Host 能保存并使用 RCA 选择卡 |
| CSD/OCR/SCR | 关键寄存器能读取或由软件可见 |
| 状态 | selected/transfer 状态明确，未选中时不发数据命令 |
| 错误 | timeout、CRC、非法状态能上报 |

失败信号：

| 失败 | 优先排查 |
|---|---|
| 初始化一直 timeout | `fOD` 是否过高、CMD 方向释放、OCR ready 等待窗口 |
| CMD7 后读写无响应 | RCA 是否保存/放入 argument 高 16 bit，selected 状态是否置位 |
| 读写容量或地址异常 | CSD 解析、容量类型、block length、地址单位 |
| 高速模式后 CRC 错 | clock divider、输出相位、IO 时序和卡能力字段 |

## 复习与自测

1. 为什么 SD Host 需要关心 SD 协议版本？  
   答案：版本影响容量类型、速度模式、命令集合和寄存器字段解释。Host 设计必须限定能力边界，否则会把不支持的协议行为误认为可用。

2. card identification mode 和 data transfer mode 的核心区别是什么？  
   答案：identification mode 主要做上电、识别、电压确认、地址分配和能力读取；data transfer mode 才进行卡选择后的读写、发送/接收数据和 programming/busy 处理。

3. CID、RCA、CSD、OCR、SCR 分别主要回答什么问题？  
   答案：CID 回答“这张卡是谁”；RCA 回答“Host 本地怎么称呼这张卡”；CSD 回答“容量、block、操作条件等能力”；OCR 回答“电压窗口和 ready/容量类型”；SCR 回答“SD 特性和总线宽度能力”。

4. 为什么识别阶段不能一开始就用高速时钟？  
   答案：上电识别阶段卡可能有频率限制，需要在 `fOD` 低速下完成识别和能力确认；过早高速可能导致卡无响应或通信错误。

5. CMD7 的作用是什么？RCA 和 CMD7 有什么关系？  
   答案：CMD7 用 RCA 选择一张卡进入 Transfer State；RCA 为 0 的特殊形式可用于取消选择，使卡回到 Stand-by。

6. AHB 侧保存原始 CSD/SCR/OCR 和保存解析字段，各自有什么价值？  
   答案要点：原始值便于软件驱动按规范完整解析和调试；解析字段便于硬件 FSM 快速判断状态、容量类型、位宽、ready 和错误。

7. 初始化完成到可读写状态至少要看到哪些成功信号？  
   答案要点：OCR ready 成立，RCA 保存，CSD/SCR 等关键能力可见，CMD7 选卡成功，状态进入 Transfer State，clock 可从 `fOD` 切到 `fPP`，错误寄存器没有 timeout/CRC/illegal state。



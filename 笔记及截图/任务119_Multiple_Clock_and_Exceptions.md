# 任务119：Multiple Clock and Exceptions

## 本章知识全景图

这一讲解决多时钟设计中最危险的约束问题：工具默认会尝试在所有相关时钟之间建立 timing check，但真实芯片里有些时钟同源同步，有些时钟异步，有些时钟互斥，有些路径虽然跨时钟却由同步器或握手协议保证功能安全。Multiple Clock and Exceptions 的核心不是“把违例消掉”，而是把每一类时钟关系和路径例外写成可审查的 SDC，使 STA 不制造假违例，也不漏掉真实违例。

| 概念 | 它回答什么问题 | 写错后的后果 |
|---|---|---|
| related clocks | 两个 clock 是否有确定相位/频率关系 | 同步路径被误当异步，或异步路径被错误计时 |
| generated clock | 派生 clock 如何继承源 clock 的相位关系 | 分频/门控/反相 clock 路径被漏算或相位错误 |
| asynchronous clocks | 两个 clock 无固定相位关系 | STA 报大量无意义违例，或 CDC 风险被假装解决 |
| exclusive clocks | 两个 clock 不会同时在同一模式有效 | mux clock、mode clock 之间产生假路径 |
| false path | 功能上不需要按 timing 闭合的路径 | 不声明会假违例，误声明会掩盖真实路径 |
| multicycle path | 数据允许多拍完成的同步路径 | 不声明会过度优化，误声明 hold 会出错 |
| max/min delay exception | 对特定路径设绝对延时边界 | 不设会失去接口约束，乱设会绕开同步检查 |

最短学习路径：先给每个 clock 分类，再判断 clock 之间是同步、异步、派生还是互斥；然后只对有明确功能理由的路径写 exception；最后用 `check_timing`、`report_timing`、`report_exceptions` 或等价报告证明例外没有过度覆盖。

## 课程上下文地图

| 前后课程 | 连接关系 |
|---|---|
| Timing Constraints | 已经知道单时钟下 input/output/reg-to-reg 路径如何约束 |
| 附加约束选项 | 已经知道用 `-from/-to/-through`、`-max/-min`、edge option 精确定位路径 |
| 本讲 | 把路径定位推进到多时钟关系和 timing exception |
| DC 输出 | 写出的 SDC 必须把 clocks 和 exceptions 一起交给下游 STA/P&R |
| 形式验证 | exception 不能替代功能等价、CDC、协议和形式检查 |

## 1. 多时钟不是“多个 create_clock”这么简单

一个 design 里有多个 `create_clock` 后，STA 会尝试根据周期、波形和共同边沿建立 launch/capture 关系。只要工具认为两个 clock 有可分析关系，它就可能分析从 clock A 发出的寄存器到 clock B 捕获的寄存器路径。

```tcl
create_clock -name ClkA -period 2.0 [get_ports ClkA]
create_clock -name ClkB -period 3.0 [get_ports ClkB]
```

如果不补充关系，工具可能会寻找两个周期的公共边沿，把跨域路径当作需要满足的同步 timing path。这个默认行为在某些同源时钟里是正确的，在真正异步 clock domain crossing 里会产生无意义违例。

多时钟约束的第一步不是写 false path，而是分类：

| 时钟关系 | 判断问题 | 典型处理 |
|---|---|---|
| 同源同步 | 是否来自同一 PLL/root clock，有确定相位关系 | 保持 timing 分析，必要时建 generated clock |
| 派生时钟 | 分频、倍频、反相、门控后仍可追溯源 clock | `create_generated_clock` |
| 异步时钟 | 频率/相位无固定关系，不能按单周期收敛 | `set_clock_groups -asynchronous` 或受控 false path |
| 互斥时钟 | 不同模式不会同时有效 | `set_clock_groups -exclusive` 或 mode-specific 约束 |
| 近似相关但有 CDC 协议 | 物理 clock 可能相关，但功能跨域靠同步/握手 | STA + CDC 检查分工，不用 exception 掩盖协议风险 |

## 2. generated clock：派生时钟必须继承正确的源关系

分频、门控、mux、反相或 PLL 输出 clock 不能只靠普通 `create_clock` 随便再建一个。派生 clock 如果和源 clock 有确定关系，应使用 generated clock 描述来源、分频/倍频和边沿。

```tcl
create_clock -name Clk -period 2.0 [get_ports Clk]

create_generated_clock -name Clk_div2 \
  -source [get_ports Clk] \
  -divide_by 2 \
  [get_pins U_divider/clk_out]
```

这条命令告诉工具：`Clk_div2` 不是孤立 clock，而是从 `Clk` 派生出来，周期和相位关系可追溯。这样 `Clk -> Clk_div2`、`Clk_div2 -> Clk` 的路径才有合理的 launch/capture 关系。

常见错误：

- 把 generated clock 当成独立 `create_clock`，丢失相位关系。
- 对 clock mux 输出没有说明不同输入 clock 的互斥关系。
- 对 clock gating cell 输出没有保留可分析的 generated clock 或 propagated clock 关系。
- 只在 RTL clock port 上建 clock，忘记在分频输出 pin 上建立派生 clock。

判断口径是 `report_clock`：派生 clock 应显示 source、period、waveform 或边沿关系。报告里如果只看到两个互不相关的普通 clock，就要回查 generated clock。

## 3. 异步时钟：STA 不负责证明 CDC 安全

异步时钟之间没有固定相位关系，STA 不能用某个固定 launch/capture 边沿证明跨域数据总能满足 setup/hold。此时要把两个问题分开：

1. STA：不要对无意义的异步跨域路径做普通同步 timing closure。
2. CDC/功能验证：必须证明跨域结构有同步器、握手、FIFO、toggle、Gray code 或其他安全协议。

常见约束：

```tcl
set_clock_groups -asynchronous \
  -group [get_clocks ClkA] \
  -group [get_clocks ClkB]
```

这条命令告诉 STA：`ClkA` 和 `ClkB` 之间不要按同步时序关系分析。它不会证明 CDC 安全，也不会检查同步器级数、数据稳定窗口、reconvergence、reset crossing 或协议丢脉冲。

工程规则很直接：异步 clock exception 只能解决 STA 假违例，不能替代 CDC signoff。写了 `set_clock_groups -asynchronous` 后，还应该有 CDC 工具报告、结构审查或仿真/形式验证证据。

## 4. exclusive clocks：互斥关系用来消除 mode 上不存在的路径

有些 clock 不异步，而是互斥。例如 clock mux 选择 `Clk_func` 或 `Clk_test`，同一时间只有一个 clock 能驱动某个子系统。默认 STA 可能会分析两个模式之间的路径，制造不存在的 launch/capture 组合。

```tcl
set_clock_groups -logically_exclusive \
  -group [get_clocks Clk_func] \
  -group [get_clocks Clk_test]
```

可以把 exclusive 理解成“模式空间里不会同时成立”。它与 asynchronous 的区别是：

| 关系 | 含义 | 重点风险 |
|---|---|---|
| asynchronous | 两个 clock 可同时存在，但相位无固定关系 | CDC 结构必须另行验证 |
| logically exclusive | 逻辑模式互斥，不会同时驱动同一功能关系 | mode 条件必须真实，不能拿来隐藏普通路径 |
| physically exclusive | 物理上同一路径/同一 mux 只能选择一个 clock | mux 结构、case analysis、test mode 要一致 |

exclusive 约束的失败信号是模式假设和 RTL/DFT 不一致。例如 scan 模式下两个 clock 实际可能同时活动，但 SDC 仍把它们 exclusive 掉，测试时序就会被漏分析。

## 5. false path：只用于功能上不需要计时的路径

`set_false_path` 的作用是告诉 STA：这条路径不需要按普通 timing path 检查。它不是“把难收敛路径删掉”的按钮。

```tcl
set_false_path \
  -from [get_clocks ClkA] \
  -to   [get_clocks ClkB]
```

或更精确：

```tcl
set_false_path \
  -from [get_pins U_cfg_reg/Q] \
  -to   [get_pins U_status_reg/D]
```

适合 false path 的场景：

- 静态配置寄存器在运行模式中不会频繁改变。
- test/debug 模式路径在功能模式不参与 timing。
- 异步 reset deassertion 已另有 reset strategy 和 RDC 检查。
- CDC 同步器前级路径不应按同步 setup/hold 收敛，但 CDC 结构另有审查。

不适合 false path 的场景：

- 普通同步路径 timing 太差。
- 没查清路径来源，只想让 report clean。
- 多周期路径误写成 false path。
- CDC 数据总线没有握手或 Gray code，就把跨域路径 false 掉。

false path 的危险在于它通常优先级很强，能直接让路径从 timing analysis 中消失。写完后必须抽样报告被屏蔽路径，并确认屏蔽理由来自功能关系，而不是来自 timing 压力。

## 6. multicycle path：多拍路径必须同时处理 setup 和 hold

`set_multicycle_path` 用于同步时钟关系下的数据允许多拍到达。例如控制信号每 3 个周期才被采样一次，默认单周期 setup 检查过紧，就可以把 setup 放宽到 3 拍。

```tcl
set_multicycle_path 3 -setup \
  -from [get_registers src_reg*] \
  -to   [get_registers dst_reg*]

set_multicycle_path 2 -hold \
  -from [get_registers src_reg*] \
  -to   [get_registers dst_reg*]
```

这里最关键的是第二条。常见口径是：setup 放宽 N 拍后，hold 通常要配套设为 N-1 拍，避免 hold 检查被错误移动到过宽的位置。不同工具和具体 clock 关系可能有细节差异，但工程原则不变：multicycle 不能只看 setup，必须核对 hold。

可视化理解：

```text
默认：launch 第 0 拍 -> capture 第 1 拍
MCP 3 setup：launch 第 0 拍 -> capture 第 3 拍
配套 hold：保持窗口也要调整，避免工具用错误边沿做 min check
```

适用场景：

- enable 控制的数据路径只在每 N 拍有效一次。
- 低速控制路径跨越高速 clock，但仍在同一同步关系下。
- 算法结构允许多个周期完成，且接收端不会每拍采样。

不适用场景：

- 跨异步 clock domain 的普通 CDC。
- 只是因为当前 timing 过不了。
- RTL 中没有 enable/protocol 证明数据确实多拍有效。

multicycle path 的合格证据不是命令存在，而是 timing report 里 setup/hold 的 launch/capture 边沿符合预期，且 RTL/协议能证明接收端不会提前使用数据。

## 7. max/min delay exception：给非默认路径保留绝对边界

有些路径不能按默认 clock-to-clock 关系分析，但也不能完全 false 掉。此时可以用 max/min delay 给绝对延时边界。

```tcl
set_max_delay 5.0 \
  -from [get_ports async_req] \
  -to   [get_pins U_sync1/D]

set_min_delay 0.2 \
  -from [get_ports async_req] \
  -to   [get_pins U_sync1/D]
```

这类约束常用于：

- 异步输入到同步器前级的物理延时边界。
- handshake 或 pulse stretching 中需要限制传输窗口的路径。
- 不适合默认同步分析，但仍有电路级最大/最小延时要求的接口。

它与 false path 的区别：

| 约束 | 对路径做什么 | 风险 |
|---|---|---|
| false path | 从普通 timing analysis 中移除 | 过度移除会漏违例 |
| max delay | 保留最大延时上限 | 数值没依据会制造虚假目标 |
| min delay | 保留最小延时下限 | 漏写可能导致 hold-like 风险 |
| clock group | 批量定义 clock 关系 | 范围太大时会屏蔽细粒度路径 |

工程里不要把这几类混用成“让报告变绿”的技巧。每条 exception 都要回答：默认 STA 为什么不适用、替代关系是什么、用什么报告证明覆盖范围没有过宽。

## 8. exception 的优先级风险：宽约束会吞掉窄约束

多时钟项目最常见的事故是先写了一个很宽的 clock group 或 false path，后面又写了精细的 max delay、multicycle path，但精细约束实际上不再生效。结果是报告 clean，真实风险被屏蔽。

危险模式：

```tcl
set_clock_groups -asynchronous \
  -group [get_clocks ClkA] \
  -group [get_clocks ClkB]

set_max_delay 2.0 \
  -from [get_clocks ClkA] \
  -to   [get_clocks ClkB]
```

如果第一条已经把两组 clock 之间所有路径切掉，第二条 max delay 可能不会按你期望约束那些路径。不同工具的报告细节不同，但审查原则一致：宽 exception 之后必须用 exception report 和 targeted timing report 证明想保留的路径没有被吞掉。

推荐做法：

1. 先列 clock interaction matrix。
2. 对每一对 clock 标注同步、异步、互斥、派生或需要局部例外。
3. 能用精确 `-from/-to/-through` 的，不先写全局 false path。
4. 写宽 clock group 后，抽样确认没有需要 max/min delay 的路径被意外移除。
5. exception 清单和 CDC 清单要互相引用。

## 9. 多时钟约束的验证闭环

写完 multiple clocks and exceptions 后，至少要做五类检查：

| 检查 | 目标 | 典型命令或报告 |
|---|---|---|
| clock 完整性 | 每个真实/派生 clock 都存在，波形正确 | `report_clock` |
| clock 关系 | 同步、异步、互斥关系是否符合设计 | clock interaction / `check_timing` / targeted `report_timing` |
| exception 覆盖 | false/multicycle/max/min 是否命中非空对象 | `report_exceptions` 或等价例外报告 |
| 路径抽样 | 被屏蔽或放宽的路径是否确实有功能理由 | `report_timing -from ... -to ...` |
| CDC/RDC 补充 | STA 不分析的跨域路径是否由 CDC/RDC 工具接管 | CDC report、结构审查、协议验证 |

最低验收标准：

```text
没有 missing clock
没有未解释 unconstrained endpoint
没有对象为空的 exception
没有用 false path 掩盖普通同步 violation
每条 clock group / false path / multicycle path 都能说出功能理由
```

如果做不到这些，SDC 不能交给下游。下游 P&R 和 signoff STA 会沿用或重读这套时序意图，错误 exception 会把前端风险带到后端。

## 10. 小型示例：两个同步 clock、一个异步 clock、一个测试 clock

假设设计中有四个 clock：

```text
Clk       主功能 clock
Clk_div2  由 Clk 分频得到
Clk_async 外部异步接口 clock
Clk_scan  scan/test 模式 clock
```

约束思路：

```tcl
create_clock -name Clk -period 2.0 [get_ports Clk]

create_generated_clock -name Clk_div2 \
  -source [get_ports Clk] \
  -divide_by 2 \
  [get_pins U_div2/clk_out]

create_clock -name Clk_async -period 5.0 [get_ports Clk_async]
create_clock -name Clk_scan  -period 20.0 [get_ports Clk_scan]

# 主功能 clock 与异步接口 clock 不做普通同步 timing closure
set_clock_groups -asynchronous \
  -group [get_clocks {Clk Clk_div2}] \
  -group [get_clocks Clk_async]

# 功能模式 clock 与 scan clock 按模式互斥
set_clock_groups -logically_exclusive \
  -group [get_clocks {Clk Clk_div2}] \
  -group [get_clocks Clk_scan]
```

这段脚本只是一种骨架。真正项目里还要确认：

- `Clk_div2` 的生成点是否正确。
- `Clk_async` 进入主域的数据是否有同步器或 FIFO。
- `Clk_scan` 是否真的和功能 clock 互斥，ATPG/scan shift 是否有单独约束。
- 是否存在跨 `Clk` 和 `Clk_div2` 的同步路径需要正常分析。
- clock group 是否过宽，是否吞掉了应该保留 max/min delay 的路径。

## 11. 和 DC 输出的连接

任务120 中 SDC 是下游交付物。多时钟和 exceptions 是 SDC 里最需要审查的部分，因为它们决定下游 STA 会看哪些路径、忽略哪些路径、放宽哪些路径。

一份可交付的 SDC 对 exceptions 的要求：

1. clock 定义完整，包括 generated clock。
2. clock group 有设计模式或异步关系依据。
3. false path 有功能理由，不是 timing 逃避。
4. multicycle path 有 RTL enable/protocol 依据，并配套 hold 检查。
5. max/min delay 有数值来源和报告验证。
6. exception 对象非空，覆盖范围不过宽。
7. 被 STA 切掉的 CDC/RDC 路径有独立验证证据。

如果这些内容没有交付，下游拿到网表和 SDC 后可能得到一个“看起来 clean”的 timing 报告，但它的 clean 只是因为真正危险的路径被错误排除了。

## 12. 常见误区

| 误区 | 正确理解 |
|---|---|
| 多个 clock 自动都是异步 | 工具会尝试分析 clock 关系；是否异步必须由设计关系决定 |
| false path 是修 timing 的工具 | false path 只用于功能上不需要计时的路径 |
| CDC 写 false path 后就安全 | false path 只影响 STA，CDC 安全要靠同步结构和 CDC/RDC 验证 |
| multicycle 只写 setup | setup 放宽后必须检查 hold，常见需要配套 N-1 hold |
| generated clock 可以随便 create_clock | 派生时钟应保留 source 和分频/相位关系 |
| clock group 越宽越省事 | 宽 clock group 可能吞掉本该保留的 max/min 或同步路径 |
| report clean 就说明 exception 正确 | 还要看 exception report、对象非空、路径抽样和 CDC 补充证据 |

## 自测题与答案

1. 为什么多个 clock 不能默认全部 `set_false_path`？

   答：有些 clock 是同源同步或 generated clock，跨 clock 路径需要正常 STA；全部 false 掉会漏掉真实 timing violation。只有功能上不需要计时或 clock 关系不适合默认同步分析的路径，才能写 exception。

2. `create_generated_clock` 解决什么问题？

   答：它描述派生 clock 与源 clock 的关系，例如分频、倍频、反相或生成点，使 STA 能正确计算相位、周期和跨源/派生 clock 的 timing path。

3. `set_clock_groups -asynchronous` 为什么不能证明 CDC 安全？

   答：它只告诉 STA 不要按同步 timing 分析这些 clock 之间的路径；CDC 安全还需要同步器、握手、FIFO、Gray code、RDC 策略等结构和验证证据。

4. false path 和 multicycle path 的核心区别是什么？

   答：false path 表示功能上不需要计时，路径从普通 timing analysis 中移除；multicycle path 表示路径仍然需要计时，但允许多个周期完成。

5. multicycle path 为什么要关注 hold？

   答：setup 放宽到 N 拍后，hold 检查的参考边沿也会受影响。如果不配套调整 hold，工具可能使用错误的保持窗口，导致虚假 hold 通过或虚假 hold 违例。

6. clock group 写得过宽有什么风险？

   答：它可能屏蔽本应正常分析或本应设置 max/min delay 的路径。结果 report 变 clean，但真实路径没有被检查。

7. 判断一条 exception 合格，至少要提供哪三类证据？

   答：第一，功能理由，例如异步、互斥、多周期协议或静态配置；第二，对象和路径非空，可由 exception report 或 targeted timing report 证明；第三，被放松或移除的风险有补充验证，例如 CDC/RDC、RTL enable/protocol 或模式约束证据。

8. 在 AI 芯片设计中，哪些模块最容易需要多时钟和 exception 审查？

   答：DMA、NoC bridge、SRAM/AXI/AHB/APB 接口、低功耗 clock gating 区、scan/test wrapper、配置寄存器跨域、外设异步接口和 NPU 计算阵列的多频域边界。

## AI+IC 工程落点

AI 芯片往往不是一个 clock 跑到底。NPU core、NoC、DMA、SRAM wrapper、外设、debug、scan/test、低功耗门控域都可能有不同 clock 或不同模式。Multiple Clock and Exceptions 是前端 SDC 中最容易“看似专业、实则危险”的部分：写少了会产生假违例和过度优化，写多了会漏掉真实违例。工程上必须把 clock relation、exception、CDC/RDC 验证和下游 STA 读入检查绑定在一起，不能只追求 `report_constraint` clean。


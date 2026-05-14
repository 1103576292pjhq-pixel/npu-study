# 78_AHB_sd_host控制器设计17

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：阅读 `sd_clock` 模块，理解 SD Host 如何生成 SD clock、如何分频、如何停钟、如何处理 DFT/test mode，以及如何追踪 clock 输出到 command/data/FIFO 模块。
- 核心概念：`test_mode`、`divide`、`divide_zero_value`、divider counter、`sd_clock_enable`、`clock_stop`、clock mux、clock gate、`fifo_sd_clock`、`out_sd_clock_dft`、clock special cell、grep tracing。
- 逻辑主线：SD clock 不是普通数据线；它同时承担协议速度、FIFO 反压、DFT 可控性和多模块同步。RTL 中 mux/gate 的位置决定停钟语义，不能只按 PPT 图直觉理解。
- 最小主线：
  - `divide` 决定半周期计数，输出周期是 `2 * divide * HCLK周期`。
  - 不分频时选择 HCLK，同时停止 divider 空翻转以省功耗。
  - `clock_stop` 应独立表达“是否输出 clock”，不应和“是否分频”语义混在一起。
  - clock mux/gate 要用专用库单元，普通组合 mux 不适合大扇出时钟。
  - `out_sd_clock_dft` 驱动 command/data 相关逻辑，`fifo_sd_clock` 驱动 FIFO，二者的停钟行为必须核对。

### 2. 概念地图

| 概念层级 | 信号/结构 | 作用 | 关键风险 |
|---|---|---|---|
| 分频 | `divide`、counter、toggle clock | 生成低速/高速 SD clock | 把 `divide=2` 错认为二分频 |
| 直通 | `divide_zero_value` | 不分频时直接选 HCLK | divider 空翻转浪费功耗 |
| 停钟 | `clock_stop` | 读 FIFO 反压时暂停 SD clock | 只影响部分路径导致语义不一致 |
| 使能 | `sd_clock_enable` | 总体允许 clock 输出 | 和 stop 语义混淆 |
| DFT | `test_mode`、`out_sd_clock_dft` | 测试模式下 clock 可控 | 功能 clock 和 test clock 切换不安全 |
| 时钟单元 | clock mux/gate special cell | 避免 glitch、skew、CTS 风险 | 用普通 mux/gate 写 clock |
| 下游连接 | command/data/FIFO/sync | 确认 clock 分发范围 | 只看局部模块，漏掉实际影响 |

### 3. 最短学习路径

1. 先算分频：`divide=1` 对应二分频，`divide=2` 对应四分频，`divide=N` 对应 `2N` 分频。
2. 再看停钟：stop 不是改变频率，而是控制是否继续给 SD/FIFO 相关模块 clock。
3. 最后看代码/PPT差异：PPT 给意图，RTL 给真实连接；发现语义混乱时要写成 review 风险。

### 4. 全讲结构地图

| 阶段 | 画面/代码主线 | 必须学会的判断 |
|---|---|---|
| 00:00-07:30 | 打开 `sd_clock`，看端口 | clock 模块首先按输入输出理解 |
| 07:30-14:30 | `divide_zero_value`、divider counter | 分频参数是半周期计数 |
| 14:30-22:00 | counter 停止、省功耗、clock stop | 功能正确之外还要避免无意义翻转 |
| 22:00-33:30 | mux/gate、PPT 与代码差异 | stop 和 divide 的语义不能互相污染 |
| 33:30-39:30 | clock special cell | clock mux/gate 要用专用单元 |
| 39:30-48:48 | grep 追踪下游连接 | `out_sd_clock_dft` 和 `fifo_sd_clock` 使用对象不同 |

## 1. `sd_clock` 模块同时处理分频、停钟、使能和 DFT

`sd_clock` 的输入包括 `test_mode`、基准 `clk/reset`、`divide`、`sd_clock_enable`、`clock_stop`；输出包括 `fifo_sd_clock` 和 `out_sd_clock_dft`。这已经说明它不只是一个 divider，而是 SD Host clock 控制中心。

![sd clock PPT diagram](<./screenshots/任务078_AHB_sd_host控制器设计17/task78_docx_002.jpeg>)

端口分工：

| 信号 | 含义 | 后续影响 |
|---|---|---|
| `divide` | 分频计数参数 | 决定 SD clock 频率 |
| `sd_clock_enable` | clock 总使能 | 关掉功能时钟输出 |
| `clock_stop` | 硬件停钟请求 | FIFO/DMA 反压时暂停 |
| `test_mode` | DFT/测试模式 | 选择测试可控 clock |
| `fifo_sd_clock` | FIFO 使用的 clock | FIFO 读写时钟 |
| `out_sd_clock_dft` | command/data/sync 使用的 clock | command/data FSM 和 shift 模块时钟 |

分频器像节拍器，`divide` 决定节拍快慢；`clock_stop` 像静音键，决定节拍是否传给外部；`test_mode` 像维修旁路，决定调试/测试时是否绕开正常演奏。三者不应互相冒充：把静音键写进速度选择里，后面就很难说明“到底是变慢了，还是没声音了”。

## 2. 分频公式是 `Tsd = 2 * divide * Thclk`

divider 的逻辑是计数到阈值后翻转输出 clock。一次完整输出周期需要两次翻转，所以 `divide` 表示半周期长度。

![divider code](<./screenshots/任务078_AHB_sd_host控制器设计17/task78_docx_006.jpeg>)

公式：

$$
T_{sd} = 2 \times divide \times T_{hclk}
$$

| `divide` | counter 行为 | 输出频率 |
|---:|---|---|
| 1 | 每 1 个 HCLK 半周期翻转 | HCLK / 2 |
| 2 | 每 2 个 HCLK 半周期翻转 | HCLK / 4 |
| 3 | 每 3 个 HCLK 半周期翻转 | HCLK / 6 |
| 8 | 每 8 个 HCLK 半周期翻转 | HCLK / 16 |

本章必须纠正一个常见误解：`divide=2` 不是二分频，而是四分频。因为计数值控制的是半周期，不是完整周期。

## 3. 不分频时要直通 HCLK，并阻止 divider 空翻转

`divide_zero_value` 用于表示不需要分频。此时最终 clock 可以直接选择 HCLK，divider 这一路即使继续计数也不会被使用。

![divide zero and counter stop](<./screenshots/任务078_AHB_sd_host控制器设计17/task78_docx_011.jpeg>)

课程特别强调功耗：如果不分频，但 counter 仍在 0 到 N 之间跳变，功能上可能不出错，功耗上是不合格设计。clock 相关逻辑翻转频繁，空转带来的动态功耗比普通低频控制信号更敏感。

合格策略：

| 条件 | counter | 输出 |
|---|---|---|
| 正常分频 | 计数、翻转 divided clock | 选择 divided clock |
| 不分频 | counter 保持或清零 | 选择 HCLK |
| stop | counter 停止或输出 gate | clock 输出暂停 |
| disable | 输出关闭 | 后级不接收 clock |

## 4. `clock_stop` 的语义应独立于“是否分频”

本讲最有价值的部分是对 RTL 和 PPT 差异的审视。PPT 上 stop 看起来是一个单独 gate；代码中 stop 会影响某些 mux 输入，使得 `fifo_sd_clock` 在分频和不分频场景下表现可能不同。

![clock stop and mux code](<./screenshots/任务078_AHB_sd_host控制器设计17/task78_docx_017.jpeg>)

课程中的判断是：如果 stop 在分频模式下让 `fifo_sd_clock` 输出 0，但在不分频模式下仍让 HCLK 通过，那么“停钟”语义就取决于是否分频。这是逻辑混乱点。

![clock stop code review point](<./screenshots/任务078_AHB_sd_host控制器设计17/task78_docx_020.jpeg>)

更清晰的设计分层应该是：

```text
频率选择：HCLK 或 divided clock
  -> 使能/停钟：enable && !clock_stop
  -> DFT/test mode mux
  -> 输出到 command/data/FIFO
```

也就是：

- divide 只决定频率。
- stop 只决定是否输出。
- test mode 只决定测试时钟选择。

如果一个条件同时改变频率选择和输出开关，后续 review 很难证明所有组合都符合设计意图。

最小真值表应当能写成：

| `sd_clock_enable` | `clock_stop` | `test_mode` | 期望语义 |
|---|---|---|---|
| 0 | 任意 | 0 | 功能 clock 不输出 |
| 1 | 0 | 0 | 输出由 `divide` 决定的功能 SD clock |
| 1 | 1 | 0 | 外部/应停路径停止，内部需搬运路径按设计说明保留或隔离 |
| 任意 | 任意 | 1 | 输出 DFT 可控 clock，满足 scan/test 约束 |

这张表不是为了替代 RTL，而是逼 RTL 作者回答每个组合的语义。若某一格只能靠“代码刚好这样走”解释，说明设计意图还不够清楚。

## 5. DFT/test mode 要保证测试 clock 可控

`test_mode` 通常让输出选择 HCLK 或专门测试 clock，目的是让 scan/DFT 阶段能可控地驱动寄存器。功能模式下，输出使用经过 enable/stop 处理的 SD clock；测试模式下，clock 选择需要满足 DFT 工具和测试向量要求。

![test mode output mux](<./screenshots/任务078_AHB_sd_host控制器设计17/task78_docx_023.jpeg>)

这里不要把 DFT 当成“课程里暂时不管”的无用输入。真实 ASIC flow 中，clock gating、clock mux、test mode 都会被 DFT 和 STA 约束检查；功能 RTL 写法若不利于测试，后端会直接暴露问题。

## 6. clock mux/gate 必须用专用单元，不要当普通数据 mux

画面中出现了专用 clock mux/gate 单元，而不是简单 `assign out_clk = sel ? a : b`。原因是时钟网络有大扇出、低 skew、无 glitch、CTS 和 STA 特殊要求。

![clock mux gate special cells](<./screenshots/任务078_AHB_sd_host控制器设计17/task78_docx_030.jpeg>)

普通组合 mux 切时钟的风险：

| 风险 | 说明 |
|---|---|
| glitch | select 变化时可能产生窄脉冲，触发寄存器误采样 |
| skew | 普通组合路径不按 clock tree 处理，时钟到达时间不可控 |
| duty distortion | 占空比被组合路径破坏 |
| STA/CTS 不收敛 | 工具无法按标准 clock network 正确处理 |

因此在 RTL 或综合约束里必须确保这些结构映射到库里的 integrated clock gate 或 clock mux cell。

## 7. grep 下游连接比只看局部代码更可靠

本讲后半段用 grep 追踪 `out_sd_clock_dft` 和 `fifo_sd_clock`。结果显示：

- `out_sd_clock_dft` 连接到 command send/receive、data send/receive、SDIF 输入以及跨域同步相关逻辑。
- `fifo_sd_clock` 连接到 FIFO。

![grep clock connections](<./screenshots/任务078_AHB_sd_host控制器设计17/task78_docx_039.jpeg>)

![out sd clock dft usages](<./screenshots/任务078_AHB_sd_host控制器设计17/task78_docx_042.jpeg>)

![fifo sd clock usages](<./screenshots/任务078_AHB_sd_host控制器设计17/task78_docx_043.jpeg>)

这一步会反过来验证 `clock_stop` 风险：如果 `fifo_sd_clock` 理论上只给 FIFO 使用，那么它是否应该被 stop 影响，要结合 FIFO 在读路径中的职责判断。课程里提出的疑问是合理的：分频时 stop 影响 FIFO clock，不分频时不影响，这种行为需要设计说明或修正。

这三张 grep 图要逐张对照 clock 的真实扇出范围：`out_sd_clock_dft` 主要影响 command/data/sync，`fifo_sd_clock` 影响 FIFO，连接清单比 PPT 框图更接近硅上事实。判断 stop 到底该不该影响 FIFO，不能靠“名字像不像外部 clock”，要靠这些 fanout 证据。

## 8. 从 clock 模块读 RTL 的方法

读 clock 模块应按下面顺序：

1. 列输入输出，先区分功能 clock、test clock、FIFO clock。
2. 写出每个 mux 的选择条件，明确它选择的是频率、使能还是测试模式。
3. 检查 counter 是否在不用时停止。
4. 检查 stop 是否对所有应暂停路径一致生效。
5. grep 下游连接，确认每一路输出实际驱动哪些模块。
6. 对 clock mux/gate 标注后端实现要求。

![clock tracing terminal](<./screenshots/任务078_AHB_sd_host控制器设计17/task78_docx_045.jpeg>)

这个方法比只看 PPT 更稳。PPT 给结构意图，RTL 决定真实行为，grep 决定真实影响范围。

## 工程检查清单

- `divide=1/2/3` 是否分别对应 HCLK/2、HCLK/4、HCLK/6。
- 不分频或 stop 时，divider counter 是否停止无意义翻转。
- `clock_stop` 是否对分频和不分频路径语义一致。
- `sd_clock_enable` 是否只表达总使能，不和 divide 语义混淆。
- `test_mode` 是否能选择 DFT 可控 clock。
- clock mux/gate 是否使用专用单元或可被综合映射到专用单元。
- `out_sd_clock_dft` 和 `fifo_sd_clock` 的下游连接是否符合设计意图。
- PPT 与 RTL 不一致时，是否记录为 review 风险并回到代码连接核实。

## 最后速记

- `divide` 是半周期计数，完整分频系数是 `2 * divide`。
- 不分频时直通 HCLK，但 divider 不应空翻转。
- stop 是“是否输出 clock”，divide 是“输出什么频率”，两者不要混写。
- clock mux/gate 是时钟专用逻辑，不是普通组合 mux。
- `out_sd_clock_dft` 主要给 command/data 控制逻辑，`fifo_sd_clock` 给 FIFO。
- 读 clock RTL 必须追下游连接，否则无法判断 stop 影响范围。

## 复习与自测

1. 为什么 `divide=2` 对应 HCLK/4？  
   答：`divide` 控制半周期计数，输出 clock 每 2 个 HCLK 周期翻转一次，完整周期需要两次翻转，所以是 4 个 HCLK 周期。

2. 不分频时 divider counter 继续跳变为什么不合格？  
   答：功能可能不受影响，但会产生无意义动态功耗；clock 相关逻辑翻转频率高，空转不应保留。

3. `clock_stop` 只在分频路径生效有什么风险？  
   答：同一个 stop 请求在分频和不分频模式下行为不同，读 FIFO 反压可能失效，语义不可证明。

4. 为什么 clock mux/gate 要用专用单元？  
   答：专用单元处理 glitch、skew、占空比、时序弧和 CTS；普通 mux/gate 无法保证时钟网络安全。

5. grep `out_sd_clock_dft` 的目的是什么？  
   答：确认它实际驱动哪些模块，从而判断 stop、enable、test mode 对 command/data/FIFO/sync 的真实影响。

6. 如果 PPT 和 RTL 对 stop 位置描述不一致，应信哪个？  
   答：先以 RTL 连接为准判断真实行为，再把和 PPT 不一致的地方记录为设计文档或 RTL 需要澄清的风险。


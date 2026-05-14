# 任务109：Timing Constraints1

## 本章知识全景图

这一讲开始把前一讲的 setup/hold 公式落到 DC timing constraints。核心不是记几条 SDC 命令，而是知道工具如何把一个 block 拆成四类 timing path，为什么 `create_clock` 是所有 setup 分析的起点，默认 clock 为什么过于理想，以及 `set_clock_uncertainty`、`set_clock_latency`、`set_clock_transition` 如何把真实时钟行为带进综合。

| 概念层级 | 核心概念 | 前置知识 | 延伸应用 |
|---|---|---|---|
| 路径拆分 | input-to-reg、reg-to-reg、reg-to-output、input-to-output | register、port、clock | 覆盖 block 内所有组合路径 |
| 时钟定义 | `create_clock -period`、duty cycle、clock object | Tcl option/argument | 给 timing 分析提供周期和参考边沿 |
| 默认模型 | synchronous default、ideal clock、zero skew/latency/transition | setup 公式 | 解释为什么默认约束过于乐观 |
| 时钟不确定性 | skew、jitter、margin、`set_clock_uncertainty` | CTS、后端 margin | 给 DC 留保守量 |
| 时钟延时和斜率 | source/network latency、transition time | clock tree、RC | 区分 pre-layout 和 post-layout clock modeling |

最短学习路径：先用四类 path 理解工具到底在分析什么；再学 `create_clock` 怎么定义周期和对象；随后看默认 ideal clock 的假设；最后补上 uncertainty、latency、transition，让 DC 在综合阶段不要过度乐观。

![Timing constraints 总览](<./screenshots/任务109_Timing_Constraints1/task109_dense_0240s_00h04m00s.jpg>)

看图要点：这张总览图要先把四类路径放进 block 级环境里读；input/output 端口外面默认还有同步寄存器，所以不补端口 delay 就等于偷偷吃掉系统周期预算。

## 本课主线地图

| 时间 | 教学主线 | 本笔记吸收方式 |
|---|---|---|
| 00:01-02:32 | timing constraints 是 DC flow 中最体现水平的部分 | 压缩为本讲目标 |
| 02:32-07:59 | 四类 timing path 和单时钟单周期前提 | 建立路径分类 |
| 07:59-17:36 | 默认 synchronous design scenario、input/output 外部延时需求 | 推出 input/output delay 的必要性 |
| 17:36-22:08 | `create_clock` 语法、period、`get_ports`、duty cycle、单位 | 写成 SDC 命令解析 |
| 22:08-28:34 | 默认 ideal clock、zero skew/latency/transition、DC 不做 CTS | 展开默认模型风险 |
| 28:34-35:06 | CTS、clock uncertainty、setup 例子 | 连接后端 margin 和公式 |
| 36:20-40:28 | source/network latency、clock transition | 区分 clock 到端口和端口到寄存器 |
| 41:04-45:27 | pre-CTS/post-CTS 约束差异 | 写成 pre/post layout clock modeling |

## 1. Timing path 只有四类起点和终点组合

DC 做 timing analysis 时，会把 block 切成从 startpoint 到 endpoint 的路径。对单时钟单周期 block，可以先掌握四类：

| 路径类型 | 起点 | 终点 | 需要的约束 |
|---|---|---|---|
| input-to-reg | input port | internal register data pin | clock、input delay |
| reg-to-reg | launch register clock pin | capture register data pin | clock |
| reg-to-output | internal register clock pin | output port | clock、output delay |
| input-to-output | input port | output port | virtual/real clock、input/output delay 或 max delay |

这四类来自两类 startpoint 和两类 endpoint 的组合：startpoint 可以是 input port 或 register；endpoint 可以是 register data pin 或 output port。理解这点后，后续所有 SDC 命令都可以问一句：它到底是在补哪一段外部时间，或者定义哪一个分析参考？

## 2. 默认同步场景会假设端口外面也接着触发器

Block-level 分析时，DC 只能看到本 block 内部；但真实芯片中，input port 前面可能有外部寄存器，output port 后面也可能有外部寄存器。默认同步场景假设这些外部数据也来自同一个上升沿触发的同步器件。

![默认设计场景](<./screenshots/任务109_Timing_Constraints1/task109_dense_0600s_00h10m00s.jpg>)

看这张图时要先接受工具的默认世界：block 外部也像接着同步触发器。这个假设方便建立模型，但如果你不声明外部已经消耗或还要预留的时间，工具就会把整周期几乎都借给本 block。

这会带来两个必须补充的信息：

- input path：外部 launch register 到本 block input port 已经消耗了多少时间。
- output path：本 block output port 到外部 capture register 还要预留多少时间。

如果不告诉工具这些时间，DC 会把所有周期预算都留给本 block 内部，综合结果就可能过于乐观。后续 `set_input_delay` 和 `set_output_delay` 就是为了解决这件事。

## 3. reg-to-reg setup 公式是所有约束的骨架

最基础的 reg-to-reg setup 检查可以写成：

$$
T_{ck\to q}+T_{comb}+T_{setup}\le T_{period}
$$

如果把外部 input delay 或 output delay 加进去，本质仍然是在切分同一个周期预算。

![reg-to-reg setup 例题](<./screenshots/任务109_Timing_Constraints1/task109_dense_0960s_00h16m00s.jpg>)

例如 input-to-reg 路径里，外部部分 $T_m$ 已经用掉时间，内部 $T_n$ 就只能使用剩余预算：

$$
T_m+T_n+T_{ck\to q}+T_{setup}\le T_{period}
$$

所以：

$$
T_n\le T_{period}-T_m-T_{ck\to q}-T_{setup}
$$

output path 也是同理。你必须告诉工具 output port 之后的外部时间 $T_t$，工具才能反推出本 block 内部 reg-to-output 路径 $T_s$ 的可用时间。

## 4. `create_clock` 定义的是 clock object，不只是一个数字

`create_clock` 给 timing 分析创建时钟对象。它至少要说明周期和作用对象。

```tcl
create_clock -period 2 [get_ports CLK]
```

![create_clock 参数](<./screenshots/任务109_Timing_Constraints1/task109_dense_1200s_00h20m00s.jpg>)

这条命令可以拆成：

| 片段 | 含义 |
|---|---|
| `create_clock` | 创建 clock object |
| `-period 2` | 周期为 2，单位由 technology library 定义，通常是 ns |
| `[get_ports CLK]` | 在端口 `CLK` 上创建 clock |
| 默认 waveform | 50% duty cycle，即 1 ns 高、1 ns 低 |

不要写 `2ns`。SDC 命令里的数值单位来自库和工具环境，参数里直接写单位字符串可能被工具当作非法 argument。

`create_clock` 像先画预算表，不是先修时钟树。它告诉工具“下一班车多久来一次、从哪个站台发车”，后面的 input/output delay、uncertainty、latency 才能围绕这个参考边沿切分时间。

如果要指定非 50% duty cycle，可以显式写 waveform：

```tcl
create_clock -period 2 -waveform {0 0.8} [get_ports CLK]
```

## 5. 默认 clock 是 ideal clock，过于乐观

只写 `create_clock -period 2 [get_ports CLK]` 时，DC 默认模型很理想：

1. 单时钟驱动所有寄存器路径。
2. duty cycle 默认 50%。
3. clock network 不插 buffer。
4. clock skew 为 0。
5. insertion latency 为 0。
6. transition time 近似为 0。

![默认 clock 行为](<./screenshots/任务109_Timing_Constraints1/task109_dense_1440s_00h24m00s.jpg>)

默认 clock 图里的 ideal clock 像一个完美节拍器：所有寄存器同时听到、边沿无限陡、传播没有代价。真实芯片里的 clock 更像一条分发网络，越往末端越要面对延时、偏斜和负载。

这意味着工具把 clock 当成无限驱动能力、瞬间到达所有寄存器、没有斜率、没有分布延迟的信号。真实芯片不可能这样。clock 从源头经过 clock tree 到各寄存器，必然有插入延时、skew、transition 和 jitter。

如果保持默认 ideal clock，DC 可能认为设计能跑 500 MHz；到了后端真实 clock tree 和线延时出现后，实际只能跑 300 MHz。这个差距不是后端“突然变差”，而是前端约束过于乐观。

## 6. DC 不做 CTS，但必须预留 CTS 相关效应

Clock Tree Synthesis 通常在 APR 阶段做，因为它依赖实际 cell placement。后端会根据寄存器物理位置插入 buffer/inverter，使 clock 到不同寄存器的到达时间尽量接近。

![clock tree 建模](<./screenshots/任务109_Timing_Constraints1/task109_dense_1800s_00h30m00s.jpg>)

DC 阶段不真正生成 clock tree，但综合必须考虑 clock tree 未来会带来的影响。否则综合出来的逻辑只在 ideal clock 下成立，接到后端会暴露 timing gap。

这就是为什么要设置：

```tcl
set_clock_uncertainty -setup 0.3 [get_clocks CLK]
set_clock_latency -source 3 [get_clocks CLK]
set_clock_latency 1 [get_clocks CLK]
set_clock_transition 0.08 [get_clocks CLK]
```

这些命令不是让 DC 现在做 CTS，而是把真实 clock 的保守估计写进综合分析。

## 7. `set_clock_uncertainty` 把 skew、jitter、margin 合成一个保守量

Clock uncertainty 可以包含 skew、jitter、工程 margin 等不确定因素。DC 不要求你把每个来源拆开输入，而是允许用一个时间量统一扣掉 setup 预算。

```tcl
set_clock_uncertainty -setup 0.3 [get_clocks CLK]
```

![uncertainty setup 例题](<./screenshots/任务109_Timing_Constraints1/task109_dense_2160s_00h36m00s.jpg>)

加上 uncertainty 后，setup 预算变成：

$$
T_{ck\to q}+T_{comb}+T_{setup}\le T_{period}-T_{uncertainty}
$$

如果 $T_{period}=2ns$，$T_{uncertainty}=0.3ns$，那么内部组合逻辑可用时间直接少 0.3ns。它的工程含义是：给后端 clock tree、jitter 和未知 margin 留空间，让 DC 不要把路径优化得刚好踩线。

## 8. Clock latency 要区分 source latency 和 network latency

Clock latency 分两段：

- source latency：真实 clock source 到 block clock port 的延时。
- network latency：block clock port 到内部 register clock pin 的延时。

![clock latency 模型](<./screenshots/任务109_Timing_Constraints1/task109_dense_2280s_00h38m00s.jpg>)

读 latency 图时要把 source latency 和 network latency 分开：前者在时钟源到 block 入口之前，后者在 block 内 clock port 到寄存器 clock pin 之间。两段都叫 latency，但它们影响的接口边界不同。

命令示例：

```tcl
set_clock_latency -source 3 [get_clocks CLK]
set_clock_latency 1 [get_clocks CLK]
```

这里的 `-source` 是从外部 clock source 到 port；不带 `-source` 的 latency 通常描述 clock port 进入设计内部后的 network latency。block-level 分析时，这两段都可能影响 input/output 和 reg-to-reg 路径预算。

不要把 latency 理解成“把 clock 改慢”。它是在 timing model 中告诉工具：clock 边沿不会瞬间到达各分析点，分析时必须考虑实际传播延时。

## 9. `set_clock_transition` 让 clock 不再是无限陡边沿

真实 clock 边沿不是垂直线，而有 10%-90% transition time。transition 影响 cell delay，因为触发器和组合门的 timing arc 与输入斜率相关。

![clock transition](<./screenshots/任务109_Timing_Constraints1/task109_dense_2400s_00h40m00s.jpg>)

命令示例：

```tcl
set_clock_transition 0.08 [get_clocks CLK]
```

如果不设 transition，工具可能按 ideal slew 估算，timing 又会偏乐观。设置 transition 的目标不是精确到后端每个 register，而是在 pre-layout 阶段给 clock slew 一个合理模型。

## 10. Pre-CTS 和 post-CTS 的约束口径不同

Pre-CTS 阶段，clock tree 还没真实生成，uncertainty 和 latency 往往要保守一些；post-CTS 阶段，后端已经有更真实的 clock tree 数据，某些估计值会被实际 extracted 值替代，uncertainty 也可能缩小。

![pre/post layout clock constraints](<./screenshots/任务109_Timing_Constraints1/task109_dense_2640s_00h44m00s.jpg>)

这张 pre/post 图回答的是同一套 clock constraint 如何随阶段切换而收紧或替换：pre-CTS 用估计和保守 margin，post-CTS 用真实 clock tree 与 propagated clock 重新计算。

视频里的典型变化是：

| 阶段 | 保留不变 | 可能变化 |
|---|---|---|
| pre-CTS | period、clock object | larger uncertainty、estimated latency、estimated transition |
| post-CTS | period、clock object | propagated clock、smaller skew margin、real clock latency/transition |

post-CTS 可能会使用 propagated clock：

```tcl
set_propagated_clock [get_clocks CLK]
```

这表示 STA 使用后端实际 clock network 计算出的到达时间，而不是前端估计的 ideal 或手工 latency。综合阶段要知道这条分界：DC 前面只是在建模，APR/STA 后面才有真实 clock tree 结果。

约束生效要用报告证明，不能只看 SDC 文件。最小检查顺序是：

```tcl
report_clock
check_timing
report_timing -delay_type max -group CLK -max_paths 3
report_constraint -all_violators
```

`report_clock` 证明 clock object 存在，`check_timing` 抓 no clock/unconstrained path，`report_timing` 证明路径进入正确 path group，`report_constraint` 证明 uncertainty、transition、fanout 等规则是否仍有违例。若这些报告没有变化，说明你写的约束可能没有绑到真实对象上。

## 本章收束与检查

### 本章最该记住的结论

- 单时钟单周期 block 的 timing path 可以先分成四类：input-to-reg、reg-to-reg、reg-to-output、input-to-output。
- `create_clock` 创建 clock object；周期数字不要写单位后缀。
- 默认 clock 是 ideal clock，skew、latency、transition 都近似为 0。
- DC 不做 CTS，但要通过 uncertainty、latency、transition 预留真实 clock 效应。
- `set_clock_uncertainty` 会直接扣减 setup 预算。
- source latency 是外部 clock source 到 port，network latency 是 port 到内部 register。
- pre-CTS 用估计值，post-CTS 更依赖 propagated clock 和真实后端数据。

### 复现清单

1. 画出一个 block，把所有路径标成四类 timing path。
2. 写 `create_clock -period 2 [get_ports CLK]`，解释每个字段。
3. 用 $T_{period}=2ns$、$T_{uncertainty}=0.3ns$ 手算 setup 可用预算减少多少。
4. 区分 `set_clock_latency -source` 和不带 `-source` 的含义。
5. 说明为什么 post-CTS 阶段要用 propagated clock。
6. 修改一条 `set_clock_uncertainty` 后重跑 `report_timing`，确认 required time 是否按预期收紧。

### 自测题

1. 为什么只写 `create_clock` 仍然不够真实？

   答：`create_clock` 定义周期和参考边沿，但默认 clock 是 ideal clock，缺少 skew、latency、transition 和 jitter/margin。真实综合需要补充相关估计。

2. `set_clock_uncertainty -setup 0.3` 对 setup 分析有什么影响？

   答：它把 setup required time 扣掉 0.3ns，相当于给 clock skew、jitter、margin 等不确定因素预留空间，内部数据路径可用预算变小。

3. 为什么 DC 不直接做 CTS？

   答：CTS 需要基于实际 placement 计算 clock source 到各寄存器的路径和插 buffer 位置；DC 阶段没有最终物理摆放，真实 CTS 应在 APR 阶段完成。


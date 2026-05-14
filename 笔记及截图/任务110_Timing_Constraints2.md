# 任务110：Timing Constraints2

## 本章知识全景图

这一讲解决的是 block 级综合约束里最容易漏掉的一类问题：RTL 只描述本模块内部连线，工具不知道端口外面的寄存器、组合逻辑、走线、采样边沿和团队预算；如果不把这些外部时间写进 SDC，DC 会按错误目标优化，STA 会按错误边界算 slack。

核心主线只有一句话：先用 `create_clock` 建立时钟对象，再用 `set_input_delay` 和 `set_output_delay` 把一个周期切成“外部已消耗、内部可使用、外部还要预留”三段，最后用 timing report 检查 arrival、required 和 slack 是否真的来自这套约束。

| 知识块 | 工具看到的对象或预算 | 写错后的失败信号 |
|---|---|---|
| `create_clock` | clock object、周期、launch/capture 边沿 | 寄存器路径 unconstrained，或 delay 引用不到时钟 |
| input path 约束 | 数据进入本模块前，外部已经用掉多少时间 | input-to-reg slack 虚高，上层集成后暴露违例 |
| output path 约束 | 数据离开本模块后，外部还要保留多少时间 | reg-to-output 没被压紧，下游采样预算被吃光 |
| timing report | arrival time、required time、slack 的计算证据 | 只看 WNS，不知道约束是否漏写或绑错对象 |
| 多端口批量约束 | 批量覆盖 data port，同时排除 clock/reset 等例外 | clock 被当成 data，或部分端口变成 unconstrained |
| virtual clock / time budgeting | 没有真实外部环境时的人造参考边沿和预算规则 | 纯组合 block 没法 STA，或预算数字无法解释 |

最短学习路径：先确认 `create_clock` 生成了正确 clock object；再手算 input/output 两类路径的最大内部延时；然后把 SDC 参数映射到公式；最后读 `report_timing`，用 slack 和 unconstrained path 反查约束是否真的生效。

![input path 约束的原始问题](<./screenshots/任务110_Timing_Constraints2/dense_01.jpg>)

看第一张 input path 图时先把一个周期切成三段：外部已经花掉的时间、block 内部可用时间、触发器 setup 和保守 margin。后面的 SDC 命令都只是把这三段写成工具能计算的对象和数字。

## 本课主线地图

| 时间 | 教学内容 | 学习主线 |
|---|---|---|
| 00:55-05:25 | 用 input path 图推导内部路径 $T_n$ 的最大延时 | 外部已消耗时间如何压缩内部预算 |
| 06:07-08:14 | `create_clock`、`set_clock_uncertainty`、`set_input_delay` 例题 | 命令参数如何落到 clock object、uncertainty、端口和参考边沿 |
| 08:48-15:07 | output path 公式、0.8 ns output delay、反推 output delay | 外部预留时间如何压缩内部输出路径 |
| 15:07-23:22 | source/network latency、uncertainty 的继承和抵消 | 单时钟可化简，多时钟和真实后端不能默认抵消 |
| 23:22-28:33 | 多 input/output 端口、`remove_from_collection`、端口覆盖 | 批量约束、例外排除、特殊端口覆盖和报告核对 |
| 28:33-35:50 | 纯组合路径、纯组合模块、virtual clock | 有真实 clock port 的组合路径与无 clock port 的纯组合模块分别怎么约束 |
| 35:50-41:05 | time budgeting 与 40% 周期规则 | 外部环境未知时，团队如何先给 block 一个可闭合预算 |

## 1. SDC 约束在 DC/STA 里改变了什么：先建对象，再切预算，再读 slack

DC/STA 不是靠猜测理解设计意图，而是靠 SDC 把“时钟、外部环境、例外路径、预算边界”变成可计算对象。没有 SDC 时，工具只能看见门级连接；有了正确 SDC，工具才知道哪些路径要优化、需要在几纳秒内完成、哪些端口外面已经消耗了时间。

一条 setup 检查在工具内部会被拆成三件事：

```text
launch 边沿发出数据
  -> data arrival time：外部 delay + 内部 data path delay
capture 边沿要求采样
  -> data required time：周期 - uncertainty - setup - 外部预留
slack = required time - arrival time
```

`create_clock` 决定 launch/capture 边沿在哪里；`set_input_delay` 和 `set_output_delay` 决定边界外的时间要从哪里扣；`set_clock_uncertainty` 决定为了 jitter、skew 和建模误差要保守扣掉多少。综合阶段的 DC 会按这些 required time 去重构逻辑、换门、插缓冲、调整面积和速度；STA 阶段会用同一套约束重新计算每条路径是否满足。

约束缺失和约束写错最危险的地方在于：报告可能看起来“没有 violation”，但真实原因是路径没有被检查，或者外部预算被当成 0。真正可信的 timing closure 不是“WNS 是正的”，而是“clock、port delay、uncertainty、launch/capture 关系都被报告证明已经生效”。

### 1.1 create_clock：先生成 clock object，后面的 delay 才有参考边沿

`create_clock` 的作用不是给端口贴一个名字，而是生成 STA 使用的 clock object：它包含周期、波形、上升/下降边沿，以及和某个端口或 pin 的绑定关系。

```tcl
create_clock -name Clk -period 2.5 [get_ports Clk]
```

这条命令有两个对象：

| 片段 | 工具对象 | 判断口径 |
|---|---|---|
| `[get_ports Clk]` | RTL/netlist 里的真实 clock port | 说明这个 clock 从哪个设计边界进入 |
| `-name Clk` | STA 里的 clock object 名字 | 后续 `set_input_delay -clock [get_clocks Clk]` 引用它 |
| `-period 2.5` | launch/capture 边沿间隔 | 决定 reg-to-reg、input-to-reg、reg-to-output 的 required time |

常见错误是把 port object 和 clock object 混成一件事。`[get_ports Clk]` 是端口集合，`[get_clocks Clk]` 是时钟集合；input/output delay 的 `-clock` 后面要引用 clock object，而被约束的数据端口要放在命令最后。

失败信号很明确：`report_clock` 里没有目标 clock，`set_input_delay` 报空集合或没有绑定，`check_timing` 出现 no clock / unconstrained endpoint，`report_timing` 的 path group 不对。出现这些信号时，不要先调 delay 数字，先确认 `create_clock` 是否真的创建了工具能引用的对象。

## 2. input delay：它给的是“外部到输入端口”的已消耗时间

input path 的本质是外部寄存器发出数据，本模块内部寄存器接收数据。工具只看本模块时，只能看到从 input port 到内部寄存器的 $T_n$，看不到端口外面的 $T_{ck}$ 和 $T_m$。`set_input_delay` 就是把这些看不到的外部时间补给工具。

![input path 公式板书](<./screenshots/任务110_Timing_Constraints2/dense_03.jpg>)

这张公式板书只负责回答“别人把数据送到我门口前已经花掉多少时间”。它不是端口物理延时图，也不是 clock port 约束图。

setup 检查可以按下面的路径读：

```text
外部 launch FF clock edge
  -> 外部 FF clock-to-Q: Tck
  -> 外部组合/走线到本模块输入端口: Tm
  -> 本模块输入端口到内部 capture FF: Tn
  -> 内部 capture FF setup: Tsetup
```

因此 setup 约束是：

$$
T_{ck}+T_m+T_n+T_{setup}\le T_{period}-T_{uncertainty}
$$

`set_input_delay -max` 对应的是 $T_{ck}+T_m$，也就是数据到达 input port 之前已经花掉的时间。它不是在说 input port 本身有延时，也不是在约束 clock port。

视频里的数值可以整理为：

```text
Tperiod = 2 ns
setup uncertainty = 0.3 ns
capture FF setup = 0.2 ns
input delay = Tck + Tm = 0.6 ns
```

内部 input-to-register 路径最大只能是：

$$
T_n\le 2-0.3-0.2-0.6=0.9\text{ ns}
$$

这 0.9 ns 是工具真正要优化的内部目标。如果没有 `set_input_delay`，工具会少扣外部已经消耗的 0.6 ns，内部路径看起来更宽松，综合结果接到真实上级模块后可能过不了。

在 input path 的 timing report 里，`data arrival time` 应该能体现“input delay + input port 到内部寄存器的路径延时”；`data required time` 应该来自 capture clock 边沿扣掉 uncertainty 和 setup。若 report 里看不到 input delay，或者该 input port 出现在 unconstrained path 里，就不能相信当前 slack。

### 2.1 input delay 命令不是填空题，要对应到公式

![input delay 命令填写](<./screenshots/任务110_Timing_Constraints2/dense_04.jpg>)

看这张命令填写图时要逐项对公式：`-clock` 找参考边沿，最后的 `[get_ports A]` 才是被约束的数据入口，`-max 1.5` 是外部到达端口前已经消耗的最大 setup 时间。

一个典型例子：

```tcl
create_clock -period 2.5 [get_ports Clk]
set_clock_uncertainty -setup 0.3 [get_clocks Clk]
set_input_delay -max 1.5 -clock [get_clocks Clk] [get_ports A]
```

| 命令片段 | 对应含义 | 易错点 |
|---|---|---|
| `create_clock -period 2.5` | 定义 $T_{period}=2.5$ ns | 单位通常沿用工具库单位，不要随便混 ns/ps |
| `set_clock_uncertainty -setup 0.3` | setup 分析要保守扣掉 0.3 ns | 它不是 data path delay，而是时序裕量扣减 |
| `-clock [get_clocks Clk]` | input delay 相对哪个时钟边沿解释 | 不是把 delay 加到 clock port 上 |
| `[get_ports A]` | 被约束的数据输入端口 | 这里才是 input delay 的作用对象 |

读这条命令时，要把它翻译成一句工程话：端口 `A` 的数据相对 `Clk` 到达，本模块之外最大已经消耗 1.5 ns，所以内部从 `A` 到接收寄存器的逻辑必须在剩余预算内完成。

## 3. output delay：它给的是“输出端口之后”的外部预留时间

output path 的方向反过来：本模块内部寄存器发出数据，外部寄存器接收数据。工具能看到内部寄存器到 output port 的 $T_s$，但看不到 output port 之后的外部路径和外部寄存器 setup。`set_output_delay` 就是把这部分外部需求预留出来。

![output path 原始问题](<./screenshots/任务110_Timing_Constraints2/dense_05.jpg>)

output path 图的读法和 input 相反：这次不是别人送到我门口，而是我送出门后别人还要留多少时间接住。

setup 检查按下面的路径读：

```text
本模块 launch FF clock edge
  -> 本模块内部 reg-to-output 路径: Ts
  -> output port 之后的外部路径/外部接收 setup: Tout
  -> 外部 capture FF setup 检查
```

简化后可以写成：

$$
T_s+T_{out}\le T_{period}-T_{uncertainty}
$$

其中 `set_output_delay -max` 对应 $T_{out}$。视频里的 output example 使用：

```text
Tperiod = 2 ns
setup uncertainty = 0.3 ns
output delay = 0.8 ns
```

那么内部 reg-to-output 的最大延时是：

$$
T_s\le 2-0.3-0.8=0.9\text{ ns}
$$

![output delay 例题板书](<./screenshots/任务110_Timing_Constraints2/dense_07.jpg>)

这张板书负责把 `set_output_delay` 翻成 required time 扣减：外部要 0.8ns，内部 reg-to-output 路径就不能把这 0.8ns 吃掉。

对应命令：

```tcl
set_output_delay -max 0.8 -clock [get_clocks Clk] [get_ports B]
```

这条命令的工程含义是：端口 `B` 输出后，外部最多需要 0.8 ns；所以本模块内部必须把 reg-to-output 路径压到剩余时间内。它不是说 `B` 端口本身延时 0.8 ns。

在 output path 的 timing report 里，`data required time` 会因为 output delay 变小：外部需要 0.8 ns，内部就不能把这 0.8 ns 吃掉。如果 output delay 缺失，reg-to-output 路径常会显得很宽松，后端或上层 STA 才发现下游采样端没有足够时间。

### 3.1 反推 output delay：从内部目标倒算外部预算

视频还给了一个反推例子：已知内部输出路径目标 $T_s=0.7$ ns，周期 2 ns，uncertainty 0.3 ns，要满足这个内部目标，output delay 最大可设为：

$$
T_{out}\le 2-0.3-0.7=1.0\text{ ns}
$$

![反推 output delay](<./screenshots/任务110_Timing_Constraints2/dense_08.jpg>)

反推图用于训练“从内部目标倒算外部预算”。它不是让你固定背 1.0ns，而是让你知道每个 delay 数字必须能回到周期切分公式。

这一步很关键：端口 delay 可以来自真实外部时序，也可以来自 block 预算目标。只要你能解释它在周期预算里代表哪一段，它就是有意义的约束；如果只是照抄一个数字，后面 timing 过不过都没有工程可信度。

## 4. input delay 与 output delay 的共同口径：它们都在切分一个周期

初学者容易把 input/output delay 当成两类完全不同的命令。其实它们共同做一件事：给内部路径留下一个最大可用时间。

| 路径类型 | 外部时间在哪边 | 工具要优化哪段内部路径 | 约束变大后的影响 |
|---|---|---|---|
| input path | input port 之前 | input port 到内部 capture FF | 内部可用时间变少 |
| output path | output port 之后 | 内部 launch FF 到 output port | 内部可用时间变少 |
| 纯组合 path | input port 之前和 output port 之后都有 | input port 到 output port 的组合逻辑 | 两边外部预算都会压缩内部可用时间 |

一句话记忆：input delay 是“别人把数据送到我门口已经花了多久”，output delay 是“我把数据送出门后别人还要多久接住”。

这句话能防两个错：

- 不会把 `-clock` 后面的时钟误认为被约束对象。
- 不会把 port delay 当成端口本身的物理延时。

## 5. clock latency 与 uncertainty：为什么视频反复强调“同一个 clock 才能抵消”

这一段的难点不是命令，而是边界。画面里用同一张图反复标注 source latency、network latency 和 uncertainty，是为了说明：input/output delay 默认会继承相同 clock 上定义的 latency 和 uncertainty；在单时钟教学例子里，launch 和 capture 两侧可能共享同样的 clock 信息，所以有些项能抵消。

![latency 与 uncertainty 的继承](<./screenshots/任务110_Timing_Constraints2/dense_10.jpg>)

看这张继承图时不要急着背化简，先分清 launch/capture 两侧哪些 clock 量共享、哪些不共享。共享项可能抵消，不共享项就是余量风险。

概念拆开看：

| 名称 | 位置 | 它影响什么 |
|---|---|---|
| source latency | 时钟源到设计 clock port | 外部时钟到达本设计边界的时间 |
| network latency | 设计 clock port 到寄存器 clock pin | 设计内部时钟网络传播时间 |
| uncertainty | jitter、skew 估计、建模误差 | setup 检查里通常作为保守扣减 |

在视频的单 clock input path 里，launch clock 和 capture clock 都是同一个 `Clk`。如果两边用同一套 latency/uncertainty，公式中相同的 clock latency 项可以抵消，最后仍然回到：

$$
input\ delay+T_n+T_{setup}\le T_{period}-T_{uncertainty}
$$

但这只能说明这个教学例子可化简，不能说明真实工程里 latency 不重要。

![单时钟化简的板书](<./screenshots/任务110_Timing_Constraints2/dense_12.jpg>)

这张板书只在单 clock 教学条件下成立。真实多 clock、generated clock 或后端 propagated clock 场景里，不能直接把 latency 当成总会抵消。

多时钟、多 generated clock、源同步接口、跨模块接口、后端 CTS 后的时钟树，都可能让 launch clock 和 capture clock 的 latency 不同。此时如果还用“反正会抵消”的心态写约束，工具会把本该扣掉的偏差留成假 slack。

实用判断：

| 如果你面对的是 | 应该怎么做 |
|---|---|
| 本讲单时钟板书例子 | 可以用抵消理解 input/output delay 的主公式 |
| 两个不同 clock 的接口 | 不要抵消，分别建模两边 clock 关系 |
| 后端还没 CTS | 用合理 uncertainty 给综合留保守余量 |
| 后端已有实际时钟树 | 用真实 latency/skew 重新 STA |
| NPU/SoC 多模块集成 | 重点检查每个接口的 launch/capture clock 是否真的是同一个 |

AI+IC 工程里，NPU 子模块常接总线、SRAM、DMA、寄存器文件或片外接口。只要接口两端 clock 关系不是“完全同源同路径”，端口约束就不能只套本讲前半段的单时钟公式。

## 6. 多端口约束：批量命令解决漏约束，集合移除解决误约束

视频从 23 分钟开始处理更真实的问题：一个模块有多个 input/output，如果逐个端口手写 delay，容易漏；如果直接 `all_inputs`，又会把 clock port 也算进去。正确策略是批量约束数据端口，同时把 clock port 从集合里移除。

![多输入输出同约束](<./screenshots/任务110_Timing_Constraints2/dense_13.jpg>)

这张多端口图解决的是漏约束问题：用集合一次覆盖多个 data port，同时用 `remove_from_collection` 把 clock port 从 data 集合里剔除。

同一组 input 使用同一 delay 时，可以写：

```tcl
set_input_delay -max 0.5 -clock [get_clocks Clk] \
    [remove_from_collection [all_inputs] [get_ports Clk]]

set_output_delay -max 1.1 -clock [get_clocks Clk] [all_outputs]
```

这里 `remove_from_collection [all_inputs] [get_ports Clk]` 的返回结果是“所有 input 端口减去 clock 端口”。如果 `all_inputs` 包含 `A B C Clk`，移除后剩下 `A B C`，这才是普通 data/control input 的集合。

为什么 clock port 必须移除？因为 clock 是参考边沿，不是数据路径起点。把 clock port 当 data input 加 delay，会导致约束语义错位：工具报告里会出现 clock 本身相对 clock 的 input delay，后续检查端口约束时很难判断真实 data port 是否完整。

## 7. 不同端口不同 delay：先默认，再覆盖，再核对最终值

视频接着讲 different port constraints：大多数端口可以用默认值，少数端口有特殊外部路径，就用后面的命令覆盖前面的默认约束。

![不同端口不同约束](<./screenshots/任务110_Timing_Constraints2/dense_14.jpg>)

不同端口图解决的是覆盖顺序问题：先给大多数端口默认值，再对特殊端口覆盖，最后必须用 report 核对最终值。

示例：

```tcl
set_input_delay -max 0.5 -clock [get_clocks Clk] \
    [remove_from_collection [all_inputs] [get_ports Clk]]

set_input_delay -max 0.8 -clock [get_clocks Clk] [get_ports C]
```

执行结果应理解为：

| 端口 | 最终 input delay | 原因 |
|---|---:|---|
| `A` | 0.5 ns | 使用批量默认值 |
| `B` | 0.5 ns | 使用批量默认值 |
| `C` | 0.8 ns | 后续命令覆盖默认值 |
| `Clk` | 无普通 input delay | 已从 input 集合移除 |

交付约束前要做报告核对，而不是只看 SDC 文件：

```tcl
report_port -verbose
report_timing -from [get_ports A]
report_timing -from [get_ports C]
report_timing -to [get_ports Out1]
```

核对重点是：clock port 没有 data input delay；特殊端口显示覆盖后的值；没有 unconstrained input/output path。

## 8. 有真实 clock 的组合路径：前后都有外部预算，中间只剩差值

视频先讲了一种“有 clock 参考的纯组合路径”：本模块中间是一段组合逻辑，但输入输出两端仍可相对真实 clock 约束。

![组合路径例题](<./screenshots/任务110_Timing_Constraints2/dense_15.jpg>)

这张组合路径图把 input delay 和 output delay 同时放进一条 input-to-output 路径，说明中间纯组合逻辑只能使用两边外部预算扣完后的差值。

例题可读成：

```text
period = 2 ns
uncertainty = 0.3 ns
input delay = 0.4 ns
output delay = 0.3 ns
```

那么中间组合逻辑最大延时：

$$
T_f\le 2-0.3-0.4-0.3=1.0\text{ ns}
$$

这个例子是从 input-to-output 的角度说明：只要输入端外部预算和输出端外部预算都给了，工具就能把中间组合逻辑压到剩余时间里。它和前面的 input path、output path 是同一个预算思想，只是内部路径从 reg-to-reg 变成 input-to-output。

## 9. virtual clock：没有真实 clock port 时，用参考时钟而不是伪造端口

更复杂的情况是当前 design 根本没有 clock port，例如一个完全组合的 block。此时仍然要告诉工具输入何时到、输出何时要被外部采样，但不能写 `[get_ports Clk]`，因为设计里没有这个端口。

![纯组合设计没有真实 clock port](<./screenshots/任务110_Timing_Constraints2/dense_16.jpg>)

纯组合设计图的边界是：设计本身没有 clock port，但系统时序仍然需要一个参考边沿；这就是 virtual clock 出场的原因。

virtual clock 的作用就是给 input/output delay 一个参考边沿。它有两个关键特征：

- 不连接当前 design 的任何 port 或 pin。
- 只作为 STA 计算 input/output delay 的时钟对象。

![virtual clock 定义](<./screenshots/任务110_Timing_Constraints2/dense_17.jpg>)

看 virtual clock 定义图时抓住边界：virtual clock 是 clock object，不是真实端口，所以后续 delay 约束必须引用 `[get_clocks VCLK]`，不能去找不存在的 `[get_ports VCLK]`。

正确写法：

```tcl
create_clock -name VCLK -period 2
set_clock_uncertainty -setup 0.3 [get_clocks VCLK]
set_input_delay  -max 0.4 -clock [get_clocks VCLK] [get_ports A]
set_output_delay -max 0.3 -clock [get_clocks VCLK] [get_ports B]
```

错误写法：

```tcl
create_clock -period 2 [get_ports VCLK]
```

除非设计里真有 `VCLK` 这个端口，否则这条命令是在查一个不存在的 port。virtual clock 必须用 `-name` 创建 clock object，再通过 `[get_clocks VCLK]` 被 input/output delay 引用。

![virtual clock 约束组合路径](<./screenshots/任务110_Timing_Constraints2/dense_18.jpg>)

这张图把 virtual clock 应用于纯组合路径，证明它只是参考坐标，不会让组合逻辑突然变成时序逻辑。

这个例子的公式还是同一个：

$$
T_{comb}\le T_{period}-T_{uncertainty}-T_{input\ delay}-T_{output\ delay}
$$

代入数值：

$$
T_{comb}\le 2-0.3-0.4-0.3=1.0\text{ ns}
$$

所以 virtual clock 不是在“让组合逻辑按时钟工作”，而是在没有真实 clock port 时，建立一个外部系统时序的参考坐标。

## 10. time budgeting：它是 block 级协作规则，不是随手填 40%

视频最后讲 time budgeting。它解决的不是“怎么算精确外部延时”，而是“外部环境暂时不精确时，block 设计人员如何仍然给出可闭合的约束”。

![time budgeting 的问题](<./screenshots/任务110_Timing_Constraints2/dense_19.jpg>)

time budgeting 问题图的价值在于暴露团队协作风险：每个 block 都假装外部很快，系统集成时延时债务会集中爆雷。

如果每个 block 设计者都不约束端口，理由是“不知道上游/下游到底多慢”，那么每个 block 内部都会看起来容易过 timing，系统集成后却把延时债务集中暴露出来。time budgeting 用统一规则把周期提前分配掉。

视频中的规则是常见的 40% 内部预算：

```text
周期 = 10 ns
内部 block 目标 = 40% * 10 ns = 4 ns
外部预留 = 60% * 10 ns = 6 ns
```

![time budgeting 示例](<./screenshots/任务110_Timing_Constraints2/dense_20.jpg>)

预算示例图把 10ns 周期切成内部 4ns、外部 6ns。它不是数学定律，而是早期 block 级协作的保守合同。

对应约束可以写成：

```tcl
create_clock -period 10 [get_ports Clk]

set_input_delay -max 6 -clock [get_clocks Clk] \
    [remove_from_collection [all_inputs] [get_ports Clk]]

set_output_delay -max 6 -clock [get_clocks Clk] [all_outputs]
```

为什么不是 50%？因为两个 block 都用 50% 时，系统刚好贴着周期边界，没有给 uncertainty、clock skew、布线、负载和 PVT 变化留余量。40% 不是数学定律，而是保守工程规则：让每个 block 在早期就按更紧目标综合，避免后期集成才发现余量被吃光。

![40% 预算的板书推导](<./screenshots/任务110_Timing_Constraints2/dense_21.jpg>)

40% 板书图要和真实接口阶段分开：早期没有真实上下游 timing 时用预算，后期拿到真实路径后必须用真实 delay 替换默认比例。

time budgeting 的正确使用边界：

| 场景 | 是否适合 |
|---|---|
| 早期 block 级综合，外部路径不精确 | 适合，用预算保证约束完备 |
| 已知真实上游/下游 timing | 应使用真实 input/output delay，而不是继续套统一比例 |
| 某些高速接口比其他端口严格 | 不能只用统一默认值，要单独覆盖 |
| 后端集成阶段 | 需要用真实寄生、真实 clock tree 和接口约束复核 |

## 11. timing report：把约束翻译成 arrival、required 和 slack

SDC 是否正确，不能只看文件内容，要看 timing report 有没有把约束翻译进公式。一个可信报告至少要让你读出三件事：数据什么时候到、要求什么时候到、差多少。

常用抽查命令可以按路径类型分开跑：

```tcl
## Tcl 注释：input-to-register
report_timing -delay_type max -from [get_ports A] -to [all_registers] -max_paths 3

## Tcl 注释：register-to-output
report_timing -delay_type max -from [all_registers] -to [get_ports B] -max_paths 3

## Tcl 注释：input-to-output 组合路径
report_timing -delay_type max -from [get_ports A] -to [get_ports B] -max_paths 3
```

读报告时不要只扫最后一行 slack，要逐项核对：

| 报告字段 | 应该读成什么 | 约束错误时的信号 |
|---|---|---|
| startpoint / endpoint | launch 和 capture 的真实边界 | 起点或终点不是你以为的端口/寄存器 |
| path group / clock | 这条路径归哪个 clock object 管 | path group 缺失、clock 名不对、路径被报 unconstrained |
| data arrival time | 外部已消耗时间 + 内部路径延时 | input delay 没进 arrival，或 clock port 被当成 data |
| data required time | capture 边沿扣掉 uncertainty、setup、output delay 后的要求 | output delay 没扣，required time 过于宽松 |
| slack | required - arrival | slack 为正但路径没被约束，或负 slack 对应错误对象 |

input path 的核心读法是：`set_input_delay` 会推高 arrival time，内部可用时间变少。output path 的核心读法是：`set_output_delay` 会压低 required time，内部输出路径必须更快。这个方向一旦读反，后面调约束会越调越乱。

setup/max 只是半张网。SDC 写完后还要抽查 min/hold 视角，避免把 timing closure 学成只看 WNS：

```tcl
report_timing -delay_type max -from [get_ports A] -to [all_registers] -max_paths 3
report_timing -delay_type min -from [get_ports A] -to [all_registers] -max_paths 3
report_timing -delay_type max -from [all_registers] -to [get_ports B] -max_paths 3
report_timing -delay_type min -from [all_registers] -to [get_ports B] -max_paths 3
```

`max` 主要服务 setup，问“最慢数据能不能赶到”；`min` 主要服务 hold，问“最快数据会不会太早污染采样”。input/output delay 也有 `-max/-min` 两套边界：只写 max，等于只描述最晚到达或最晚要求；真实接口还需要根据外部最早到达、最早采样要求补 min 口径。

## 12. constraint debug：先查对象，再查覆盖，再查路径

约束调试要按依赖顺序做。先查 clock object 是否存在，再查端口集合是否覆盖，再查具体 timing path；不要一看到 slack 不好就先改数字。

```tcl
report_clock
check_timing
report_port -verbose
report_timing -delay_type max -from [get_ports A]
report_timing -delay_type max -to [get_ports B]
report_timing -delay_type min -from [get_ports A]
report_timing -delay_type min -to [get_ports B]
report_constraint -all_violators
```

| 现象 | 首查位置 | 常见原因 |
|---|---|---|
| `set_input_delay` 执行后 report 没变化 | `report_clock` / `get_clocks` | `-clock` 引用空 clock object 或 clock 名不一致 |
| 某些 input 没有 delay | `report_port -verbose` | 批量集合漏端口，或命令顺序被后续覆盖 |
| clock port 也出现 input delay | port 属性和 SDC 集合 | `all_inputs` 没排除 clock |
| WNS 很好但集成失败 | `check_timing` 和 unconstrained path | 路径未约束，或外部 delay 没建模 |
| 特殊端口没有按 0.8 ns 覆盖 | SDC 命令顺序和 port 报告 | 默认命令写在后面，把特殊端口覆盖回去了 |
| virtual clock 不生效 | `report_clock` | 写成了不存在的 `[get_ports VCLK]`，没有创建 `-name VCLK` |
| hold 视角完全没查 | `report_timing -delay_type min` | 只写/只查 max，漏掉 min delay 和 hold 风险 |

调试口径要固定：先证明对象存在，再证明属性生效，再证明路径进入 report，最后才讨论 slack 优化。这个顺序能避免把“约束没生效”误判成“电路太慢”。

## 13. 本讲 SDC 写作检查单

写完 SDC 后，不要只问“命令有没有写”，要问“每条路径是否真的被工具看见”。

| 检查项 | 合格信号 | 失败信号 |
|---|---|---|
| clock 定义 | 每个真实 clock port 有 `create_clock`，`report_clock` 可见 | data path 被报 unconstrained，或 delay 引用空 clock |
| input delay | 除 clock/reset 等例外外，普通 input 有 delay | `all_inputs` 里漏端口或把 clock 当 data |
| output delay | 普通 output 有 delay 或有明确例外 | reg-to-output 路径没有外部预留 |
| 特殊端口 | 覆盖值在报告中生效 | SDC 后写了覆盖，但报告仍是默认值 |
| virtual clock | 无真实 clock port 时用 `create_clock -name` | 对不存在的 `[get_ports VCLK]` 建 clock |
| latency/uncertainty | 明确知道哪些 clock 共享、哪些不共享 | 多 clock 接口套用单 clock 抵消逻辑 |
| time budget | 预算比例能解释成内部/外部分配 | 数字只是照抄，无法对应周期切分 |
| timing report | arrival/required/slack 能对应手算公式 | slack 正但路径没被约束，或 required/arrival 方向读反 |
| min/hold 口径 | 有 `-min` delay 或明确说明接口最早到达假设 | 只检查 setup/WNS，hold 风险被隐藏 |
| 工程交付 | DC、STA、后端和形式验证使用同一份边界假设 | 综合约束、签核约束和形式验证 setup 互相矛盾 |

## 14. 易错点

1. `create_clock` 生成的是 clock object，不只是给端口命名。
   后续 delay 引用的是 `[get_clocks Clk]`，不是把 `[get_ports Clk]` 当成数据对象。

2. `-clock [get_clocks Clk]` 不是被约束端口。
   被约束端口在命令最后，例如 `[get_ports A]` 或 `[all_outputs]`。

3. `set_input_delay` 的值越大，不是越安全。
   它越大，说明外部已经用掉越多时间，内部路径可用时间越少。

4. `set_output_delay` 的值越大，也不是越安全。
   它越大，说明外部接收端还需要更多时间，内部输出路径必须更快。

5. clock port 不能被普通 input delay 批量约束。
   用 `remove_from_collection` 排除 clock port 是为了保持约束语义干净。

6. virtual clock 不是真实端口。
   它只作为 STA 参考对象，通常用 `create_clock -name VCLK -period ...` 创建。

7. 单时钟抵消不是多时钟规则。
   一旦 launch/capture clock 不同，latency 和 uncertainty 必须重新分析。

8. WNS 为正不等于约束正确。
   如果有 unconstrained path，或者 input/output delay 没有进入 report，正 slack 只是没有检查出来的问题。

9. 只看 `-delay_type max` 不等于时序完整。
   setup/max 检查证明最慢路径能否赶到；hold/min 检查最快路径是否太早到。真实接口约束要能解释 max 和 min 两侧边界。

## 15. 自测与答案

1. 周期 2 ns，uncertainty 0.3 ns，内部 capture FF setup 0.2 ns，input delay 0.6 ns，input-to-reg 内部路径最大是多少？
   答：$2-0.3-0.2-0.6=0.9$ ns。

2. `set_input_delay -max 1.5 -clock [get_clocks Clk] [get_ports A]` 中，`1.5` 表示什么？
   答：表示数据到达端口 `A` 之前，外部 launch FF 的 clock-to-Q、外部组合逻辑和走线等最多已经消耗 1.5 ns。

3. 周期 2 ns，uncertainty 0.3 ns，output delay 0.8 ns，内部 reg-to-output 最大是多少？
   答：$2-0.3-0.8=0.9$ ns。

4. 为什么 `all_inputs` 后要移除 clock port？
   答：clock port 是参考边沿，不是 data input。如果给它加普通 input delay，会污染端口约束语义，并掩盖真正 data port 是否完整约束。

5. 一个纯组合模块没有 `clk` 端口，但要约束 input-to-output 最大延时，应如何建立参考时钟？
   答：用 virtual clock，例如 `create_clock -name VCLK -period 2`，再让 `set_input_delay` 和 `set_output_delay` 的 `-clock` 引用 `[get_clocks VCLK]`。

6. time budgeting 中周期 10 ns、内部预算 40%，为什么 input/output delay 常设成 6 ns？
   答：因为内部只允许使用 4 ns，外部预算就是 $10-4=6$ ns。设置 6 ns 的 port delay，会迫使内部路径按 4 ns 目标优化。

7. 如果上层集成时发现某个 input port 的真实外部路径是 8 ns，而早期统一预算只给 6 ns，应如何处理？
   答：不能继续沿用默认预算；应单独覆盖该端口的 input delay，并重新检查内部可用时间是否还能满足 timing。

8. `create_clock -name Clk -period 2.5 [get_ports Clk]` 里，`[get_ports Clk]` 和 `[get_clocks Clk]` 分别代表什么？
   答：`[get_ports Clk]` 是设计边界上的真实 clock port；`[get_clocks Clk]` 是 STA 中创建出的 clock object，供 `set_input_delay`、`set_output_delay`、`set_clock_uncertainty` 等命令引用。

9. timing report 中 slack 为正，为什么还要查 `check_timing` 或 unconstrained path？
   答：因为 slack 为正只说明“已被检查的路径”满足当前约束；如果路径没被 clock 或 port delay 覆盖，它可能根本没进有效检查范围。

10. 一个 output path 的 `set_output_delay -max 0.8` 漏写后，报告通常会偏乐观还是偏悲观？为什么？
    答：偏乐观。工具没有扣掉下游还需要的 0.8 ns，内部 reg-to-output 路径得到过宽的 required time。

11. 为什么要同时抽查 `report_timing -delay_type min`？
    答：因为 max/setup 只检查最慢路径能否赶到；min/hold 检查最快路径是否太早到达。只看 max 会漏掉 hold 和最早到达边界，尤其是 IO 接口或短组合路径。

## 16. 数字 IC/EDA 工程落点与 AI+IC 实践动作

同一份约束会被多个环节消费，但每个环节关心的证据不同。

| 环节 | 如何使用这些约束 | 交付时要看什么 |
|---|---|---|
| DC 综合 | 用 clock、input/output delay 和 uncertainty 决定优化目标 | `compile` 后的 `report_timing`、`report_constraint`、面积/时序取舍是否合理 |
| STA / PrimeTime | 用同一套 SDC 加真实库、寄生和时钟信息做签核 | WNS/TNS、unconstrained path、clock group、IO path 是否完整 |
| 后端 P&R | 根据约束做 floorplan、CTS、布线优化和接口复核 | CTS 后 latency/skew 是否更新，IO budget 是否仍成立 |
| 形式验证 / Formality | 不证明 timing，但必须和综合后的结构假设一致 | SVF、clock/reset、case analysis、scan/test mode、黑盒和常量设置是否与综合一致 |
| SoC/NPU 集成 | 把子模块约束接入总线、SRAM、DMA、片外接口 | launch/capture clock 是否同源，跨模块 IO delay 是否由真实上游/下游替换预算值 |

形式验证这一项容易误解：`set_input_delay` 和 `set_output_delay` 本身不是等价性证明目标，Formality 不会因为它们存在就证明 timing 正确；它真正需要的是综合和验证使用一致的模式、常量、时钟/reset 口径，以及 DC 输出的 SVF 辅助信息。timing 由 STA 签核，等价性由 formal setup 保证两份网表逻辑一致。

做一个最小 SDC 约束练习，目标是训练“报告核对”而不是只写命令。

准备一个组合模块：

```verilog
module comb_block(
    input  logic a,
    input  logic b,
    input  logic c,
    output logic y
);
    assign y = (a & b) ^ c;
endmodule
```

写两版约束：

```tcl
## Tcl 注释：版本 A，错误，把不存在的真实 clock port 当参考
create_clock -period 2 [get_ports VCLK]

## Tcl 注释：版本 B，正确，创建 virtual clock
create_clock -name VCLK -period 2
set_clock_uncertainty -setup 0.3 [get_clocks VCLK]
set_input_delay  -max 0.4 -clock [get_clocks VCLK] [all_inputs]
set_output_delay -max 0.3 -clock [get_clocks VCLK] [all_outputs]
```

检查目标：

- `VCLK` 是否作为 clock object 存在。
- input-to-output 的最大组合预算是否等于 $2-0.3-0.4-0.3=1.0$ ns。
- 是否还有 unconstrained path。

这个练习会直接迁移到 NPU 子模块、AXI/AHB 外设接口、DMA 控制器和 SRAM wrapper 的约束检查：先确认路径被约束，再讨论 timing 是否能优化到目标。


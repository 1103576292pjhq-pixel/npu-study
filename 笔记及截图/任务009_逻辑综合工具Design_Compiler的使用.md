# 任务09：逻辑综合工具 Design Compiler 的使用

## 本章知识全景图

### 一眼看懂这讲在讲什么

逻辑综合不是把 Verilog “翻译一下”，而是让工具在指定工艺库和约束下，把 RTL 变成可实现、可检查、可交付的门级网表。Design Compiler 的学习重点不是记住图形界面按钮，而是建立一条完整闭环：读入设计、绑定库、施加约束、执行优化、查看报告、导出网表。

核心概念：RTL、gate-level netlist、target library、link library、SDC、Design Compiler、Design Vision、`dc_shell`、translation、mapping、optimization、`report_timing`、QoR。

逻辑主线：

1. RTL 只说明功能，不说明用哪套标准单元、跑多快、端口外面接什么。
2. 工艺库决定“能用哪些门”，约束决定“按什么目标优化”。
3. DC 先把 RTL 展开成内部结构，再映射到库单元，最后围绕时序、面积、功耗做优化。
4. 综合是否成功不能只看生成了网表，必须看 timing、area、power、QoR 等报告。
5. 图形界面适合入门观察，真实工程要把流程沉淀为 Tcl 脚本。

### 概念地图

| 层级 | 关键对象 | 解决的问题 | 最容易错在哪里 |
|---|---|---|---|
| 输入层 | RTL、top module、filelist | 告诉工具设计功能和层次 | 只读了部分文件，top 指错，模块引用解析失败 |
| 库层 | target library、link library、symbol library | 告诉工具可用单元和引用关系 | target/link 混淆，库版本与工艺目标不匹配 |
| 约束层 | SDC、clock、delay、load、drive | 告诉工具优化目标和外部环境 | 不约束或乱约束，导致报告看似干净但无意义 |
| 优化层 | compile、mapping、optimization | 生成满足目标的门级实现 | 只看命令执行完，不看 QoR 和 violation |
| 交付层 | netlist、reports、SDC、log | 给后端、STA、形式验证继续使用 | 少交报告、脚本不可复现、日志里有 unresolved warning |

### 最短学习路径

1. 先把 DC 放到 RTL 到门级网表的流程位置里。
2. 再区分 RTL、library、SDC、script 四类输入各自管什么。
3. 接着理解 `read_verilog -> elaborate/link -> check_design -> compile -> report -> write`。
4. 然后重点学 clock、input/output delay、load、drive 这些约束。
5. 最后用 `report_timing` 和 QoR 报告判断综合结果是否能继续交付。

一个稳的比喻是：工艺库像货架，约束像任务书，综合器像在限定货架和任务书里组装方案的工程师。货架上没有的门，它不能凭空拿；任务书没写频率和外部负载，它就不知道方案该偏快、偏小还是偏省电。这个比喻的边界是：DC 会做复杂逻辑优化，不是人工拼积木；但“只能在给定库和给定目标内搜索”这点必须记牢。

## 1. 逻辑综合处在 RTL 与物理实现之间

RTL 通过功能仿真以后，设计仍然只是行为级描述；后端需要的是由标准单元连接起来的门级网表。逻辑综合正是这个转换点：它把寄存器、组合逻辑、层次模块映射到某个工艺库里的触发器、门、MUX、缓冲器和加法器等真实单元。

视觉核对：02:18-02:40，画面给出 synthesis 的位置和定义，重点看 RTL 经过综合后变成 gate-level netlist。

![综合定义：RTL 到门级网表](<./screenshots/任务009_逻辑综合工具Design_Compiler的使用/01_synthesis_definition_02m18s.jpg>)

这张图只看转换方向：左边是设计意图和 RTL，右边是具体门级实现。不要把芯片图理解成“综合直接制造芯片”，综合交付的是网表和实现证据，不是实体硅片。

综合工具回答的不是“代码能不能跑”，而是下面这些工程问题：

- RTL 能否被目标工艺库实现。
- 指定时钟周期下关键路径能否收敛。
- 面积、功耗和时序之间如何取舍。
- 生成的 netlist 是否能交给 STA、后端实现、形式验证和门级仿真。

这里的第一条边界很重要：仿真通过只说明行为在 testbench 激励下符合预期；综合通过才说明这段 RTL 可以被硬件单元实现。写 RTL 时如果随手使用不可综合结构，仿真可能正常，综合却会失败或生成错误硬件。

### 1.1 一个最小例子：`assign y = a & b` 会变成什么

假设 RTL 写成：

```systemverilog
assign y = a & b;
```

仿真器只关心真值表：`a=1,b=1` 时 `y=1`，其他情况 `y=0`。综合器还要回答“用哪一个真实库单元实现”。如果 target library 里有 `AND2X1`，工具可能直接映射成二输入与门；如果库里只有 NAND 和 INV，工具可能映射成 `NAND2X1 + INVX1`；如果目标频率很紧，工具可能选择更强驱动的 `AND2X2` 或在后级插 buffer。

所以综合不是语法翻译，而是带约束的实现选择。同一段 RTL，在不同工艺库、不同负载、不同周期下，可能得到不同门级结构。这也是为什么综合报告要和库、约束、脚本一起保存。

## 2. DC 的三个核心动作：转换、映射、优化

Design Compiler 的工作可以压成三步：translation 把 RTL 转成内部布尔/寄存器结构，mapping 把内部结构匹配到库单元，optimization 在约束目标下调整结构。只说“DC 会生成网表”太粗，因为真正影响结果质量的是映射和优化。

视觉核对：06:55-07:20，画面展示 RTL translation 到门级结构的过程；11:31-12:00，画面把综合流程串起来。

![综合中的转换动作](<./screenshots/任务009_逻辑综合工具Design_Compiler的使用/02_synthesis_translation_06m55s.jpg>)

![综合流程主线](<./screenshots/任务009_逻辑综合工具Design_Compiler的使用/03_synthesis_flow_11m31s.jpg>)

第一张图看 RTL 到 gate-level 的形态变化，第二张图只看三段主线：load library and design、apply constraints、analyze/write results。中间英文很多，但读者先抓住“读入对象 -> 施加目标 -> 检查结果”即可。

三步可以这样理解：

| 阶段 | 工具在做什么 | 输出/检查点 |
|---|---|---|
| Translation | 解析 Verilog，展开参数和层次，识别寄存器、组合逻辑、运算符 | 语法、层次、top、未解析模块 |
| Mapping | 把内部逻辑映射到 target library 中的标准单元 | 是否能找到可用 cell，是否有 unmapped logic |
| Optimization | 根据时序、面积、功耗约束重构逻辑、插缓冲、换门尺寸 | slack、area、power、QoR |

优化不是魔法。工具只能在库和约束允许的空间里搜索：库太慢，约束太激进，路径结构太长，都可能导致 violation。反过来，如果没有时钟或 I/O 约束，工具也可能生成“看似成功”的网表，但这个结果没有真实性能目标。

把三步和失败信号对应起来更好用：

| 阶段 | 常见失败信号 | 优先回查 |
|---|---|---|
| Translation | 语法错误、宏未定义、参数展开异常 | RTL 文件、include 路径、编译选项 |
| Link / Mapping | unresolved reference、unmapped cell、找不到 DesignWare 或宏单元 | filelist、top、link library、target library |
| Optimization | negative slack、area 暴涨、QoR 不达标、unconstrained path | SDC 约束、微结构、pipeline、库角和负载模型 |

这张表能防止乱改：层次没 link 干净时，不该先调时钟周期；时序真实不收敛时，也不能只清 warning。

## 3. 工艺库决定工具能选什么硬件

target library 是综合的硬件货架，里面描述标准单元的功能、面积、时序弧、功耗等信息；link library 帮助 DC 解析设计中引用到的模块和库单元。没有库，DC 不知道该把 `a & b` 映射成哪个真实与门，也不知道某个触发器的建立时间、保持时间和 clock-to-Q 延迟。

视觉核对：16:08-16:35，画面展示 library setup，重点看 target/link library 的设置位置。

![库文件设置](<./screenshots/任务009_逻辑综合工具Design_Compiler的使用/04_library_setup_16m08s.jpg>)

这张图要看两行高亮：target library 是“能映射成什么”，link library 是“能解析到什么”。初学者只要先把这两个问题分开，后面 unresolved reference 和 unmapped logic 就容易定位。

常见 Tcl 形态如下：

```tcl
set target_library "typical.db"
set link_library   "* typical.db dw_foundation.sldb"
```

两类库不要混：

- `target_library`：综合时真正用于映射的目标标准单元库。
- `link_library`：链接层次和引用时可查找的库集合，通常包含 `*`、target library、DesignWare 或其他宏单元库。

如果 `link` 后出现 unresolved reference，说明某些模块或单元没被解析出来；如果库角不对，比如把慢角/快角混用，后续 timing 结论也会偏离真实签核环境。

## 4. 读入设计后必须检查层次和引用

读 RTL 不是把文件丢给工具就结束。DC 需要知道顶层模块、依赖文件、参数展开结果和模块引用关系。真实工程中，读入阶段最常见的问题是 filelist 不完整、top 名字不对、子模块路径漏掉、宏定义缺失。

视觉核对：20:45-21:15，画面显示 `read_verilog` 一类动作，重点看设计文件被读入后进入工具环境。

![读入 Verilog 设计](<./screenshots/任务009_逻辑综合工具Design_Compiler的使用/05_read_verilog_20m45s.jpg>)

这张图要看 `read_verilog TOP.v A.v B.v` 这种输入集合。综合器不会自动猜完整工程；你漏给一个子模块，它就只能在 link 阶段报 unresolved。

最小脚本骨架可以写成：

```tcl
set TOP top_module
read_verilog [list ./rtl/top_module.v ./rtl/sub_module.v]
current_design $TOP
link
check_design
```

检查口径：

- `current_design` 是否指向正确 top。
- `link` 是否有 unresolved module/cell。
- `check_design` 是否报告多驱动、未连接、组合环、宽度不一致等问题。
- 读入日志里是否有 syntax warning 或 ignored construct。

如果这一阶段没干净，后面的约束和报告都不可靠。不要把 `compile` 当成第一条检查线，设计层次先干净，优化才有意义。

## 5. 时钟约束是综合优化的方向盘

没有 clock constraint，工具不知道目标频率；时钟约束过紧，工具可能拼命优化仍然报负 slack；时钟约束过松，结果面积和功耗可能低，但实际性能达不到系统要求。综合约束的第一优先级通常是 `create_clock`。

视觉核对：25:21-25:55，画面展示 clock constraint，重点看 clock period 与端口/时钟名绑定。

![时钟约束](<./screenshots/任务009_逻辑综合工具Design_Compiler的使用/06_clock_constraints_25m21s.jpg>)

这张图要看 period、clock port 和 uncertainty。clock 约束不是写给报告看的注释，而是告诉工具“每条同步路径最多有多少时间预算”。

典型写法：

```tcl
create_clock -name clk -period 10.0 [get_ports clk]
set_clock_uncertainty 0.2 [get_clocks clk]
```

含义拆开：

- `-period 10.0` 表示目标时钟周期为 10 ns，也就是 100 MHz。
- `[get_ports clk]` 把约束绑定到顶层时钟端口。
- `set_clock_uncertainty` 给抖动、偏斜、建模误差留余量。

综合工具优化的是“满足捕获沿前数据到达”的路径。如果没有时钟，`report_timing` 可能没有有效路径；如果时钟名写错，约束没有绑定到真实端口，结果等同于没约束。

约束不是后补作业，而是预算模型。`create_clock` 给总预算，`set_input_delay` 说明外部上游已经花掉多少预算，`set_output_delay` 说明下游还要预留多少预算，`set_load` 和 `set_driving_cell` 说明边界处不是理想零负载、无限驱动。没有这些信息，工具就像被要求“尽量做好”却没有交付标准。

## 6. I/O 约束描述芯片外部世界

输入延迟、输出延迟、驱动能力和负载不是装饰性约束，它们告诉 DC：端口外面还有上游寄存器、板级走线、下游负载或其他模块。只约束内部 clock，不约束 I/O，会让工具误以为外部环境理想，导致端口附近路径优化不足。

视觉核对：29:58-30:25，画面展示 input delay；34:35-35:05，画面展示环境/负载类约束。

![输入延迟约束](<./screenshots/任务009_逻辑综合工具Design_Compiler的使用/07_input_delay_29m58s.jpg>)

![环境约束](<./screenshots/任务009_逻辑综合工具Design_Compiler的使用/08_environmental_constraint_34m35s.jpg>)

第一张图看外部发射寄存器到芯片输入端口已经消耗的时间；第二张图看输出端口后面接了负载，不是理想悬空。I/O 约束的本质是把芯片边界外的世界告诉综合器。

常见写法：

```tcl
set_input_delay  2.0 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 2.0 -clock clk [all_outputs]
set_load 0.05 [all_outputs]
set_driving_cell -lib_cell INVX1 [remove_from_collection [all_inputs] [get_ports clk]]
```

这些约束分别回答：

- 输入信号到达芯片端口时，已经消耗了多少时钟周期预算。
- 输出信号离开芯片后，下游还需要多少时间。
- 输出端口要驱动多大的负载。
- 输入端口由怎样的上游单元驱动。

新手容易把 I/O 约束看成后端才关心的内容。实际上综合阶段已经要根据端口环境决定门尺寸、缓冲和逻辑重构，否则后续 STA 可能集中爆出边界路径问题。

## 7. 报告是交付证据，不是流程尾巴

综合运行结束只说明工具完成了一次优化尝试，不能说明设计可交付。必须用报告回答：有没有时序违例，面积多少，功耗趋势怎样，是否有 unmapped cell，QoR 是否符合预期。

视觉核对：39:11-39:40，画面展示 QoR/report；43:48-44:20，画面展示 timing report。

![QoR 报告](<./screenshots/任务009_逻辑综合工具Design_Compiler的使用/09_report_qor_39m11s.jpg>)

![Timing 报告](<./screenshots/任务009_逻辑综合工具Design_Compiler的使用/10_report_timing_43m48s.jpg>)

QoR 图看 WNS/TNS、cell count、area 这些汇总信号；timing 图看具体路径。汇总告诉你“整体健康吗”，路径告诉你“最差问题在哪里”。

至少要看：

```tcl
report_qor
report_timing -max_paths 10
report_area
report_power
check_design
check_timing
```

`report_timing` 的读法：

| 字段/概念 | 读法 |
|---|---|
| startpoint | 路径从哪个寄存器或输入端口发射 |
| endpoint | 路径到哪个寄存器或输出端口捕获 |
| data arrival time | 数据实际到达时间 |
| data required time | 数据最晚必须到达时间 |
| slack | required - arrival，负数表示 violation |

负 slack 不是“报告不好看”，而是这条路径在目标周期内来不及。综合阶段可以尝试放宽约束、改 RTL 结构、加流水、减少组合层级、换库或调整优化策略；不能只把报告留给后端。

一个极简 timing path 可以这样读：

```text
Startpoint: u_reg0/Q
Endpoint  : u_reg1/D
Clock     : clk, period = 2.00 ns
Data arrival time  = 1.72 ns
Data required time = 1.85 ns
Slack              = 0.13 ns
```

第一遍先不陷入每个 cell delay，先回答四个问题：路径从哪个寄存器出发，到哪个寄存器结束，目标周期是多少，slack 是正还是负。若 required 为 1.85 ns 而 arrival 为 2.10 ns，slack 就是 `-0.25 ns`，说明这条路径来不及，需要回到组合逻辑层级、驱动能力、约束真实性或 pipeline 结构上判断。

## 8. Design Vision 适合学习观察，工程交付要靠脚本

Design Vision 的价值是让初学者看到设计层次、库设置、约束入口和报告位置；但工程中不能依赖手工点击，因为手工操作不可复现，也很难审查每次运行差异。成熟流程会把 DC 操作固化为 Tcl 脚本，并保存日志和报告。

视觉核对：48:25-49:00，画面展示 Design Vision 设置/界面，重点看图形界面只是脚本流程的可视化入口。

![Design Vision 设置入口](<./screenshots/任务009_逻辑综合工具Design_Compiler的使用/11_design_vision_setup_48m25s.jpg>)

这张图要看 GUI 动作背后的脚本动作：点开 setup 本质上是在设置库和工作目录；点击读入、综合、报告，本质上对应 `read/link/compile/report/write`。工程交付看脚本和产物，不看鼠标点过哪里。

一个可复现综合目录通常包含：

```text
dc/
  run.tcl
  constraints/top.sdc
  filelist.f
  reports/
    timing.rpt
    area.rpt
    power.rpt
    qor.rpt
  outputs/
    top_mapped.v
    top.sdc
    top.ddc
  logs/
    dc.log
```

脚本化的最低要求：

- 每次运行的输入文件、库、约束可追踪。
- 报告路径固定，便于比较不同版本。
- 日志保留 warning/error，方便回溯。
- 输出网表和约束文件成对交付。

GUI 与脚本要这样对应：

| GUI 里看见的动作 | 脚本/产物里的工程证据 |
|---|---|
| 设置库路径 | `set target_library`、`set link_library` |
| 读入设计 | `read_verilog`、filelist、log |
| 指定 top | `current_design`、`link` |
| 添加约束 | `create_clock`、`set_input_delay`、SDC |
| 执行综合 | `compile` / `compile_ultra` |
| 查看报告 | `report_timing/report_area/report_power/report_qor` |
| 导出结果 | mapped netlist、SDC、DDC、reports、logs |

学习阶段可以用 GUI 看结构，交付阶段必须能用脚本复现同一结果。

在进入最小脚本前，先记三条失败回路：

| 失败类型 | 回退位置 | 不要先做什么 |
|---|---|---|
| 层次、引用、top 错 | filelist、include、`current_design`、link library | 不要先调时钟周期 |
| unconstrained path 或 clock 失效 | SDC、clock 端口、I/O 约束 | 不要先判断 RTL 太慢 |
| 约束真实但 slack 负 | RTL 微结构、组合层级、pipeline、库选择 | 不要只把报告交给后端 |

## 9. 最小可复现综合闭环

下面这个骨架不是完整项目脚本，但它表达了 DC 运行的必要顺序：

```tcl
set TOP top_module

set target_library "typical.db"
set link_library   "* typical.db dw_foundation.sldb"

read_verilog [list ./rtl/top_module.v ./rtl/sub_module.v]
current_design $TOP
link
check_design

create_clock -name clk -period 10.0 [get_ports clk]
set_clock_uncertainty 0.2 [get_clocks clk]
set_input_delay  2.0 -clock clk [remove_from_collection [all_inputs] [get_ports clk]]
set_output_delay 2.0 -clock clk [all_outputs]
set_load 0.05 [all_outputs]

compile_ultra

report_qor > ./reports/qor.rpt
report_timing -max_paths 10 > ./reports/timing.rpt
report_area > ./reports/area.rpt
report_power > ./reports/power.rpt

write -format verilog -hierarchy -output ./outputs/${TOP}_mapped.v
write_sdc ./outputs/${TOP}.sdc
write -format ddc -hierarchy -output ./outputs/${TOP}.ddc
```

成功信号：

- `link` 和 `check_design` 没有未解析模块和关键结构错误。
- `check_timing` 没有 unconstrained path 或 clock 缺失。
- `report_timing` 的关键路径 slack 满足目标。
- 输出网表、SDC、报告、日志齐全。

失败信号：

- 报告里出现大量 unconstrained endpoints。
- clock 没绑定到真实端口。
- `compile` 完成但仍有 unmapped logic。
- timing 全是 N/A 或无有效路径。
- 只生成 netlist，没有报告和日志。

## 本章速记

- DC 的输入是 RTL + library + constraint + script，不是单独一个 Verilog 文件。
- target library 决定映射单元，link library 解决引用关系。
- SDC 约束是优化目标，尤其是 clock、I/O delay、load、drive。
- 综合结果必须由 `report_timing`、`report_area`、`report_power`、`report_qor` 证明。
- 图形界面用于理解，脚本用于交付。

## 自测题与答案

1. **为什么 RTL 仿真通过后还需要综合？**  
   答：RTL 仿真只验证行为，综合把 RTL 映射成目标工艺库下的门级网表，并检查在约束下是否能满足时序、面积、功耗等实现要求。

2. **target library 和 link library 的区别是什么？**  
   答：target library 是综合映射时可选的标准单元库；link library 用来解析设计层次、实例化模块和库单元引用，范围通常比 target library 更大。

3. **没有 `create_clock` 会造成什么后果？**  
   答：工具不知道目标周期，时序路径可能无法被有效分析和优化，`report_timing` 结论没有真实约束意义。

4. **`set_input_delay` 描述的是什么？**  
   答：输入信号到达芯片端口前已经由外部路径消耗的时间预算，它让综合工具知道内部输入路径还剩多少时序余量。

5. **判断综合是否可交付至少要看哪些证据？**  
   答：`check_design/check_timing`、`report_timing`、`report_area`、`report_power`、`report_qor`、输出 gate-level netlist、输出 SDC 和完整 log。

6. **为什么工程中不能只依赖 Design Vision 手工操作？**  
   答：手工点击不可复现、不可审查、难以比较版本差异；工程交付需要脚本固定输入、约束、运行命令、报告和输出路径。


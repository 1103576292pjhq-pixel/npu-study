# 任务113：Environmental Attributes

## 本章知识全景图
这一讲回答一个容易被初学者忽略的问题：综合工具即使知道 RTL、clock、input/output delay，也仍然不知道真实外部环境。输入边沿有多慢、输入由什么强度的 cell 驱动、输出后面挂多大电容，都会改变库查表得到的 delay 和 transition。

| 环境属性 | 工具缺省时的问题 | 需要补充的约束 |
|---|---|---|
| output capacitive load | output 被当成零负载或理想负载 | `set_load` |
| input transition | 输入边沿快慢未知 | `set_input_transition` |
| driving cell | 外部驱动强度未知 | `set_driving_cell` |
| max capacitance | 输出负载上限未知 | `set_max_capacitance` |
| load budget | block 级没有下游完整信息 | 用保守负载预算模拟下游压力 |

![环境属性影响 timing](<./screenshots/任务113_Environmental_Attributes/video_dense_01_03m54s.jpg>)

最短学习路径：先理解 cell delay 由 input transition 和 output load 共同决定；再分别掌握 `set_load`、`set_input_transition`、`set_driving_cell`；最后用 load budget 和 max capacitance 把 block 级环境建模成可执行约束。

## 全视频地图
| 时间 | 画面证据 | 内容 | 学习任务 |
|---|---|---|---|
| 03:45 | Factors Affecting Timing | 约束不只需要 clock/input/output delay | 理解环境属性为什么必要 |
| 07:48-11:42 | output capacitive load | 输出负载影响 transition 和 cell delay | 学会 `set_load` |
| 15:36-23:24 | input transition / driving cell | 输入边沿和外部驱动建模 | 区分 `set_input_transition` 与 `set_driving_cell` |
| 27:18-39:00 | load budgeting examples | block 级负载预算 | 学会保守建模下游输入电容 |
| 42:54-46:48 | command summary | 命令总表 | 建立环境属性脚本骨架 |

## 视觉核对清单

本讲的图像要按“外部世界进入 delay 查表”的链路读。clock 和 delay 只是时间合同，environment attributes 则像天气、载重和路况：同一辆车、同一段路，在空载和重载、好路和泥路下到达时间不同。对标准单元库来说，load、transition、driving cell 就是这种路况。

Liberty 库通常把 cell delay 存成二维或多维查表：横轴可能是 input transition，纵轴可能是 output load，表格里的值才是 delay 或 output transition。DC 读到 `set_input_transition`、`set_driving_cell`、`set_load` 后，本质是在告诉工具到哪张表、哪个坐标附近做插值。环境属性不是“额外注释”，而是 delay 数字的坐标系。

| 截图 | 看图要点 | 漏看后果 |
|---|---|---|
| Factors Affecting Timing | delay 不只由逻辑级数决定，还受负载和边沿影响 | timing clean 是理想环境下的假象 |
| output capacitive load | `set_load` 描述实际/预算负载 | 输出被当成 0 负载，后端爆 transition/max cap |
| input transition / driving cell | 输入边沿可直接指定，也可由外部驱动 cell 推导 | 把输入端看成理想阶跃 |
| load budgeting | block 级要用保守扇出预算模拟未知下游 | 子模块综合过松，集成后失真 |
| max capacitance | max cap 是上限约束，不是实际负载 | 把 DRC 限制和物理负载混为一谈 |

## 1. 环境属性不是装饰，它决定库 delay 的查表条件
标准单元 delay 不是固定常数。库里通常按输入 transition 和输出 load 建表，工具根据当前 cell 的输入边沿和输出负载插值得到 delay。

如果没有环境属性，工具只能假设默认输入边沿和输出负载。这个默认值可能让报告过于乐观，也可能和真实上级/下级模块完全不一致。环境属性的目标就是让 block 级综合接近系统级真实连接。

## 2. output capacitive load：输出负载会拖慢 transition 和 cell delay
输出端后面接的不是空气，而是下游 cell 输入电容、走线电容、IO 或其他 block。负载越大，输出驱动越慢，transition 越差，cell delay 也会增加。

![output capacitive load](<./screenshots/任务113_Environmental_Attributes/video_dense_02_07m48s.jpg>)

用 `set_load` 建模输出负载：

```tcl
set_load 0.05 [all_outputs]
```

如果题目给出芯片级最大输出负载，例如某端口最大 30 fF，而库单位是 pF，就要先做单位换算：

```tcl
    # 30 fF = 0.03 pF
set_load 0.03 [get_ports B]
```

![output load 建模例子](<./screenshots/任务113_Environmental_Attributes/video_dense_03_11m42s.jpg>)

判断口径：`set_load` 描述“实际或预算负载是多少”，不是“最大允许负载是多少”。最大允许值要用 `set_max_capacitance`。

## 3. input transition：输入边沿慢会让第一级逻辑变慢
输入端信号的 rise/fall transition 会影响 input port 后面第一级 cell 的 delay。边沿越慢，门电路穿越阈值区间越久，输出响应也越慢。

![input transition effect](<./screenshots/任务113_Environmental_Attributes/video_dense_04_15m36s.jpg>)

```tcl
set_input_transition 0.12 [remove_from_collection [all_inputs] [get_ports Clk]]
```

视频强调默认 DC 会假设 input transition 为 0，这会把输入环境理想化。真实项目中，外部 block 或 IO 不可能给所有输入提供理想瞬时边沿。

## 4. driving cell：用库单元模拟外部驱动能力
`set_driving_cell` 比 `set_input_transition` 更结构化：它不是直接给一个边沿时间，而是告诉工具 input port 由哪个库 cell 驱动。工具可以根据这个 cell 的输出能力和负载计算 transition。

![driving cell 建模](<./screenshots/任务113_Environmental_Attributes/video_dense_06_23m24s.jpg>)

```tcl
set_driving_cell -lib_cell FD1 [get_ports IN1]
```

如果没有指定驱动 pin，DC 会使用库 cell 定义中的第一个 output pin。实际工程里建议明确 pin，避免多输出 cell 或库命名导致歧义。

`set_input_transition` 和 `set_driving_cell` 不要混成一个概念：

| 命令 | 建模方式 | 适合场景 |
|---|---|---|
| `set_input_transition` | 直接指定输入边沿时间 | 已知外部边沿或做简化预算 |
| `set_driving_cell` | 指定外部驱动 cell | 希望更接近库模型和驱动强度 |

同一个 input 上不要无意识叠加两套输入边沿模型。若项目同时出现 `set_input_transition` 和 `set_driving_cell`，要查工具版本和约束优先级，并在 `report_port -verbose` 中确认最终生效的是哪一个。否则你以为自己建模的是外部 driver，工具实际可能按固定 transition 算；或者反过来，导致 report 和设计假设不一致。

## 5. load budgeting：block 级没有完整下游时，用保守预算模拟
block 级综合经常不知道所有下游模块的真实布局和电容，只能先做 load budget。视频给出的方法是：假设当前 block 输出会驱动若干下游 input pin，把这些 pin 的输入电容或保守估算合成到 output load 上。

![load budgeting 原则](<./screenshots/任务113_Environmental_Attributes/video_dense_07_27m18s.jpg>)

![load budget example 1](<./screenshots/任务113_Environmental_Attributes/video_dense_08_31m12s.jpg>)

示例脚本思路：

```tcl
set ALL_INP_EXC_CLK [remove_from_collection [all_inputs] [get_ports Clk]]
set_driving_cell -no_design_rule -lib_cell FD1 $ALL_INP_EXC_CLK

    # 假设每个 output 要驱动 10 个同类输入负载
set_load [expr {$MAX_INPUT_LOAD * 10}] [all_outputs]
```

这里的 `10` 不是固定标准，而是题目或项目定义的保守扇出预算。它的作用是避免 block 输出在综合时被当成轻负载。

![load budget example 2](<./screenshots/任务113_Environmental_Attributes/video_dense_09_35m06s.jpg>)

## 6. max capacitance：限制负载上限，而不是声明实际负载
`set_max_capacitance` 用来限制 design、port 或 net 的最大电容。它属于 design rule constraint。违反 max cap 时，工具可能需要插 buffer、换更强驱动，或报告 DRC violation。

![max capacitance command summary](<./screenshots/任务113_Environmental_Attributes/video_dense_12_46m48s.jpg>)

典型写法：

```tcl
set_max_capacitance 0.2 [all_outputs]
```

和 `set_load` 的区别：

| 约束 | 含义 | 类比 |
|---|---|---|
| `set_load` | 当前输出实际/预算要驱动多少负载 | “车上现在载了多重” |
| `set_max_capacitance` | 当前输出最多允许驱动多少负载 | “这辆车最大载重限制” |

## 7. 本讲环境属性命令骨架
![commands covered 1](<./screenshots/任务113_Environmental_Attributes/video_dense_11_42m54s.jpg>)

```tcl
set MAX_CAP 0.2
set_max_capacitance $MAX_CAP [current_design]

set ALL_INP_EXC_CLK [remove_from_collection [all_inputs] [get_ports Clk]]
set_input_transition 0.12 $ALL_INP_EXC_CLK
set_driving_cell -lib_cell FD1 $ALL_INP_EXC_CLK

set LOAD_BUDGET 0.05
set_load $LOAD_BUDGET [all_outputs]
```

这组命令通常和 clock/input/output delay 放在同一个约束文件里。clock 和 timing budget 解决“时间要求”，environment attributes 解决“电气环境”。

## 常见误区
| 误区 | 正确理解 |
|---|---|
| 只要写了 clock 和 delay 就够 | delay 查表还需要 transition/load |
| output load 不写就是 0，报告更好 | 报告更好不代表真实，可能低估后级负载 |
| `set_load` 等于 max cap | 一个是实际负载，一个是上限约束 |
| driving cell 随便选 | 它代表外部驱动能力，会影响输入 transition |
| 所有 input 都能统一套属性 | clock、reset、特殊 IO 可能需要单独处理 |

## 工程练习

1. 判断 `set_load` 与 `set_max_capacitance` 的 PASS/FAIL。

   合格答案：`report_port -verbose` 或相关 report 能看到 output load，说明实际/预算负载已挂到端口；`report_constraint -all_violators` 没有未解释的 max capacitance violation，说明上限约束没有被违反。前者是“车上装了多少货”，后者是“这辆车最大允许载重”。

2. 给 input transition 建报告闭环。

   合格答案：排除 clock/reset 等特殊端口后，对普通 input 设置 `set_input_transition` 或 `set_driving_cell`；在 `report_port -verbose` 中确认属性出现；再看 `report_timing` 中第一级 cell delay 是否基于该环境计算。

## 复习与自测
1. 为什么输出负载会影响 timing？  
   答：输出负载越大，驱动 cell 的 transition 和 delay 通常越差，data arrival time 会变晚。

2. `set_input_transition` 和 `set_driving_cell` 有什么区别？  
   答：前者直接指定输入边沿；后者用库 cell 模拟外部驱动，让工具计算输入边沿。

3. `set_load` 和 `set_max_capacitance` 的区别是什么？  
   答：`set_load` 描述实际/预算负载，`set_max_capacitance` 描述最大允许电容上限。

4. block 级不知道下游真实负载时怎么办？  
   答：使用保守 load budget，根据下游输入电容、扇出估计或项目规则设置 output load。

## AI+IC 连接
NPU 中高 fanout 控制信号、广播 enable、SRAM/NoC 接口输出都容易被负载低估。环境属性把“逻辑综合”连接到“物理电气现实”：没有 transition/load 建模，MAC array 或 DMA block 的 early timing 可能看起来 clean，后端却因为负载和 transition 爆出大量 violation。


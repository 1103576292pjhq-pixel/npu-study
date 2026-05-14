# 任务111：Timing Constraints3

## 本章知识全景图
这一讲解决的是约束文件从“能写几条 SDC”到“能交付工程 flow”的问题。前两讲已经讲清 input/output delay 的公式，这一讲把它收束成三件事：端口约束怎么算、约束脚本怎么组织、脚本交付前怎么检查。

| 学习单元 | 必须掌握的判断 | 工程口径 |
|---|---|---|
| registered outputs | 输出端寄存器化后 output delay 怎么算 | 内部输出组合逻辑趋近于 0，外部预算可用周期减外部最快 clock-to-Q 反推 |
| timing constraint summary | 哪些路径由哪些命令约束 | input path 靠 input delay，reg-to-reg 靠 clock，output path 靠 output delay |
| interactive command debug | 不熟 DC 命令时怎么试错 | 在 `dc_shell-topo` 里先逐条执行，再固化进 `.con` |
| sourced constraint file | 为什么工程中不用手敲命令 | `source TOP.con` 让约束可复用、可审查、可记录 |
| constraint sanity check | 怎么证明约束不是“能跑但不可信” | `dcprocheck` 查语法，`check_timing` 查缺失/冲突/clock gating，报告重定向留证据 |

![registered output 的约束场景](<./screenshots/任务111_Timing_Constraints3/video_dense_01_03m15s.jpg>)

最短学习路径：先看 registered output 的公式，再看三类 path 的约束归属；然后把交互式命令转成 `source` 文件；最后用 `dcprocheck` 和 `check_timing` 建立交付前检查门。

## 全视频地图
| 时间 | 画面证据 | 课程内容 | 学习任务 |
|---|---|---|---|
| 03:15-06:31 | registered output 图和 Tcl 计算式 | 输出端寄存器化、`expr {}`、`set_output_delay` | 把 output delay 从结构图反推到 SDC |
| 09:46 | Timing Constraint Summary | input、output、reg-to-reg 三类路径总结 | 判断约束完整性 |
| 13:02 | Executing Commands Interactively | DC shell 逐条调命令 | 学会先试错再写脚本 |
| 16:17-19:33 | Sourcing Constraint Files / Batch Mode | `source TOP.con`、run script、`tee` 日志 | 建立批处理 flow |
| 22:49-29:20 | constraint file recommendations / `dcprocheck` | `reset_design`、注释、续行、语法检查 | 写可维护约束文件 |
| 32:35-35:51 | `check_timing`、报告重定向 | missing constraints、multiple clocks、redirect | 建立检查证据 |
| 39:07 | Commands Covered Summary | 本讲命令总表 | 回收知识清单 |

## 视觉核对清单

本讲的截图要按“预算合同”读：clock 是合同的计量单位，input/output delay 是外部已经拿走或还要保留的时间，`source TOP.con` 是把合同放进工具，`check_timing` 是审合同有没有漏项。不要把这些图看成命令截图；它们是在训练“约束从哪里来，怎样证明它生效”。

| 截图 | 看图要点 | 漏看后果 |
|---|---|---|
| registered output 图 | 输出端寄存器化让内部路径边界清楚，output delay 可从外部预算反推 | 把 output delay 当固定模板数字，换接口就不会算 |
| Timing Constraint Summary | input、output、reg-to-reg 三类路径都要被约束覆盖 | 只约束 clock，留下 unconstrained path |
| interactive commands | 先查对象和 option，再沉淀到脚本 | 大脚本失败时不知道是对象空还是语法错 |
| source / batch mode | 约束文件进入 DC，并留下 log 证据 | 手敲命令不可复现，无法审查版本 |
| dcprocheck / check_timing | 语法检查和语义检查不是一回事 | 文件能 source 但约束缺失仍未发现 |

## 1. registered output：不是“输出端简单”，而是预算边界清晰
输出端寄存器化的价值是把模块内部输出路径变短、变可控。图中每个 output 前都有寄存器，寄存器 Q 到 output port 之间没有复杂组合逻辑，因此本模块内部不再吞掉大量 output path budget。

视频给出的数值可以整理成：

```text
周期 T = 10 ns
外部最快寄存器 clock-to-Q min = 0.9 ns
输出端约束 max output delay = 10 - 0.9 = 9.1 ns
```

对应 SDC：

```tcl
set ALL_INP_EXC_CLK [remove_from_collection [all_inputs] [get_ports Clk]]
set_input_delay  -max 1.5 -clock Clk $ALL_INP_EXC_CLK
set_output_delay -max [expr {10 - 0.9}] -clock Clk [all_outputs]
```

这里 `expr {10 - 0.9}` 的作用是让 Tcl 执行算术求值。方括号 `[]` 是命令替换，大括号 `{}` 是把表达式作为整体传入；如果把它当普通字符串或漏掉 `expr`，工具不会按你想象做数学计算。

![`expr` 与 registered output 公式](<./screenshots/任务111_Timing_Constraints3/video_dense_02_06m31s.jpg>)

## 2. timing constraint summary：完整性先于优化
约束完整性是综合结果可信的前提。视频中的 summary 图把路径分成三类：

![Timing Constraint Summary](<./screenshots/任务111_Timing_Constraints3/video_dense_03_09m46s.jpg>)

| 路径类型 | 约束命令 | 缺失后果 |
|---|---|---|
| all input paths | `set_input_delay` | 工具不知道外部已经消耗多少时间，内部输入路径目标不明确 |
| all reg-to-reg paths | `create_clock` | 工具不知道寄存器之间的周期要求 |
| all output paths | `set_output_delay` | 工具不知道 output port 后面还要预留多少时间 |

约束不完整时，综合工具可能不会优化某些路径；约束过紧时，工具会用面积和功耗强行换 timing；约束过松时，报告会好看但实际频率达不到。真正合格的约束要同时满足“完整”和“准确”。

## 3. 先交互式调试，再写成约束文件
DC 命令不熟时，不要直接写进大脚本赌一次运行。视频中用 `dc_shell-topo` 演示了逐条敲命令的排错方式：

![交互式执行命令](<./screenshots/任务111_Timing_Constraints3/video_dense_04_13m02s.jpg>)

常用调试命令：

```tcl
help *clock*
help -verbose create_clock
man create_clock
man set_input_delay
get_ports *
get_ports Clk
```

交互式模式要解决的是命令对象和参数问题：端口名是否存在、collection 是否为空、option 是否拼对、必选参数是否缺失。调通后再写入 `TOP.con`，否则错误会被大脚本淹没在几百行日志里。

## 4. `source TOP.con`：把约束变成可复用资产
工程中约束文件通常集中保存，再由 DC flow 调用：

![source constraints file](<./screenshots/任务111_Timing_Constraints3/video_dense_05_16m17s.jpg>)

```tcl
read_verilog A.v B.v TOP.v
current_design MY_TOP
link
check_design
source TOP.con
```

再外层可以用 batch mode 执行：

![batch mode run script](<./screenshots/任务111_Timing_Constraints3/video_dense_06_19m33s.jpg>)

```bash
dc_shell-topo -f RUN.tcl | tee -i dc.log
```

`tee -i dc.log` 的意义是保存可追溯证据。综合可能跑很久，真正的工作不是看屏幕滚动，而是第二天读 `dc.log`、`check_timing.log`、`precompile.rpt` 判断是否成功。

## 5. 约束文件可维护性：`reset_design`、注释、续行都不是形式主义
如果一个 design 在同一会话里被 source 多个 constraint script，旧约束可能残留。`reset_design` 的作用是清空当前 design 上已有约束，保证后面的脚本从干净状态开始。

![constraint file recommendation 1](<./screenshots/任务111_Timing_Constraints3/video_dense_07_22m49s.jpg>)

可维护写法：

```tcl
reset_design

    # create clock
create_clock -period 10 [get_ports Clk]

    # constrain data inputs, excluding clock
set ALL_INP_EXC_CLK [remove_from_collection [all_inputs] [get_ports Clk]]
set_input_delay -max 1.5 \
  -clock [get_clocks Clk] \
  $ALL_INP_EXC_CLK
```

![constraint file recommendation 2](<./screenshots/任务111_Timing_Constraints3/video_dense_08_26m04s.jpg>)

注释用 `#`，续行用 `\`，约束扩展名推荐用 `.con`。不要过度使用别名和缩写，也不要把多步逻辑塞进难读的一行；约束文件以后一定会被别人审查。

## 6. `dcprocheck` 和 `check_timing` 是两种不同检查
`dcprocheck TOP.con` 是语法检查，能在不完整启动 DC flow 的情况下发现 Tcl/SDC 写法问题。

![dcprocheck 语法检查](<./screenshots/任务111_Timing_Constraints3/video_dense_09_29m20s.jpg>)

`check_timing` 是约束语义检查，重点发现：

- missing endpoint constraints
- missing / overlapping / multiple clocks
- clock-gating cells that may interfere with the clock
- unconstrained 或异常 timing path

![check_timing 检查约束缺失与冲突](<./screenshots/任务111_Timing_Constraints3/video_dense_10_32m35s.jpg>)

常见报告重定向：

```tcl
redirect -tee -file check_timing.log {check_timing}
redirect -append -tee -file precompile.rpt {report_port -verbose}
redirect -append -tee -file precompile.rpt {report_clock -skew}
redirect -append -tee -file precompile.rpt {report_constraint -all_violators}
```

![报告重定向](<./screenshots/任务111_Timing_Constraints3/video_dense_11_35m51s.jpg>)

`-tee` 同时显示和写文件，`-append` 追加到已有报告。交付一份约束文件时，最好同时交付对应检查日志，否则别人只能相信“它应该是对的”。

## 7. 本讲命令清单
![commands covered](<./screenshots/任务111_Timing_Constraints3/video_dense_12_39m07s.jpg>)

```tcl
reset_design
create_clock -period 2 [get_ports Clk]
create_clock -period 1.5 -name VCLK # virtual clock
set_clock_uncertainty -setup 0.2 [get_clocks Clk]
set_clock_latency -source -max 0.3 [get_clocks Clk]
set_clock_transition -max 0.12 [get_clocks Clk]
set_input_delay  -max 0.5 -clock Clk [get_ports A C F]
set_input_delay  -max 0.8 -clock Clk [all_inputs]
set_output_delay -max 1.1 -clock Clk [get_ports OUT1 OUT2]
```

这张清单的学习方式不是背命令，而是把每条命令放回预算模型：它约束的是 clock、input、output、latency、transition 还是 virtual clock。

## 工程练习

1. 给一份 `.con` 建最小验收门。

   合格答案：`dcprocheck TOP.con` 无语法错误；`source TOP.con` 后 `report_clock` 能看到所有 clock；`report_port -verbose` 能看到 input/output delay、transition/load；`check_timing` 不报关键 unconstrained；`report_constraint -all_violators` 中 violation 可解释。它像验收一份施工合同：不是合同能打印就合格，而是条款覆盖所有施工边界。

2. 解释 `dcprocheck` 通过但 `check_timing` 失败的场景。

   合格答案：`dcprocheck` 只说明 Tcl/SDC 写法基本合法；`check_timing` 会发现对象没覆盖、clock 缺失、端点未约束、多 clock 冲突等语义问题。前者像语法老师，后者像工程审计。

## 复习与自测
1. `dcprocheck` 和 `check_timing` 的区别是什么？  
   答：`dcprocheck` 查约束文件语法；`check_timing` 查设计约束完整性和一致性。

2. 为什么工程里不推荐长期手敲 DC 命令？  
   答：手敲不可复现、不可审查、不可保存；`source` 和 batch script 才能形成可追溯 flow。

3. `reset_design` 放在 constraint script 前面的原因是什么？  
   答：清掉当前 design 上已有约束，避免旧约束污染本次约束结果。

4. registered output 场景为什么容易估算 output delay？  
   答：output port 前没有复杂组合逻辑，模块内部输出路径边界清晰，外部预算可按周期和外部寄存器 clock-to-Q 反推。

## AI+IC 连接
NPU block 级综合也必须交付 SDC 和检查报告。一个 MAC array、DMA 或 SRAM controller 不能只说“RTL 过了综合”，还要说明 input/output budget、clock、transition、load 是否完整，`check_timing` 是否 clean。约束文件是 AI 芯片子模块进入后端和系统集成的合同，不是工具练习文件。



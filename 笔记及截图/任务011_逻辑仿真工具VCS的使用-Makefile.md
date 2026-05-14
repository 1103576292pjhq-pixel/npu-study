# 任务11：逻辑仿真工具 VCS 的使用：Makefile

## 本章知识全景图

### 一眼看懂这讲在讲什么

VCS 仿真不是一次性手敲长命令，而是一条可重复工程流程：编译 RTL/testbench，运行仿真可执行文件，生成日志和波形，用 DVE 定位问题，再用 Makefile 把这些动作固化成目标。Makefile 的价值不是“少打字”，而是让每次仿真的输入、选项、输出和清理规则可复现。

核心概念：VCS、DVE、testbench、DUT、X unknown、compile、run、waveform、Makefile、target、dependency、recipe、variable、phony target、clean、log、filelist。

逻辑主线：

1. 先从波形里的 X 学会 debug：未知态通常来自未初始化、未赋值、复位不足、多驱动或未连接。
2. 再把 VCS 流程拆成 compile 与 run：编译生成 `simv`，运行 `simv` 产生日志和波形。
3. 然后用 Makefile 把长命令组织成 `compile/run/dve/clean` 等目标。
4. 最后用日志、波形和中间文件判断一次仿真是否真的完成。

### 概念地图

| 层级 | 对象 | 工程作用 | 常见错误 |
|---|---|---|---|
| 设计层 | DUT、testbench、filelist | 指定被测设计和激励环境 | 漏文件、top 错、testbench 未初始化 |
| 编译层 | `vcs` 命令、选项、log | 生成仿真可执行体 `simv` | 选项手打不一致，日志没保存 |
| 运行层 | `./simv`、dump、seed | 执行仿真并产生行为证据 | 只编译不运行，没生成波形 |
| 调试层 | DVE、waveform、time cursor | 定位信号变化与 X 来源 | 只看输出，不追输入和激励时间 |
| 工程层 | Makefile target | 固化 compile/run/wave/clean | recipe 前不用 Tab，target 命名混乱 |

### 最短学习路径

1. 看到 X 先查 testbench 初始化和 reset。
2. 能手动执行一次 VCS compile/run。
3. 把命令拆成 Makefile 变量和 target。
4. 每个 target 都要有清晰输入、输出和失败信号。
5. 用 `make clean && make run` 检查流程是否可重复。

## 1. 波形里的 X 是 debug 入口，不是工具异常

红色 X 表示 unknown。它常见于输入未初始化、寄存器未 reset、条件分支漏赋值、多驱动冲突、模块未连接等场景。课程开头先看 X，是因为数字前端验证首先要会从波形反推代码和 testbench。

视觉核对：01:50-02:20，画面展示 unknown/X 波形；重点看输入在赋值前为 X，输出受其影响也可能变成 X。

![unknown X 波形](<./screenshots/任务011_逻辑仿真工具VCS的使用-Makefile/unknown_x_waveform_110s.jpg>)

排查顺序：

1. 找 X 第一次出现的时间点。
2. 看 X 是输入、内部寄存器还是输出。
3. 回到 testbench 查该信号是否有初始赋值。
4. 查 reset 是否覆盖相关寄存器。
5. 查是否有多驱动、未连接、case/if 分支漏赋值。

关键判断：如果 DUT 输入本身是 X，DUT 输出变 X 不一定说明设计错；先修 testbench 激励和 reset，再判断 DUT 逻辑。

## 2. 波形工具要服务“定位”，不是服务“观看”

真实仿真波形很长，靠拖动时间轴找事件效率很低。波形工具必须会按上升沿、下降沿、跳变沿、指定值搜索，把时间点和代码激励关联起来。

视觉核对：05:00-05:30，画面展示 waveform edge search，重点看如何按边沿定位事件。

![波形边沿搜索](<./screenshots/任务011_逻辑仿真工具VCS的使用-Makefile/waveform_edge_search_300s.jpg>)

一次有效波形检查至少回答：

- reset 什么时候释放。
- clock 是否持续跳变。
- 输入激励在什么时候变化。
- 输出何时从 X 变成确定值。
- 输出变化是否与输入和时钟关系一致。
- 出错时间点能否回到 testbench 对应语句。

波形不是截图留档，而是 debug 索引。只说“我打开波形看了”没有意义，必须能指出时间点、信号、因果链和下一步检查位置。

## 3. VCS 流程分成编译和运行两段

VCS 是编译型仿真器。它先读取 RTL、testbench、库文件和选项，生成仿真可执行文件；再运行这个可执行文件，才会产生仿真输出、日志和波形。把 compile 与 run 混在一起，容易分不清错误发生在哪一段。

视觉核对：10:05-10:35，画面展示 VCS compile command；17:40-18:10，画面展示工作目录和生成文件。

![VCS 编译命令](<./screenshots/任务011_逻辑仿真工具VCS的使用-Makefile/vcs_compile_command_605s.jpg>)

![VCS 工作目录](<./screenshots/任务011_逻辑仿真工具VCS的使用-Makefile/vcs_directory_1060s.jpg>)

常见命令形态：

```bash
vcs -full64 -sverilog -debug_access+all -timescale=1ns/1ps \
  -f filelist.f \
  -l compile.log

./simv -l sim.log
```

编译阶段失败信号：

- 语法错误。
- 找不到文件。
- top module 未解析。
- timescale 或库选项缺失。
- 编译日志里有 fatal/error。

运行阶段失败信号：

- `simv` 不存在或不可执行。
- 仿真不结束，缺少 `$finish`。
- 日志出现 fatal、assertion failure 或自检 FAIL。
- 波形文件未生成。

## 4. Makefile 把仿真动作变成可重复目标

Makefile 的核心结构是 target、prerequisites 和 recipe。target 表示你要生成的文件或要执行的动作；prerequisites 是前置依赖；recipe 是真正执行的命令。GNU Make 要求 recipe 行通常以 Tab 开头，这个细节错了会直接报错。

视觉核对：06:54-07:25，画面引入 Makefile；20:58-21:25，画面展示 Makefile 生成/组织动作。

![Makefile 入口](<./screenshots/任务011_逻辑仿真工具VCS的使用-Makefile/makefile_intro_414s.jpg>)

![Makefile 生成结果](<./screenshots/任务011_逻辑仿真工具VCS的使用-Makefile/makefile_generation_1258s.jpg>)

最小结构：

```makefile
VCS = vcs
VCS_OPTS = -full64 -sverilog -debug_access+all -timescale=1ns/1ps
FILELIST = filelist.f

.PHONY: compile run dve clean

compile:
	$(VCS) $(VCS_OPTS) -f $(FILELIST) -l compile.log

run: compile
	./simv -l sim.log

dve: run
	dve -vpd vcdplus.vpd &

clean:
	rm -rf simv csrc *.log *.vpd DVEfiles
```

这段 Makefile 的工程含义：

- `compile` 固定编译选项和文件列表。
- `run` 依赖 `compile`，避免没编译就运行。
- `dve` 依赖 `run`，确保有波形再打开。
- `clean` 清掉中间文件，方便从干净状态复测。

## 5. target 设计要反映真实流程边界

好的 Makefile target 不是随便起几个名字，而是把流程切在稳定边界上。编译、运行、打开波形、清理文件，分别是不同边界；每个边界都有自己的输入、输出和失败信号。

视觉核对：27:44-28:10，画面展示 Makefile result；47:00-47:30，画面编辑 Makefile。

![Makefile 执行结果](<./screenshots/任务011_逻辑仿真工具VCS的使用-Makefile/makefile_result_1664s.jpg>)

![编辑 Makefile](<./screenshots/任务011_逻辑仿真工具VCS的使用-Makefile/makefile_edit_2820s.jpg>)

推荐 target：

| target | 输入 | 输出/动作 | 失败信号 |
|---|---|---|---|
| `compile` | RTL、TB、filelist、VCS options | `simv`、`compile.log` | 语法错误、文件缺失、top 未解析 |
| `run` | `simv`、运行参数 | `sim.log`、波形文件 | 仿真卡住、FAIL、无 dump |
| `dve` | 波形数据库 | 打开图形波形 | 找不到波形或 DVE 启动失败 |
| `clean` | 中间文件列表 | 干净工作区 | 误删源码或清理不彻底 |
| `all` | 默认目标 | 一键完成主要流程 | 默认目标没有覆盖关键动作 |

不要把 `clean` 写得过于激进，尤其不要用宽泛路径误删 RTL、testbench、约束或源数据。仿真清理只应该删工具生成物。

## 6. 中间文件是判断流程阶段的证据

VCS 编译和运行会生成一批中间目录、可执行文件、日志和波形数据库。初学者容易觉得这些文件很乱，但它们恰好可以帮助判断流程走到哪一步。

视觉核对：36:43-37:15，画面展示 VCS intermediate files；55:05-55:35，画面展示 VCS command options。

![VCS 中间文件](<./screenshots/任务011_逻辑仿真工具VCS的使用-Makefile/vcs_intermediate_files_2203s.jpg>)

![VCS 命令选项](<./screenshots/任务011_逻辑仿真工具VCS的使用-Makefile/vcs_command_options_3305s.jpg>)

常见文件/目录：

| 文件/目录 | 含义 |
|---|---|
| `simv` | VCS 编译生成的仿真可执行文件 |
| `csrc/` | C 编译中间目录 |
| `compile.log` | 编译日志 |
| `sim.log` | 运行日志 |
| `vcdplus.vpd` / `*.vcd` / `*.fsdb` | 波形数据库，取决于 dump 设置和工具 |
| `DVEfiles/` | DVE 会话相关文件 |

判断口径：

- 没有 `simv`：编译没有成功。
- 有 `simv` 但没有 `sim.log`：可能没运行。
- 有 `sim.log` 但没有波形：dump 语句或运行选项可能缺失。
- 日志里有 PASS/FAIL：优先相信自检结果，再看波形解释细节。

## 7. Makefile 调试的常见坑

Makefile 的错误往往不是数字逻辑错误，而是工程脚本错误。最常见的是 Tab、变量展开、路径、目标依赖和清理范围。

关键排查：

- recipe 命令行必须以 Tab 开头，不是普通空格。
- 变量名大小写要一致。
- `run` 依赖 `compile`，否则干净目录下会找不到 `simv`。
- `dve` 依赖波形文件或 `run`，否则打开的是空会话。
- `clean` 不要删除源文件。
- 文件路径含空格时要谨慎处理，课程目录最好避免空格和特殊字符。

如果 `make run` 没有执行预期命令，先用：

```bash
make -n run
```

让 make 只打印将要执行的命令，不真正执行。这样可以检查变量展开和依赖关系。

## 8. 最小可复现 VCS + Makefile 闭环

目录建议：

```text
vcslab/
  rtl/
    full_adder.v
  tb/
    full_adder_tb.v
  filelist.f
  Makefile
```

`filelist.f`：

```text
./rtl/full_adder.v
./tb/full_adder_tb.v
```

Makefile：

```makefile
VCS = vcs
VCS_OPTS = -full64 -sverilog -debug_access+all -timescale=1ns/1ps
FILELIST = filelist.f

.PHONY: all compile run dve clean

all: run

compile:
	$(VCS) $(VCS_OPTS) -f $(FILELIST) -l compile.log

run: compile
	./simv -l sim.log

dve: run
	dve -vpd vcdplus.vpd &

clean:
	rm -rf simv simv.daidir csrc DVEfiles *.log *.vpd *.vcd
```

验收动作：

```bash
make clean
make compile
make run
make dve
```

通过标准：

- `make compile` 生成 `simv`，`compile.log` 无 fatal/error。
- `make run` 生成 `sim.log`，仿真正常结束。
- 波形文件存在，DVE 能打开。
- `make clean` 后工具生成物被清理，源码和 Makefile 保留。

## 9. 深层理解：Makefile 是仿真流水线的“站台调度表”

只会手敲 VCS 命令，像每次出门都临时问路；写好 Makefile，则像把路线、车次、换乘口和终点都写进站台调度表。调度表本身不替你走路，但它保证每次都从同一个入口出发、经过同样的检查点、把结果放到同样的位置。仿真工程最怕的不是某一次跑不起来，而是今天能跑、明天忘了怎么跑，或者自己能跑、同学拉下来跑不起来。

把本章的图连起来看，会得到一条很清楚的证据链：

| 配图 | 不要只看什么 | 真正要读出的工程信息 |
|---|---|---|
| unknown X 波形 | 波形里有很多红色未知态 | X 首次出现的时间点、源头信号、是否跨过 reset 后仍存在 |
| 波形边沿搜索 | DVE 可以拖动波形 | debug 应按“时间点 -> 信号源头 -> 代码分支”回溯 |
| VCS 编译命令 | 命令很长 | 命令由源文件、宏、库、debug 选项、日志和波形选项组成 |
| VCS 工作目录 | 目录里文件很多 | 哪些是源码，哪些是工具生成物，哪些可以 clean |
| Makefile 入口 | 有 `compile/run/dve/clean` | target 把一次手工动作变成可复现入口 |
| Makefile 生成结果 | 生成了 `simv` 和日志 | 编译阶段已经完成，下一步才是运行行为检查 |
| Makefile 执行结果 | 终端输出没有报错 | 仍要看日志、波形和自检结果，不能只看命令返回 |
| 编辑 Makefile | 改几行文本 | 改的是工程流程，不是 RTL 功能；误删 clean 边界会很危险 |
| VCS 中间文件 | `csrc/simv.daidir` 等目录 | 这些是工具工作痕迹，可用于定位阶段，也应被 clean 管控 |
| VCS 命令选项 | 选项很多 | 每个选项都应能回答“影响编译、运行、波形还是 debug” |

Makefile 的关键不是“少打字”，而是“少产生不可解释的差异”。一个好的仿真入口应该像实验室标准操作规程：谁来跑、在哪台机器跑、跑第几次，都能说清输入、动作、输出和失败信号。

## 10. 操作闭环：从失败现象反推责任层

遇到问题时不要先改 RTL。先判断失败卡在哪一层：

| 失败现象 | 第一责任层 | 先查什么 | 不要急着做什么 |
|---|---|---|---|
| `make: *** No rule to make target` | Makefile 目标层 | target 名称、依赖文件、当前目录 | 不要改 Verilog |
| `missing separator` | Makefile 语法层 | recipe 前是否是 Tab | 不要重装 VCS |
| `Error-[SE] Syntax error` | RTL/TB 编译层 | 报错文件、行号、宏展开、filelist | 不要看波形 |
| 没有 `simv` | 编译产物层 | `compile.log`、VCS 选项、源文件路径 | 不要运行 `./simv` |
| `./simv` 跑不完 | 仿真控制层 | `$finish`、timeout、死循环、等待条件 | 不要只关终端 |
| 没有波形 | dump 配置层 | dump 语句、波形文件名、Makefile `dve` 目标 | 不要怀疑 DUT 功能 |
| 波形有 X | 设计/激励层 | reset、初始化、未连接、多驱动、未覆盖分支 | 不要把 X 当显示问题 |

这个表的价值在于把“仿真失败”拆成可处理的小故障。工程调试像查水管漏水：先判断漏在水源、阀门、管道还是出水口，再动手；不能一看到地上有水就把整栋楼拆掉。

## 本章速记

- X 是 debug 线索，先查初始化、reset、未赋值、多驱动和未连接。
- VCS 分 compile 和 run；compile 生成 `simv`，run 执行 `simv`。
- Makefile 的 recipe 行要用 Tab。
- target 要按真实流程边界设计：compile、run、dve、clean。
- 日志和中间文件是判断流程阶段的证据。
- 可重复仿真比手敲一次成功更重要。

## 自测题与答案

1. **波形中出现 X，最先查什么？**  
   答：先查 X 出现的时间点和源头信号，再查 testbench 初始化、reset 覆盖、未赋值分支、多驱动和未连接。

2. **VCS 的 compile 和 run 分别做什么？**  
   答：compile 读取 RTL/testbench/选项并生成 `simv`；run 执行 `simv`，产生日志、输出和波形。

3. **Makefile 中 recipe 行为什么必须注意 Tab？**  
   答：GNU Make 用 Tab 识别 recipe 命令行，普通空格可能导致 `missing separator` 等错误。

4. **`run: compile` 的含义是什么？**  
   答：执行 `run` 前先保证 `compile` 完成，避免在没有 `simv` 的情况下运行仿真。

5. **没有生成波形文件时应该查哪些地方？**  
   答：查 testbench 是否有 dump 语句，运行选项是否打开波形，`sim.log` 是否正常结束，波形文件名和 DVE 打开参数是否一致。

6. **为什么不建议每次手敲 VCS 长命令？**  
   答：手敲容易漏选项、路径不一致、日志不可追踪；Makefile 能固定流程，保证自己和团队重复运行得到同样入口和证据。

## 工程核对口径

完成本章后，用这 4 个问题检查自己是否真正会用，而不是只看懂了截图：

1. 给你一个新目录，你能否在 3 分钟内判断 RTL、testbench、Makefile、日志、波形和 VCS 中间目录分别在哪里？
2. 给你一条 VCS 长命令，你能否拆出“源文件、选项、日志、波形、debug 能力”五类信息？
3. 给你一个 `make run` 失败日志，你能否先判断是 Makefile 层、编译层、运行层还是波形层？
4. 给你一段新 RTL，你能否写出最小 `compile/run/dve/clean` 四目标 Makefile，并保证 `clean` 不删除源码？


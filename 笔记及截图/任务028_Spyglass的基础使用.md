# 任务28：SpyGlass 的基础使用

## 本章知识全景图

SpyGlass 是静态 RTL signoff 工具，不靠 testbench 跑出某次波形，而是根据 RTL 结构、clock/reset/domain 约束和 goal 规则集提前发现 lint、CDC、RDC 等风险。本章的主线不是“打开 GUI 点一遍”，而是建立 `RTL/filelist -> project -> SGDC/SDC -> goal -> report -> fix/waiver` 的可复现检查闭环。

可以把 SpyGlass 理解成 RTL 结构安检机：`filelist/top` 是行李清单，SGDC/SDC 是申报单，goal 是扫描模式，report 是可疑项清单。清单漏了东西时“没有报警”不代表安全，申报错了时“满屏报警”也不代表 RTL 全错；先让工具知道真实设计，再讨论每条风险。

| 层级 | 核心对象 | 本章要掌握的判断 |
|---|---|---|
| 工程入口 | 目录、project、top、filelist | 工具必须先完整读入设计 |
| 设计意图 | clock、reset、SGDC、SDC | 静态检查依赖约束表达真实工作模式 |
| 检查目标 | goal、rule、severity | 不同阶段跑不同规则集，不能只数 violation |
| 报告处理 | setup、path、rule、waiver | 先分诊根因，再决定改 RTL、补约束或 waiver |
| 交付证据 | `.prj`、约束、report、waiver、run log | 报告要能重跑，waiver 要有边界 |

最短学习路径：

```text
SpyGlass 为什么不需要 TB
  -> project file 如何记录工程输入
  -> SGDC / SDC / waiver / report 各解决什么
  -> goal 如何决定检查规则
  -> report 如何按 setup / RTL / constraint / waiver 分诊
```

## 全视频地图

| 时间段 | 教学块 | 必须保留的知识动作 |
|---|---|---|
| 00:00-12:00 | CDC 回顾与静态检查定位 | 明确 SpyGlass 查的是设计结构和意图，不是仿真激励覆盖 |
| 12:00-25:00 | 打开工程、读设计、GUI 与 shell | 进入正确目录，确认 RTL/top/filelist 能被读入 |
| 25:00-38:00 | project file、SGDC、report、waiver | 把 GUI 操作还原成可复现 project Tcl |
| 38:00-50:00 | goal、set_option、help/man | 用文档理解 option 和 rule，不靠猜菜单 |
| 50:00-61:00 | SDC 到 SGDC、约束分类 | 知道约束不是压红字，而是告诉工具设计事实 |
| 61:00-66:17 | CDC guideline 与工程收束 | 把 report message 对回结构规则和处理证据 |

## 1. SpyGlass 查结构风险，不是替代仿真

仿真回答“这组激励下行为是否正确”，SpyGlass 回答“这个 RTL 结构在给定约束下是否存在系统性风险”。CDC、RDC、lint、setup 问题都可能在普通仿真里没暴露，但静态结构已经不安全。

![CDC reconvergence 回顾](<./screenshots/任务028_Spyglass的基础使用/cdc_reconvergence_recap_270s.jpg>)

截图核对：视频 04:00-05:00，画面应展示 reconvergence 回顾；重点是两个同步后的控制重新汇合时，仿真不一定覆盖错位周期。

因此跑 SpyGlass 时通常读设计 RTL，不读 testbench。TB 只说明某些输入序列下的行为，静态检查要看的是设计本身：

- 是否存在未同步 CDC。
- reset 是否异步释放到多个域。
- 位宽、未驱动、多驱动、latch、组合环是否危险。
- generated clock、clock gating、domain 是否表达清楚。
- waiver 是否有边界。

## 2. 先让工具完整读入设计，再谈 violation

SpyGlass 的第一关不是清 warning，而是 setup 干净：文件路径、语言模式、top、include、macro、clock/reset 约束都要让工具理解。setup 没过，后面的 violation 可信度很低。

![SpyGlass 读入设计](<./screenshots/任务028_Spyglass的基础使用/spyglass_read_design_800s.jpg>)

截图核对：视频 13:00-14:00，画面应显示读入设计或工程入口；检查点是 top 和 RTL 层次是否正确。

这一组界面图要按流程读，不按菜单记：读入设计图证明工具已经看见 RTL 层次；工程/shell 图证明 GUI 和命令入口能指向同一个 project；project file 图证明这些动作能固化；约束/report 图证明设计意图和检查结果有文件落点；goal 图证明当前跑的是哪一类规则。

常见入口：

```bash
spyglass &
spyglass -project CDC.prj
```

GUI 里点出来的动作最终也应能落回 project file 或命令行。不能复现的 GUI 操作，不适合作为交付流程。

![打开已有工程和 shell](<./screenshots/任务028_Spyglass的基础使用/open_existing_project_shell_1300s.jpg>)

截图核对：视频 21:00-22:00，画面应显示已有工程和内置 shell；重点是 GUI 与命令入口不是两套孤立流程。

## 3. Project file 本质上是 Tcl 脚本

`.prj` 不是神秘工程文件，它记录的是读文件、设 top、设 option、加载约束、选择 goal 等命令。理解 project file，才能把一次 GUI 实操变成可复现工程。

![project file options](<./screenshots/任务028_Spyglass的基础使用/project_file_options_1660s.jpg>)

截图核对：视频 27:00-29:00，画面应显示 project 文件或 option；读者要能把一行 option 翻译成工具输入事实。

project 里常见对象：

| 对象 | 作用 | 错了会怎样 |
|---|---|---|
| `read_file` / filelist | 告诉工具 RTL 文件 | parse/elaboration 不完整 |
| top | 指定分析顶层 | 层次错、报告路径不可信 |
| language / include / macro | 解释源码语法和条件编译 | 大量假错误或漏分析 |
| SGDC / SDC | 表达 clock/reset/domain/intent | CDC/RDC 误报或漏报 |
| goal | 选择检查规则集 | 跑错检查，报告不可用 |
| waiver | 记录已接受风险 | 无边界 waiver 会掩盖真问题 |

最小 project / Tcl 口径可以这样写，具体命令名随工具版本调整，但信息不能缺：

```tcl
read_file -type sourcelist ./filelist.f
set_option top my_top
read_sdc ./constraints/top.sdc
read_sgdc ./constraints/top.sgdc
current_goal lint/lint_rtl
run_goal
write_report ./reports/lint_rtl.rpt
```

这段脚本的学习价值不是背命令，而是记住五个输入事实：读哪些 RTL，顶层是谁，约束在哪里，跑哪个 goal，报告落到哪里。GUI 操作如果不能还原出这五项，就不适合作为工程交付。

## 4. SGDC、SDC、waiver、report 各管一类证据

SpyGlass 静态检查强依赖约束。SDC 更偏综合/STA 时序约束，SGDC 更偏 SpyGlass 对 clock/reset/CDC design intent 的理解。两者都不是为了“让红字变少”，而是为了让工具更接近真实芯片工作模式。

![SGDC、waiver、report 文件](<./screenshots/任务028_Spyglass的基础使用/sgdc_waiver_report_files_1970s.jpg>)

截图核对：视频 32:00-34:00，画面应出现 SGDC、waiver、report 类文件；重点看它们各自进入报告闭环的位置。

| 文件 | 主要内容 | 交付要求 |
|---|---|---|
| `.prj` | 工程输入和运行配置 | 可在同目录重新打开/运行 |
| `.sgdc` | SpyGlass design constraint | clock/reset/domain/CDC 意图清晰 |
| `.sdc` | 时钟、IO、时序例外等 | 转换到 SGDC 后必须复核 |
| waiver | 已知问题的豁免说明 | 每条有 rule、path、原因、保护条件 |
| report | 检查结果 | 能追到源码路径和规则说明 |

## 5. Goal 决定检查规则集，不是所有红字一起清

SpyGlass 的 goal 是检查目标。Lint、CDC、RDC、constraint setup 属于不同风险域，不能混在一起按 violation 数量“清零”。

![goal selection](<./screenshots/任务028_Spyglass的基础使用/goal_selection_2200s.jpg>)

截图核对：视频 36:00-38:00，画面应展示 goal 选择；重点看当前阶段到底跑 lint、CDC 还是其他规则集。

正确流程：

```text
确认 setup 干净
  -> 选择当前阶段 goal
  -> run
  -> 读 report
  -> 按 rule / severity / path 分类
  -> 改 RTL、补约束或写有边界 waiver
```

不要第一步就 waiver，也不要只看 violation 数是否下降。

## 6. Help / man 是工程工具的一部分

EDA 工具选项很多，靠猜菜单会把错误配置带进工程。遇到 `set_option`、`current_goal`、`set_goal_option` 等命令时，应该查 Help/User Guide 或 `man`，确认默认值、作用范围和影响。

![SpyGlass Help/User Guide](<./screenshots/任务028_Spyglass的基础使用/spyglass_help_tutorial_1100s.jpg>)

截图核对：视频 18:00-19:00，画面应显示 Help/User Guide；重点是把文档当成实操的一部分。

![man set_option](<./screenshots/任务028_Spyglass的基础使用/man_set_option_help_2610s.jpg>)

截图核对：视频 43:00-44:00，画面应显示命令帮助；读者要确认 option 的作用域，而不是凭名字猜含义。

学习工具的可靠方法：

1. 跑通最小工程。
2. 遇到陌生 option 查文档。
3. 修改一个 option。
4. 观察 project file 和 report 变化。
5. 固化成脚本或 project 配置。

## 7. SDC 到 SGDC：能转换，但必须复核

SpyGlass 可以参考或转换 SDC，但转换结果不能直接当成正确 design intent。综合/STA 关心时序路径，CDC/RDC 静态检查更关心 clock domain、reset domain、generated clock、case mode 和协议意图。

![SDC 到 SGDC](<./screenshots/任务028_Spyglass的基础使用/sdc_to_sgdc_option_2380s.jpg>)

截图核对：视频 39:00-41:00，画面应显示 SDC/SGDC 相关选项；重点是转换后仍要人工复核 domain 语义。

复核表：

| 约束对象 | 复核问题 |
|---|---|
| primary clock | 是否定义完整，频率和名字是否匹配 RTL |
| generated clock | 分频/门控时钟是否归到正确 domain |
| reset | assert/deassert 关系是否表达清楚 |
| mode / case analysis | 当前检查模式是否符合真实工作场景 |
| false path / exception | 是否掩盖了真实 CDC/RDC 风险 |

## 8. 报告读法：先分诊，再处理

SpyGlass report 的固定读法是：

```text
setup / elaboration
  -> clock / reset / domain
  -> severity / rule / path
  -> source / constraint 根因
  -> fix / waiver 决策
```

![constraint classes](<./screenshots/任务028_Spyglass的基础使用/constraint_classes_3040s.jpg>)

截图核对：视频 50:00-52:00，画面应展示约束或 report 分类；重点看报告是否先被分成 setup、约束、RTL 真问题。

风险分类：

| 类别 | 典型问题 | 处理原则 |
|---|---|---|
| setup/elaboration | filelist 缺失、top 错、语言模式错 | 先修 setup，否则 report 不可信 |
| lint/RTL | latch、位宽截断、未驱动、多驱动、组合环 | 能改 RTL 优先改 RTL |
| CDC | 未同步、reconvergence、fast-to-slow、多 bit CDC | 补同步结构、协议或有证据 waiver |
| RDC | reset release、reset domain crossing | 每域同步释放，说明模式条件 |
| constraint | clock/reset/domain 不完整 | 补 SGDC/SDC，不用 waiver 掩盖 |
| waiver | 已确认但不修改 | 有 rule、path、原因、保护条件和失效边界 |

## 9. CDC guideline：从 message 追到结构规则

CDC guideline 的价值是把 report message 对回结构规则。看到 violation，不要只复制错误信息，要追：

```text
message
  -> rule
  -> 结构模式
  -> 源码路径
  -> 约束条件
  -> 处理动作
```

![CDC guideline 文档](<./screenshots/任务028_Spyglass的基础使用/cdc_guideline_document_3860s.jpg>)

截图核对：视频 64:00-66:00，画面应出现 CDC guideline 或相关文档；重点是用规则解释报告，而不是把红字当成孤立文本。

如果 report 说 reconvergence，要回到 CDC 结构：多路同步后的相关控制是否重新组合；如果 report 说 generated clock，要回到 clock definition；如果 report 说 reset release，要回到 reset synchronizer。

## 最小交付闭环：从 project 到 report 分诊

SpyGlass 的最小闭环不是“跑出一个 report”，而是能证明 report 的输入可信、规则明确、每条高风险问题都有处理动作。setup 不干净时，后面的 violation 不能直接当 signoff 结论。

| 环节 | 要交付的证据 | 不通过信号 |
|---|---|---|
| 输入 | RTL/filelist、top、语言模式、include/macro、工具版本 | parse/elaboration 还没干净 |
| 约束 | clock、reset、generated clock、mode、SGDC/SDC | clock/reset/domain 未识别 |
| goal | 当前阶段使用的 lint/CDC/RDC/setup goal | 不知道跑的是哪套规则 |
| report | rule、severity、path、message、source/constraint 根因 | 只统计 violation 数 |
| 分诊 | RTL 修复、补约束、补同步结构、waiver 分类 | setup、constraint、RTL 真问题混在一起 |
| 交付 | `.prj`、约束、run log、report、waiver 边界 | waiver 没有 rule/path/原因/失效条件 |

最小实操任务：任选一条 SpyGlass message，写成下面六列。

```text
rule -> path -> risk class -> root cause -> action -> evidence
```

如果 `risk class` 写不出来，就不要急着修 RTL 或写 waiver；先回到 setup、clock/reset/domain 和 goal 选择。

示例：

| 字段 | 示例写法 |
|---|---|
| rule | `CDC_RECONV` |
| path | `u_ctrl/a_sync2`、`u_ctrl/b_sync2` 汇合到 `u_ctrl/enable` |
| risk class | true CDC risk 或缺协议证明 |
| root cause | 两个相关控制分别同步后重新组合，目的域可能看到源域不存在的组合 |
| action | 合并编码跨域、改成握手，或补充协议证明后 waiver |
| evidence | 修改 diff、重跑 report、波形/协议说明、waiver 失效条件 |

这样的记录能把 report 从“红字列表”变成工程决策表。

## 复习与自测

1. 为什么 SpyGlass 做 CDC 检查时通常不需要 testbench？
2. `.prj`、`.sgdc`、`.sdc`、waiver、report 分别解决什么问题？
3. 为什么 violation 很多时不能第一步批量 waiver？
4. SDC 能转换或参考，为什么还要复核 SGDC？
5. 怎样判断一个问题是 RTL 真问题、约束缺失还是 setup 问题？
6. 一条合格 waiver 至少要写哪些字段？

参考答案：

1. SpyGlass 做的是静态结构分析，重点是 RTL、clock/reset/domain 和设计意图；testbench 只能证明某些激励下的行为。
2. `.prj` 记录工程输入和运行配置；`.sgdc` 表达 SpyGlass 需要的设计意图；`.sdc` 表达时序约束；waiver 记录已接受风险；report 给出规则、路径和结果。
3. 批量 waiver 可能掩盖真问题。应先按 setup、constraint、RTL、CDC/RDC 分类，再决定修复或有边界 waiver。
4. SDC 偏时序，SGDC 偏静态检查意图；转换可能漏掉 CDC/RDC 需要的 domain、mode 和协议语义。
5. setup 问题通常源于读入不完整或约束缺失；RTL 真问题能追到源码结构；约束缺失表现为工具不了解 clock/reset/domain。
6. rule、path、severity、原因、保护条件、失效条件、责任人或审查依据。




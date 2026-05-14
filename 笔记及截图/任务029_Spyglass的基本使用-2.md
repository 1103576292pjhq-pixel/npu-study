# 任务29：SpyGlass 的基本使用 2

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：用 SpyGlass 做 CDC 检查时，先把设计、时钟、复位、generated clock 和约束建模正确，再谈 violation 修复。
- 核心概念：CDC setup、top、RTL filelist、clock/reset、generated clock、SGDC、CDC goal、setup verification、violation 分类、waiver、工具环境错误。
- 逻辑主线：CDC 工具不是“点 Run 后看红字”的工具；它先依赖一份可信的设计事实模型。setup 错了，violation 数量没有意义；setup 对了，report 才能分成真 CDC bug、约束缺失和可证明安全结构。
- 最短学习路径：官方文档建立风险类型 -> 创建工程和工作目录 -> 加 RTL/top/filelist -> 建 clock/reset/generated clock -> 验证 setup -> 跑 CDC goal -> 分类处理 report -> 修 RTL、补约束或写有证据的 waiver。

### 2. 概念地图

| 概念层级 | 核心概念 | 前置知识 | 延伸应用 |
|---|---|---|---|
| CDC 风险 | metastability、multi-bit crossing、reconvergence、reset crossing | 时钟域、同步器、FIFO | RTL CDC 修复、RDC 检查 |
| 工程输入 | top、RTL filelist、language、macro/include | Verilog/SystemVerilog 工程结构 | SpyGlass/VCS/DC 共用 filelist |
| 约束建模 | clock、reset、generated clock、gated clock、SGDC | SDC/时钟树基本概念 | CDC setup、约束审查 |
| 报告判断 | setup report、CDC violation、rule/path/clock domain | report 阅读、路径定位 | violation 分诊、回归闭环 |
| 工程处置 | RTL fix、constraint fix、waiver、rerun | 同步器、握手、异步 FIFO | signoff 证据、review 清单 |
| 环境排错 | GUI/Qt/library/license | Linux 工具环境 | 区分工具失败和设计失败 |

### 3. 阅读顺序

1. 先把 CDC report 当成“时钟域模型 + RTL 结构 + 约束”的结果，不把红字当最终结论。
2. 再按工作目录、project、filelist、top、clock/reset、generated clock 的顺序搭 setup。
3. 然后先验证 setup，再处理 violation。
4. 最后每条 violation 都必须落到三类动作之一：改 RTL、补约束、带证据 waiver。

## 全视频地图

| 时间段 | 教学块 | 必须保留的知识动作 |
|---|---|---|
| 00:00-05:00 | 打开官方 CDC 文档 | 从文档里的 CDC 结构认识工具规则不是菜单，而是硬件风险模型 |
| 05:00-15:00 | CDC setup 和 generated clock 文档 | 理解 top、clock、reset、generated clock 是 CDC 分析的输入事实 |
| 15:00-25:00 | 创建工作目录和 SpyGlass project | 固化工作目录，建立工程，避免路径和输出混乱 |
| 25:00-35:00 | 拷贝 CDC 文件、查看 RTL/filelist | 确认工具能读懂设计，filelist/top 是 CDC 分析入口 |
| 35:00-45:00 | 运行 CDC goal、阅读 setup/report | 先查 setup 是否完整，再看 violation 类型和路径 |
| 45:00-54:48 | 环境报错和收尾 | 区分 `libQtCore` 这类工具依赖问题与 RTL/CDC 设计问题 |

## 1. CDC 检查先从风险模型开始，不从按钮开始

SpyGlass CDC 的核心任务是发现跨时钟域结构风险。按钮只是入口，真正的判断依据是时钟域、同步结构、复位释放和多 bit 数据一致性。

![官方 CDC 文档中的 MUX/CDC 例子](<./screenshots/任务029_Spyglass的基本使用-2/official_cdc_doc_75s.jpg>)

视觉核验：视频 01:00-03:30，画面打开官方 CDC 文档并展示 CDC 示例；读者应把图里的 mux、同步器、generated clock、reset 结构对应到 report rule，而不是只记文档页标题。

CDC 常见风险：

| 风险 | 含义 | 正确处理方向 |
|---|---|---|
| metastability | 异步采样导致触发器进入亚稳态 | 单 bit 控制信号用同步器 |
| multi-bit CDC | 多 bit 数据逐位跨域可能不一致 | 异步 FIFO、握手保持、Gray code |
| reconvergence | 多条同步路径重新汇合导致组合不一致 | 合并控制、协议约束、结构重写 |
| reset crossing | 复位释放跨域或 reset domain 不一致 | 异步 assert、同步 deassert、RDC 检查 |
| generated/gated clock | 工具不知道时钟来源或关系 | 建 generated clock / gated clock 约束 |

CDC 检查不能替你证明设计意图。它只能基于 RTL 和约束推断结构风险，所以约束质量直接决定报告质量。

## 2. CDC setup 是把设计事实喂给工具

CDC setup 的作用是告诉工具：这个设计的入口是谁、有哪些源文件、哪些信号是时钟、哪些信号是复位、哪些时钟来自生成逻辑、哪些跨域结构有特殊协议。

![创建 SpyGlass CDC setup](<./screenshots/任务029_Spyglass的基本使用-2/cdc_setup_doc_220s.jpg>)

视觉核验：视频 03:30-07:00，画面讲 `Creating SpyGlass CDC Setup`；读者应确认 setup 不是附加步骤，而是 CDC 分析的前提。

最低 setup 清单：

| 输入 | 为什么必须有 |
|---|---|
| top module | 没有入口，工具不知道从哪里建立层次 |
| RTL/filelist | 源文件不完整会造成黑盒、漏路径或误报 |
| language/macro/include | 编译条件不同会改变实际 RTL 结构 |
| clock/reset | CDC/RDC 依赖时钟域和复位域定义 |
| generated/gated clock | 时钟关系不建模会误判 domain |
| CDC constraints/SGDC | 表达安全结构、false path、特殊同步协议 |

setup 不完整会产生两类错误：真问题漏报，合法结构误报。真正的工程流程是先让 setup 可信，再看 violation。

## 3. 工作目录和 project 是复现边界

CDC 检查要在独立工作目录中跑，让 project 文件、中间数据库、report 和 log 都能追溯。

![创建 CDC check 工作目录](<./screenshots/任务029_Spyglass的基本使用-2/create_work_dir_410s.jpg>)

视觉核验：视频 06:30-09:00，画面创建 CDC 工作目录；读者应确认当前路径，因为相对路径、report 输出和工程数据库都依赖它。

典型动作：

```bash
mkdir cdc_chk_myown
cd cdc_chk_myown
spyglass &
```

打开 GUI 后创建 project：

![SpyGlass 工程界面](<./screenshots/任务029_Spyglass的基本使用-2/spyglass_project_745s.jpg>)

视觉核验：视频 11:30-14:00，画面进入 SpyGlass project 界面；读者应检查工程是否绑定正确 top、goal、约束和输出目录。

project 不是“界面里的一个名字”，它要固化五件事：

1. 输入文件集合。
2. top module。
3. 检查 goal，例如 CDC。
4. 约束文件。
5. 报告输出位置。

正式项目中更推荐脚本或配置文件驱动 SpyGlass，而不是完全靠 GUI 手点；GUI 可以帮助学习流程，交付必须可重跑。

## 4. RTL/filelist 是 CDC 分析的地基

CDC 工具首先要能读懂设计。源文件不完整、include 漏掉、宏定义不一致，都会让后续 CDC report 偏离真实设计。

![拷贝 CDC 实验文件](<./screenshots/任务029_Spyglass的基本使用-2/copy_cdc_files_2525s.jpg>)

视觉核验：视频 41:30-43:30，画面拷贝 CDC 实验文件；读者应确认 RTL、约束、filelist 位于可复现实验目录中。

![RTL 文件列表](<./screenshots/任务029_Spyglass的基本使用-2/rtl_file_list_2705s.jpg>)

视觉核验：视频 44:00-46:00，画面查看 RTL 文件列表；读者应确认正式项目要把这些文件固化到 filelist，而不是依赖临时 GUI 点击。

filelist 检查项：

| 检查项 | 失败后果 |
|---|---|
| 文件路径 | design unit 找不到，层次不完整 |
| package/include | 类型、参数、宏缺失 |
| 顶层模块名 | 工具从错误层次分析 |
| 语言模式 | SV 语法或接口解析失败 |
| 宏定义 | 仿真、综合、SpyGlass 看到不同 RTL |

一份可靠 filelist 可以被 SpyGlass、VCS、DC 复用。文件清单统一，是减少工具间差异的第一步。

## 5. clock/reset/generated clock 是最低限度约束

CDC 分析的本质是判断 source flop 和 destination flop 属于什么 clock/reset domain。clock/reset 没建好，violation 分类就会整体偏掉。

![CDC 约束文档](<./screenshots/任务029_Spyglass的基本使用-2/cdc_constraints_doc_875s.jpg>)

视觉核验：视频 14:30-17:00，画面展示 CDC constraint 文档；读者应把它读成 clock/reset/generated clock 的建模入口。

约束至少要表达：

```text
哪些信号是 primary clock
哪些信号是 reset
哪些 clock 是 generated clock
哪些 clock 是 gated clock
哪些 crossing 是已知安全结构
哪些路径需要特殊建模或豁免
```

没有 clock，工具无法判断跨域；没有 reset，复位释放风险无法归类；没有 generated clock，相关时钟可能被误判为异步，或异步时钟被误判为相关。

## 6. generated clock 改变 CDC 判断边界

generated clock 不是普通信号注释，它直接决定两个寄存器是否被认为属于相关时钟域。

![generated clock 与 CDC 检查](<./screenshots/任务029_Spyglass的基本使用-2/generated_clock_970s.jpg>)

视觉核验：视频 15:30-18:00，画面讲 generated clock；读者应确认它会影响 domain 关系，而不是只影响报告显示名。

一个好用的比喻是时钟族谱：primary clock 是祖先，generated clock 是子 clock，约束要说明它从谁来、经过分频、门控还是 mux、相位和频率关系是什么。族谱缺了，工具可能把亲属当陌生人，报出一堆假异步；也可能把陌生人当亲属，漏掉真正 CDC。

典型来源：

- 分频器产生的 clock。
- PLL 输出 clock。
- clock gate 后的 clock。
- 由时钟选择器或 mux 产生的派生时钟。

CDC 分析顺序可以压缩为：

```text
识别 clock/reset
  -> 建 source/destination domain
  -> 判断 domain 关系
  -> 寻找 crossing path
  -> 判断同步结构是否安全
```

第一步错，后面每一步都会错。generated clock 漏建时，报告里可能出现大量假 violation，也可能把真正风险隐藏掉。

## 7. 先验证 setup，再处理 violation

运行 CDC goal 后，第一件事不是看红字数量，而是验证 setup 是否完整。

![验证 CDC setup](<./screenshots/任务029_Spyglass的基本使用-2/cdc_check_report_doc_1075s.jpg>)

视觉核验：视频 17:30-23:00，画面讲 `Verifying SpyGlass CDC Setup` 和 report；读者应先找 top、clock/reset、generated clock 是否被识别，再看 violation。

读这张 report 图时先不要急着看 violation 数字。第一层先确认 top 对不对，第二层确认 clock/reset/generated clock 是否被识别，第三层确认 black box 和 unresolved reference 是否可接受，最后才看 CDC path。setup 层没过，后面的红字只是噪声的形状。

正确顺序：

1. 设计是否成功读入。
2. top 是否正确。
3. clock 是否全部识别。
4. reset 是否全部识别。
5. generated/gated clock 是否建模。
6. black box 和 unresolved reference 是否可接受。
7. CDC violation 是否按路径和规则分类。

violation 很少不一定安全，可能是 clock 没识别；violation 很多不一定设计烂，可能是 setup 漏了 generated clock。setup report 是 CDC report 的可信门槛。

## 8. CDC report 要按修复路径分诊

同一份 CDC report 里会混着 RTL 真问题、约束缺失、合法但工具无法证明的结构。不能只按数量清零。

| report 类别 | 典型原因 | 处理动作 |
|---|---|---|
| setup 问题 | top、filelist、clock/reset 不完整 | 修 setup 后重跑 |
| true CDC bug | 跨域未同步、多 bit 直接跨域、reconvergence | 改 RTL 结构 |
| constraint missing | generated clock、reset、false path 漏建 | 补 SGDC/约束后重跑 |
| safe but not proven | 设计协议保证安全但工具不能自动证明 | 写 waiver，保留证据 |
| tool/env issue | license、GUI、库依赖失败 | 修工具环境，不归为 RTL bug |

处理 violation 的最小表格：

| 字段 | 必填内容 |
|---|---|
| rule id | 哪条 CDC 规则 |
| path | source flop 到 destination flop |
| source/destination clock | 两端时钟域 |
| type | setup / true bug / constraint missing / waiver |
| action | 改 RTL / 补约束 / waiver / 环境修复 |
| evidence | 修改 diff、报告截图、波形、协议说明或重跑结果 |

这张表比“violation 从 100 条降到 0 条”更重要，因为它说明每条问题为什么被处理。

### CDC message 分诊卡

读一条 CDC message 时，先把它拆成可审查证据链，再决定动作。报告里的 rule 名称只说明工具怀疑什么，不能直接说明设计一定错。

| 分诊步骤 | 要记录的证据 | 判断口径 |
|---|---|---|
| 1. rule 定位 | rule id、message、severity | 先知道工具在查单 bit、multi bit、reconvergence、reset 还是 generated clock |
| 2. domain 定位 | source clock、destination clock、reset domain | 两端 domain 识别错误时，先修 clock/reset 约束 |
| 3. path 定位 | source flop、destination flop、中间组合逻辑 | 找不到真实 RTL 路径时，先查 filelist/top/black box |
| 4. 结构判断 | 同步器、握手、FIFO、Gray code、普通组合路径 | 有明确安全结构才可能 waiver；没有结构就倾向改 RTL |
| 5. 约束判断 | SGDC/SDC/generated clock/false path 是否缺失 | 结构正确但工具不知道，补约束后必须重跑 |
| 6. 收敛证据 | 重跑 report、波形、协议说明、review 记录 | 没有重跑和证据，不能把 message 当成已关闭 |

最容易误判的是“数量”。`0 violation` 可能只是 clock 没建出来，`1000 violation` 也可能只是 generated clock 漏建。真正能交付的是每条 message 的来源、类型、动作和重跑证据。

## 9. waiver 是工程承诺，不是删除红字

waiver 的含义是：我确认这条 crossing 在设计协议下安全，并留下可审查证据。它不是“我不想看这条 warning”。

最小 waiver 模板：

```text
rule id:
source clock:
destination clock:
path:
structure type:
why safe:
evidence:
owner:
invalid when:
review date:
```

一条合格 waiver 至少要说明：

- 这条 crossing 属于哪种结构。
- 为什么协议保证安全。
- 依据来自代码、波形、形式验证、架构文档还是上级约束。
- 以后哪些改变会让 waiver 失效。

如果写不出 `why safe` 和 `evidence`，这条问题不该 waive，应继续分析或修改 RTL。

## 10. 工具环境错误要和设计错误分开

课程中出现 `libQtCore` 类问题，这属于工具 GUI/Qt 依赖或运行环境问题，不等于 RTL CDC 有错。

![libQtCore 环境问题](<./screenshots/任务029_Spyglass的基本使用-2/debug_libqt_issue_3230s.jpg>)

视觉核验：视频 52:00-54:20，画面出现 `libQtCore` 或异常终止相关信息；读者应把它归为工具环境排错，而不是 CDC violation。

处理方向：

```text
检查 SpyGlass 安装路径
检查 license
检查 LD_LIBRARY_PATH
检查 Qt/GUI 依赖库
能否命令行模式跑同一个 goal
```

工程上要分清两条线：工具启动失败先修环境；工具成功运行后 report 指出的 CDC 路径才进入设计分析。

## 11. 推荐实操流程

```text
准备 RTL/filelist
  -> 创建独立 CDC 工作目录
  -> 创建 SpyGlass project
  -> 设置 top
  -> 选择 CDC goal
  -> 添加 clock/reset/generated clock/SGDC
  -> 跑 setup verification
  -> 修 setup 噪声
  -> 跑 CDC check
  -> 按 rule/path/domain 分类 report
  -> 改 RTL / 补约束 / 写 waiver
  -> 重跑并记录收敛证据
```

命令行批处理的最小包可以按下面组织：

```text
cdc_chk_myown/
  filelist.f
  constraints/top.sgdc
  constraints/top.sdc
  run_cdc.tcl
  reports/
```

`run_cdc.tcl` 至少要表达：读入 `filelist.f`、设置 top、加载 SGDC/SDC、选择 CDC goal、跑 setup verification、输出 setup/report。GUI 可以用来学习和定位，批处理脚本负责让别人复跑同一结果。

如果出现 `libQtCore`、license 或 `LD_LIBRARY_PATH` 这类错误，先把它记成工具环境失败：工具没启动或没跑完时，没有 CDC 结论。只有 setup 和 goal 正常跑完以后，report 里的 path 才能进入设计分析。

最小验收：任选一条 CDC message，能填出：

```text
rule -> source clock -> destination clock -> path -> 类型 -> 处理动作 -> 验收证据
```

如果还不能判断它属于改 RTL、补约束还是 waiver，就不能进入报告清零。

## 12. 与 AI+IC 工程的连接

AI 加速器和 SoC 里会有大量跨域：CPU 总线域、NPU 计算域、DMA 域、外设域、低功耗域、debug/test clock。CDC 问题不一定在仿真中稳定复现，却可能在芯片上变成偶发死锁、数据错位、DMA 丢包或中断丢失。

对 NPU 项目尤其要盯住：

- 配置寄存器从 CPU/APB 域进入计算域。
- DMA done/interrupt 从数据搬运域回到 CPU 域。
- 多 bit descriptor、地址、长度跨域时是否有握手或 FIFO。
- 低功耗 clock gate 后 generated/gated clock 是否建模。

SpyGlass CDC 的训练价值是让你在 RTL 阶段就把这些结构风险找出来，而不是等板级或流片后碰运气。

## 复习与自测

1. 为什么 CDC 检查前要先确认 clock/reset 识别完整？
   - 答案要点：CDC 判断依赖 source/destination clock/reset domain。clock/reset 漏建会导致误报、漏报或错误分类。

2. generated clock 约束写错会怎样影响 CDC 报告？
   - 答案要点：工具可能把相关时钟误认为异步，产生大量假 violation；也可能把真正异步路径误判为安全，造成漏报。

3. CDC violation 的处理为什么不等于“一律改 RTL”？
   - 答案要点：violation 可能来自真实 RTL bug、约束缺失、setup 错误或合法但工具无法证明的结构。不同类型对应不同动作。

4. filelist 相比 GUI 手动加文件有什么工程优势？
   - 答案要点：filelist 可复现、可版本管理、可被 VCS/DC/SpyGlass 复用，减少工具之间看到不同 RTL 的风险。

5. `libQtCore` 报错更像工具环境问题，还是设计 CDC 问题？
   - 答案要点：工具环境问题。应查 GUI/Qt 依赖、安装路径、license、环境变量，不应归为 RTL CDC bug。

6. 一个 CDC waiver 最少应该说明哪些信息？
   - 答案要点：rule/path、source/destination clock、结构类型、为什么安全、证据、owner、失效条件。



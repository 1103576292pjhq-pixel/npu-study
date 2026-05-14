# 任务105：Design and Technology Data 2

## 本章知识全景图

这一讲把前一讲的 library、target/link/search path 补成一条更完整的 DC 读设计链：先让 DC 在正确目录和正确库环境里启动，再把 RTL、IP、DDC、约束和 current design 组织进 DC memory，最后用 link/check/write DDC 形成可复用的综合中间状态。

| 概念层级 | 核心概念 | 前置知识 | 延伸应用 |
|---|---|---|---|
| 工程坐标 | CWD、search_path、`.synopsys_dc.setup` | Linux 目录、DC 启动方式 | 避免脚本找错 RTL、库、约束和输出目录 |
| DC 读入链 | `read_verilog`、`current_design`、`link`、`check_design` | Verilog module/instance | 建立可检查的 top 设计上下文 |
| 层次设计 | design、reference、instance、IP、macro | RTL 例化关系 | 解释为什么 link 能解析外部 IP 和 library cell |
| 推荐读法 | `analyze` + `elaborate` | RTL 参数、HDL 格式 | 改 parameter、指定 top、支持更复杂工程 |
| 中间格式 | DDC before/after compile | DC memory、约束、库信息 | 加速多轮综合、给同一家工具链继续使用 |

最短学习路径：先确认 CWD 和 setup 文件，再理解 current design 为什么必须指定；随后用 link/check_design 区分“能解析 reference”和“连接端口是否合理”；最后掌握 DDC 在 compile 前后分别保存什么、为什么能节省后续迭代时间。

![Library setup 命令总览](<./screenshots/任务105_Design_and_Technology_Data_2/task105_dense_0480s_00h08m00s.jpg>)

看图要点：这张图是进入配置，不是收尾复盘；target/link/search path 先把环境搭稳，后面的 `check_timing` 和 DCG 相关性才有意义。

## 本课主线地图

| 时间 | 教学主线 | 本笔记吸收方式 |
|---|---|---|
| 00:19-05:44 | 复盘 technology library、target/link/search_path 和 `set_app_var` | 合并为 DC setup 的工程职责 |
| 05:44-13:07 | CWD、`dc_shell -topo`、read/link/source/check/write flow | 重写为最小可执行流程与失败信号 |
| 13:33-22:53 | 层次设计、多个 Verilog、DDC、current design、link | 展开成 top 解析和 reference 解析机制 |
| 22:53-28:01 | `check_design`、DMM、warning 和 return value | 区分 warning 可跑通和结果可信 |
| 28:01-34:29 | `analyze` + `elaborate`、HDL 格式和参数覆盖 | 写成实际项目推荐读法 |
| 34:29-42:14 | IP/macro library、读 DDC、link 解析外部模块 | 解释 IP/DDC 缺失时的 unresolved model |
| 42:14-54:25 | compile 前后保存 DDC、DDC 与 Verilog 的工具链边界 | 形成多轮综合和后端交接口径 |
| 54:25-56:05 | 命令总结和后续 lab 预告 | 压缩为复习清单 |

## 1. DC 环境的第一件事是让路径和库都可解释

CWD 是 DC 解释相对路径的坐标原点；search_path 是“文件名简写”机制；target/link library 是综合与解析 reference 的库环境。三者没有先建好，后面读 RTL、link IP、source 约束、write 输出都会变成随机碰运气。

一个最小综合目录可以整理成：

```text
dc_lab/
├─ rtl/       # top.v、A.v、B.v 等 RTL
├─ libs/      # target library、link library、IP .db
├─ cons/      # SDC / constraint scripts
├─ unmapped/  # compile 前 DDC
├─ mapped/    # compile 后 netlist / DDC
└─ .synopsys_dc.setup
```

视频里反复强调不能在 `mapped/` 这种子目录下随手启动 DC。原因不是目录名字不好看，而是你站错 CWD 后，`rtl/top.v`、`libs/*.db`、`cons/*.sdc` 这些相对路径都会失效；link 解析不到 reference，compile 就无法做 mapping。

`set_app_var` 的价值也在这里。对 DC 保留变量，推荐写：

```tcl
set_app_var search_path ". ./rtl ./libs ./cons"
set_app_var target_library "sc_max.db"
set_app_var link_library "* sc_max.db ip1.db"
```

如果把 `link_library` 敲成不存在的保留变量名，`set_app_var` 更容易暴露错误；普通 Tcl `set` 可能只创建一个普通变量，工具不一定按你以为的方式使用它。

## 2. `dc_shell -topo` 是为了提高综合和 APR 的相关性

`dc_shell -topo` 启动的是带拓扑/物理估计能力的 DCG 思路，不是单纯多了一个显示选项。传统逻辑综合只按逻辑估计 timing；topographical 综合会用一个粗略物理布局模型估算线延时，让 DC 阶段的 timing 和后续 APR 后的 timing 更接近。

常见错觉：DC 只要能把 RTL 变成 gate netlist 就够了；正确理解：真实项目关心 DC timing 和 APR timing 的相关性。如果 DC 完全不考虑物理结构，综合时看起来满足的路径，布局布线后可能因为线长和拥塞变差。

本讲给出的基本 flow 可以压成下面这条链：

```tcl
dc_shell -topo
read_verilog top.v
current_design my_top
link
check_design
source top.con
check_timing
compile_ultra
write -format verilog -hierarchy -output mapped/my_top.v
write -format ddc -hierarchy -output mapped/my_top.ddc
```

这条链的关键不是背命令顺序，而是知道每一步挡住哪类错误：

| 步骤 | 解决的问题 | 失败信号 |
|---|---|---|
| `read_verilog` | RTL 进入 DC memory | 文件找不到、语法不支持、module 未读全 |
| `current_design` | 明确这次综合的 top | 工具默认错 top，后续报告对象不对 |
| `link` | 解析 top 里的 reference | unresolved reference、IP/macro 找不到 |
| `check_design` | 检查端口连接和结构风险 | missing port、unconnected input、mismatch |
| `check_timing` | 检查约束是否完整合理 | clock/port/constraint 不完整 |
| `compile_ultra` | mapping 和 optimization | target library 不完整、QoR 不收敛 |
| `write` | 把 memory 里的结果落盘 | 退出后后端没有可接收文件 |

## 3. current design 是在告诉 DC “以谁为 top”

读进多个 RTL 后，DC memory 里会同时存在很多 design object；工具不知道你要综合哪个 block。`current_design my_top` 就是在把当前操作对象锁定为 `my_top`，后续 link、check、compile、report 默认都围绕它展开。

![层次设计例子](<./screenshots/任务105_Design_and_Technology_Data_2/task105_dense_0960s_00h16m00s.jpg>)

看图要点：层次设计图要先分清 current design 是当前操作对象，不是当前打开的文件；DC memory 里可同时装很多 design，但 compile/report 默认围绕被选中的 top。

如果只读一个文件，工具可能用默认规则猜出 top；但真实工程常常有几十个甚至几百个 Verilog 文件，top module 也不一定出现在最后。依赖默认规则会带来两个风险：

1. 你以为在综合 top，实际报告的是某个子模块。
2. link 时 reference 解析路径变了，missing model 的报错位置也会误导排查。

正确习惯是：读完全部设计文件后显式写 `current_design`，再 `link`。

```tcl
read_verilog A.v
read_verilog B.v
read_verilog top.v
current_design my_top
link
check_design
```

`link` 的动作是沿着 `my_top` 的 instance/reference 往下找模块定义。能在当前 DC memory 找到的，就绑定到读进来的 design；找不到的，再去 link library 中找 IP、macro 或 library cell。找不到就是 unresolved reference。

## 4. `check_design` 不是可选装饰，它是端口和结构风险闸门

`link` 主要确认 reference 名字能不能解析；`check_design` 进一步检查连接关系是否合理。端口数量不一致、端口名大小写不匹配、input 悬空、输出不连、层次连接错误，很多都要靠 `check_design` 把 warning 报出来。

![check_design 之后的风险检查](<./screenshots/任务105_Design_and_Technology_Data_2/task105_dense_1440s_00h24m00s.jpg>)

看图要点：`check_design after link` 图的价值是把“名字找到了”和“连接合理”分开，return value 能继续不等于 warning 可以忽略。

这里要区分两个层次：

| 现象 | 工具可能怎样处理 | 工程判断 |
|---|---|---|
| return value 为 1 | 工具认为可以继续跑 | 不等于结果一定是你想要的 |
| warning | 工具可忽略并继续 | 工程师必须判断是否 expected |
| missing port | 有时会当悬空处理 | 多数情况下要回 RTL 或例化处检查 |
| unconnected input | 可能能综合出结果 | 结果可能不是预期功能 |

不要把 warning 当成“没事”。warning 的含义通常是：工具能继续，但风险转交给你判断。严格 flow 中，`check_design` 之后要先把 warning 分类，确认哪些是 expected，哪些必须回 RTL 修。

一个实用分类口径是：由 intentionally unused output、已知 tie-off 或明确黑盒边界产生的 warning，可以在审查表里标 expected；missing port、unconnected functional input、width mismatch、unresolved design、clock/reset 连接异常，必须回 RTL、例化或库配置修掉。warning 像安检门的提示音，不一定说明货物不能进场，但没有人工判定就不能当作安全放行。

## 5. `analyze` + `elaborate` 是更适合实际项目的读设计方式

`read_verilog` 对入门 lab 足够，但实际项目更常用 `analyze` + `elaborate`。前者把 HDL 文件分析进 work library，后者指定 top 并展开层次；这套方式更适合多文件、多 HDL、parameter override 和复杂工程。

![analyze 与 elaborate](<./screenshots/任务105_Design_and_Technology_Data_2/task105_dense_1680s_00h28m00s.jpg>)

典型写法：

```tcl
analyze -format verilog {A.v B.v top.v}
elaborate my_top
current_design my_top
link
check_design
```

如果 RTL 中有 parameter，`elaborate` 可以覆盖默认值：

```tcl
analyze -format verilog {A.v B.v top.v}
elaborate my_top -parameters "A_WIDTH=8,B_WIDTH=16"
```

这一步的工程意义很大。parameter 的默认值写在 RTL 里，但不同项目、不同综合配置可能需要不同位宽、深度或宏参数。用 `elaborate -parameters` 可以不改 RTL 源码，只在综合配置中覆盖参数，避免因为临时改源码污染设计版本。

如果只有一个参数，语法看起来很简单；如果有多个参数，建议用清晰的引号和分隔符，保证整个 parameter list 被当成一个 option argument 传给工具。

## 6. link 负责把 IP、macro 和 DDC 接进 top

top 里例化的模块不一定都来自 RTL 文件。它可能来自 IP `.db`，来自 hard macro library，也可能来自其他人提前保存的 DDC。link 的职责就是把这些外部定义和 top 里的 instance 对上。

![IP 和 macro library 的解析](<./screenshots/任务105_Design_and_Technology_Data_2/task105_dense_2160s_00h36m00s.jpg>)

看图要点：IP/macro 解析图要看 `link` 如何逐项对表，current design 里的 instance/reference 必须能在 DC memory 或 `link_library` 里找到定义。

如果 top 里有：

```verilog
RAM512 u_ram (...);
decode u_decode (...);
encode u_encode (...);
```

那么 DC 要能在以下位置找到定义：

| reference | 可能来源 | 没找到时的后果 |
|---|---|---|
| `RAM512` | IP `.db`、macro library | link 报 unresolved model |
| `decode` | 读入的 RTL 或 DDC | instance 无法展开 |
| `encode` | 读入的 RTL 或 DDC | instance 无法展开 |

DDC 也可以被读进 DC memory：

```tcl
read_ddc decode.ddc
read_ddc encode.ddc
read_verilog top.v
current_design my_top
link
```

如果你忘了读 DDC，top 里的 `u_decode`、`u_encode` 可能就找不到对应 model。不要把这种错误误判成 top.v 语法问题；根因是 DC memory 里缺少被例化模块的定义。

## 7. DDC 是 DC memory 的快照，compile 前后保存的价值不同

DDC 不是普通 Verilog 网表。它可以保存 design、层次、库绑定、约束、变量和工具内部信息。它的好处是打开快、信息全，适合 Synopsys 工具链内部复用。

![compile 前保存 DDC](<./screenshots/任务105_Design_and_Technology_Data_2/task105_dense_2640s_00h44m00s.jpg>)

可以在 compile 前保存一版：

```tcl
write -format ddc -hierarchy -output unmapped/my_top.ddc
```

compile 前 DDC 的价值是跳过耗时的读 RTL、analyze、elaborate、link 阶段。比如你只是要改 SDC 频率、调整 clock uncertainty 或换一组约束，就可以从这版 DDC 继续，不必重新从 RTL 读起。

更具体地说，compile 前 DDC 像综合断点快照：它已经把“人、工具、材料和图纸”登记好，但还没有开始最终施工。如果只是把 `create_clock` 从 5ns 改成 4ns、单独调整某个 IO delay、试一组更保守 uncertainty，直接读这版 DDC 再 source 新约束即可；如果 RTL 改了、IP 库换了、top 层次变了，就不能偷懒复用旧断点。

compile 后也建议保存一版：

```tcl
compile_ultra
write -format ddc -hierarchy -output mapped/my_top.ddc
write -format verilog -hierarchy -output mapped/my_top.v
```

compile 后 DDC 更接近综合结果，它能带着更多综合后的信息给后续 Synopsys 工具使用。如果后端也是 ICC/ICC2 这类同家工具，DDC 很方便；如果后端工具不是 Synopsys，则必须输出标准 Verilog netlist 和 SDC，因为 DDC 不是跨厂商标准格式。

| 输出 | 信息完整度 | 适合用途 |
|---|---|---|
| `mapped/my_top.v` | 标准 gate-level netlist | 给任意后端、仿真、形式验证 |
| `mapped/my_top.sdc` | 标准约束 | 给 STA / P&R 继续约束 |
| `mapped/my_top.ddc` | Synopsys 内部信息更全 | 同家工具链快速恢复和继续分析 |

## 8. `.synopsys_dc.setup` 把常用变量和 alias 固化下来

本讲最后回到 setup 文件。`.synopsys_dc.setup` 是隐藏文件，DC 启动时会自动读取安装级、用户级、项目级 setup。项目级 setup 的价值是把本项目的 library、search_path、symbol library、alias 等固定下来。

![变量和 alias 总结](<./screenshots/任务105_Design_and_Technology_Data_2/task105_dense_3240s_00h54m00s.jpg>)

常见内容包括：

```tcl
set_app_var search_path ". ./rtl ./libs ./cons"
set_app_var target_library "sc_max.db"
set_app_var link_library "* sc_max.db ip1.db"
set_app_var symbol_library "sc.sdb"

alias rc "report_constraint -all_violators"
alias rt "report_timing"
alias ra "report_area"
```

alias 不是为了炫技，而是为了减少重复敲长命令。真正需要注意的是：setup 中的库路径和变量必须和当前 CWD、项目目录结构一致，否则 DC 启动时看似正常，后面读文件和 link 时才暴露问题。

## 本章收束与检查

### 本章最该记住的结论

- CWD 错了，search_path、source、read、write 都可能错；不要在输出目录里随手启动 DC。
- `set_app_var` 用来设置 DC application variable，比普通 `set` 更能暴露保留变量拼写错误。
- `current_design` 是显式指定 top，不要让 DC 在多文件工程里猜。
- `link` 解决 reference 能否找到；`check_design` 解决连接和结构是否有风险。
- `analyze` + `elaborate` 比 `read_verilog` 更适合实际项目，尤其是 parameter override。
- DDC 是 DC memory 快照，compile 前后都可保存；跨工具交接仍要输出 Verilog netlist 和 SDC。

### 复现清单

1. 在项目根目录启动 `dc_shell -topo`，确认 CWD 能看到 `rtl/ libs/ cons/ mapped/`。
2. 用 `printvar target_library`、`printvar link_library`、`printvar search_path` 检查 setup 是否生效。
3. 读完 RTL 后执行 `current_design my_top`、`link`、`check_design`。
4. 如果 top 中例化 IP/macro/DDC 模块，确认它们在 link library 或 DC memory 中存在。
5. compile 前保存 `unmapped/my_top.ddc`；compile 后保存 `mapped/my_top.ddc` 和 `mapped/my_top.v`。

### 自测题

1. 为什么不能只看 `link` 通过就认为设计结构没问题？

   答：`link` 主要确认 reference 名称能否解析；端口不匹配、悬空输入、missing port、层次连接风险需要 `check_design` 报 warning 后由工程师判断。

2. `analyze` + `elaborate` 相比 `read_verilog` 的关键优势是什么？

   答：它把 HDL 分析和 top 展开分开，适合多文件、多 HDL 和 parameter override；可在不改 RTL 的情况下通过 `elaborate -parameters` 覆盖参数。

3. 为什么 DDC 不能替代标准 Verilog netlist 作为所有后端工具的交接文件？

   答：DDC 是 Synopsys 内部格式，信息更全但不是跨厂商标准；跨工具交接应使用 Verilog netlist、SDC 等行业通用格式。


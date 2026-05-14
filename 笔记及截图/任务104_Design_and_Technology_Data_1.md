# 任务104：Design and Technology Data 1

## 本章知识全景图

Design Compiler 不能只靠一份 Verilog 文件完成综合；它必须同时知道“要综合什么设计”和“允许用什么工艺单元实现”。本节的核心就是把 `design data`、`technology data`、`target_library`、`link_library`、`search_path` 和 `.synopsys_dc.setup` 串成一条可执行的 DC 环境配置链。

| 知识块 | 解决的问题 | 直接结论 |
|---|---|---|
| CWD 与目录结构 | DC 从哪里找文件、往哪里写结果 | 当前工作目录决定相对路径、项目级 setup 和输出位置 |
| `read_verilog` | 读 RTL 到底读进了哪里 | RTL、库和 design object 会进入 DC memory，后续 link/compile/report 都基于内存对象 |
| target library | DC 用哪些标准单元做 mapping | `target_library` 指向工艺库 `.db`，决定可用 cell、timing、area、power |
| technology data | `.db/.lib` 里到底有什么 | 工艺库描述 library、cell、pin、delay lookup table、PVT、面积、功耗、电容 |
| link library | 为什么 target library 不等于查找全集 | `link_library` 负责解析当前 design 中的所有 reference，常见写法是 `* your.db` |
| search_path | 为什么脚本里可以少写路径 | 它声明文件搜索目录，但也带来同名文件歧义风险 |
| `.synopsys_dc.setup` | 为什么 DC 启动后变量已经存在 | 安装级、用户级、项目级 setup 会在启动时自动执行 |
| 换工艺库 | 旧 RTL 怎样迁移到新库重新综合 | 从原始 RTL 出发，更新 target/link/search/constraints，重新 link、check、compile、write |

最短学习路径：先确认 CWD 和工程目录，再理解 `read_verilog` 把 design 放进 DC memory；随后区分 target library 与 link library；最后用 search_path 和 `.synopsys_dc.setup` 把路径、库和 alias 固化。

看图要点：这张总图先看全链路，CWD 决定相对路径，`read_verilog` 把 design 放进 DC memory，target/link library 决定后续能不能映射和解析 reference。

![DC 调用与 read_verilog 总图](<./screenshots/任务104_Design_and_Technology_Data_1/task104_dense_0480s_00h08m00s.png>)

## 本课主线地图

| 时间 | 画面主线 | 本笔记吸收方式 |
|---|---|---|
| 00:50-03:49 | Invoking DC、CWD、项目目录、`dc_shell -topo` | 重组为当前工作目录和文件职责 |
| 04:20-08:26 | `read_verilog rtl/MYREG_rt1.v`、DC memory、当前 design | 展开 read command 的五个动作和缺模块风险 |
| 09:41-12:18 | 未设置 target library 导致 compile 报错 | 作为技术库必要性的失败信号 |
| 13:02-17:24 | target library `.db/.lib`、cell、pin、lookup table | 展开 technology data 的内容 |
| 17:24-22:33 | `set_app_var target_library`、`write -format verilog` | 形成最小命令链和网表落盘边界 |
| 23:13-30:03 | link library、`*`、`link` 提前检查 reference | 展开 target/link 差异和工程排错顺序 |
| 31:09-35:27 | shortening file name、`search_path` | 解释路径简化与歧义风险 |
| 35:27-41:26 | 三层 `.synopsys_dc.setup`、alias、自动 source | 建立环境配置层级 |
| 41:26-46:18 | old 55nm -> new 40nm 工艺库迁移 | 写成换库重新综合的操作口径 |

## 1. CWD 是 DC 项目的坐标原点

Current Working Directory 不是一个无关紧要的目录名；DC 脚本里的相对路径、项目级 setup、输出文件和日志位置，都默认围绕 CWD 解释。

一个清晰的综合工程目录通常长这样：

```text
risc_design/
├─ rtl/        # RTL design files
├─ libs/       # .db/.lib technology libraries
├─ cons/       # SDC / timing constraints
├─ mapped/     # mapped gate-level netlist output
└─ .synopsys_dc.setup
```

如果你在 `risc_design` 下启动：

```sh
dc_shell -topo
```

那么 `read_verilog rtl/MYREG_rt1.v` 中的 `rtl/` 就是相对 `risc_design` 解释。CWD 错了，后面最常见的问题就是脚本找不到 RTL、找不到库、source 错约束，或者把输出写到意外目录。

工程习惯上，目录名要表达文件职责：

| 目录 | 放什么 | 错放的后果 |
|---|---|---|
| `rtl/` | Verilog/SystemVerilog 源文件 | RTL 和网表混在一起，容易读错版本 |
| `libs/` | `.db/.lib`、IP library、macro library | target/link library 路径混乱 |
| `cons/` | `.sdc`、`.con`、时序/设计规则约束 | 约束版本不可追踪 |
| `mapped/` | 综合后的 gate-level netlist | 后端拿到旧网表或未映射网表 |
| `reports/` | timing/area/power/constraint 报告 | QoR 证据丢失 |

目录能随便起，但职责不能随便。综合脚本的可维护性首先来自清晰目录。

## 2. `read_verilog` 是把 design object 放进 DC memory

`read_verilog` 不是简单地“打开一个 RTL 文件”；它会读取文件、解析模块、执行初步 translation，并把 design 放入 DC memory。

看图要点：这张图只拆 `read_verilog` 内部动作，说明读 RTL 不是文件打开，而是伴随库装载、RTL 翻译、design 入内存和 current design 选择的一串动作。

![read_verilog 的真实含义](<./screenshots/任务104_Design_and_Technology_Data_1/task104_dense_0360s_00h06m00s.png>)

可以把 `read_verilog rtl/MYREG_rt1.v` 拆成五个结果：

1. 加载默认库和用户指定的 link library。
2. 读入 RTL 文件。
3. 把 Verilog/VHDL 转换成未映射的内部表示。
4. 把 design 放入 DC memory。
5. 把某个 design 设为 current design，供后续命令默认操作。

这解释了一个常见错误：top 模块里实例化了 `sub_fifo`，但你只读了 `top.v`，没有读 `sub_fifo.v`。这时 `read_verilog` 可能能读进 top，但 `link` 或 `compile` 会报 unresolved reference，因为 DC memory 和 link library 里都找不到这个 reference。

正确排查顺序：

```tcl
read_verilog ./rtl/top.v
read_verilog ./rtl/sub_fifo.v
current_design top
link
check_design
```

先让所有 design object 进入 DC memory，再 link 检查引用关系。不要等 `compile_ultra` 跑起来后才发现少读模块。

## 3. target library 是 mapping 的工艺依据

Target library 回答的是：综合器可以用哪一个工艺库里的标准单元来实现你的 RTL。

看图要点：缺 target library 的报错页要当作失败信号记，工具不是找不到 RTL，而是没有可用标准单元完成 mapping。

![缺 target library 的失败信号](<./screenshots/任务104_Design_and_Technology_Data_1/task104_dense_0600s_00h10m00s.png>)

典型命令：

```tcl
set_app_var target_library "libs/65nm_wc.db"
```

这里推荐用 `set_app_var`，因为 target_library 是 DC application variable。普通 `set` 只是 Tcl 变量赋值，可能只创建或修改局部 Tcl 变量，并不一定改变工具真正使用的 app variable。对 DC 环境变量，优先使用 `set_app_var`，语义更明确。

如果 target library 没设好，`compile` 阶段会失败或只能停留在未映射状态。原因很直接：工具不知道可用标准单元清单、单元延迟、驱动能力、面积和功耗，就无法进行 gate mapping 和 optimization。

## 4. Technology data 不是一个文件名，而是一套 cell 行为模型

`.db` 或 `.lib` 里记录的是工艺库对标准单元的描述；它告诉工具每个 cell 在特定 PVT 和负载条件下会怎样工作。

看图要点：technology library 图要看成 cell 行为合同，里面的 PVT、pin、电容、面积、功耗和 lookup table 决定工具如何计算延时和选择单元。

![Technology library 内部内容](<./screenshots/任务104_Design_and_Technology_Data_1/task104_dense_0960s_00h16m00s.png>)

| 数据 | 作用 |
|---|---|
| library name | 识别这套库，如某工艺、某电压温度 corner |
| PVT/corner | process、voltage、temperature 条件，决定 timing/power 模型 |
| unit 定义 | 时间、电压、电容、电流等单位 |
| cell name | 标准单元名，如 `AND2_X1`、`DFFR_X2`、`BUF_X4` |
| cell area | 面积估算和优化依据 |
| leakage power | 静态功耗估算依据 |
| pin direction | 输入、输出、时钟、复位等引脚属性 |
| capacitance/max_capacitance | 输入电容和输出负载限制 |
| timing lookup table | 不同 input transition、output load 下的延迟查表 |

`.lib` 是可读的 Liberty 文本格式；`.db` 是 Synopsys 工具常用的二进制数据库格式，读取快但不适合人直接读。通常库供应商给 `.lib`，再转换成 `.db` 供 DC 使用。

时序优化依赖 lookup table。比如同一个 `NAND2_X1`，输出负载越大、输入边沿越慢，cell delay 越大。DC 不是凭感觉选 cell，而是用这些表计算路径延迟和优化方向。

## 5. 设置 target library 后，结果还必须写出网表

综合结果首先存在 DC memory 中；如果不 `write`，退出工具后后端没有可接收文件。

看图要点：写出网表图说明 DC memory 里的结果必须落盘，`compile_ultra` 成功不等于后端已经拿到 mapped netlist。

![写出 gate-level netlist](<./screenshots/任务104_Design_and_Technology_Data_1/task104_dense_1320s_00h22m00s.png>)

一个最小命令链可以写成：

```tcl
read_verilog ./rtl/MYREG_rt1.v
set_app_var target_library "libs/65nm_wc.db"
source ./cons/myreg.con
check_timing
compile_ultra
write -format verilog -hierarchy -output ./mapped/MYREG_mapped.v
report_constraint -all_violators
```

这里每条命令都有边界：

- `read_verilog` 负责把设计读进来。
- `set_app_var target_library` 负责指定可用于 mapping 的目标库。
- `source` 负责读入约束脚本。
- `check_timing` 负责先检查时序约束是否完整。
- `compile_ultra` 负责综合和优化。
- `write -format verilog` 负责把 mapped netlist 落盘。
- `report_constraint` 负责看哪些约束仍然违例。

成功信号不是“命令没报错”这么简单，而是 mapped 文件存在、网表中出现目标库标准单元、报告能解释 QoR。

## 6. link library 是 reference 解析的全集

Target library 只告诉 DC 用什么库来映射标准单元；link library 告诉 DC 当前 design 里所有 reference 到哪里找。

看图要点：link library 图里最容易误读的是 `*`，它不是普通目录通配符，而是把当前 DC memory 中已读入的 design 纳入 reference 查找。

![link library 与星号](<./screenshots/任务104_Design_and_Technology_Data_1/task104_dense_1680s_00h28m00s.png>)

典型写法：

```tcl
set_app_var target_library "your_library.db"
set_app_var link_library "* your_library.db"
link
```

`*` 的意思是：先把 DC memory 里已经读入的 design 也纳入查找范围。没有 `*`，DC 可能只去外部库文件里找 reference，而忽略你刚刚读进来的 RTL 子模块。

Link 的查找逻辑可以理解为：

1. 设计里出现一个实例或 reference。
2. DC 先在当前 memory 中找有没有同名 design。
3. 找不到时，再去 `link_library` 指定的库里找。
4. 仍找不到，就报 unresolved reference。

这也是为什么建议在 compile 前显式执行：

```tcl
link
check_design
check_timing
```

提前 link 能把“缺模块、缺库、库名写错、IP wrapper 没读入”这类问题提早暴露。否则它们可能在 compile 中途才爆出来，浪费更长调试时间。

## 7. target library 与 link library 的差异要用错误来记

把这两个变量混淆，是初学 DC 的高频错误。

| 变量 | 主要问题 | 典型内容 | 不设好的后果 |
|---|---|---|---|
| `target_library` | 用哪些 cell 做 mapping 和 optimization | `"ss40_wc.db"` | 无法映射到目标工艺，compile 报 target library 相关错误 |
| `link_library` | 到哪里解析所有 reference | `"* ss40_wc.db ip.db sram.db"` | 子模块、IP、macro、标准单元 reference 找不到 |

一个 AI 芯片模块中，除了普通标准单元，还可能实例化 SRAM macro、PLL wrapper、hard multiplier、clock gating cell 或第三方 IP。它们未必都属于 target library，但必须能在 link 阶段被解析。否则综合器连设计层次都无法闭合。

因此，不要把 `link_library` 只写成 target library 的复制品；实际项目里它经常是 DC memory、标准单元库、宏库、IP 库的组合。

## 8. search_path 是路径声明，不是排错魔法

`search_path` 让你在脚本中少写长路径，但它不会自动判断哪个同名文件才是你想要的版本。

看图要点：search_path 图的职责是解释“少写路径”的代价：它能帮你找文件，但不会替你判断同名文件哪个才是对的。

![search_path 文件查找机制](<./screenshots/任务104_Design_and_Technology_Data_1/task104_dense_2040s_00h34m00s.png>)

典型写法：

```tcl
set_app_var search_path ". ./rtl ./libs ./cons"

read_verilog MYREG_rt1.v
set_app_var target_library "65nm_wc.db"
source myreg.con
```

这会让 DC 在当前目录、`rtl/`、`libs/`、`cons/` 等目录中查找文件。好处是脚本短；风险是同名文件歧义。

风险例子：

```text
rtl/MYREG_rt1.v
backup/MYREG_rt1.v
old/MYREG_rt1.v
```

如果这些目录都进了 search_path，工具会按搜索顺序找到某一个版本。你以为综合的是最新版，实际可能读到了旧版。所以工程上要么避免同名冲突，要么在关键文件上写明确路径。

## 9. `.synopsys_dc.setup` 是 DC 启动时自动 source 的环境脚本

`.synopsys_dc.setup` 的价值是把重复环境配置前置：库路径、search_path、target/link library、alias 等可以在 DC 启动时自动生效。

看图要点：setup 文件位置图要按作用域读，安装级管全局默认，用户级管个人习惯，项目级才应该承载当前设计的库路径和关键变量。

![三层 setup 文件位置](<./screenshots/任务104_Design_and_Technology_Data_1/task104_dense_2280s_00h38m00s.png>)

| 层级 | 位置 | 适合放什么 |
|---|---|---|
| 安装级 default setup | `$SYNOPSYS/admin/setup/.synopsys_dc.setup` | 公司或安装默认配置，不应放具体项目私有路径 |
| 用户级 general setup | `~/.synopsys_dc.setup` | 个人 alias、常用显示设置、非项目专属习惯 |
| 项目级 project-specific setup | 当前 CWD 下 `.synopsys_dc.setup` | 当前项目的 search_path、target/link library、alias |

项目级 setup 示例：

```tcl
set_app_var search_path ". ./rtl ./libs ./cons ./mapped"
set_app_var target_library "ss40_wc.db"
set_app_var link_library "* ss40_wc.db"

alias h history
alias rc "report_constraint -all_violators"
alias rt "report_timing"
```

setup 文件的好处是少敲重复命令；风险是配置变得“隐形”。如果某个同事不知道 target library 在 setup 里被改过，他可能误以为脚本没有设置库也能跑。因此项目 setup 要短、清楚、可版本化，并且正式 run 脚本最好仍显式记录关键库变量。

## 10. 换工艺库不是改输出文件名，而是重新定义目标技术环境

从 55nm 迁移到 40nm 时，RTL 可以保持不变，但 target/link library、search_path 和约束口径都要重新审视。

看图要点：换库示例图的核心不是新旧文件名，而是说明旧 gate-level netlist 已经绑定旧 cell，迁移新工艺优先从 original RTL 重新综合。

![切换 technology library 示例](<./screenshots/任务104_Design_and_Technology_Data_1/task104_dense_2640s_00h44m00s.png>)

基本流程：

```tcl
set_app_var search_path ". ./rtl ./libs ./cons"
set_app_var target_library "libs/new_40_slow40.db"
set_app_var link_library "* libs/new_40_slow40.db"

read_verilog ORIGINAL_RTL.v
link
check_timing
source cons/new_con.tcl
compile_ultra
write -format verilog -output mapped/NEW_NETL.v
```

为什么强调从 original RTL 开始？因为旧 gate-level netlist 已经绑定旧工艺库 cell。把旧网表直接拿去新库环境下跑，可能出现旧 cell 名在新库里不存在、功能等价难以确认、约束意义变化等问题。

如果你只有旧 netlist，也不是完全不能处理，但要把它视为“重新映射/技术迁移问题”，而不是简单的“重新综合 RTL”。必须检查：

- 旧库 cell 是否能被新库替代。
- 是否需要读入旧库和新库同时完成 link。
- 是否有可用的 technology mapping 规则。
- 重新映射后的功能等价是否能验证。
- 时序约束是否按新工艺目标重新定义。

对初学者，最稳妥的记法是：有原始 RTL 时，换库优先从 RTL 重新综合；只有旧网表时，要先确认 cell 和库迁移机制，不能只替换 `.db` 文件名。

## 11. 一条可复用的 DC 环境检查顺序

当 DC 报“找不到文件、找不到库、找不到 reference、不能 compile”时，不要直接怀疑工具坏了。按下面顺序排查：

1. `pwd`：确认 CWD 是否是项目根目录。
2. `printvar search_path`：确认 RTL、libs、cons 目录是否在搜索路径中。
3. `printvar target_library`：确认目标工艺库是否设置成真实 `.db`。
4. `printvar link_library`：确认包含 `*`，并包含标准单元库、IP 库、macro 库。
5. `read_verilog` 后查看 log：确认 top 和子模块是否 loaded into memory。
6. `current_design top`：确认当前设计不是误设成子模块。
7. `link`：提前解析 reference。
8. `check_design`：检查缺模块、悬空端口、层次问题。
9. `source constraints` 后 `check_timing`：确认约束不是空的或错误的。
10. `compile_ultra` 后检查 `report_constraint -all_violators` 和 QoR 报告。

这套顺序能把“路径问题、库问题、设计层次问题、约束问题、优化问题”分开。混在一起看，只会让报错越来越像玄学。

## 12. 本课在数字前端/NPU 工程中的位置

NPU/AI 芯片里，一个模块很少只依赖纯 RTL。常见情况是：控制逻辑是 RTL，存储是 SRAM macro，乘法器可能是综合推断或 IP，时钟门控 cell 需要库支持，低功耗 cell 也需要额外库和约束。

因此，本节训练的是综合环境意识：

- RTL 只是 design data 的一部分。
- 工艺库决定标准单元、延迟和功耗模型。
- SRAM、PLL、特殊 IO、clock gating cell 等需要被 link library 正确解析。
- search_path 和 setup 决定脚本能否稳定读到同一批文件。
- 换工艺库会影响 timing、area、power、DRC，不是换个文件名就结束。

从工程角度看，能写 RTL 是第一步；能搭出可复现、可排错、可迁移的 DC 环境，才接近数字前端交付。

## 本章收束与检查

- CWD 是 DC 解释相对路径和项目级 setup 的坐标原点。
- `read_verilog` 会把 RTL 转成内部 design object，并放进 DC memory。
- 缺子模块或 top 设置错，往往在 link/check 阶段暴露。
- target library 决定 mapping/optimization 可用哪些标准单元。
- `.lib` 可读，`.db` 是 DC 常用二进制库；库里包含 cell、pin、PVT、area、power、timing lookup table。
- link library 负责解析所有 reference，`*` 表示 DC memory。
- search_path 简化路径，但同名文件会带来歧义。
- `.synopsys_dc.setup` 有安装级、用户级、项目级三层；项目级最适合放当前项目配置。
- 换工艺库优先从 original RTL 重新综合，并同步更新 target/link/search/constraints。

## 自测题

1. `read_verilog` 和 `link` 的职责差别是什么？  
   答：`read_verilog` 负责读 RTL、解析模块并把 design 放入 DC memory；`link` 负责解析当前 design 中实例化的 reference，确认它们能在 DC memory 或 link_library 中找到。

2. target library 和 link library 的区别是什么？  
   答：target library 是 mapping/optimization 使用的目标标准单元库；link library 是解析所有 design/IP/macro/library reference 的查找全集。

3. `set_app_var link_library "* ss40_wc.db"` 中 `*` 表示什么？  
   答：表示 DC memory 中已经读入的 design object。它让 link 先能找到当前会话里的 RTL 子模块，而不是只去外部 `.db` 文件找。

4. 为什么推荐用 `set_app_var target_library`，而不是普通 `set target_library`？  
   答：`target_library` 是 DC application variable。`set_app_var` 明确修改工具变量；普通 `set` 可能只是 Tcl 变量，语义和作用范围不如 `set_app_var` 清楚。

5. `.lib` 和 `.db` 的关系是什么？  
   答：`.lib` 是 Liberty 文本库，可读，描述 cell/pin/timing/power 等信息；`.db` 是 Synopsys 工具常用二进制数据库格式，通常由 `.lib` 转换而来，供 DC 高效读取。

6. search_path 的好处和风险分别是什么？  
   答：好处是脚本可以少写路径，统一从指定目录查找文件；风险是多个目录有同名文件时，工具可能按搜索顺序读到非预期版本。

7. 为什么换 55nm 到 40nm 工艺库时，推荐从 original RTL 重新综合？  
   答：旧 gate-level netlist 已绑定旧库 cell，新库未必有同名/等价 cell。原始 RTL 是工艺无关描述，更适合作为新 target library 下重新 mapping 和 optimization 的起点。

8. 如果 DC 报 unresolved reference，优先检查哪些项？  
   答：检查子模块 RTL 是否读入、current_design 是否正确、link_library 是否包含 `*`、IP/macro 库是否加入、search_path 是否能找到相关文件。

## 练习与检查动作

为一个小模块建立最小 DC 目录：

```text
demo_synth/
├─ rtl/top.v
├─ cons/top.sdc
├─ libs/your_tech.db
├─ mapped/
└─ .synopsys_dc.setup
```

在 `.synopsys_dc.setup` 中写：

```tcl
set_app_var search_path ". ./rtl ./libs ./cons ./mapped"
set_app_var target_library "your_tech.db"
set_app_var link_library "* your_tech.db"
```

检查标准：

- 在 `dc_shell` 中 `pwd` 能确认 CWD 是 `demo_synth`。
- `printvar target_library` 和 `printvar link_library` 能看到预期库。
- `read_verilog top.v` 后 `link` 不报 unresolved reference。
- `compile_ultra` 后 `write -format verilog` 能在 `mapped/` 生成 mapped netlist。
- 如果故意删除 `*`，能解释为什么某些 RTL 子模块可能 link 失败。


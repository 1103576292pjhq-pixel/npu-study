# 任务107：Design and Library Objects

## 本章知识全景图

这一讲解决的是 DC memory 里“对象到底是什么”的问题。综合脚本不是在操作字符串，而是在操作带类型和属性的 design object：design、port、pin、net、cell、reference、instance、collection。理解这些对象，后面的约束命令才不会把同名的 port、net、pin、cell 搞混。

| 概念层级 | 核心概念 | 前置知识 | 延伸应用 |
|---|---|---|---|
| 层次对象 | design、reference、instance | Verilog module/instantiation | 解释 top、子模块和 IP 的关系 |
| 连接对象 | port、pin、net | module 端口、cell 引脚 | 写 input/output delay、load、fanout 约束 |
| 库对象 | leaf cell、library cell | target/link library | 区分 RTL 层次和标准单元层次 |
| 查询对象 | `get_ports`、`get_pins`、`get_cells`、`get_nets` | Tcl 命令、通配符 | 精准选择约束对象 |
| 集合对象 | collection、filter、attribute | Tcl list 概念 | 批量约束、排除 clock、遍历端口 |

最短学习路径：先用层次图分清 design、reference、instance，再用 port/pin/net 分清连接关系；随后掌握 `get_*` 命令如何给返回结果贴类型标签；最后学习 collection 的筛选、删除、遍历和属性查询。

![Design objects 总图](<./screenshots/任务107_Design_and_Library_Objects/task107_dense_0120s_00h02m00s.jpg>)

看图要点：这张总图先把 reference 和 instance 分开读。reference 是模板定义，instance 是模板在层次里的一个具体出现；后面的 `get_cells`、`get_references`、属性过滤都建立在这个区分上。

## 本课主线地图

| 时间 | 教学主线 | 本笔记吸收方式 |
|---|---|---|
| 00:23-10:21 | design、port、pin、net、cell、reference、instance、leaf cell | 重构为 DC 对象关系表 |
| 10:21-16:02 | 同名对象问题和 `get_*` 命令 | 写成约束对象选择原则 |
| 16:02-21:39 | 通配符、命令嵌套、collection 标签 | 展开为 Tcl/DC collection 模型 |
| 22:04-28:08 | `get_ports`、`get_pins`、`get_nets`、hierarchical 选项 | 建立 top 层和层次查询边界 |
| 29:14-34:42 | `all_inputs`、`all_outputs`、`all_clocks`、`all_registers` | 区分 all 类命令的全局性和成本 |
| 34:42-43:48 | collection 操作、filter、remove、attributes | 写成批量约束工作流 |

## 1. design 和 instance 都是相对层次说的

Design 不是固定指“整个芯片”，而是 DC memory 中一个可作为分析对象的设计单元。top module 可以是 design，子模块如果被单独作为 current design，也可以是 design。

同一个 RTL module 被例化后，会出现 reference 和 instance 两层含义：

```verilog
encoder u1 (...);
encoder u2 (...);
```

`encoder` 是 reference，是被引用的模块定义；`u1` 和 `u2` 是 instance，是这个 reference 在当前 design 中的两个具体实例。一个 reference 可以有多个 instance。

| 名称 | 回答的问题 | 例子 |
|---|---|---|
| design | 当前被 DC 操作的设计单元是谁 | `top`、`encoder` |
| reference | instance 来源于哪个 module/cell 定义 | `encoder`、`DFF_X1` |
| instance | 当前层次里具体哪一个例化对象 | `u1`、`u2`、`u_reg0` |

常见错觉：`u1` 也是一个 design。正确理解：`u1` 是 instance；它的 reference 可能是一个 design，也可能是 library cell。是否把 reference 当 design 分析，要看你当前站在哪个层次。

一个好用的直觉是：design 像一张电路图纸，reference 像图纸编号，instance 像这张图纸在现场被安装出来的某一台设备。两个 instance 可以来自同一张 reference 图纸，但它们在层次地址、连接关系和时序路径上是两个不同对象。

## 2. port、pin、net 是连接关系的三个切面

Port 是 design 边界上的输入输出；pin 是 instance/cell 上的引脚；net 是 port 和 pin、pin 和 pin 之间的连线。三者名字可能相同，但对象类型完全不同。

例如 top 的输出叫 `OUT1`，它连接的 net 也可能叫 `OUT1`。如果你写：

```tcl
set_load 3 OUT1
```

工具不知道你想给 port 设负载，还是给 net 设负载。正确写法要用 `get_*` 明确对象类型：

```tcl
set_load 3 [get_ports OUT1]
set_load 3 [get_nets OUT1]
```

区别不在字符串，而在 collection 上的类型标签。`[get_ports OUT1]` 返回的是 port collection；`[get_nets OUT1]` 返回的是 net collection。外层命令拿到带标签的对象后，才知道这条约束应该作用在哪里。

## 3. leaf cell 是层次树的最底层库单元

Cell 这个词容易混。层次设计里的子模块 instance 可以被宽泛地叫 cell；但 library cell 或 leaf cell 指的是不能再往下展开的标准单元或库单元，例如 `DFF_X1`、`INV_X1`、`NAND2_X1`。

![leaf cell 与层次对象](<./screenshots/任务107_Design_and_Library_Objects/task107_dense_0240s_00h04m00s.jpg>)

看图要点：leaf cell 图只负责澄清层次底边界：当对象已经落到标准单元或库单元时，继续向下展开就不再是 RTL 层次，而是 library pin、timing arc 和 cell model。

对综合来说，leaf cell 是 mapping 的落点。RTL 里的 `always @(posedge clk)` 经过综合后，可能变成某个库里的 DFF cell；组合逻辑可能变成一串 NAND/INV/BUF。到了 gate-level netlist，行为语句消失，剩下的是 library cell instance 和 net 连接。

### 3.1 Library objects 是标准件目录，不是设计层次本身

`Design and Library Objects` 里的 library objects 不能只理解成 leaf cell 的另一种叫法。设计对象描述“这个设计里有什么实例、端口、引脚和连线”；库对象描述“工艺库允许使用哪些标准件、每个标准件有什么引脚、延时弧、面积和功耗”。

| 对象族 | 典型对象 | 回答的问题 | 常见命令/属性 |
|---|---|---|---|
| design object | design、cell/instance、port、pin、net | 当前设计层次里有哪些具体对象 | `get_designs`、`get_cells`、`get_ports`、`get_pins`、`get_nets` |
| library object | library、lib_cell、lib_pin、timing arc、operating condition | 工艺库提供哪些标准单元和模型 | `get_libs`、`get_lib_cells`、`get_lib_pins`、`get_attribute ref_name` |
| 连接关系 | instance -> reference/lib_cell | 当前实例最终对应哪个模板或库单元 | `ref_name`、`is_sequential`、`dont_touch`、`area` |

这两族对象像“现场设备”和“标准件目录”。`U123` 是现场某个 DFF instance；`DFF_X1` 是目录里的标准件型号。名字可以相似，身份不能混。给 `U123` 加 `dont_touch` 是约束现场这个实例；查看 `DFF_X1` 的 pin/timing arc 是查询库里这个型号的行为模型。

一个最小确认动作：

```tcl
set regs [filter_collection [get_cells -hierarchical *] "is_sequential == true"]
foreach_in_collection r $regs {
  puts "[get_object_name $r]  ref=[get_attribute $r ref_name]"
}
```

输出里的左边是 design instance 名，右边 `ref_name` 才把它连到 library cell。写约束时若把这两层混掉，就会出现“对象查到了但属性不是你以为的那类”的问题。

## 4. `get_*` 命令的核心价值是消除对象歧义

`get_ports`、`get_pins`、`get_cells`、`get_nets` 不是为了让脚本变长，而是为了告诉 DC：我要的对象类型是什么。

![get 命令和对象类型](<./screenshots/任务107_Design_and_Library_Objects/task107_dense_0840s_00h14m00s.jpg>)

看这张命令图时要意识到：`get_ports/get_pins/get_cells/get_nets` 的价值不是少打字，而是把返回对象类型限定住。后续外层命令、过滤条件和属性查询，都是在这个类型基础上解释的。

常见形态：

```tcl
get_ports A
get_ports {A B C D}
get_ports Z*
get_ports Y??Z
get_pins U1/A
get_cells U*
get_nets data_*
```

通配符规则要记清：

| 通配符 | 含义 | 例子 |
|---|---|---|
| `*` | 任意长度字符串，也可以是 0 个字符 | `Z*` 匹配 `Z`、`Z1`、`Z_DATA` |
| `?` | 恰好一个字符 | `Y??Z` 只匹配中间两个字符的名字 |

命令嵌套用方括号：

```tcl
set_load 3 [get_ports OUT1]
```

方括号里的命令先执行，把返回的 collection 交给外层命令。后续复杂脚本可能嵌套多层，但原则不变：内层先求对象，外层对对象施加约束或操作。

如果对象类型选错，脚本可能不是立刻报错，而是“成功作用在错误对象上”。例如你想约束顶层输入 port，却用 `get_nets A` 拿到内部 net；report 里也许有对象名 `A`，但 input delay 并没有真正落到端口边界。这类错误最隐蔽，因为字符串看起来对，集合身份已经错。

## 5. collection 不是普通字符串列表，而是带类型和属性的对象集合

Collection 可以粗略类比成“贴了标签的 list”。普通 Tcl list 只是字符串序列；DC collection 里的每个元素带对象类型和属性，工具能知道它是 port、net、pin、cell，还是 register。

这个差异直接影响脚本写法。拿到 collection 后，如果想打印真实对象名，应使用：

```tcl
get_object_name [get_ports A]
```

不要直接把 collection 当字符串打印；很多时候你看到的只是内部句柄，不是人可读名字。

Collection 即使为空，也可能带类型标签。例如：

```tcl
set empty_ports [get_ports DOES_NOT_EXIST*]
```

它可能是一个空的 port collection。空集合不代表语法错；它可能用于后续条件追加、筛选或脚本分支判断。

## 6. 顶层查询和层次查询不能混用

默认情况下，`get_pins`、`get_cells`、`get_nets` 往往只返回当前层次可见对象；如果要查更深层的对象，需要使用 hierarchical 选项或显式层次路径。

```tcl
get_pins U1/*
get_pins -hierarchical */CLK
get_cells -hierarchical U*
get_nets U1/*
```

层次查询强大，但也更容易返回巨量对象。尤其在大设计中，`get_pins -hierarchical *` 或 `get_cells -hierarchical *` 可能生成非常大的 collection，既占内存，也让后续 filter 变慢。

原则是先限定层次，再限定类型，再限定属性：

```tcl
set u1_regs [filter_collection [get_cells -hierarchical U1/*] "is_sequential == true"]
```

这样比先拿全芯片所有 cell 再过滤更可控。

## 7. `all_*` 命令适合表达全局意图，但要注意返回规模

`all_inputs`、`all_outputs`、`all_clocks`、`all_registers` 是常见快捷命令。它们返回的是带标签的 collection，适合批量约束。

```tcl
set_input_delay 0.5 -clock [get_clocks CLK] [all_inputs]
set_output_delay 0.8 -clock [get_clocks CLK] [all_outputs]
set_clock_uncertainty 0.2 [all_clocks]
```

但这些命令不能无脑用。`all_registers` 可能返回当前 design 下所有层次里的寄存器，在大设计中数量很大。你只是想调试一个 block，却拿了全芯片所有 register，会让报告和脚本都变重。

更稳的写法是先缩小范围：

```tcl
set regs_in_u_dma [filter_collection [all_registers] "full_name =~ U_DMA/*"]
sizeof_collection $regs_in_u_dma
```

## 8. Collection 操作是批量约束的基础工具

真正的综合约束很少只作用在一个对象上。常见动作包括计数、遍历、添加、删除、按属性筛选。

| 操作 | 用途 | 示例 |
|---|---|---|
| `sizeof_collection` | 统计对象数量 | `sizeof_collection [all_registers]` |
| `foreach_in_collection` | 遍历 collection | 对每个 port 打印名字 |
| `add_to_collection` | 合并对象 | 把特殊端口加进集合 |
| `remove_from_collection` | 从集合删除对象 | 从 all_inputs 中删除 clock |
| `filter_collection` | 按属性筛选 | 找 `dont_touch == true` 的 cell |
| `list_attributes` | 查看可筛选属性 | 查 port/cell 有哪些属性 |

典型例子：给所有输入端口加 input delay，但排除 clock port。

```tcl
set data_inputs [remove_from_collection [all_inputs] [get_ports CLK]]
set_input_delay -max 0.6 -clock [get_clocks CLK] $data_inputs
```

如果不排除 clock，工具可能把 clock port 当普通 data input 约束，后续 timing 分析会被污染。

## 9. 属性筛选让脚本从“按名字猜”变成“按对象事实选”

按名字筛选很脆弱，因为命名风格会变。属性筛选更接近对象事实。

例如找所有 reference name 不以 `AN` 开头的 cell：

```tcl
set cells [get_cells *]
set selected [filter_collection $cells "ref_name !~ AN*"]
```

找 `dont_touch` 为 true 的 cell：

```tcl
get_cells -filter "dont_touch == true"
```

想知道 cell 或 port 有哪些属性，可以查：

```tcl
list_attributes -application -class cell
list_attributes -application -class port
```

这一步很实用。很多时候你不是不知道怎么写 filter，而是不知道对象上有哪些属性名。先查属性，再写 filter，脚本才不会靠猜。

## 本章收束与检查

### 本章最该记住的结论

- design、reference、instance 是层次关系；port、pin、net 是连接关系。
- 同名对象必须用 `get_ports`、`get_nets`、`get_pins` 等命令区分类型。
- collection 是带类型和属性的对象集合，不是普通字符串列表。
- `get_object_name` 用于把 collection 元素转换成人可读对象名。
- `all_*` 命令适合批量对象，但大设计中要控制范围。
- `remove_from_collection` 和 `filter_collection` 是写可靠约束脚本的基础。

### 复现清单

1. 用 `get_ports *`、`get_nets *` 分别查看同名 port/net 的返回差异。
2. 用 `get_pins U1/*` 和 `get_pins -hierarchical */CLK` 比较层次查询范围。
3. 用 `get_attribute [get_cells U1] ref_name` 确认 design instance 对应哪个 reference/lib_cell。
4. 用 `sizeof_collection [all_registers]` 观察全局 collection 大小。
5. 从 `[all_inputs]` 中用 `remove_from_collection` 删除 clock，再给数据输入加约束。
6. 用 `list_attributes -application -class cell` 查属性，再写 filter。

### 自测题

1. 为什么 `set_load 3 OUT1` 不是推荐写法？

   答：`OUT1` 可能同时是 port、net 或其他对象名。推荐写成 `set_load 3 [get_ports OUT1]` 或 `set_load 3 [get_nets OUT1]`，明确对象类型。

2. reference 和 instance 的区别是什么？

   答：reference 是被例化的定义，如 `encoder` 或 `DFF_X1`；instance 是当前层次中的具体例化名，如 `u1`、`u2`。

3. 为什么 collection 需要 `get_object_name` 才适合打印？

   答：collection 元素在 DC 内部可能以句柄形式存在，直接打印不一定是人可读对象名；`get_object_name` 会返回实际对象名。


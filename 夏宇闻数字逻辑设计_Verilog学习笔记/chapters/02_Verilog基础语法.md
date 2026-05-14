# 02 Verilog 基础语法：从“像 C”走到“能综合成硬件”

## 本章知识全景图

Verilog 语法不能按普通编程语言来学；每个语法点都要同时问三件事：它在仿真中怎么执行，它在综合中可能变成什么硬件，它最容易制造什么错误。

| 语法族 | 学习目标 | 工程后果 |
|---|---|---|
| module 与端口 | 建立硬件层次和接口 | 决定模块边界、例化关系、信号方向 |
| 常量、wire、reg、memory | 建立值、网络、过程变量和存储阵列 | 决定位宽、驱动、寄存器/RAM 推导 |
| 运算符和表达式 | 写组合计算和判断条件 | 决定面积、延迟、未知值传播 |
| 赋值和块语句 | 区分连续赋值、阻塞、非阻塞、顺序/并行过程 | 决定组合逻辑、寄存器、仿真调度 |
| if/case/循环 | 写选择、译码和重复结构 | 分支不完整会推导锁存器；循环可能不可综合 |
| initial/always | 写仿真入口和硬件过程块 | RTL 主线靠 always 表达组合/时序逻辑 |
| task/function/system task | 封装过程、计算和仿真辅助 | 需要区分可综合代码和 testbench 代码 |
| 预处理 | 宏、包含、时间尺度、条件编译 | 改变编译文本和仿真时间单位 |

最短路径：先会读模块和信号，再会写组合逻辑，再会写时序 always，最后再处理任务、系统任务和预处理。

## 1. module：Verilog 的最小硬件边界

`module` 不是 C 函数，而是一个会长期存在的硬件实体；每例化一次，就得到一份硬件结构或一份层次实例。

基本形式：

```verilog
module module_name(port1, port2, port3);
  input  port1;
  output port2;
  inout  port3;

  // declarations
  // continuous assignments
  // always / initial blocks
  // submodule instances
endmodule
```

最小组合逻辑例子：

```verilog
module and2(
  output y,
  input  a,
  input  b
);
  assign y = a & b;
endmodule
```

读一个模块时先看四件事：

1. 端口方向：`input`、`output`、`inout`。
2. 位宽：标量、向量、总线。
3. 内部信号：哪些是 `wire`，哪些在过程块中赋值。
4. 逻辑来源：`assign`、`always`、门级实例、子模块实例。

多个模块之间的关系是层次结构，不是函数调用栈。下面两个例化会产生两个独立实例：

```verilog
and2 u_and0(.y(y0), .a(a0), .b(b0));
and2 u_and1(.y(y1), .a(a1), .b(b1));
```

常见误用：

| 误用 | 后果 | 正确做法 |
|---|---|---|
| 以为 module 像函数一样“调用后返回” | 无法理解并行硬件实例 | 把 module 看作电路图中的一个模块 |
| 端口位宽不一致 | 截断、扩展、警告或功能错 | 每个端口显式写位宽 |
| 忘记分号或 `endmodule` | 语法错误影响后续解析 | 每条声明/语句边界清楚 |
| 输出端口没有驱动 | 仿真为 x/z，综合有未驱动警告 | 用 `assign`、always 或子模块驱动 |

## 2. 常量和数字：位宽是硬件的一部分

Verilog 数字常量的关键不是“数值是多少”，而是“多少位、什么进制、是否含未知/高阻”。

常用形式：

```verilog
<位宽>'<进制><数值>
```

例子：

```verilog
4'b1010      // 4 位二进制
8'hA5        // 8 位十六进制
12'd37       // 12 位十进制
1'bx         // 1 位未知
1'bz         // 1 位高阻
8'b1010_1100 // 下划线只提高可读性
```

进制标记：

| 标记 | 含义 |
|---|---|
| `b` | binary，二进制 |
| `o` | octal，八进制 |
| `d` | decimal，十进制 |
| `h` | hexadecimal，十六进制 |

`x` 表示未知值，`z` 表示高阻态。它们不是普通数字。`x` 常说明仿真中某个值未初始化、多驱动冲突或条件无法确定；`z` 常出现在三态总线或未驱动网络上。RTL 初学阶段不要随手用 `x` 修补逻辑，因为它可能在仿真里掩盖真实分支，也可能导致综合解释与你预期不同。

参数常量用于把硬编码数字变成可配置结构：

```verilog
module regfile #(parameter W = 8, parameter DEPTH = 16) (
  input  [W-1:0] din,
  output [W-1:0] dout
);
endmodule
```

常见误用：

- 不写位宽：`'hff`、`10` 这类常量可能按默认整数宽度参与表达式，导致截断或扩展。
- 混淆十进制和位宽：`8'd255` 是 8 位值，`8'd256` 会溢出截断。
- 用 `x` 当 don't-care：这在综合优化中可能有特殊含义，正式 RTL 要谨慎。

## 3. wire、reg、memory：不要被名字误导

`wire`、`reg`、`memory` 分别回答三个问题：谁驱动这个信号，它能不能在过程块里被赋值，它是不是可寻址的一组存储单元。

### 3.1 wire：网络和连接

`wire` 表示网络型数据，通常由连续赋值、门级实例或子模块输出驱动。

```verilog
wire a;
wire [7:0] data;

assign data = in0 & in1;
```

硬件含义：`wire` 更接近连线。它本身不保存状态，值来自驱动它的逻辑。如果没有驱动，仿真可能表现为高阻或未知；如果多个驱动冲突，可能产生不确定值。

### 3.2 reg：过程赋值变量，不一定是寄存器

`reg` 的名字很容易误导初学者。它表示该变量可以在 `always` 或 `initial` 过程块中被赋值，不保证一定综合成触发器。

组合逻辑中的 `reg`：

```verilog
reg y;

always @* begin
  y = a & b;
end
```

这里 `y` 如果每条路径都被赋值，综合结果是组合逻辑，不是触发器。

时序逻辑中的 `reg`：

```verilog
reg q;

always @(posedge clk) begin
  q <= d;
end
```

这里 `q` 在时钟边沿更新，综合为触发器。

判断口径：`reg` 是否成为寄存器，取决于它在哪种 always 块里、是否有时钟边沿、赋值是否覆盖所有组合路径。

### 3.3 memory：用 reg 数组描述存储

存储器写法：

```verilog
reg [7:0] mem [0:255]; // 256 个 8 位单元
```

`reg [7:0] a;` 是一个 8 位寄存器变量。`reg mem [7:0];` 是 8 个 1 位存储单元。二者不是同一个结构。

读写 memory 必须指定地址：

```verilog
mem[3] = 8'h00;
data   = mem[addr];
```

常见误用：

| 写法 | 问题 |
|---|---|
| `mem = 0;` | 不能把整个 memory 当普通向量直接整体赋值 |
| 地址越界 | 仿真和综合行为不可依赖 |
| 多写端口随便写 | RAM 推导依赖工具和结构，需明确端口和时序 |

## 4. 运算符：相似符号背后是硬件代价

Verilog 运算符看起来接近 C，但每个表达式都会变成某种组合逻辑或判断网络。

### 4.1 算术运算符

| 运算符 | 含义 | 硬件提醒 |
|---|---|---|
| `+` | 加法/正号 | 加法器，位宽越大延迟越长 |
| `-` | 减法/负号 | 减法器或补码加法 |
| `*` | 乘法 | 资源重，可能需要 DSP block 或流水线 |
| `/` | 除法 | 对综合不友好，常需专门结构 |
| `%` | 取模 | 非 2 的幂时硬件代价高 |

例子：

```verilog
assign {cout, sum} = a + b + cin;
```

左侧拼接 `{cout, sum}` 明确接收加法结果的进位和低位和。

### 4.2 位运算符与逻辑运算符

位运算逐位处理向量：

```verilog
assign y = a & b;
assign z = ~a;
```

逻辑运算把表达式当作真假条件：

```verilog
assign hit = valid && (addr == target);
```

区别：

| 表达式 | 结果含义 |
|---|---|
| `a & b` | 每一位分别与 |
| `a && b` | a 是否非零 且 b 是否非零 |

初学者最常把 `&` 和 `&&` 混用。写组合逻辑掩码通常用位运算；写条件判断通常用逻辑运算。

### 4.3 关系、等式和 case 等式

| 运算符 | 含义 |
|---|---|
| `>` `<` `>=` `<=` | 关系比较 |
| `==` `!=` | 逻辑等式，遇到 x/z 可能得到未知 |
| `===` `!==` | case 等式，x/z 也逐位比较 |

关键区别：

```verilog
if (a == 1'bx)  hit = 1'b1; // 通常不能可靠判断 a 是否为 x
if (a === 1'bx) hit = 1'b1; // 可以逐位匹配 x
```

`===` 和 `!==` 常用于 testbench 或需要明确识别 x/z 的仿真检查。可综合 RTL 中应谨慎使用。

### 4.4 移位、拼接、复制、缩减

移位：

```verilog
assign y = a << 2;
```

拼接：

```verilog
assign bus = {opcode, rd, rs};
```

复制：

```verilog
assign mask = {8{enable}};
```

缩减：

```verilog
assign parity = ^data; // data 所有位异或归约
assign all1   = &data; // data 所有位与归约
```

这些运算是 RTL 中非常常用的位级结构。NPU/CPU 里的指令字段拆分、符号扩展、掩码生成、奇偶校验都会用到。

### 4.5 优先级规则

不要依赖记忆优先级写复杂表达式。硬件代码的目标不是炫技，而是让读代码的人和综合工具都清楚。

推荐写法：

```verilog
assign hit = valid && ((addr & mask) == target);
```

而不是：

```verilog
assign hit = valid && addr & mask == target;
```

括号能减少误解，也能避免维护者改错。

## 5. 赋值：连续赋值、阻塞赋值、非阻塞赋值

赋值语句是 Verilog 最容易导致“仿真看起来对，硬件想错了”的部分。

### 5.1 连续赋值 `assign`

连续赋值驱动网络型信号，常用于组合逻辑：

```verilog
wire y;
assign y = (sel) ? a : b;
```

只要右侧输入变化，左侧网络就重新计算。它像一段永久存在的组合电路。

### 5.2 阻塞赋值 `=`

阻塞赋值在过程块中立即更新变量，下一条语句看到的是新值：

```verilog
always @* begin
  t = a & b;
  y = t | c;
end
```

组合逻辑过程块常用阻塞赋值，因为它表达“按顺序计算中间变量”，最后综合成组合网络。

### 5.3 非阻塞赋值 `<=`

非阻塞赋值在当前时间步末统一更新，适合描述时钟边沿的寄存器同时更新：

```verilog
always @(posedge clk) begin
  b <= a;
  c <= b;
end
```

这个例子综合为两个串联触发器。时钟到来后，`b` 取旧的 `a`，`c` 取旧的 `b`。

如果改成阻塞赋值：

```verilog
always @(posedge clk) begin
  b = a;
  c = b;
end
```

仿真中 `c` 可能立即看到新的 `b`，容易与想要的两级寄存器不一致。

实践规则：

| 场景 | 推荐赋值 |
|---|---|
| `assign` 连续组合逻辑 | `assign` |
| `always @*` 组合逻辑 | 阻塞赋值 `=` |
| `always @(posedge clk)` 时序逻辑 | 非阻塞赋值 `<=` |
| 同一个变量 | 不要在多个 always 块里赋值 |

第 7 章会更深入处理阻塞/非阻塞，本章先建立最低安全规则。

## 6. 块语句：begin/end 是顺序块，fork/join 是并行仿真块

`begin/end` 把多条语句组成一个顺序块：

```verilog
always @* begin
  t = a & b;
  y = t | c;
end
```

顺序块内部按语句顺序执行，但综合结果不一定是“一个接一个的硬件”。在组合 always 中，这通常只是组合表达式的计算顺序。

`fork/join` 表示并行过程：

```verilog
initial fork
  #10 a = 1'b1;
  #20 b = 1'b1;
join
```

它主要用于 testbench。可综合 RTL 初学阶段不要把 `fork/join` 当常规硬件并行写法。硬件并行更常通过多个 `assign`、多个 always 块或多个模块实例表达。

命名块可用于局部声明或控制块退出：

```verilog
begin : search_block
  integer i;
  // ...
end
```

常见误用：

- 在可综合 RTL 中用 `#10` 表达等待 10ns。
- 以为 `begin/end` 内所有赋值都会生成串行硬件。
- 用 `fork/join` 写设计逻辑，导致综合不可用或风格混乱。

硬件等待应写成时钟周期、计数器、握手或状态机。

## 7. 条件语句：if/case 的重点是覆盖所有硬件路径

条件语句的危险不在语法，而在漏掉某些输入组合时，硬件必须保持旧值，于是综合出锁存器。

### 7.1 if/else

形式：

```verilog
if (cond) begin
  y = a;
end else begin
  y = b;
end
```

组合逻辑安全写法：

```verilog
always @* begin
  if (sel) begin
    y = a;
  end else begin
    y = b;
  end
end
```

危险写法：

```verilog
always @* begin
  if (sel) y = a;
end
```

当 `sel == 0` 时，`y` 没有新赋值。为了让 `y` 保持旧值，综合工具可能推导锁存器。

更稳的组合逻辑风格：

```verilog
always @* begin
  y = b;          // 默认值
  if (sel) y = a; // 覆盖值
end
```

### 7.2 if 嵌套与 else 配对

`else` 总是与最近的未匹配 `if` 配对。复杂嵌套必须用 `begin/end` 明确范围。

```verilog
if (outer) begin
  if (inner) begin
    y = a;
  end
end else begin
  y = b;
end
```

没有清晰缩进和块边界，代码很容易和设计意图分离。

### 7.3 case/casez/casex

基本形式：

```verilog
always @* begin
  case (sel)
    2'b00: y = a;
    2'b01: y = b;
    2'b10: y = c;
    default: y = d;
  endcase
end
```

`case` 适合译码和多路选择。安全重点：

- 分支表达式位宽要匹配。
- 分支不要重复。
- 组合逻辑通常要有 `default`。
- 每个分支都要对输出完整赋值。

`casez` 把 `z` 或 `?` 当作无关项，常用于带 don't-care 的译码。`casex` 会把 `x` 也当无关项，风险更高，因为它可能掩盖未知值传播。现代 RTL 中一般更谨慎使用 `casex`。

锁存器风险：

```verilog
always @* begin
  case (sel)
    2'b00: y = a;
    2'b11: y = b;
  endcase
end
```

当 `sel` 为 `01` 或 `10` 时，`y` 没有赋值，可能推导锁存器。

修正：

```verilog
always @* begin
  case (sel)
    2'b00: y = a;
    2'b11: y = b;
    default: y = 1'b0;
  endcase
end
```

## 8. 循环语句：循环是“硬件展开”还是“仿真过程”

循环语句不能只按软件执行次数理解。可综合循环通常会被展开成重复硬件结构，或在明确时钟控制下变成多周期状态机。

| 语句 | 典型用途 | 综合提醒 |
|---|---|---|
| `forever` | testbench 时钟、无限激励 | 设计 RTL 中少用，常不可综合 |
| `repeat(n)` | testbench 重复激励 | n 固定时可用于有限过程，但要谨慎 |
| `while(cond)` | testbench 或抽象行为 | 运行期不定条件通常不适合综合 |
| `for(init; cond; step)` | 固定位宽批量逻辑、数组赋值 | 循环边界静态时常可综合 |

组合逻辑里的固定循环：

```verilog
integer i;
always @* begin
  for (i = 0; i < 8; i = i + 1) begin
    y[i] = a[i] & b[i];
  end
end
```

这通常会展开成 8 个与门。

testbench 时钟：

```verilog
initial begin
  clk = 1'b0;
  forever #5 clk = ~clk;
end
```

这段代码用于仿真，不是综合成硬件时钟发生器的通用方式。

判断标准：如果循环次数在综合时无法确定，或者循环依赖运行时条件无限等待，就要改写成 FSM、计数器或握手协议。

## 9. initial 和 always：过程块入口

`initial` 执行一次，`always` 反复执行；RTL 设计的主体通常在 `always` 里。

### 9.1 initial

`initial` 常用于 testbench 初始化、读文件、产生激励：

```verilog
initial begin
  rst_n = 1'b0;
  #20 rst_n = 1'b1;
end
```

在 FPGA 中，部分工具支持寄存器初值或 RAM 初始化；在 ASIC RTL 中，不应依赖 `initial` 完成复位设计。工程主线仍然应该写清 reset。

### 9.2 always 组合逻辑

推荐现代写法：

```verilog
always @* begin
  y = a & b;
end
```

`@*` 表示自动包含右侧敏感信号，减少漏写敏感列表导致的仿真错误。旧代码可能写成：

```verilog
always @(a or b) begin
  y = a & b;
end
```

### 9.3 always 时序逻辑

```verilog
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    q <= 1'b0;
  end else begin
    q <= d;
  end
end
```

这表示带异步低有效复位的触发器。第 7 章会进一步区分同步复位、异步复位、复位释放和状态机写法。

最小安全规则：

- 组合 always：敏感列表完整，分支完整，阻塞赋值。
- 时序 always：边沿触发，非阻塞赋值，复位策略清楚。
- 不要一个变量多处驱动。

## 10. task 和 function：封装不是模块例化

`task` 和 `function` 用来封装可复用过程，但它们不是硬件层次模块。

| 项 | function | task |
|---|---|---|
| 返回值 | 必须返回一个值 | 可以无返回值，可通过 output/inout 传出 |
| 时间控制 | 不应包含延时、事件等待 | 可以包含时间控制，常用于 testbench |
| 常见用途 | 组合计算、位处理、简单复用表达式 | 测试流程、复杂仿真动作 |
| 综合性 | 内容简单、无时间控制时常可综合 | 取决于内容；带延时/等待通常不可综合 |

function 例子：

```verilog
function [3:0] max4;
  input [3:0] a;
  input [3:0] b;
  begin
    if (a > b) max4 = a;
    else       max4 = b;
  end
endfunction
```

task 例子：

```verilog
task show_byte;
  input [7:0] data;
  begin
    $display("data=%h", data);
  end
endtask
```

第二个例子是仿真辅助，不是硬件功能。

常见误用：

- 用带 `#delay` 的 task 写设计逻辑。
- 把 function 当 module，希望它产生独立硬件实例。
- 在 function 中写会产生状态的行为。

如果你想表达层次硬件，用 `module`；如果你想复用纯组合计算，用 `function`；如果你想组织 testbench 操作，用 `task`。

## 11. 系统任务：大多属于仿真世界

系统任务和系统函数主要帮助仿真、调试、文件读写和随机激励。

| 系统任务/函数 | 用途 | 是否综合为硬件 |
|---|---|---|
| `$display`、`$write` | 打印信息 | 否 |
| `$monitor` | 信号变化时持续打印 | 否 |
| `$time` | 读取仿真时间 | 否 |
| `$finish` | 结束仿真 | 否 |
| `$stop` | 暂停仿真 | 否 |
| `$readmemb`、`$readmemh` | 从文件初始化存储 | 依工具和目标而定，常用于仿真/FPGA 初始化 |
| `$random` | 产生随机数 | testbench 常用，不作为普通硬件随机源 |

例子：

```verilog
initial begin
  $readmemh("rom.hex", mem);
end
```

这常用于仿真中加载 ROM/RAM 内容。FPGA 工具可能支持转成初始化文件；ASIC 设计不能想当然认为它会变成硬件文件系统。

调试输出：

```verilog
initial begin
  $display("start simulation");
  #100 $finish;
end
```

这属于 testbench，不属于可综合设计主体。

## 12. 编译预处理：改变送进工具的文本

预处理命令在编译前工作，它们不是运行时硬件逻辑。

### 12.1 `define`

```verilog
`define DATA_W 8

wire [`DATA_W-1:0] data;
```

宏是文本替换。简单常量更推荐用 `parameter/localparam`，因为参数属于 Verilog 语义，更容易被工具理解。

### 12.2 `include`

```verilog
`include "defs.vh"
```

用于包含共享定义。风险是路径、重复包含、宏污染。工程中要约定 include 目录和头文件职责。

### 12.3 `timescale`

```verilog
`timescale 1ns/1ps
```

前者是时间单位，后者是时间精度。它影响 `#5` 这类仿真延时的解释。不同文件 timescale 不一致，会让 testbench 行为难以排查。

### 12.4 条件编译

```verilog
`ifdef SIM
  initial $display("simulation only");
`endif
```

条件编译常用于区分仿真代码、调试代码和特定平台代码。风险是同一份 RTL 在不同宏配置下变成不同设计，必须让构建脚本和文档记录宏配置。

## 13. 语法到硬件的总判断表

| 语法 | 主要用途 | 硬件/仿真边界 |
|---|---|---|
| `module` | 硬件层次 | 例化产生结构，不是函数调用 |
| `assign` | 连续组合逻辑 | 驱动 net/wire |
| `always @*` | 组合过程 | 分支必须完整 |
| `always @(posedge clk)` | 时序过程 | 用非阻塞赋值表达寄存器更新 |
| `initial` | 仿真初始化 | ASIC RTL 不依赖它复位 |
| `if/case` | 条件和译码 | 漏分支会推导锁存器 |
| `for` | 固定重复结构 | 静态边界可综合，动态等待改 FSM |
| `task` | 过程封装 | testbench 常用，设计中谨慎 |
| `function` | 组合计算复用 | 不写时间控制 |
| `$display` 等 | 仿真观测 | 不生成业务硬件 |
| `` `define`` | 文本宏 | 优先用参数表达硬件配置 |

## 14. 本章最小可综合模板

组合逻辑模板：

```verilog
module mux2(
  output reg y,
  input      sel,
  input      a,
  input      b
);
  always @* begin
    if (sel) y = a;
    else     y = b;
  end
endmodule
```

时序逻辑模板：

```verilog
module dff(
  output reg q,
  input      clk,
  input      rst_n,
  input      d
);
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) q <= 1'b0;
    else        q <= d;
  end
endmodule
```

组合 + 时序分离模板：

```verilog
module counter_en(
  output reg [3:0] count,
  input            clk,
  input            rst_n,
  input            en
);
  reg [3:0] next_count;

  always @* begin
    next_count = count;
    if (en) next_count = count + 4'd1;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) count <= 4'd0;
    else        count <= next_count;
  end
endmodule
```

这个模板体现了第 3 章最重要的语法边界：组合逻辑负责算下一步，时序逻辑负责在时钟边沿保存状态。

## 15. 常见错误总表

| 错误 | 典型代码气味 | 修正 |
|---|---|---|
| 组合逻辑漏赋值 | `always @* if(sel) y=a;` | 写默认值或完整 else |
| 时序逻辑用阻塞赋值 | `always @(posedge clk) q = d;` | 寄存器更新用 `<=` |
| 敏感列表漏信号 | `always @(a) y=a&b;` | 用 `always @*` |
| 多 always 驱动同一 reg | 两个块都写 `q <= ...` | 一个状态寄存器只在一个时序块赋值 |
| 把仿真任务写进设计 | `$display`、`#10` 在设计主体里 | 移到 testbench 或改成 RTL 控制 |
| 位宽随意 | 常量不写宽度、端口宽度不匹配 | 显式位宽、检查综合警告 |
| 滥用 `casex` | x 被当作 don't-care | 优先 case/casez，明确 default |
| 把 reg 当触发器同义词 | 组合块里的 reg 也以为是寄存器 | 看赋值所在过程和触发条件 |

## 16. 自测题

1. 为什么说 `reg` 不一定综合成寄存器？分别写出组合逻辑和时序逻辑里的例子。
2. `assign y = a & b;` 和 `always @* y = a & b;` 都能表示组合逻辑，它们的左侧信号类型有什么区别？
3. 用一句话说明阻塞赋值和非阻塞赋值的仿真调度差别。
4. 为什么不完整的 `if` 或缺少 `default` 的 `case` 可能推导锁存器？
5. `case`、`casez`、`casex` 的风险等级为什么不同？
6. `initial $readmemh(...)` 在 testbench、FPGA、ASIC 三种语境下分别应如何看待？
7. 把一个运行期不定次数的 `while` 循环改成硬件，你会用什么结构？
8. 写一个 4 位计数器，并说明哪段是组合逻辑，哪段是时序逻辑。

答案检查口径：

- 能把语法形式、仿真语义、综合后果分开说。
- 能主动检查位宽、分支覆盖、敏感列表和赋值方式。
- 能区分设计主体和 testbench。
- 能把“等待”和“循环”改写成时钟、计数器、握手或 FSM。

# 06 FSM 与可综合 Verilog 风格：把“下一拍做什么”写成可靠硬件

## 本章知识全景图

RTL 设计不是把 C 程序翻译成 Verilog，而是把“当前状态、输入条件、下一拍动作、输出控制”写成综合器能稳定识别的寄存器和组合逻辑。

| 学习块 | 核心问题 | 工程判断 |
|---|---|---|
| FSM 基本模型 | 状态是什么，什么时候改变 | 状态只应在时钟边沿更新 |
| 状态编码 | 用几位寄存器表示状态 | FPGA 常偏好 one-hot，面积紧张时考虑二进制/Gray |
| 可综合子集 | 哪些 Verilog 写法能变成硬件 | 写法必须同时满足仿真语义和综合器识别规则 |
| 复位策略 | 上电或异常后状态机回到哪里 | 主 FSM 必须有明确复位和非法状态恢复口径 |
| 锁存器风险 | 组合逻辑为什么会“记住旧值” | 纯组合块要给所有输出完整赋值 |
| 阻塞/非阻塞赋值 | `=` 和 `<=` 为什么会改仿真结果 | 组合逻辑用 `=`，时序逻辑用 `<=` |
| 复杂控制器 | 多阶段协议怎么写 | 把协议步骤拆成主 FSM 和子 FSM，并做前后仿真 |

最短路径：先把 FSM 看成“状态寄存器 + 下一状态组合逻辑 + 输出逻辑”，再掌握可综合 always 块和复位样板，最后用阻塞/非阻塞规则保证综合前后仿真一致。

## 1. FSM 是状态寄存器和组合逻辑的配合

有限状态机的本质是：用寄存器保存“现在走到哪一步”，用组合逻辑根据“当前状态 + 输入”算出“下一步去哪、这一拍输出什么”。

```text
           input
             |
             v
current_state ---> [next-state / output logic] ---> next_state
      ^                                           |
      |                                           v
      +----------- state register <---- clock edge
```

状态机有两个常见输出模型：

| 类型 | 输出取决于 | 直观含义 | 风险点 |
|---|---|---|---|
| Moore | 当前状态 | 到了某个状态就输出某个控制信号 | 输出通常晚一拍，但波形稳定 |
| Mealy | 当前状态 + 当前输入 | 输入满足条件时立即输出 | 输出可能受输入毛刺影响，必要时寄存 |

初学 RTL 时，优先把状态更新写成同步逻辑，把下一状态和输出写成组合逻辑；遇到 Mealy 输出时，要额外判断它是否直接控制寄存器写使能、总线三态或跨模块握手。如果直接控制关键时序，通常要寄存一拍或保证输入已经同步。

## 2. 同一个四状态 FSM 可以有多种写法

一个四状态控制器可以包含 `IDLE`、`START`、`STOP`、`CLEAR` 四个状态，输入为 `A` 和 `reset`，输出为 `F`、`G`。核心转移关系可以抽象成：

| 当前状态 | 条件 | 下一状态 | 输出含义 |
|---|---|---|---|
| `IDLE` | `A=1` | `START` | 开始一次流程 |
| `START` | `A=0` | `STOP` | 进入停止判断 |
| `STOP` | `A=1` | `CLEAR` | 产生 `F` |
| `CLEAR` | `A=0` | `IDLE` | 产生 `G` 并回到空闲 |

同一张状态图至少可以写成四种 Verilog 风格。

| 写法 | 结构 | 优点 | 主要风险 |
|---|---|---|---|
| 单 always 块，二进制/Gray 编码 | 状态寄存器、转移、部分输出写在同一个边沿块 | 小状态机紧凑 | 状态和输出混在一起，复杂后难检查 |
| 单 always 块，one-hot 编码 | 每个状态一个触发器位 | FPGA 译码简单，速度常更好 | 需要处理多余状态和非法 one-hot |
| 状态寄存器 + 连续赋值 | `state` 用边沿块，`next_state/F/G` 用 `assign` | 状态存储和组合决策分开 | 复杂条件用三目表达式会难读 |
| 状态寄存器 + 组合 always | `state <= next_state`，组合块算 `next_state` 和输出 | 最常用、最适合扩展 | 组合块缺省赋值不完整会推锁存器 |

推荐初学者掌握这种两段式骨架：

```verilog
localparam IDLE  = 2'b00;
localparam START = 2'b01;
localparam STOP  = 2'b10;
localparam CLEAR = 2'b11;

reg [1:0] state, next_state;
reg f, g;

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) state <= IDLE;
  else        state <= next_state;
end

always @* begin
  next_state = state;
  f = 1'b0;
  g = 1'b0;

  case (state)
    IDLE: begin
      if (a) next_state = START;
    end

    START: begin
      if (!a) next_state = STOP;
    end

    STOP: begin
      if (a) begin
        next_state = CLEAR;
        f = 1'b1;
      end
    end

    CLEAR: begin
      if (!a) begin
        next_state = IDLE;
        g = 1'b1;
      end
    end

    default: begin
      next_state = IDLE;
    end
  endcase
end
```

这个骨架把职责分开：

1. 第一个 `always` 只描述触发器：复位时进 `IDLE`，否则在时钟边沿装载 `next_state`。
2. 第二个 `always @*` 只描述组合决策：默认保持当前状态，默认输出为 0，再按状态覆盖。
3. 每个输出都有默认值，避免“某个分支没赋值就记住旧值”的隐含锁存器。

如果要把输出也寄存起来，可以增加一个输出寄存器块，或把输出更新放在状态寄存器块里。选择取决于控制信号是否允许组合毛刺、是否需要和状态同拍对齐。

## 3. 设计 FSM 的步骤不是画图，而是关闭状态空间

FSM 设计的真正任务是把一个时序问题的所有可能情况收进有限状态空间。

| 步骤 | 要回答的问题 | 产物 |
|---|---|---|
| 逻辑抽象 | 输入条件是什么，输出动作是什么 | 输入/输出信号表 |
| 状态定义 | 哪些历史信息必须记住 | 状态集合 |
| 状态转移 | 每个状态遇到每类输入后去哪里 | 状态图或状态表 |
| 状态化简 | 哪些状态等价，可以合并 | 更少的状态 |
| 状态编码 | 每个状态用哪些比特表示 | `localparam` / `parameter` |
| 输出策略 | 输出随状态，还是随状态和输入 | Moore/Mealy 决策 |
| 复位与非法状态 | 上电、异常、非法码怎么处理 | 复位分支和 `default` |
| 仿真验证 | 典型、边界、非法路径是否覆盖 | testbench 和波形 |

在 Verilog 中，传统手工逻辑化简、触发器类型选择、驱动方程推导不再是主工作。综合器会把状态表映射成触发器和组合逻辑。设计者的责任变成三件事：

1. 状态空间不能漏。
2. 时序边界不能乱。
3. 仿真语义不能和综合后硬件背离。

## 4. 状态编码、default 和非法状态恢复

状态编码不是纯语法问题，它会影响译码复杂度、触发器数量、速度和非法状态处理。

| 编码 | 特点 | 适合场景 | 注意 |
|---|---|---|---|
| 二进制编码 | `N` 个状态约需 `ceil(log2(N))` 位 | 触发器资源紧张，状态较多 | 译码组合逻辑可能更深 |
| Gray 编码 | 相邻状态只变 1 位 | 顺序路径强、希望减少跳变 | 不是所有 FSM 都天然相邻 |
| one-hot 编码 | 一个状态对应一个置 1 位 | FPGA、速度优先、状态数中等 | 多余非法码多，必须处理恢复 |

one-hot 在 FPGA 中常有优势，因为 FPGA 触发器资源相对充足，而 LUT 译码可以变浅。代价是状态寄存器位数更多，并且可能出现多个 bit 同时为 1 或全 0 的非法状态。

`default` 的工程含义要分历史写法和现代写法看：

| 写法 | 含义 | 风险 |
|---|---|---|
| `default: next_state = 'bx;` | 把非法状态交给综合器当 don't care，可能得到更小逻辑 | 前仿真会出现 `x`，且可能掩盖非法状态恢复问题 |
| `default: next_state = IDLE;` | 任何未列状态都回到安全状态 | 逻辑可能略多，但安全性和调试更直接 |
| SystemVerilog `unique case` + assertion | 告诉工具状态应唯一，并用断言抓非法状态 | 需要工具和验证流程支持 |

零基础写可综合 RTL 时，推荐优先使用安全恢复：

```verilog
default: begin
  next_state = IDLE;
end
```

如果为了面积或速度故意用 don't-care，需要有仿真、门级仿真、断言或形式验证支撑，不能只因为“综合器能优化”就把非法状态恢复省掉。

还要谨慎使用 `casex`。`casex` 会把 `x` 和 `z` 当成通配符，控制 FSM 时可能把未知状态误匹配成合法状态。现代 RTL 中更常见的选择是：

- 普通 `case`：状态必须精确匹配。
- `casez`：只在明确需要把 `z` 或 `?` 当通配符时使用。
- SystemVerilog `unique case` / `priority case`：把意图交给工具检查。

宇宙飞船控制器例子可以压缩成一个典型控制器模式：`HOLD` 等待 `all_systems_go`，`SEQUENCE` 等倒计时归零，`LAUNCH` 产生发射输出，`ON_MISSION` 保持任务状态，`LAND` 产生降落输出；`abort_mission` 作为异常输入把流程拉向降落。这个例子训练三件事：先给所有输出缺省值，再按状态覆盖；把“当前状态”和“下一状态”分开；异常路径必须能从任何主流程阶段接管控制。

## 5. 复位策略：先确定“硬件从哪里开始”

复位不是装饰代码，而是状态机能否从上电和异常中回到有效状态的入口。

异步复位：复位信号一来，不等时钟边沿，触发器立即复位。

```verilog
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) q <= 1'b0;
  else        q <= d;
end
```

同步复位：复位信号只在时钟有效边沿被采样。

```verilog
always @(posedge clk) begin
  if (!rst_n) q <= 1'b0;
  else        q <= d;
end
```

两者差别：

| 对比项 | 异步复位 | 同步复位 |
|---|---|---|
| 响应时刻 | 复位信号有效即响应 | 等时钟边沿 |
| always 敏感表 | 包含时钟和复位边沿 | 只包含时钟边沿 |
| 优点 | 上电或时钟未稳定时也能拉住状态 | 时序关系更统一 |
| 风险 | 复位释放可能造成亚稳或不同触发器释放不同步 | 时钟不运行时无法复位 |

工程上常用“异步拉低、同步释放”的复位同步器，保证复位进入时足够快，释放时和时钟对齐。初学阶段至少要做到：

1. 一个时序块只有一个主时钟。
2. 复位极性命名清楚，例如低有效写 `rst_n`。
3. 复位分支覆盖所有状态寄存器和关键输出寄存器。
4. 不要在同一个模块里混用多套互相打架的复位风格。
5. 如果有 `set` 和 `reset`，明确优先级，通常先处理 reset。

## 6. always 块规则和锁存器风险

`always` 块能写组合逻辑、时序逻辑，也能写锁存器。问题在于：综合器不会猜你的本意，它只按代码需要生成硬件。

| 写法 | 硬件含义 | 推荐程度 |
|---|---|---|
| `always @(posedge clk)` | 边沿触发寄存器 | 时序逻辑默认写法 |
| `always @(posedge clk or negedge rst_n)` | 带异步复位的寄存器 | 常用，但释放要注意同步 |
| `always @*` | 组合逻辑 | 组合逻辑推荐写法 |
| `always @(a or b or c)` | 旧式手写敏感列表组合逻辑 | 容易漏信号，现代优先用 `@*` |
| `always @(enable or d)` 且不完整赋值 | 透明锁存器或仿真/综合不一致 | 只有明确要 latch 才写 |

纯组合块的最低安全模板：

```verilog
always @* begin
  y = 1'b0;
  next_state = state;

  case (state)
    IDLE: if (start) next_state = BUSY;
    BUSY: begin
      y = 1'b1;
      if (done) next_state = IDLE;
    end
    default: next_state = IDLE;
  endcase
end
```

锁存器通常来自“不完整赋值”。例如：

```verilog
always @* begin
  if (en) q = d;
end
```

当 `en=0` 时，`q` 没有新值。为了保持旧值，综合器只能生成电平敏感锁存器。正确的纯组合写法要补全分支：

```verilog
always @* begin
  if (en) q_next = d;
  else    q_next = 1'b0;
end
```

如果本来就要“使能为 0 时保持旧值”，应该把它写成触发器：

```verilog
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) q <= 1'b0;
  else if (en) q <= d;
end
```

还有一个硬规则：一个 `reg` 或 `integer` 变量只能有一个过程赋值所有者。两个 `always` 块同时给同一个寄存器赋值，综合后可能变成多驱动，仿真还会出现竞争。

```verilog
// 错误：q 有两个过程驱动源
always @(posedge clk) q <= d1;
always @(posedge clk) q <= d2;
```

## 7. 可综合模块样板：组合、时序、锁存器和三态

本章列出大量小模块，重点不是背代码，而是识别哪些写法综合成哪类硬件。

### 7.1 组合逻辑样板

| 模块 | 典型写法 | 综合出来的硬件 | 判断点 |
|---|---|---|---|
| 8 位加法器 | `assign {cout, sum} = a + b + cin;` | 加法器 | 位宽和进位必须明确 |
| ALU 译码 | `case (opcode)` | 运算选择器 + 算术/逻辑单元 | `default` 必须处理 |
| 比较器 | `assign equal = (a == b);` | 比较逻辑 | `==` 用于二值综合，仿真 `x` 要谨慎 |
| 3-8 译码器 | `assign out = 8'b1 << in;` | 左移译码逻辑 | 输出位宽要够 |
| 优先编码器 | `if/else if` 或条件表达式链 | 优先选择逻辑 | 优先级必须符合需求 |
| 多路器 | 三目、`case`、`if/else` | mux | 分支互斥时逻辑更清晰 |
| 奇偶校验 | `^input_bus` | 归约异或树 | 位宽越大，组合路径越长 |
| 三态输出 | `assign out = en ? in : 1'bz;` | 三态驱动或 mux | 现代 FPGA 内部三态多被综合成 mux |
| 双向端口 | `inout` + 三态控制 | 顶层 I/O 三态 | 内部总线不要滥用 `z` |
| task 排序组合逻辑 | 固定次数 task 调用 | 组合比较交换网络 | task 不能含不可综合延迟和非静态循环 |

组合逻辑写法的核心规则：

```verilog
always @* begin
  out = 8'h00;
  case (opcode)
    3'd0: out = a + b;
    3'd1: out = a - b;
    3'd2: out = a & b;
    3'd3: out = a | b;
    3'd4: out = ~a;
    default: out = 8'hxx;
  endcase
end
```

`default: out = 8'hxx` 在仿真中暴露未知分支，在综合中可能帮助优化。真正交付工程时，要根据安全需求决定是输出 `x`、输出安全值，还是触发断言。

### 7.2 时序逻辑样板

| 模块 | 本质 | 推荐写法 |
|---|---|---|
| D 触发器 | 时钟边沿采样 `d` | `always @(posedge clk) q <= d;` |
| 锁存器 | 使能有效时透明，否则保持旧值 | 只有明确需要 latch 才写 |
| 移位寄存器 | 每拍把数据推向下一位/下一级 | 时序块中用 `<=` |
| 计数器 | 当前计数值加一或装载 | 状态寄存器 + 组合下一值 |
| 预计算计数器 | 组合块算 `preout/cout`，时序块装载 `preout` | 组合/时序分离 |

移位寄存器应这样写：

```verilog
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) dout <= 8'b0;
  else        dout <= {dout[6:0], din};
end
```

如果写成阻塞赋值：

```verilog
q1 = d;
q2 = q1;
q3 = q2;
```

在同一个时钟边沿的仿真语义下，`q2` 会立刻看到新的 `q1`，`q3` 会立刻看到新的 `q2`，三段流水可能被压成一段。这就是阻塞/非阻塞规则必须掌握的原因。

## 8. 阻塞赋值和非阻塞赋值：不是风格偏好，是仿真调度问题

`=` 和 `<=` 的差别不在“能不能综合”，而在“仿真器什么时候更新左值”。同一段代码可能综合成你想要的硬件，却在前仿真中给出另一种行为。

### 8.1 阻塞赋值 `=`

阻塞赋值可以理解成过程内立即执行：

```verilog
a = b;
c = a;
```

第二句看到的是第一句更新后的 `a`。在组合逻辑中，这正好适合表达“先算临时值，再算输出”：

```verilog
always @* begin
  t1 = a & b;
  t2 = c & d;
  y  = t1 | t2;
end
```

但在时序逻辑中，如果多个寄存器应该在同一个时钟边沿同时更新，阻塞赋值会把“同时更新”伪装成“按语句顺序更新”。

### 8.2 非阻塞赋值 `<=`

非阻塞赋值分两步：

1. 在当前仿真时刻开始时计算 RHS。
2. 在当前仿真时刻结束时统一更新 LHS。

因此：

```verilog
q1 <= d;
q2 <= q1;
q3 <= q2;
```

三条语句都先读取旧值，然后在同一个时钟时刻结束时更新。它表达的正是三个触发器并行采样：

```text
d -> q1 -> q2 -> q3
```

可以把 Verilog 同一仿真时刻内的常用队列理解成：

| 队列 | 典型事件 | 对赋值的影响 |
|---|---|---|
| 活动事件队列 | 阻塞赋值、连续赋值、计算非阻塞 RHS、`$display` | 这里读到的是当前尚未被 NBA 更新的值 |
| 非阻塞更新队列 | 更新非阻塞 LHS | 本时刻末尾统一写入寄存器变量 |
| 监控队列 | `$monitor`、`$strobe` | 能看到非阻塞更新后的值 |
| `#0` 停止运行队列 | `#0` 延迟赋值 | 只是换队列，不是可靠消除竞争的方法 |

### 8.3 反馈振荡器为什么会 race

两个边沿块用阻塞赋值互相读写：

```verilog
always @(posedge clk or posedge rst)
  if (rst) y1 = 0;
  else     y1 = y2;

always @(posedge clk or posedge rst)
  if (rst) y2 = 1;
  else     y2 = y1;
```

两个 `always` 块是并行进事件队列的，仿真器不保证哪个先执行。如果第一个先执行，`y1` 可能先拿到旧/新 `y2`；如果第二个先执行，结果可能反过来。代码行为依赖调度顺序，就是 race。

改成非阻塞后：

```verilog
always @(posedge clk or posedge rst)
  if (rst) y1 <= 0;
  else     y1 <= y2;

always @(posedge clk or posedge rst)
  if (rst) y2 <= 1;
  else     y2 <= y1;
```

两个块都先读旧值，最后一起更新。执行先后不再改变结果。

### 8.4 移位寄存器的四类写法

| 写法 | 代码形态 | 前仿真 | 综合意图 | 结论 |
|---|---|---|---|---|
| 一个时序块内正向阻塞 | `q1=d; q2=q1; q3=q2;` | `d` 同拍穿到 `q3` | 可能不是三段寄存器 | 错 |
| 一个时序块内反向阻塞 | `q3=q2; q2=q1; q1=d;` | 看似正确 | 可综合 | 依赖语句顺序，不推荐 |
| 多个时序块阻塞 | 三个 `always @(posedge clk)` 分别赋值 | 执行顺序不定 | 可能综合成寄存器链 | 前后仿真可能不一致 |
| 非阻塞 | `q1<=d; q2<=q1; q3<=q2;` | 正确 | 正确 | 推荐 |

判断句：只要你想表达“这些寄存器在同一个边沿同时采样”，就用非阻塞赋值。

### 8.5 LFSR 反馈为什么更适合非阻塞

LFSR 这类反馈时序逻辑中，下一拍的某一位来自旧状态的异或，例如：

```verilog
wire fb = q1 ^ q3;

always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    q3 <= 1'b1;
    q2 <= 1'b1;
    q1 <= 1'b1;
  end else begin
    q3 <= q2;
    q2 <= fb;
    q1 <= q3;
  end
end
```

如果用阻塞赋值，`q1 = q3` 读到的是不是旧 `q3`，取决于前面是否已经改写了 `q3`。复杂反馈一旦靠语句顺序维持，就很难检查和维护。

### 8.6 组合逻辑为什么反而推荐阻塞赋值

组合逻辑没有“下一拍同时采样”的概念。它要表达的是当前输入经过多层逻辑得到当前输出。

错误倾向：

```verilog
always @* begin
  tmp1 <= a & b;
  tmp2 <= c & d;
  y    <= tmp1 | tmp2;
end
```

`y` 在本轮计算中读到的是旧的 `tmp1/tmp2`，不是刚算出的值。即使用额外敏感项让它再次触发，也会降低仿真效率并制造理解负担。

推荐：

```verilog
always @* begin
  tmp1 = a & b;
  tmp2 = c & d;
  y    = tmp1 | tmp2;
end
```

### 8.7 八条赋值规则

| 规则 | 为什么 |
|---|---|
| 时序电路用非阻塞 `<=` | 模拟触发器同边沿并行采样 |
| 锁存器建模用非阻塞 `<=` | 避免透明保持路径和其他过程交叉时产生 race |
| 组合 always 用阻塞 `=` | 临时变量和输出应在同一组合传播中立即可见 |
| 同一 always 同时写组合和时序时按时序处理，用 `<=` | 这个块的本质是边沿触发 |
| 同一 always 不混用 `=` 和 `<=` | 除非非常清楚调度，否则检查困难 |
| 不要多个 always 写同一个变量 | 多驱动和竞争会让仿真/综合不一致 |
| 看非阻塞更新后的值用 `$strobe` | `$display` 发生在非阻塞 LHS 更新前 |
| 不用 `#0` 解决竞争 | `#0` 只是换事件队列，不能修复所有权和时序设计错误 |

同一个过程块里，如果对同一个变量连续写多次非阻塞赋值，最后一次赋值决定该仿真时刻结束后的值：

```verilog
always @(posedge clk) begin
  q <= 1'b0;
  if (load) q <= d;
end
```

这类写法常用于“默认值 + 条件覆盖”。它只适合在同一个过程块内表达优先级；不能扩展成多个 `always` 块分别写同一个 `q`。

`$display`、`$monitor`、`$strobe` 的差别可以记成：

| 系统任务 | 观察时刻 | 用途 |
|---|---|---|
| `$display` | 当前活动事件队列中立即显示 | 看阻塞赋值或当前旧值 |
| `$monitor` | 仿真步结束后监控变化 | 持续观察 |
| `$strobe` | 当前仿真时刻所有赋值完成后显示 | 看非阻塞最终更新值 |

## 9. 序列检测器：从码流识别到状态转移

序列检测器要在输入码流中发现指定序列 `10010`。输入 `x` 每拍进入一位，输出 `z=1` 表示“这一拍刚好识别到序列”。

示例码流中可以出现重叠检测。例如第一次检测的后两位可能成为第二次检测的前两位。状态机不能检测完就简单回到空闲，否则会漏掉重叠序列。

一种状态含义：

| 状态 | 已经匹配到的有效后缀 | 输入 `0` 后 | 输入 `1` 后 |
|---|---|---|---|
| `IDLE` | 无 | `IDLE` | `A` |
| `A` | `1` | `B` | `A` |
| `B` | `10` | `C` | `F` |
| `C` | `100` | `G` | `D` |
| `D` | `1001` | `E` 且 `z=1` | `A` |
| `E` | 检出后保留重叠后缀 | `C` | `A` |
| `F` | 另一路重叠后缀 | `B` | `A` |
| `G` | 另一路重叠后缀 | `G` | `F` |

输出可以写成 Mealy 形式：

```verilog
assign z = (state == D) && (x == 1'b0);
```

状态更新仍然用同步寄存器：

```verilog
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) state <= IDLE;
  else        state <= next_state;
end
```

下一状态用组合块写完整：

```verilog
always @* begin
  next_state = state;

  case (state)
    IDLE: next_state = x ? A : IDLE;
    A:    next_state = x ? A : B;
    B:    next_state = x ? F : C;
    C:    next_state = x ? D : G;
    D:    next_state = x ? A : E;
    E:    next_state = x ? A : C;
    F:    next_state = x ? A : B;
    G:    next_state = x ? F : G;
    default: next_state = IDLE;
  endcase
end
```

这个例子的训练价值在于：状态不是“程序执行到第几行”，而是“为了判断下一位，必须记住的历史后缀”。这也是很多协议解析器、包头检测器、神经网络加速器命令流解析器的共同模式。

## 10. EEPROM 读写器：复杂控制器要拆成主 FSM 和子 FSM

串行 EEPROM 控制器的价值不在于背完整代码，而在于学会把协议步骤拆成可综合的嵌套状态机。

### 10.1 先分清三类模块

| 模块 | 角色 | 是否要求可综合 |
|---|---|---|
| EEPROM 行为模型 | 模拟外部芯片怎样响应 SCL/SDA | 不要求，可用延迟、事件等待、显示任务 |
| EEPROM 读写控制器 | 真正要放进 FPGA/ASIC 的硬件 | 必须可综合 |
| 测试信号源 | 产生读写请求、地址、数据并检查结果 | 不要求可综合 |

这条边界很关键。验证环境可以写得像“脚本”，真实控制器必须写成寄存器、组合逻辑、三态 I/O 和 FSM。

### 10.2 I2C/二线制 EEPROM 的控制动作

读写控制器至少要处理这些总线动作：

| 动作 | SCL/SDA 关系 | 控制意义 |
|---|---|---|
| 总线空闲 | SCL 高，SDA 高 | 可以开始传输 |
| START | SCL 高时 SDA 由高到低 | 一次传输开始 |
| 数据位有效 | SCL 高期间 SDA 稳定 | 接收端采样数据 |
| 数据改变 | SCL 低期间改变 SDA | 为下一位准备 |
| ACK/NACK | 第 9 个时钟位 | 接收端应答 |
| STOP | SCL 高时 SDA 由低到高 | 一次传输结束 |

写一个字节的大致帧：

```text
START -> control byte(write) -> ACK -> address byte -> ACK -> data byte -> ACK -> STOP
```

读指定地址的大致帧：

```text
START -> control byte(write) -> ACK -> address byte -> ACK
      -> repeated START -> control byte(read) -> ACK -> data byte -> NACK -> STOP
```

### 10.3 可综合控制器的拆分方式

复杂控制器可以拆成：

| 状态机 | 任务 | 典型状态 |
|---|---|---|
| 主 FSM | 决定当前执行读流程还是写流程 | `Idle`、`Ready`、`Write_start`、`Ctrl_write`、`Addr_write`、`Data_write`、`Read_start`、`Ctrl_read`、`Data_read`、`Stop`、`Ackn` |
| 输出移位子 FSM | 把并行字节一位一位送到 SDA | `bit7` 到 `bit0`、`end` |
| 输入移位子 FSM | 从 SDA 一位一位采样成并行数据 | `bit7` 到 `bit0`、`end` |
| START 子 FSM | 生成启动条件 | `begin`、`bit`、`end` |
| STOP 子 FSM | 生成停止条件 | `begin`、`bit`、`end` |

主 FSM 不直接写完每个 bit 的细节，而是启动子 FSM，并通过一个完成标志等待子 FSM 结束：

```text
main_state = Ctrl_write
  if FF == 0: 调用 shift8_out 子流程
  else:       装载下一个字节，进入 Addr_write
```

这个结构在工程上很常见：主状态机负责“阶段”，子状态机负责“阶段内部的节拍”。例如 NPU DMA 控制器中，主 FSM 可以负责 `IDLE/READ/COMPUTE/WRITEBACK`，子 FSM 负责 burst 计数、bank 轮转或 AXI handshake。

### 10.4 task 在可综合设计中的边界

Verilog `task` 可以用于可综合 RTL，但它必须像“代码展开”一样静态可确定。适合：

- 固定宽度移位。
- 固定状态机片段。
- 不含 `#delay`、`@event` 等仿真时间控制。
- 不含不可静态确定次数的循环。

不适合：

- 用 `@(posedge something)` 在 task 内等待外部事件。
- 用 `#10` 之类延迟描述硬件行为。
- 在可综合控制器里调用 `$display`、`$fopen` 这类仿真系统任务。

行为模型可以用这些仿真结构；可综合控制器不可以。

### 10.5 前仿真和后仿真

复杂控制器至少要看两类结果：

| 验证 | 看什么 | 失败信号 |
|---|---|---|
| 前仿真 | RTL 功能是否符合协议 | ACK 不来、数据错、状态卡死 |
| 后仿真/时序仿真 | 综合、布局布线后延迟是否仍满足协议 | SCL/SDA 相位错、采样边沿错、时序路径失败 |

前仿真通过只说明“逻辑意图对”；后仿真和时序报告通过，才更接近“硬件实现也对”。

## 11. 可综合 RTL 风格检查表

写完 FSM 或控制器后，逐项检查：

| 检查项 | 通过标准 |
|---|---|
| 时钟 | 主状态寄存器只由一个时钟边沿触发 |
| 复位 | 所有状态寄存器有明确复位值 |
| 状态编码 | 每个状态有唯一编码，非法状态有处理 |
| 下一状态 | 组合块中默认 `next_state = state` 或安全状态 |
| 输出 | 组合输出有默认值，寄存输出有复位值 |
| 赋值 | 时序块用 `<=`，组合块用 `=` |
| 驱动 | 每个寄存器只有一个过程赋值所有者 |
| 锁存器 | 除非明确需要，否则综合日志不应出现 latch |
| 敏感列表 | 组合逻辑用 `always @*` 或 SystemVerilog `always_comb` |
| case | 有 `default`，不让非法状态静默卡死 |
| 仿真 | 前仿真覆盖正常、边界、复位、非法输入 |
| 综合 | 综合警告全部解释，不能忽略多驱动、锁存器、不可综合语句 |

现代 SystemVerilog 中，可以把意图写得更明确：

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) state <= IDLE;
  else        state <= next_state;
end

always_comb begin
  next_state = state;
  unique case (state)
    IDLE: if (start) next_state = BUSY;
    BUSY: if (done)  next_state = IDLE;
    default:         next_state = IDLE;
  endcase
end
```

如果课程或工具链仍使用 Verilog-2001，就用 `always @(posedge clk...)` 和 `always @*`。思想不变：边沿块管寄存器，组合块管决策。

## 12. 和 AI+IC 硬件设计的连接

NPU、RISC-V 核、DMA、片上总线和 SRAM 控制器都离不开 FSM。

| 场景 | FSM 控制什么 | 常见错误 |
|---|---|---|
| MAC 阵列启动 | `load_weight`、`load_act`、`acc_en`、`write_back` | 使能早一拍或晚一拍 |
| SRAM 读写 | 地址、片选、写使能、读数据采样 | 忘记读延迟，采样旧数据 |
| AXI/valid-ready | 请求、等待、握手完成、响应 | 未保持 valid，或重复接收 |
| 卷积滑窗 | 行缓冲读写、窗口移位、边界补零 | 状态漏掉边界条件 |
| 指令译码控制 | 取指、译码、执行、访存、写回 | 控制信号组合毛刺进寄存器 |

阻塞/非阻塞 bug 在 AI 芯片里尤其危险，因为它可能只改变一拍延迟。仿真看起来“差不多”，但流水线对齐一错，乘加结果、地址、mask、valid 信号就会错位。

## 13. 自测题

1. 用一句话解释：FSM 为什么必须包含“当前状态”和“下一状态”两个概念？
2. `Mealy` 输出和 `Moore` 输出的区别是什么？哪一种更容易受输入毛刺影响？
3. 为什么 one-hot 编码在 FPGA 中经常有速度优势？它为什么需要非法状态处理？
4. 写出一个带低有效异步复位的 D 触发器模板。
5. 写出一个两段式 FSM 骨架，要求包含状态寄存器、组合下一状态、`default`。
6. 下面代码为什么会推锁存器？

```verilog
always @* begin
  if (sel) y = a;
end
```

7. 为什么时序逻辑中推荐 `<=`，组合逻辑中推荐 `=`？
8. 三段移位寄存器中，`q1=d; q2=q1; q3=q2;` 为什么不是三拍延迟？
9. `$display` 和 `$strobe` 在观察非阻塞赋值时有什么差别？
10. 序列检测器为什么要考虑重叠序列？
11. EEPROM 控制器为什么要区分行为模型、可综合控制器和测试信号源？
12. 在一个 NPU DMA 控制器里，主 FSM 和子 FSM 可以分别负责什么？

答案检查口径：

- 能把 FSM 拆成状态寄存器、下一状态逻辑、输出逻辑。
- 能写出安全复位和两段式 FSM 模板。
- 能解释阻塞/非阻塞的仿真调度差异，而不是只背“组合用阻塞、时序用非阻塞”。
- 能识别锁存器、多驱动、非法状态、`casex` 掩盖未知值、`#0` 伪修复竞争等风险。
- 能从序列检测器和 EEPROM 控制器看出：复杂控制不是写很多 if，而是把协议阶段映射为可验证状态。

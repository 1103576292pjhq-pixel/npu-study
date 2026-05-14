# 任务17：task / function

## 本章知识全景图

### 一眼看懂这讲在讲什么

- **本章主题**：SystemVerilog 的 `task` 和 `function` 如何封装代码，以及它们在 RTL design 与 testbench 中分别能做什么、不能做什么。
- **核心概念**：`task`、`function`、`void function`、`return`、`input/output/inout/ref`、`automatic/static`、作用域、仿真时间。
- **逻辑主线**：`function` 适合无时间消耗的计算，`task` 适合带步骤、等待和事件控制的仿真动作；真正危险的不是语法本身，而是把 testbench 的时间行为和副作用误塞进 RTL。
- **最短学习路径**：先分清 design/TB 边界，再判断子程序是否消耗仿真时间，最后检查参数传递、生命周期和作用域副作用。

| 概念层级 | 核心概念 | 前置知识 | 延伸应用 |
|---|---|---|---|
| 代码组织 | task / function | 过程块、语句块 | testbench helper、RTL 组合函数 |
| 时间语义 | 是否消耗仿真时间 | `#delay`、`@event`、`wait` | 判断能否用于 RTL |
| 数据传递 | input/output/inout/ref | 变量、赋值、副作用 | scoreboard、packet、数组传参 |
| 生命周期 | automatic/static | 局部变量、并发调用 | 避免多线程污染共享临时变量 |
| 作用域 | module/block/subroutine scope | 同名变量遮蔽 | 大型 TB 可维护性 |

**能不能放进 RTL，不看它叫 `task` 还是 `function`，看它是否能被解释成确定硬件；能不能写进 testbench，则看它能否清楚表达刺激、等待、检查和清理动作。**

## 1. 先分清 design 和 testbench：封装不会自动变成硬件

`task` 和 `function` 都只是 SystemVerilog 的子程序封装机制，不能把一段行为“魔法式”变成新硬件模块。RTL design 的目标是综合成电路；testbench 的目标是产生激励、推进仿真时间、观察结果和报告错误。

![design 与 testbench 边界](<./screenshots/任务017_task-function/design_tb_boundary_75s.jpg>)

🔍 视觉验证：视频 01:15-03:00（课程页切入 `task and function`：应看到 design 与 testbench 边界被作为本讲入口。）

| 位置 | 目标 | 典型语法 | 交付证据 |
|---|---|---|---|
| RTL design | 描述可综合硬件 | `always_ff`、`always_comb`、`assign`、有限制的 `function` | 网表、综合报告、仿真波形 |
| testbench | 驱动和检查 DUT | `initial`、`task`、`#delay`、`@(posedge clk)`、`$display` | 日志、波形、断言、覆盖 |

把等待时钟、延时、文件打印、随机刺激放进 testbench 是正常的；把这些直接放进可综合 RTL 则通常是错误的。学习 `task/function` 的第一步不是背模板，而是问：这段代码服务硬件结构，还是服务仿真过程？

## 2. `task`：适合描述一段会沿仿真时间推进的动作

`task` 的价值是把多步动作封装成一个可复用过程，尤其适合 testbench 里“复位一次”“发一笔 transaction”“等待响应”“检查超时”这类动作。它可以有输入、输出、双向或引用参数，也可以包含延时和事件等待。

![task 特点](<./screenshots/任务017_task-function/task_features_205s.jpg>)

🔍 视觉验证：视频 03:17-04:30（task 特点页：应看到多语句、参数和仿真时间控制被放在同一组规则里。）

典型 testbench task：

```systemverilog
task automatic send_one_byte(
    input  logic [7:0] data,
    output logic       done
);
    @(posedge clk);
    tx_data  <= data;
    tx_valid <= 1'b1;

    @(posedge clk);
    tx_valid <= 1'b0;
    done = 1'b1;
endtask
```

这段代码消耗两个时钟边沿，所以它描述的是“测试环境怎样驱动一笔输入”，不是“综合出一个名叫 `send_one_byte` 的硬件模块”。如果把它放在 RTL 里，综合器无法把 `@(posedge clk)` 内嵌到一个普通子程序调用中得到清晰硬件结构。

`task` 的工程判断表：

| 需求 | 适合 task 吗 | 原因 |
|---|---|---|
| 复位 DUT，等待若干拍后释放 | 适合 | 这是 testbench 时间动作 |
| 驱动一次 valid/ready 握手 | 适合 | 需要跨多个时钟边沿 |
| 等待 monitor 收到输出 | 适合 | 需要事件等待 |
| 计算 parity 或掩码 | 通常不需要 | `function` 更清楚 |
| 在 RTL 中写一段可综合状态转移 | 不建议 | 应写成明确 `always_ff/always_comb` |

## 3. `function`：适合无时间消耗的计算，不适合等待和推进流程

`function` 的硬边界是“不消耗仿真时间”。它可以被当作一个组合计算表达式使用：输入进来，当前仿真时刻内算出结果。它不能包含 `#delay`、`@(event)`、`wait`，也不能调用会消耗时间的 `task`。

![function 时间规则](<./screenshots/任务017_task-function/function_rules_285s.jpg>)

🔍 视觉验证：视频 04:32-05:10（function 规则页：应看到 function 不消耗仿真时间，不能包含等待语句。）

典型 RTL function：

```systemverilog
function automatic logic [31:0] sat_add(
    input logic [31:0] a,
    input logic [31:0] b
);
    logic [32:0] sum;

    sum = {1'b0, a} + {1'b0, b};
    if (sum[32])
        return 32'hFFFF_FFFF;
    else
        return sum[31:0];
endfunction
```

硬件视角下，这不是 CPU 在运行时调用函数，而是一段可展开的组合逻辑。多处调用可能被综合器复制或优化共享，取决于上下文。设计者真正要保证的是：输入完整、输出确定、没有隐藏时间行为、没有依赖不清楚的外部状态。

`function` 常见错误：

- 在 function 里写 `#10`、`@(posedge clk)`、`wait(valid)`，这破坏无时间语义。
- 在 RTL function 里偷偷读写全局变量，让计算结果依赖调用点之外的状态。
- 某些分支没有给返回值，导致仿真和综合都难以判断意图。
- 把复杂时序流程塞进 function，以为“封装后更高级”，实际只是把错误藏起来。

## 4. `return` 和函数名赋值：返回路径必须覆盖所有分支

SystemVerilog 的 function 可以像 C 一样使用 `return`，也可以用传统 Verilog 写法给函数名赋值。两种方式都能返回值，但 `return` 更直接，适合让 reviewer 快速看到每条路径的结果。

![return 语句](<./screenshots/任务017_task-function/return_value_745s.jpg>)

🔍 视觉验证：视频 11:54-12:44（return 对比页：应看到 `return` 返回表达式值，并与函数名赋值写法并列。）

传统写法：

```systemverilog
function int add(input int a, input int b);
    add = a + b;
endfunction
```

推荐写法：

```systemverilog
function int add(input int a, input int b);
    return a + b;
endfunction
```

复杂分支里要先问一个问题：每条路径有没有明确返回？下面这种写法风险更低：

```systemverilog
function automatic logic [1:0] decode_mode(input logic [3:0] opcode);
    unique case (opcode)
        4'h0: return 2'd0;
        4'h1: return 2'd1;
        4'h2: return 2'd2;
        default: return 2'd3;
    endcase
endfunction
```

如果漏掉 `default`，某些非法输入下 function 的输出语义就不清楚。RTL 中这种“不清楚”往往会变成 latch、X 传播、综合警告或后续波形难定位。

## 5. `void function`：没有返回值，不等于可以消耗时间

`void function` 只是“没有函数返回值”的 function，它仍然必须保持 function 的无时间边界。它适合做无时间的打包、格式化、短检查、组合转换；只要需要等时钟或等事件，就应改用 task。

![void function 参数](<./screenshots/任务017_task-function/void_arguments_805s.jpg>)

🔍 视觉验证：视频 13:13-15:40（void function 与参数方向页：应看到“无返回值”不改变 function 的无时间语义。）

适合的 `void function`：

```systemverilog
function automatic void pack_req(
    input  req_t req,
    output logic [67:0] bits
);
    bits = {req.valid, req.opcode, req.addr, req.data};
endfunction
```

不适合的写法：

```systemverilog
function void wait_ready();
    @(posedge clk);       // 错：function 不能等待事件
    wait (ready == 1'b1); // 错：function 不能消耗仿真时间
endfunction
```

`void` 只改变返回值形式，不改变 function 的时间规则。

## 6. 参数传递：`input/output/inout` 是复制，`ref` 是同一个对象

参数方向不仅影响读写权限，也影响数据何时被复制。`input` 在调用时拷入，`output` 在返回时拷出，`inout` 先拷入再拷出；`ref` 不拷贝，子程序内部和外部看到的是同一个对象。

![复制传参与引用传参](<./screenshots/任务017_task-function/copy_vs_ref_params_1955s.jpg>)

🔍 视觉验证：视频 22:48-33:00（参数传递对比页：应看到普通参数复制与 `ref` 引用传递的差异。）

| 方向 | 进入子程序时 | 退出子程序时 | 副作用 |
|---|---|---|---|
| `input` | 拷入 | 不拷出 | 内部修改不影响外部 |
| `output` | 初值通常不作为输入使用 | 拷出 | 退出后更新外部 |
| `inout` | 拷入 | 拷出 | 内外都有数据流 |
| `ref` | 不拷贝 | 不拷贝 | 直接修改同一对象 |

最小例子：

```systemverilog
task automatic t_input(input int x);
    x = x + 1;
endtask

task automatic t_ref(ref int x);
    x = x + 1;
endtask

int a = 1;
t_input(a); // a 仍然是 1
t_ref(a);   // a 变成 2
```

`ref` 很有用，尤其是传大数组、packet、queue、scoreboard 数据结构时能避免拷贝成本。但它也很危险，因为调用者的数据会被直接改掉。函数名和参数名必须暴露意图，例如 `update_scoreboard(ref sb_t sb, input packet_t pkt)` 比 `calc(ref x)` 更诚实。

## 7. `ref` 常与 `automatic` 配合：并发 testbench 不能共享临时变量

在并发 testbench 中，多个线程可能同时调用同一个 task/function。如果子程序内部临时变量是共享的，一个线程的中间结果可能被另一个线程覆盖。`automatic` 让每次调用拥有独立局部变量副本，更适合可重入 helper。

![ref 与 automatic](<./screenshots/任务017_task-function/ref_automatic_1435s.jpg>)

🔍 视觉验证：视频 23:51-24:55（`ref` 与 `automatic` 同屏：应看到引用参数和可重入局部变量被关联。）

推荐写法：

```systemverilog
function automatic void swap(ref int a, ref int b);
    int tmp;
    tmp = a;
    a = b;
    b = tmp;
endfunction
```

如果 `tmp` 在并发调用之间共享，两个线程交错执行时可能互相污染。验证环境中这类问题特别隐蔽：语法没错、单线程能跑，多线程回归时才偶发失败。

## 8. `automatic/static` 与作用域：可见范围和存活时间不是一回事

作用域回答“变量在哪里可见”，生命周期回答“变量活多久”。这两个概念不同，但经常一起导致 bug。

![automatic 与 static 生命周期](<./screenshots/任务017_task-function/automatic_static_scope_2195s.jpg>)

🔍 视觉验证：视频 35:42-36:25（生命周期图：应看到 `automatic/static` 与局部变量存活时间的关系。）

| 类型 | 生命周期 | 并发调用风险 |
|---|---|---|
| `automatic` | 调用进入时创建，退出时销毁 | 每次调用独立，适合可重入 |
| `static` | 整个仿真期间保留 | 多次调用共享状态，需要明确设计意图 |

`static` 不是不能用。它适合明确需要跨调用保存状态的 helper，例如统计调用次数：

```systemverilog
function void count_call();
    static int count;
    count++;
    $display("count=%0d", count);
endfunction
```

但如果你只是需要一个临时变量，默认应写 `automatic`，尤其是在并发 testbench 里。

![作用域示例](<./screenshots/任务017_task-function/scope_example_2735s.jpg>)

🔍 视觉验证：视频 33:11-45:35（作用域代码页：应看到变量声明位置如何决定可见范围。）

作用域自查：

- module 级变量：整个模块内部可见，容易被多个过程块读写。
- block 级变量：只在对应 `begin/end` 块内可见。
- task/function 内部变量：只在子程序内部可见，但生命周期取决于 `automatic/static`。
- 同名变量会遮蔽外层变量，读代码时要确认当前名字解析到哪一层。

## 9. 选择 task/function 的工程表

| 你要做什么 | 推荐 | 原因 |
|---|---|---|
| 计算 parity、mask、饱和加法、地址解码 | `function automatic` | 无时间组合计算 |
| 打包/拆包结构体，无需等待 | `void function automatic` | 无返回值但无时间 |
| reset DUT，等待 10 拍 | `task automatic` | 消耗仿真时间 |
| 驱动 transaction 并等待 ready | `task automatic` | 有事件等待 |
| 在 RTL 内描述状态机 | `always_ff` + `always_comb` | 明确综合结构 |
| 在 TB 中传大数组并修改 | `task/function automatic` + `ref` | 避免拷贝并暴露副作用 |

真正成熟的写法不是“所有 helper 都用同一种模板”，而是每次封装前先回答四个问题：

1. 它是否消耗仿真时间？
2. 它是否应该被综合成硬件？
3. 它是否修改调用者对象？
4. 它是否可能被并发调用？

这四个问题比背语法更重要。

## 10. 和 AI+IC / NPU 学习的连接

NPU 项目里会大量出现可复用 RTL 计算函数和 testbench 驱动任务。比如地址对齐、burst 长度裁剪、mask 生成适合写成无时间 `function`；AXI transaction 驱动、等待中断、超时检查适合写成 `task`。如果把两者混淆，轻则仿真代码难维护，重则把不可综合行为混进 design。

最小练习：

```systemverilog
function automatic logic [3:0] byte_mask(input logic [1:0] size);
    unique case (size)
        2'd0: return 4'b0001;
        2'd1: return 4'b0011;
        2'd2: return 4'b1111;
        default: return 4'b0000;
    endcase
endfunction

task automatic drive_write(input logic [31:0] addr, input logic [31:0] data);
    @(posedge clk);
    awaddr  <= addr;
    wdata   <= data;
    awvalid <= 1'b1;
    wvalid  <= 1'b1;
    wait (awready && wready);
    @(posedge clk);
    awvalid <= 1'b0;
    wvalid  <= 1'b0;
endtask
```

前者是组合计算，后者是 testbench 时间动作。这个区分会贯穿后面的 FIFO、总线、eFlash 控制器和 NPU 验证。

## 11. 深层理解：task/function 是“封装动作”和“封装计算”的分界线

可以把 `function` 理解成计算器：给它输入，它立刻算出结果，不等时钟、不等握手、不推进时间。可以把 `task` 理解成一段流程动作：它可能等时钟、发请求、等 ready、收响应，像一个会沿时间轴走的操作员。

这个比喻能防止两个常见误解：

- `void function` 只是“没有返回值的计算器”，不是可以等待时钟的流程动作。
- `task` 能消耗时间，但不等于适合写进 design；很多 task 是 testbench driver，不应该进入可综合 RTL。

选择时按这张表：

| 问题 | 倾向 function | 倾向 task |
|---|---|---|
| 是否消耗仿真时间？ | 不消耗 | 可能消耗 |
| 是否等待时钟/事件/握手？ | 不等待 | 可以等待 |
| 是否只返回计算结果？ | 是 | 不一定 |
| 是否驱动 transaction 流程？ | 不适合 | 适合 |
| 是否可能并发调用？ | 用 `automatic` 避免共享局部变量 | 更应使用 `automatic` 和清晰作用域 |

## 12. 配图复盘：从边界、时间和生命周期读图

| 配图 | 读图重点 | 应形成的判断 |
|---|---|---|
| design 与 testbench 边界 | 子程序位于哪一侧 | design 代码和验证动作不要混放 |
| task 特点 | task 可以有时间控制 | 适合 driver、monitor、timeout 等流程 |
| function 时间规则 | function 不消耗仿真时间 | 适合 mask、地址、校验码等纯计算 |
| return 语句 | 返回路径是否完整 | 所有分支都应给出明确返回 |
| void function 参数 | 无返回值但仍无时间 | 可做即时检查/打印，不可等待时钟 |
| 复制传参与引用传参 | 对象是否共享 | `ref` 是同一个对象，副作用要显式管理 |
| ref 与 automatic | 并发调用是否隔离局部变量 | 不加 `automatic` 容易出现交叉污染 |
| automatic/static 生命周期 | 变量何时创建、何时销毁 | 并发 testbench helper 默认优先 automatic |
| 作用域示例 | 名字能否被访问 | 可见范围和存活时间是两件事 |

## 13. 操作闭环：封装前先写契约

每写一个 task/function，先写 5 行契约：

```text
用途：它封装计算还是封装动作？
时间：是否允许 @/#/wait？
输入输出：哪些参数只读，哪些参数会被修改？
副作用：是否驱动信号、改全局变量、打印日志？
并发：是否可能同时被多个线程调用，是否需要 automatic？
```

没有契约的子程序像没有标签的工具箱：短期能用，项目一大就会拿错工具。尤其是验证环境里，`ref` 和 `static` 的副作用常常只在并发回归中暴露；单次 demo 通过并不能证明封装安全。

## 复习与自测

1. **判断题**：`void function` 没有返回值，所以可以写 `@(posedge clk)`。  
   **答案**：错。`void` 只表示无返回值，不改变 function 不能消耗仿真时间的规则。

2. **判断题**：`ref` 参数不会复制对象，因此子程序内部修改会影响调用者。  
   **答案**：对。`ref` 传的是同一个对象，适合大对象和需要显式副作用的场景。

3. **推导题**：为什么并发 testbench helper 建议写 `automatic`？  
   **答案要点**：并发线程可能同时调用同一个 task/function；`automatic` 让每次调用拥有独立局部变量，避免共享临时变量互相污染。

4. **设计题**：地址掩码计算和 AXI 写 transaction 驱动分别应该用什么封装？  
   **答案要点**：地址掩码是无时间组合计算，适合 `function automatic`；AXI 写驱动需要等待时钟和握手，适合 `task automatic`。

## 工程核对口径

完成本章后，用这些题检查自己：

1. 能否把“地址对齐计算”和“AXI 写事务驱动”分别正确放进 function 和 task？
2. 能否解释为什么 `void function` 仍然不能等待时钟？
3. 能否说明 `ref` 为什么会带来副作用，以及何时值得使用？
4. 能否举例说明 `static` 局部变量在并发调用中怎样污染结果？
5. 能否在 NPU testbench 中把 driver、monitor、scoreboard helper 分别封装成合适的 task/function？



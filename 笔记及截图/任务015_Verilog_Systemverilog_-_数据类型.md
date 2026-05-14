# 任务15：Verilog / SystemVerilog 数据类型

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：SystemVerilog 数据类型不是语法装饰，而是在表达位宽、四态值、驱动方式、存储形态和 RTL/testbench 边界。
- 核心概念：2-state、4-state、`bit`、`byte`、`int`、`real`、`time`、`logic`、`reg`、`wire`、`string`、`enum`、`typedef`、fixed array、dynamic array、queue、associative array、array methods、`struct`、`union`。
- 逻辑主线：写 SV 类型前先问三件事：它是多少 bit，是否需要暴露 `X/Z`，它要综合成硬件还是只服务仿真。能回答这三问，类型选择才不是背语法。
- 最短学习路径：先区分 2 值和 4 值，再区分变量和网络，再学习枚举与数组，最后把动态结构放回 testbench，把固定结构放回 RTL。

### 2. 概念地图

| 概念层级 | 核心概念 | 前置知识 | 延伸应用 |
|---|---|---|---|
| 值域 | 2-state / 4-state | `0/1/X/Z` | X 传播、复位检查、仿真可信度 |
| 标量与整数 | `bit/byte/int/longint/real/time` | 位宽、signed/unsigned | 计数、时间、TB 算法变量 |
| RTL 信号 | `logic/reg/wire` | 连续赋值、过程赋值 | 可综合 RTL、驱动归属、lint |
| 可读编码 | `typedef enum logic [...]` | 状态机、底层编码 | FSM、协议状态、波形调试 |
| 数组 | packed / unpacked / dynamic / queue / associative | 位向量、存储器、索引 | 总线打包、FIFO、scoreboard |
| 聚合类型 | `struct/union` | 字段、共享存储解释 | 协议包、NPU 指令字段、总线请求 |

### 3. 阅读顺序

1. 先用 2 值/4 值判断这个类型能不能暴露未知态。
2. 再用 `logic/wire` 判断这个对象由谁驱动。
3. 然后用 packed/unpacked 判断它是连续位向量还是元素集合。
4. 最后把 queue、dynamic array、associative array 放在 testbench 语境下使用，不要默认当成可综合硬件。

## 全视频地图

| 时间段 | 教学块 | 必须保留的知识动作 |
|---|---|---|
| 00:00-05:00 | 为什么前端要学 SystemVerilog | 能看懂验证代码，能写简单 testbench，也能判断哪些类型不应进入 RTL |
| 05:00-20:00 | 基本数值类型 | 区分位宽、signed/unsigned、2-state/4-state、浮点和 time |
| 20:00-25:00 | 字符串与枚举 | 学会字符串方法的 TB 属性；用 enum 提升状态可读性 |
| 25:00-35:00 | 固定数组与维度 | 区分数组初始化、索引、维度大小和 packed/unpacked 的硬件含义 |
| 35:00-50:00 | 动态数组、队列、关联数组 | 理解 `new/delete/push/pop` 和任意索引主要服务仿真建模 |
| 50:00-61:47 | 数组方法与总结 | 区分 `find/find_index/sort/shuffle` 的仿真便利性和 RTL 可综合边界 |

## 1. 数据类型先问硬件语义，不先背名字

SystemVerilog 横跨 RTL 与验证。RTL 代码最终要综合成线、寄存器、组合逻辑和存储器；testbench 代码只在仿真器里运行，可以使用更像软件的数据结构。

看到一个类型声明时，先问：

```text
它有多少 bit？
它能不能表达 X/Z？
它最终要综合成硬件，还是只服务仿真检查？
```

这三问比“这个语法怎么写”更重要。因为语法正确不等于工程正确，尤其是在 AI 芯片设计中，数据通路位宽、状态机编码、scoreboard 队列和 transaction 存储都依赖类型边界。

## 2. 2-state 类型：仿真快，但可能掩盖未知态

2-state 类型只能表达 `0/1`，不能表达 `X/Z`。它适合 testbench 中的计数、循环、纯算法变量，但不适合承接需要暴露未知态的关键 RTL 信号。

![2 值与 4 值类型概览](<./screenshots/任务015_Verilog_Systemverilog_-_数据类型/four_state_types_500s.jpg>)

视觉核验：视频 05:00-16:00，画面讲 `bit`、`byte`、`shortint/int/longint`、signed/unsigned 和浮点；读者应把重点放在位宽和值域，而不是只记类型名。

| 类型 | 常见位宽 | 默认符号性 | 适合用途 |
|---|---:|---|---|
| `bit` | 1 | unsigned | TB 标志、简单 0/1 变量 |
| `byte` | 8 | signed | 字节数据、字符串/文件处理辅助 |
| `shortint` | 16 | signed | TB 算法变量 |
| `int` | 32 | signed | 循环变量、计数、函数返回 |
| `longint` | 64 | signed | 大整数建模 |
| `real` | 64-bit 双精度 | 非整数 | TB 浮点计算，不用于可综合 RTL |
| `shortreal` | 32-bit 单精度 | 非整数 | TB 浮点计算 |
| `time` | 64-bit unsigned | unsigned | 仿真时间记录 |

2-state 的风险在复位和驱动错误里最明显：本来应该在波形中冒出的 `X`，可能被 2-state 变量压成确定的 `0/1`。所以普通 RTL 信号更常用 4-state 类型，TB 内部计算变量可以用 2-state 类型提高效率。

## 3. 4-state 类型：`logic` 是 RTL 默认选择，但不是寄存器同义词

4-state 类型能表达 `0/1/X/Z`，更适合暴露复位遗漏、冲突驱动和未初始化问题。

![logic 与 reg 的关系](<./screenshots/任务015_Verilog_Systemverilog_-_数据类型/logic_vs_reg_875s.jpg>)

视觉核验：视频 10:00-18:00，画面讲 `reg`、`logic`、连续赋值和过程赋值；读者应确认类型名不直接决定硬件，赋值语境和时钟条件才决定组合逻辑或寄存器。

`logic` 常用于替代传统 Verilog 的 `reg`，但要避免两个误解：

- `reg` 不一定综合成寄存器。
- `logic` 也不一定是组合逻辑。

硬件由过程语义决定：

```systemverilog
logic [7:0] a, b, y, q;

always_comb begin
    y = a + b;      // 组合逻辑
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        q <= '0;
    else
        q <= y;     // 寄存器
end
```

同样是 `logic`，`y` 是组合输出，`q` 是触发器输出。综合工具看的是 `always_comb` / `always_ff`、敏感条件和赋值规则，不是只看类型名。

## 4. `wire` 与 `logic` 的差别是驱动模型

`wire` 表达网络连接，由连续赋值、模块端口或多个驱动源共同决定；`logic` 表达变量，通常由一个过程块或单一连续赋值驱动。

```systemverilog
wire  ready_net;
logic valid_q;

assign ready_net = a & b;  // 连续赋值网络

always_ff @(posedge clk) begin
    valid_q <= valid_d;    // 过程赋值变量
end
```

工程判断：

| 场景 | 推荐类型 | 原因 |
|---|---|---|
| 模块间连接、连续赋值网络 | `wire` 或明确 net 类型 | 网络语义清晰 |
| `always_comb/always_ff` 内过程赋值 | `logic` | 单驱动变量语义清晰 |
| 多驱动/三态总线 | 谨慎使用 net 类型 | 需要明确解析规则 |
| 普通 RTL 寄存器/组合输出 | `logic` | 保留 `X/Z` 暴露能力 |

驱动归属不清比类型名字更危险。同一个 `logic` 被多个过程块写，通常会制造仿真竞争和综合歧义。

## 5. `typedef enum logic` 让状态既可读又可控

枚举的价值不是少写几个数字，而是让状态名、底层位宽和非法状态检查都更明确。

![typedef enum 枚举类型](<./screenshots/任务015_Verilog_Systemverilog_-_数据类型/typedef_enum_1340s.jpg>)

视觉核验：视频 20:00-26:00，画面讲 enum 和固定数组前的类型组织；读者应确认 enum 最好显式绑定底层位宽。

推荐写法：

```systemverilog
typedef enum logic [1:0] {
    S_IDLE,
    S_RUN,
    S_DONE
} state_e;

state_e state, state_n;
```

比起散落的 `localparam`，这种写法有三个优点：

- 波形和日志更容易显示状态名。
- 底层位宽明确，综合和 review 更透明。
- 类型系统能帮助发现非法赋值和遗漏状态。

`enum logic [1:0]` 最终仍是 2 位状态寄存器。名字服务可读性，位宽服务硬件实现，两者都要写清。

## 6. packed array：连续位向量的分组表达

packed 维度写在变量名左侧，更像一个连续 bit vector，只是按维度分组。

![packed array 与维度位置](<./screenshots/任务015_Verilog_Systemverilog_-_数据类型/packed_array_1695s.jpg>)

视觉核验：视频 27:00-33:00，画面解释数组维度和大小；读者应区分左侧 packed 维度与右侧 unpacked 维度。

```systemverilog
logic [3:0][7:0] lane_data;
```

这表示一个 32-bit packed 向量，分成 4 个 8-bit lane。它适合：

- 总线字段。
- SIMD/NPU lane 数据。
- 协议包打包。
- 可整体切片、拼接、端口传递的数据。

```systemverilog
lane_data[0]      = 8'h12;
lane_data[1][3:0] = 4'hA;
logic [31:0] flat = lane_data;
```

在 NPU 数据通路里，`logic [LANES-1:0][DW-1:0]` 比一堆散落信号更能表达“多 lane 数据整体传输、局部访问”的意图。

## 7. unpacked / fixed array：元素集合或存储器形态

unpacked 维度写在变量名右侧，更像一组元素。它常用于寄存器数组、小 RAM、FIFO 存储体或 TB 固定数组。

![固定数组与 memory 形态](<./screenshots/任务015_Verilog_Systemverilog_-_数据类型/array_memory_1940s.jpg>)

视觉核验：视频 25:00-35:00，画面讲固定数组、初始化、索引和维度；读者应确认 `mem[i]` 是第 i 个元素，而不是默认可整体拼接的向量。

```systemverilog
logic [7:0] mem [0:15];
```

这表示 16 个元素，每个元素 8 bit。与 packed array 对比：

| 写法 | 更像什么 | 典型用途 |
|---|---|---|
| `logic [3:0][7:0] a` | 一个 32-bit 连续向量，按 byte 分组 | 总线、lane、协议字段 |
| `logic [7:0] a [0:3]` | 4 个 8-bit 元素 | memory、寄存器数组、FIFO |

固定数组的大小在编译/ elaboration 阶段确定。可综合 RTL 需要这种确定性，因为硬件必须在综合前知道要生成多少寄存器、多少 RAM 或多少组合连接。

## 8. dynamic array / queue / associative array：验证工具箱，不是 RTL 默认存储

动态数组、队列和关联数组是 testbench 的高表达力工具。它们能在仿真时分配、增长、查找和删除，但这类“运行时数据结构”通常没有直接的固定硬件对应。

![队列的 push/pop 操作](<./screenshots/任务015_Verilog_Systemverilog_-_数据类型/queue_methods_2240s.jpg>)

视觉核验：视频 35:00-43:00，画面讲动态数组和队列的 `new/delete/push/pop`；读者应把它们放在 transaction 管理和 scoreboard 语境下理解。

![关联数组的任意索引](<./screenshots/任务015_Verilog_Systemverilog_-_数据类型/associative_array_2800s.jpg>)

视觉核验：视频 43:00-52:00，画面用字符串索引和任意索引说明 associative array；读者应确认它适合按 ID/名字查找的仿真模型。

| 类型 | 大小何时确定 | 索引 | 常见操作 | 主要用途 |
|---|---|---|---|---|
| dynamic array | 仿真运行时 `new[]` | 整数 | `new`、`delete` | 可变长度缓存、激励数据 |
| queue | 仿真中动态变化 | 整数 | `push_back`、`pop_front`、`insert`、`delete` | transaction 队列、scoreboard |
| associative array | 按需分配 | 任意 key 类型 | `exists`、`first`、`next`、`delete` | 稀疏表、按 ID 查找 |

典型 testbench 用法：

```systemverilog
packet_t exp_q[$];        // queue
packet_t by_id[int];      // associative array
byte     payload[];       // dynamic array
```

不要把 `queue` 当成可综合 FIFO。真正 RTL FIFO 需要固定深度、读写指针、满空判断和存储体；queue 是仿真器里的动态容器。

## 9. `struct` / `union`：把字段组织成可传递对象

`packed struct` 适合表达协议字段和总线请求：既能按字段访问，也能整体当作 bit vector 传递。

![struct 与 union 示例](<./screenshots/任务015_Verilog_Systemverilog_-_数据类型/struct_union_2510s.jpg>)

视觉核验：视频 50:00-56:00，画面讲聚合类型和字段组织；读者应区分 `packed struct` 的整体位向量属性与 `union` 的共享存储解释。

```systemverilog
typedef struct packed {
    logic        valid;
    logic [3:0]  opcode;
    logic [31:0] addr;
    logic [31:0] data;
} bus_req_t;

bus_req_t req;
```

这类写法适合：

- AHB/AXI 请求字段。
- NPU 指令字段。
- DMA 描述符。
- pipeline stage payload。

`union` 表示多种解释共享同一片存储。它在验证、协议解析、格式转换中有价值；RTL 中要谨慎使用，必须确认综合工具支持和团队代码规范，避免读者看不出真实硬件意图。

## 10. 数组方法：TB 好用，RTL 要先问硬件对应

数组方法能大幅简化 testbench 查找、排序和随机打乱，但不能因为仿真器支持就直接放入可综合 RTL。

![数组操作方法列表](<./screenshots/任务015_Verilog_Systemverilog_-_数据类型/array_summary_3600s.jpg>)

视觉核验：视频 55:00-61:47，画面总结固定数组、动态数组、队列、关联数组和 `find/find_index/sort/shuffle` 等方法；读者应把方法先判为仿真便利能力，再检查是否有固定硬件对应。

常见方法：

- `size()`：返回大小。
- `delete()`：删除元素或清空动态结构。
- `find()` / `find_index()`：按条件查找。
- `sort()` / `reverse()` / `shuffle()`：排序、反转、随机打乱。

scoreboard 示例：

```systemverilog
int idx[$];
idx = q.find_index with (item.id == target_id);
```

这在 testbench 中很自然；若放到 RTL，就要解释会综合成多少比较器、怎样处理可变长度、是否需要固定排序网络。如果无法回答，就不要放进 RTL。

## 11. 深层理解：数据类型是在给硬件“量尺寸”

SystemVerilog 数据类型不是给变量起名字，而是在给硬件量尺寸、定材料、定存放方式。`logic [31:0]` 像一排 32 根线，packed struct 像把多段线束捆成一根总线，unpacked array 像一排编号抽屉，queue 像 testbench 里的临时队列。前几种能比较自然地落到硬件，后几种更多是仿真环境里的组织工具。

判断一个类型能不能进入 RTL，不要先问“语法支持吗”，要先问：

1. 它的大小在综合前是否确定？
2. 它能否解释成固定数量的线、寄存器或存储体？
3. 它的索引、push/pop、查找等操作是否需要运行时动态分配？
4. 它暴露未知态，还是把未知态压扁成 0/1？

这个判断对 AI 芯片尤其关键。NPU 的激活值、权重、地址、mask、opcode、valid/ready 都是位级结构；如果类型边界不清，后面就会出现位宽截断、符号扩展错误、scoreboard 和 RTL 行为不一致、波形看不出状态名等问题。

## 12. 配图复盘：从图读出可综合边界

| 配图 | 读图重点 | 工程判断 |
|---|---|---|
| 2 值与 4 值类型概览 | `bit/int` 与 `logic` 的差别 | RTL 默认保留 4-state，避免吞掉 X |
| `logic` 与 `reg` | `logic` 不是“必然寄存器” | 是否成寄存器取决于赋值过程块 |
| `typedef enum` | 状态名和底层位宽同时存在 | FSM 波形更可读，也更容易检查非法状态 |
| packed array | 维度写在变量名前 | 更像连续位向量，可切片、拼接、作为端口 |
| fixed array / memory | 维度写在变量名后 | 更像多个元素或存储体 |
| queue | push/pop 动态变化 | 适合 TB transaction，不是 RTL FIFO |
| associative array | 任意索引 | 适合稀疏查表和 scoreboard |
| struct/union | 字段组织 | packed struct 可做总线 payload |
| 数组方法 | 方法丰富 | 方法越动态，越要先问是否可综合 |

图里的每一种类型都可以用一个问题概括：它是“电路结构”，还是“验证工具箱”？这比背语法更接近工程判断。

## 13. 类型选择决策表

| 需求 | 推荐类型 | 边界 |
|---|---|---|
| 普通 RTL 信号 | `logic [N-1:0]` | 保留 `X/Z`，位宽显式 |
| 模块连接或连续赋值网络 | `wire` / 明确 net 类型 | 多驱动和网络语义更清楚 |
| 状态机 | `typedef enum logic [N-1:0]` | 显式状态位宽，避免裸 enum 默认宽度不透明 |
| 总线字段打包 | `packed struct` / packed array | 适合整体切片、拼接、端口传递 |
| RAM/FIFO 存储 | unpacked array | 大小固定，接近硬件存储结构 |
| TB transaction 队列 | queue / dynamic array | 动态增长，默认不进入 RTL |
| 稀疏查表 | associative array | 按 ID/字符串索引，主要服务仿真 |
| 计数和循环变量 | `int` | TB 常用；RTL 计数器要显式位宽 |

判断标准很朴素：如果它要综合成硬件，就必须能说清会变成多少根线、多少个寄存器、什么组合逻辑或什么存储结构。如果只服务 testbench，就优先考虑表达力和仿真检查能力。

## 复习与自测

1. `bit` 和 `logic` 都能表达 0/1，为什么普通 RTL 信号仍优先用 `logic`？
   - 答案要点：`logic` 是 4-state，能暴露 `X/Z`，更容易发现复位遗漏、冲突驱动和未初始化问题；`bit` 可能把未知态压成确定值。

2. `logic` 一定综合成寄存器吗？
   - 答案要点：不是。`always_comb` 中赋值的 `logic` 可综合成组合逻辑；`always_ff @(posedge clk)` 中赋值的 `logic` 才通常对应寄存器。

3. `logic [3:0][7:0] a` 和 `logic [7:0] a [0:3]` 的硬件直觉分别是什么？
   - 答案要点：前者是 32-bit packed 向量，按 4 个 byte 分组；后者是 4 个 8-bit 元素，更像寄存器数组或小存储器。

4. 状态机为什么推荐 `typedef enum logic [N-1:0]`？
   - 答案要点：状态名可读，底层位宽明确，波形调试和非法状态检查更好，也避免裸 enum 位宽不透明。

5. 为什么 queue 不能直接当成可综合 FIFO？
   - 答案要点：queue 是仿真运行时动态容器；RTL FIFO 需要固定深度、指针、满空逻辑和明确存储体。

6. `packed struct` 对 NPU/总线设计有什么价值？
   - 答案要点：能把 valid、opcode、addr、data 等字段组织成可整体传递的 bit vector，同时保留字段访问，可用于指令字段、DMA 描述符和 pipeline payload。

## 工程核对口径

学完本章后，看到任何类型声明都要能说清三件事：

1. 它在 RTL 中会变成线、寄存器、存储器、组合逻辑，还是只适合 testbench 容器？
2. 它是否保留 `X/Z`，是否可能掩盖 reset、未初始化或多驱动问题？
3. 它的 packed/unpacked 维度是否和端口传递、切片、数组索引、波形观察一致？

最小练习：把一个简单 NPU transaction 拆成 `valid/opcode/addr/data/strb` 五个字段，分别写成裸信号、packed struct、unpacked array 三种形式，然后解释哪一种适合端口，哪一种适合存储，哪一种适合 scoreboard。



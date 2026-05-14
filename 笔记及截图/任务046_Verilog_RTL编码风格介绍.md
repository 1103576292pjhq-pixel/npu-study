# 46_Verilog_RTL编码风格介绍

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：RTL coding style 不是把 Verilog 写得整齐，而是让代码能综合成确定硬件，能被别人读懂、审查、仿真、lint、综合、集成和长期维护。
- 核心概念：可综合性、模块结构、命名规范、条件完整性、latch、三段式 FSM、阻塞/非阻塞赋值、reset、CDC、单驱动。
- 逻辑主线：先把 Verilog 从“软件脚本”纠正为“硬件结构描述”，再用文件组织、命名、缩进和条件覆盖减少阅读和综合歧义，最后用 FSM、赋值语义和工程规则守住前端交付底线。
- 最小主线：
  - 每一行 RTL 最终都会变成寄存器、组合逻辑、mux、译码器或连线。
  - 文件结构和命名决定别人能不能快速找到接口、状态和数据流。
  - 组合逻辑必须覆盖所有路径，否则综合器可能推 latch。
  - 时序逻辑用非阻塞，组合逻辑用阻塞，是为了贴近硬件采样和组合传播语义。
  - reset、CDC、inout、单驱动不是风格偏好，而是硅前质量门。

### 2. 概念地图

| 概念层级 | 核心概念 | 前置知识 | 延伸应用 |
| :---: | :---: | :---: | :---: |
| 文件层 | 文件头、模块名、修改记录 | Verilog module | review、版本追踪、交接 |
| 接口层 | port、parameter、wire/reg/logic | 信号方向、位宽 | 子系统集成 |
| 可读层 | 缩进、`begin/end`、命名 | `if/case/always` | 波形 debug |
| 综合层 | 完整赋值、`default`、单驱动 | 组合逻辑、时序逻辑 | lint、综合一致性 |
| 控制层 | 三段式 FSM | 状态、次态、输出 | 控制器设计 |
| 工程层 | reset、CDC、inout、memory | 时钟域、亚稳态 | tapeout 质量 |

### 3. 阅读顺序

- 先理解 RTL style 的第一目标：生成确定硬件。
- 再掌握文件、模块、命名和排版这类“读代码入口”。
- 最后把条件覆盖、FSM、赋值语义、reset/CDC 当成可检查规则，而不是背诵口号。

### 4. 全讲结构地图

| 视频阶段 | 画面/讲解主线 | 本阶段要学会的判断 |
|---|---|---|
| 00:00-08:30 | 从 coding style 的目的讲到文件头和修改记录 | RTL 风格首先服务可综合、可读和可交接 |
| 08:30-17:20 | 展开模块基本结构：端口、参数、内部信号、instance、main code | 模块顺序稳定，别人才能快速定位边界和实现 |
| 17:20-22:30 | 讨论缩进、`begin/end`、代码块层级 | 排版直接影响控制层级是否可读 |
| 22:30-30:30 | 讲信号命名、低有效后缀、缩写和注释 | 命名要能在波形和代码中同时工作 |
| 30:30-36:30 | 讲位宽、条件完整性、`case/default` 和 latch 风险 | 组合逻辑每条路径必须有确定赋值 |
| 36:30-43:30 | 讲三段式 FSM 的状态寄存、次态和输出 | FSM 拆段是为了 debug 和综合稳定 |
| 43:30-50:30 | 讲阻塞/非阻塞、时序并行采样和单驱动 | 赋值符号对应硬件语义，不只是语法偏好 |
| 50:30-57:22 | 汇总 reset、CDC、inout、memory 等工程规则 | coding style 最终要经住 lint、综合、STA、CDC 和集成 |

## 1. Coding style 的第一目标是生成确定硬件

RTL 不是“能跑就行”的程序文本，而是综合工具要翻译成门级网表的硬件描述。可综合性排在第一位，因为不可综合的写法连硬件都生成不了；可读性排在第二位，因为读不懂的 RTL 很难 review、debug 和长期维护。

视觉验证：视频 07:45-08:30（文件头区域展示作者、模块名、版本、版权和修改记录，说明 RTL 文件要先交代归属和功能）。

![文件头示例](<./screenshots/任务046_Verilog_RTL编码风格介绍/task46_00_file_header_07m45s.jpg>)

合格 RTL 文件至少要回答四个问题：

- 这个模块叫什么，属于哪个子系统。
- 它的输入、输出和参数是什么。
- 它内部有哪些组合逻辑、时序逻辑和子模块。
- 最近修改过什么，为什么改。

如果一个文件打开就是 `module ...`，没有功能说明、端口语义和修改记录，短期能写，长期难维护。数字前端代码会被设计、验证、后端、DFT、集成同事反复读取；读不出来的 RTL 会把每个环节都拖慢。

## 2. 模块结构先分层，再写逻辑

Verilog 模块应该按稳定顺序组织：文件头、`module` 声明、端口、参数、内部信号、子模块例化、组合逻辑、时序逻辑、`endmodule`。顺序稳定以后，别人读你的文件时不用全文搜索。

视觉验证：视频 16:10-17:20（模块内部按接口、内部信号、instance、main code 排列；读者先知道边界，再看实现）。

![模块整体结构](<./screenshots/任务046_Verilog_RTL编码风格介绍/task46_01_module_structure_16m10s.jpg>)

推荐骨架：

```systemverilog
module example #(
    parameter DATA_W = 32
) (
    input  logic              clk,
    input  logic              rst_n,
    input  logic [DATA_W-1:0] data_i,
    output logic [DATA_W-1:0] data_o
);

logic [DATA_W-1:0] data_d;

always_comb begin
    data_d = data_i;
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_o <= '0;
    end else begin
        data_o <= data_d;
    end
end

endmodule
```

这段结构的重点不是语法新旧，而是读者一眼能分清：哪些是接口，哪些是中间信号，哪些是组合推导，哪些是寄存器保存。

## 3. 缩进和 `begin/end` 是控制层级的可视化

缩进不是审美问题，它是在屏幕上表达控制层级。`always`、`if/else`、`case` 嵌套一多，缩进混乱会直接让读者找不到某个 `end` 对应哪个条件。

视觉验证：视频 19:30-20:40（代码中 `begin/end` 成对出现，缩进把 `always`、`if`、`else` 的层级显式展示出来）。

![begin/end 与缩进](<./screenshots/任务046_Verilog_RTL编码风格介绍/task46_02_begin_end_indent_19m30s.jpg>)

更稳妥的写法：

```systemverilog
always_comb begin
    hit = 1'b0;

    if (valid) begin
        if (addr[15:12] == 4'h3) begin
            hit = 1'b1;
        end
    end
end
```

不稳定写法：

```systemverilog
if (valid)
    hit = 1'b1;
    sel = addr[3:0];  // 这一行不属于 if，但肉眼很容易误读
```

前端工程里，代码审查常常不是发现复杂算法错误，而是发现这种“看起来像一组，实际不是一组”的结构错误。即使某个 `if` 当前只有一行语句，团队规范也常要求统一加 `begin/end`，因为后续加第二行时最容易漏包裹。

## 4. 信号命名要把方向、含义和时序阶段写进名字

好的信号名能让读者不看实现也知道它大概是什么。`tx_data`、`rx_valid`、`ready`、`ack`、`addr`、`cnt`、`state` 这类缩写是约定俗成的工程语言；乱造缩写会让波形 debug 变成猜测。

视觉验证：视频 23:15-25:00（命名规则按普通信号、宏、低有效、打一拍信号等分类；命名直接服务波形阅读）。

![信号命名规则](<./screenshots/任务046_Verilog_RTL编码风格介绍/task46_03_signal_naming_23m15s.jpg>)

常见后缀的工程含义：

| 后缀/缩写 | 含义 | 错用后果 |
|---|---|---|
| `_n` | 低有效，如 `rst_n` | 若实际高有效，会误导 reset 逻辑 |
| `_i/_o` | 模块输入/输出 | 端口方向不清，集成容易接反 |
| `_d/_q` | 组合下一值/寄存器当前值 | 状态保存和组合推导混在一起 |
| `_r`、`_ff1`、`_ff2` | 寄存或同步后的阶段 | 波形里难判断延迟关系 |
| `cnt` | counter | 计数宽度和终止条件需要明确 |
| `en`、`valid`、`ready` | 使能、有效、可接收 | handshake 语义混淆会导致丢数据 |

低有效命名尤其不能乱用。`reset_n` 天然告诉读者“0 表示复位有效”；如果实现里写成高有效，波形会非常反直觉，集成时也容易把极性接反。

## 5. 位宽要显式，条件要完整

RTL 里的数字常量最好写清位宽和进制，例如 `5'd4`、`8'hFF`、`32'h0000_0004`。位宽不清会把 bug 藏到隐式扩展、截断和拼接里。

组合逻辑中的 `if/else` 或 `case` 如果没有覆盖所有可能路径，综合工具可能为了“保持旧值”推断 latch。组合逻辑本来应该由当前输入决定当前输出；一旦出现 latch，就变成带记忆的电平敏感电路。

视觉验证：视频 32:40-34:10（`if/else` 的最后分支和 `case default` 被强调；组合逻辑每条路径都要有确定赋值）。

![条件完整性](<./screenshots/任务046_Verilog_RTL编码风格介绍/task46_04_condition_default_32m40s.jpg>)

组合逻辑推荐先给默认值：

```systemverilog
always_comb begin
    next_state = state;
    grant      = 1'b0;

    unique case (state)
        IDLE: begin
            if (req) begin
                next_state = BUSY;
                grant      = 1'b1;
            end
        end
        BUSY: begin
            if (done) begin
                next_state = IDLE;
            end
        end
        default: begin
            next_state = IDLE;
        end
    endcase
end
```

这里的默认赋值不是多余，它确保每个输出在每次组合计算中都有确定值。若没有默认赋值，`grant` 在某些路径上没有新值，综合器只能插入保存旧值的结构，这就是 latch 风险。

## 6. 三段式状态机把“存状态、算次态、用状态”分开

状态机是 RTL 控制器的核心写法。三段式通常拆成三块：时序逻辑保存当前状态，组合逻辑计算下一状态，输出逻辑根据当前状态产生控制信号。拆开后，状态跳错、输出错、复位错能分别定位。

视觉验证：视频 38:50-40:20（代码中 `state` 与 `next_state` 分开，当前状态等到时钟沿才更新，组合逻辑提前计算次态）。

![三段式状态机](<./screenshots/任务046_Verilog_RTL编码风格介绍/task46_05_fsm_three_blocks_38m50s.jpg>)

三段式最小骨架：

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end

always_comb begin
    next_state = state;
    case (state)
        IDLE: if (start) next_state = WORK;
        WORK: if (done)  next_state = IDLE;
        default: next_state = IDLE;
    endcase
end

always_comb begin
    busy = (state == WORK);
end
```

这种拆法的好处是定位清楚：状态不更新，看第一段和 reset；状态跳错，看 next-state 条件；输出错，看输出译码。后续 SRAM BIST、eFlash erase/program/read 控制器都会用到同一个结构思想。

## 7. 时序逻辑用非阻塞，组合逻辑用阻塞

时序逻辑描述一批寄存器在同一个时钟沿同时采样，所以应使用非阻塞赋值 `<=`。组合逻辑描述当前输入经组合路径推导当前输出，所以通常使用阻塞赋值 `=`。

视觉验证：视频 44:10-46:00（时序 always 中多条赋值并列出现，课程强调寄存器在同一时钟沿并行更新）。

![非阻塞赋值](<./screenshots/任务046_Verilog_RTL编码风格介绍/task46_06_nonblocking_assignment_44m10s.jpg>)

时序逻辑：

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        a_q <= 1'b0;
        b_q <= 1'b0;
    end else begin
        a_q <= din;
        b_q <= a_q;
    end
end
```

这表示 `b_q` 采的是旧的 `a_q`，不是这一拍刚写入的 `din`。如果误用阻塞赋值，仿真可能表现成“先更新 a，再更新 b”，和真实寄存器并行采样行为不一致。

还要守住单驱动规则：同一个 `reg/logic` 不要在多个 `always` 块里赋值。两个过程同时驱动一个寄存器，硬件上没有自然答案，综合和仿真都会变得不可靠。

## 8. reset、CDC、inout 和存储选择是工程底线

课程末尾的规则可以压成四类工程底线：复位要确定、跨时钟域要同步、片内方向要清楚、大容量存储不要用寄存器堆硬堆。

视觉验证：视频 54:15-56:30（设计规则集中列出 reset、CDC、inout、大容量 memory 等工程限制）。

![设计规则汇总](<./screenshots/任务046_Verilog_RTL编码风格介绍/task46_07_design_rules_54m15s.jpg>)

| 规则 | 正确理解 | 失败信号 |
|---|---|---|
| 片内少用 `inout` | 片内互连通常用明确方向和 mux，`inout` 多出现在 pad 边界 | 综合结构不可控，时序和验证难分析 |
| 异步低有效 reset 常见 | `posedge clk or negedge rst_n` 能让 reset 不依赖时钟立即生效 | reset 极性写反，仿真启动全是 X |
| 单 bit CDC 至少两级同步 | 单 bit 跨域打两拍降低亚稳态传播概率 | 偶发丢脉冲，仿真不复现 |
| bus 跨域不能直接逐位两拍 | 多 bit 每一位到达时间不同 | 采到混合值 |
| 组合逻辑无环 | 组合输出不能无寄存器反馈决定自身 | 仿真震荡，综合报 loop |
| 大容量用 SRAM | 大 array 用寄存器堆会面积大、时序差 | 面积暴涨、综合耗时 |

这些规则共同目标是让硬件结构稳定。好的 RTL 不是“仿真里过一次”，而是能经得住 lint、综合、STA、CDC、DFT 和回归测试。

## 9. 最小闭环：写一段小状态机并检查四件事

学习本讲后，可以用一个小状态机做闭环：

```text
需求：
  收到 start 后 busy 拉高，计数 8 拍后 done 拉高 1 拍并回到空闲。

检查：
  1. 文件头和模块结构是否完整。
  2. reset 后 state/counter/output 是否确定。
  3. next_state 和输出组合逻辑是否有默认赋值。
  4. 时序逻辑是否只用 <=，同一寄存器是否只有一个 always 驱动。
```

如果这四项都过，再看命名、缩进和注释。不要一开始追求复杂功能；先让最小控制器符合工程写法。

## 10. 工程检查清单：一段 RTL 先过这些硬门槛

读别人 RTL 或提交自己代码时，可以先用这张表快速扫一遍。它不是完整 lint 替代品，但能抓住初学者最常犯、代价又很高的问题。

| 检查项 | 通过标准 | 失败后果 |
|---|---|---|
| 文件组织 | 文件头、模块功能、端口、参数、内部信号、例化、main code 顺序清楚 | 接手者难以判断边界和历史 |
| 位宽 | 常量和信号位宽明确，拼接/截断可解释 | 隐式扩展或截断导致综合后行为偏差 |
| 组合逻辑 | 默认赋值完整，`case` 有兜底路径 | latch、X 传播、综合/仿真不一致 |
| 时序逻辑 | 同一寄存器单 always 驱动，使用非阻塞赋值 | multiple driver 或仿真顺序伪行为 |
| FSM | state register、next-state、output decode 分层明确 | 状态跳转和输出问题难定位 |
| reset | 极性与命名一致，复位后关键寄存器确定 | 仿真启动 X，芯片上电状态不确定 |
| CDC | 单 bit 同步、bus 用握手/FIFO/异步协议 | 偶发失败且仿真难复现 |
| memory | 大容量数组用 SRAM/macro，不用触发器硬堆 | 面积、功耗、时序不可接受 |

## 11. 深层理解：coding style 是硬件可判读契约

RTL 编码风格不是审美规则，而是多人协作时的硬件契约。契约的目标是让设计、验证、综合、STA、CDC、后端和后续维护者都能读出同一件事：这段代码会生成什么硬件，边界在哪里，哪些信号由谁驱动，失败时从哪里查。

一个好的 RTL 文件像一张清楚的电路施工图：

- 文件头说明这张图属于哪个房间、谁画的、改过什么。
- 模块端口说明门、窗、水电接口在哪里。
- 命名规则让每根线在图纸和波形现场都能对上。
- 缩进和 `begin/end` 让结构层级不会被看错。
- 默认赋值和 `default` 保证每条路径都有归宿。
- 三段式 FSM 把状态寄存、下一状态和输出控制分开，像把配电箱、开关逻辑和用电设备分区。

## 12. 从 style 到工具闭环：lint、sim、synthesis 分别抓什么

| 失败信号 | 常见来源 | 最先在哪一关暴露 | 处理口径 |
|---|---|---|---|
| latch inferred | 组合逻辑漏默认赋值或分支不全 | lint / synthesis | 补默认赋值、补 `default`、拆清条件 |
| multiple driver | 同一信号多个 always/assign 驱动 | lint / elaboration | 保证单驱动，必要时用 mux 合并 |
| X propagation | reset 缺失、未初始化、case 未覆盖 | simulation | 查 reset、默认值、非法状态 |
| width truncation | 常量位宽不明、拼接/截断不清 | lint / simulation | 显式位宽和 cast |
| reset polarity wrong | `_n` 命名与实际极性不一致 | sim / bring-up | 修命名或修连接，不能靠注释解释 |
| CDC unsafe | 单 bit 未同步、bus 直接跨域 | CDC tool / silicon risk | 用同步器、握手、异步 FIFO |
| synthesis mismatch | 使用不可综合语句或仿真技巧 | synthesis | TB 代码和 RTL 代码分离 |

style 的价值就在这里：让问题尽量在 lint 和仿真阶段暴露，而不是流到综合、STA、FPGA bring-up 或硅后。

## 13. 配图复盘：每张图对应一个可检查规则

| 配图 | 读图重点 | 对应规则 |
|---|---|---|
| 文件头示例 | 归属、功能、修改记录 | 文件可交接 |
| 模块整体结构 | port、parameter、internal、instance、main code | 边界先于实现 |
| begin/end 与缩进 | 层级清晰 | 控制结构不被误读 |
| 信号命名规则 | `_n/_i/_o/_d/_q` 等后缀 | 波形和代码能互相定位 |
| 条件完整性 | default、完整赋值 | 防 latch |
| 三段式状态机 | 状态寄存、次态、输出 | debug 和综合稳定 |
| 非阻塞赋值 | 寄存器并行采样 | 避免过程顺序假象 |
| 设计规则汇总 | reset/CDC/memory/inout | 前端交付质量门 |

## 14. 最后速记

### 14.1 本章最该记住的结论

- RTL coding style 的第一目标是让代码综合成确定硬件。
- 缩进、命名、文件头和模块顺序服务的是多人 review 与波形 debug。
- 组合逻辑漏赋值会让综合器推 latch。
- 三段式 FSM 让状态存储、跳转条件和输出控制分开。
- 时序逻辑用 `<=`，组合逻辑用 `=`，并守住单驱动。

### 14.2 复现 / 复习清单

- 能解释 `_n`、`_d/_q`、`_ff1/_ff2` 的含义。
- 能写出三段式 FSM 最小骨架。
- 能指出一个漏 `default` 的 `case` 为什么危险。
- 能解释 `b_q <= a_q` 采的是旧 `a_q`。
- 能列出 CDC 单 bit 与 bus 跨域的不同处理口径。

## 复习与自测

1. 为什么 coding style 首先强调可综合性？

   答案：RTL 最终要被综合成网表；不可综合的写法无法生成硬件，后续仿真、STA、后端都接不上。

2. 组合逻辑中 `case` 看起来列完所有二进制取值，还要不要写 `default`？

   答案：工程上仍建议写。信号可能出现 X/Z，状态编码也可能未来扩展；`default` 可以给异常路径一个确定归宿。

3. 为什么时序逻辑里通常用非阻塞赋值？

   答案：寄存器在同一时钟沿并行采样。非阻塞赋值更接近这种并行更新语义，避免代码顺序影响仿真结果。

4. `rst_n` 里的 `_n` 表示什么？如果实际高有效会怎样？

   答案：`_n` 表示低电平有效。若实际高有效，命名会误导使用者，集成时极易把 reset 极性接反。

5. 三段式状态机的三段分别解决什么问题？

   答案：第一段时序逻辑保存当前状态；第二段组合逻辑计算下一状态；第三段用当前状态生成输出控制信号。

6. 为什么大容量数组不建议直接用寄存器堆综合？

   答案：寄存器堆实现会占用大量触发器和组合译码，面积、功耗、时序和综合时间都不划算；工程上应使用 SRAM macro 或专用 memory。

## 工程核对口径

完成本章后，拿到一份 RTL 至少要能检查：

1. 文件结构是否让接口、参数、内部信号、实例和主逻辑一眼可找。
2. 命名是否表达方向、极性、时钟域、寄存器阶段和同步链。
3. 组合逻辑是否全路径赋值，时序逻辑是否单驱动并使用非阻塞。
4. FSM 是否能从波形直接读出当前状态、下一状态和输出原因。
5. 这份代码能否通过 lint、仿真、综合、CDC 和 review 的基本质量门。


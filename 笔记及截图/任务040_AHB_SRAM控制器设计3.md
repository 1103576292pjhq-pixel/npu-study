# 40_AHB_SRAM控制器设计3

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：把 AHB SRAM controller 从 RTL 文件推进到最小仿真闭环，读清工程目录、顶层实例、testbench、AHB 写读 task、Makefile、filelist 和 Verdi 层级。
- 核心概念：`model/rtl/tb/tc/sim`、`sramc_top`、`ahb_slave_if`、`sram_core`、`.port(signal)`、`HTRANS_NONSEQ`、`ahb_write_32`、`ahb_read_32`、`Makefile`、`model.list/rtl.list/tb.list`、`FSDB`、`Verdi hierarchy`。
- 逻辑主线：工程验证不是“运行一条命令”，而是从目录定位 DUT 和模型，用 TB 生成 AHB 写读事务，再通过 Makefile/filelist 编译运行，最后在波形里证明 TB -> DUT -> SRAM macro 的链路闭合。
- 最小学习路径：先认工程目录，再看顶层实例和端口连接，然后读 TB 如何生成 AHB 两阶段事务，最后用仿真入口和 Verdi 追信号。

### 2. 概念地图

| 层级 | 核心对象 | 本讲要掌握的判断 | 后续用途 |
|---|---|---|---|
| 工程组织 | `model/rtl/tb/tc/sim` | 文件按职责分区，不按方便程度堆放 | 定位 bug、维护 filelist |
| 顶层集成 | `sramc_top` | `ahb_slave_if` 与 `sram_core` 如何连接 | 判断 controller 边界 |
| TB 驱动 | clock/reset、AHB task | TB 生成的是协议波形，不是可综合硬件 | 写 sanity test 和回归用例 |
| 协议编码 | `HTRANS` 参数 | 用可读常量替代裸二进制 | 减少 hard code 和误读 |
| 仿真入口 | Makefile、filelist | 工具到底编译了哪些文件 | 排查 compile/module not found |
| 波形证据 | FSDB、Verdi hierarchy | 沿 TB -> DUT -> SRAM 找第一处不一致 | debug AHB SRAM controller |

### 3. 本讲最短主线

```text
进入工程目录
  -> 确认 model/rtl/tb/tc/sim 职责
  -> 读 sramc_top 的实例化边界
  -> 读 sramc_top_tb 的 reset、write_32、read_32
  -> 用 Makefile 调 VCS，filelist 决定编译源
  -> 用 Verdi 层级和波形验证写读闭环
```

## 全视频地图

| 时间段 | 视频块 | 画面证据 | 这一段要学会什么 |
|---|---|---|---|
| 01:28-04:30 | 工程目录定位 | `model/rtl/tb/tc/sim` 目录层级 | 先把 DUT、SRAM 模型、TB、testcase 和仿真入口分清，后面 debug 才不会乱翻文件。 |
| 04:46-19:30 | 顶层实例化 | `sramc_top` 中 `ahb_slave_if` 与 `sram_core` 实例 | 读 `.port(signal)` 时看清当前层真实连线，判断 AHB 侧和 SRAM 侧边界。 |
| 20:10-24:00 | TB top 与协议常量 | clock/reset、AHB 信号、`HTRANS_*` 参数 | TB 不是硬件实现，它负责产生合法 AHB 事务波形；协议编码要命名。 |
| 24:25-34:00 | 写读 task | `ahb_write_32`、`ahb_read_32` | AHB 写读 task 的关键是地址阶段和数据阶段错一拍，采样点必须和协议对齐。 |
| 34:41-44:00 | Makefile/filelist | `run_rtl`、`run_rtl_verdi`、`model.list/rtl.list/tb.list` | 可复现实验依赖固定入口；编译错误优先查 filelist、路径、库模型和宏定义。 |
| 45:25-48:53 | Verdi 闭环 | TB、DUT、`ahb_slave_if`、`sram_core` 层级 | 最终用波形证明 TB -> DUT -> SRAM macro -> HRDATA 的链路闭合。 |
## 1. 工程目录是验证闭环的第一张地图

AHB SRAM controller 工程至少要区分 `model`、`rtl`、`tb`、`tc`、`sim`。这不是形式主义，而是为了让每个 bug 都有明确落点：模型问题去 `model`，设计问题去 `rtl`，激励问题去 `tb/tc`，编译和运行问题去 `sim`。

🔍 视觉核验：视频 01:28-04:30，画面中应能看到工程目录及 `model/rtl/tb/tc/sim` 等层级。
- **教学职责**：这张图负责建立工程定位能力，让读者知道 RTL、模型、TB、testcase 和仿真入口分别在哪里。
- **看图要点**：不要只看目录名，要把每个目录和“谁产生信号、谁被测、谁编译运行”对应起来。
- **看不懂会漏什么**：后续出现 compile error、波形不对或 module not found 时，会在错误目录里找问题。

![工程目录](<./screenshots/任务040_AHB_SRAM控制器设计3/task40_00_project_dirs_01m28s.jpg>)

| 目录 | 职责 | 初学者最容易误解的点 |
|---|---|---|
| `model/` | SRAM 行为模型、库模型或 macro wrapper | 不是本轮主要设计对象，通常作为被集成模型使用 |
| `rtl/` | `sramc_top.v`、`ahb_slave_if.v`、`sram_core.v` 等设计文件 | controller 的功能逻辑在这里 |
| `tb/` | testbench top、任务封装、dump 配置 | 这里可以写时钟等待和仿真 task，不能当作可综合 RTL |
| `tc/` | testcase 或测试序列 | 后续扩展 byte、halfword、边界地址等用例 |
| `sim/` | Makefile、filelist、仿真输出、FSDB | 这是复现实验和 debug 的入口 |

合格的工程阅读能力不是“知道文件很多”，而是能快速回答四个问题：DUT 在哪，SRAM 模型在哪，testbench 从哪驱动，仿真从哪里启动。

可以把这个工程目录理解成一次硬件实验的工作台：`rtl/` 是被测板卡，`model/` 是外接器件模型，`tb/tc/` 是信号发生器和实验脚本，`sim/` 是电源开关、编译按钮和示波器入口。这个比喻的价值在于定位责任；它不是说 TB 可以替代真实硬件，也不是说模型一定等价于最终 SRAM 宏。

## 2. 顶层实例化决定模块边界

读 `sramc_top.v` 时，先找 instance。顶层通常把 `ahb_slave_if` 和 `sram_core` 连起来，前者是 AHB 到 SRAM 控制信号的转换层，后者代表 SRAM macro 组合或封装。先确认边界，再深入某个子模块，顺序不能反。

🔍 视觉核验：视频 04:46-19:30，画面应能看到 `sramc_top.v` 中 `ahb_slave_if` 与 `sram_core` 的实例化，以及 `.port(signal)` 形式的端口连接。
- **教学职责**：这张图负责训练读顶层实例化的基本功，尤其是从端口连接判断模块边界。
- **看图要点**：点号前是子模块端口，括号里是当前层信号；debug 时真正沿括号里的信号追。
- **看不懂会漏什么**：会把同名端口当成必然同义，改错层级，或漏掉 `ahb_slave_if` 到 `sram_core` 的关键中间信号。

![顶层实例](<./screenshots/任务040_AHB_SRAM控制器设计3/task40_01_top_instances_04m46s.jpg>)

Verilog 实例化里，点号前是子模块端口，括号里是当前层信号：

```systemverilog
ahb_slave_if u_ahb_slave_if (
    .hclk   (hclk),
    .haddr  (haddr),
    .hrdata (hrdata)
);
```

`.haddr` 是 `ahb_slave_if` 的端口名，`haddr` 是顶层连进去的信号名。两者可以同名，也可以不同名。阅读代码时不能只靠名字猜，要看括号里真正接到哪根线。

顶层连接还隐含了验证路径。AHB 侧的 `hsel/htrans/hwrite/haddr/hwdata` 进入 slave interface，SRAM 侧的 `bank*_csn`、`sram_w_en`、`sram_addr`、`sram_wdata` 进入 memory macro，`sram_q*` 再组合回 `hrdata`。后续波形 debug 就沿这条边界走。

顶层读法要同时回答“数据怎么走”和“控制怎么走”。写路径看 `HWDATA -> sram_wdata -> SRAM D`，控制路径看 `HSEL/HTRANS/HWRITE/HSIZE/HADDR -> bank*_csn/sram_w_en/sram_addr`；读路径看 `SRAM Q -> sram_data_out -> HRDATA`。如果只看数据线，不看控制线，最容易漏掉“数据是对的，但写到了错误地址或错误 byte lane”。

## 3. Testbench top 生成的是 AHB 事务波形

RTL 模块自己不会动，TB top 负责生成 clock、reset、初始值、AHB 控制信号、写数据、读数据变量和 `$finish`。本讲的 testbench 只做几次 32-bit 写读，它是 sanity test，不是完整验证。

🔍 视觉核验：视频 20:10-22:00，画面应能看到 `sramc_top_tb.v` 中的 clock/reset、AHB 控制信号、写数据、读数据变量。
- **教学职责**：这张图负责说明 testbench top 的任务是产生可重复的 AHB 事务环境。
- **看图要点**：先找 clock/reset，再找 AHB 控制、地址、写数据、读数据变量，最后找 `$finish` 或 testcase 入口。
- **看不懂会漏什么**：会把 TB 里的 `task` 当软件函数，忽略它实际是在时钟边沿驱动总线波形。

![TB top](<./screenshots/任务040_AHB_SRAM控制器设计3/task40_02_tb_top_20m10s.jpg>)

典型骨架可以压缩成：

```systemverilog
initial begin
    reset_all_signals();
    release_reset();

    ahb_write_32(32'h0, 32'h1122_3344);
    ahb_write_32(32'h4, 32'h5566_7788);

    ahb_read_32(32'h0, rdata);
    ahb_read_32(32'h4, rdata);
end
```

这只能证明基本 word 写读路径可跑，不能证明 byte/halfword、未对齐访问、越界地址、reset 后读、wait state、BIST 或低功耗逻辑都正确。sanity test 是入口，不是验收完成。

TB 的最小成功信号不是“仿真结束了”，而是：reset 后没有 X 传播，写事务的地址阶段和数据阶段对齐，读事务返回预期值，且完成拍 `HREADYOUT=1`、`HRESP=OKAY`。如果 TB 没检查这些信号，仿真跑完也可能只是“没有触发报错”。

## 4. 协议常量要命名，不能到处裸写二进制

`HTRANS` 的 `IDLE/BUSY/NONSEQ/SEQ` 如果到处写成 `2'b00/01/10/11`，读者很难把数值和协议含义对应起来。TB 和 RTL 中应该用参数或宏命名协议编码。

🔍 视觉核验：视频 22:06-24:00，画面应能看到 `HTRANS_IDLE`、`HTRANS_BUSY`、`HTRANS_NONSEQ`、`HTRANS_SEQ` 一类可读常量。
- **教学职责**：这张图负责把协议编码和语义绑定，避免裸二进制在 TB/RTL 中扩散。
- **看图要点**：确认 `NONSEQ/SEQ` 是有效传输候选，`IDLE/BUSY` 不应触发 SRAM 访问。
- **看不懂会漏什么**：会把 `2'b10` 当普通数值，review 时看不出这拍是否应该产生一次访问。

![HTRANS 参数](<./screenshots/任务040_AHB_SRAM控制器设计3/task40_03_htrans_params_22m06s.jpg>)

推荐形式：

```systemverilog
localparam HTRANS_IDLE   = 2'b00;
localparam HTRANS_BUSY   = 2'b01;
localparam HTRANS_NONSEQ = 2'b10;
localparam HTRANS_SEQ    = 2'b11;

htrans = HTRANS_NONSEQ;
```

如果多个文件都要使用同一组协议编码，应该放进统一 include 或 package。协议含义一旦分散 hard code，后续 review 和 debug 都会变慢。

## 5. `ahb_write_32` 是一个波形生成器，不是软件函数

`ahb_write_32(addr, data)` 在 TB 里生成一笔 AHB single transfer。AHB 写传输有地址阶段和数据阶段，地址/control 先出现，下一拍才是对应的 `HWDATA`。这个错一拍关系是 SRAM controller 设计的核心难点之一。

🔍 视觉核验：视频 24:25-34:00，画面应能看到 `ahb_write_32` 和 `ahb_read_32` task 对 AHB 控制信号、地址和数据的驱动。
- **教学职责**：这张图负责把 AHB 两阶段传输落成 testbench task 的时序动作。
- **看图要点**：写 task 中地址/control 先出现，下一拍才给 `HWDATA`；读 task 中地址阶段后再采样 `HRDATA`。
- **看不懂会漏什么**：会在 TB 里把地址和写数据同拍驱动，仿真可能看似简单通过，却没有覆盖真实 AHB 写时序。

![写读 task](<./screenshots/任务040_AHB_SRAM控制器设计3/task40_04_write_read_tasks_24m25s.jpg>)

写 task 的最小语义：

```text
posedge N:
  HSEL=1
  HTRANS=NONSEQ
  HWRITE=1
  HSIZE=word
  HADDR=addr

posedge N+1:
  HWDATA=data
  将 HSEL/HTRANS 等控制恢复到 idle 或未选中
```

第二拍清空控制信号很关键。如果控制信号不收回，DUT 可能把下一拍误识别成另一笔有效访问。后续如果要支持 back-to-back 或 burst，就不能简单清空，而要把下一笔地址阶段接上来。本讲 task 只是 sanity test 级 bus functional model。

如果 DUT 支持 wait state，写 task 不能只固定等一个时钟。更稳的 BFM 口径是：地址阶段被 `HREADYIN/HREADYOUT` 接受后，再进入数据阶段；完成拍检查 `HRESP`。本讲可以先用单周期假设跑通，但读代码时要知道这个假设在哪里。

## 6. `ahb_read_32` 的核心是读数据采样点

读 task 先发地址阶段，`HWRITE=0`，然后等待 DUT 在数据阶段返回 `HRDATA`。如果采样早了，读到旧值或 X；如果采样晚了，可能撞上下一个事务。

读 task 的检查口径：

```text
posedge N:
  发读地址和控制

posedge N+1:
  DUT 应该进入读数据返回阶段

约定采样点:
  rdata = HRDATA
```

这个采样点必须和 DUT 的读策略匹配。如果 DUT 是组合读且单周期返回，`N+1` 内数据应稳定；如果 DUT 插入 wait state，TB task 就不能固定等一拍，而要等待 `HREADYOUT` 或项目约定的完成条件。

读 task 的最低检查不应只保存 `rdata`，还要判断采样是否发生在完成拍：

```systemverilog
wait (hreadyout == 1'b1);
if (hresp != 1'b0) $error("AHB read response error");
rdata = hrdata;
```

这里的代码是判定口径，不要求课程工程必须完全照抄。核心是：`HRDATA` 是否有效由协议完成条件决定，不由“我等了一拍”决定。

## 7. Makefile 固定仿真入口，filelist 固定编译边界

Makefile 的价值是把 VCS 编译、运行、dump、Verdi 打开等动作固化下来。工程里不要靠手敲长命令复现实验，因为手敲命令无法保证别人得到同样结果。

🔍 视觉核验：视频 34:41-37:00，画面应能看到 Makefile 中的 `run_rtl`、`run_rtl_verdi`、`clean` 等目标。
- **教学职责**：这张图负责把仿真实验入口固定下来，让同一工程可以被重复运行。
- **看图要点**：区分清理、编译运行、带波形运行、打开 Verdi 的目标；确认默认目标到底调用了哪个 testcase。
- **看不懂会漏什么**：会靠手敲命令调试，别人复现不了；或者旧编译产物没清掉，误以为 RTL 修改已经生效。

![Makefile 目标](<./screenshots/任务040_AHB_SRAM控制器设计3/task40_05_makefile_targets_34m41s.jpg>)

典型目标含义：

| 目标 | 作用 |
|---|---|
| `make clean` | 清理旧仿真产物、日志、波形和临时编译文件 |
| `make run` 或 `make run_rtl` | 编译并运行默认 testcase |
| `make run_rtl_verdi` | 生成 Verdi 可读波形并打开调试环境 |
| `make clean_run` | 先清理再完整重跑 |

🔍 视觉核验：视频 37:12-44:00，画面应能看到 `model.list`、`rtl.list`、`tb.list` 或类似 filelist 被 Makefile 调用。
- **教学职责**：这张图负责说明“参与编译的文件”由 filelist 决定，而不是由你打开了哪些文件决定。
- **看图要点**：模型、RTL、TB 通常分 filelist；相对路径往往以 `sim/` 为基准。
- **看不懂会漏什么**：会改了 RTL 却没加入 filelist，或者新增模块后报 `module not found`，根因不是 Verilog 语法而是编译边界。

![filelist](<./screenshots/任务040_AHB_SRAM控制器设计3/task40_06_filelists_37m12s.jpg>)

很多编译错误不是 RTL 逻辑错，而是 filelist 没把文件加进来、路径相对 `sim/` 不对、库模型缺失、宏定义缺失或编译顺序不对。排查顺序是：

```text
module not found
  -> 找 module 所在文件
  -> 查是否加入对应 filelist
  -> 查相对路径是否以 sim 目录为基准
  -> 查宏定义、库文件和编译顺序
```

可复现命令要固定在 `sim/` 目录执行，典型流程是：

```bash
cd sim
make clean
make run_rtl
make run_rtl_verdi
```

成功信号包括：编译无 fatal error，仿真日志有 testcase 完成信息，生成 FSDB 或项目约定波形文件，Verdi 能打开 TB/DUT/SRAM 层级。失败信号包括：`module not found`、宏未定义、库模型路径错误、仿真卡死、没有生成波形、日志里出现 X/timeout/error。

## 8. Verdi/FSDB 证明的是链路闭合

FSDB 不是为了“有一张波形截图”，而是为了证明 TB 的事务真的到达 DUT，DUT 真的产生 SRAM 控制，SRAM macro 真的响应，读数据真的回到 AHB。

🔍 视觉核验：视频 45:25-48:53，画面应能看到 Verdi hierarchy 中的 TB、`sramc_top`、`ahb_slave_if`、`sram_core` 以及 SRAM 子实例。
- **教学职责**：这张图负责把“仿真跑过”升级成“波形证据能证明链路闭合”。
- **看图要点**：从 TB 层级进入 DUT，再进入 `ahb_slave_if` 和 `sram_core`；不要只看顶层 `HRDATA`。
- **看不懂会漏什么**：读写错误时会只盯返回值，找不到第一处不一致的信号，debug 时间会成倍增加。

![Verdi 层级](<./screenshots/任务040_AHB_SRAM控制器设计3/task40_07_verdi_hierarchy_45m25s.jpg>)

推荐固定观察信号组：

```text
TB AHB 侧:
  hclk, hreset_n, hsel, htrans, hwrite, hsize, haddr, hwdata, hrdata

DUT 识别层:
  valid_ahb, wr_valid_d, rd_valid, addr_d, size_d

SRAM 控制层:
  bank0_csn, bank1_csn, sram_w_en, sram_addr_out, sram_wdata

SRAM 返回层:
  sram_q0 ... sram_q7, sram_data_out, hrdata
```

读写不一致时，不要盯着最后的 `HRDATA`。沿 TB -> DUT -> SRAM macro 找第一处不符合预期的信号。TB 错，改 task；DUT valid 错，改 AHB 有效条件；bank/lane 错，改地址切片和 byte enable；SRAM q 正确但 `HRDATA` 错，改返回 mux 或采样时序。

## 可复现流程：从写读 task 到波形证据

用一组最小动作把本讲闭环跑完整：

```text
1. 进入 sim 目录，先 make clean，避免旧编译产物污染结论。
2. make run_rtl，确认 RTL、model、TB、testcase 都能编译运行。
3. 若读写失败，先看日志里的地址、期望值、实际值和 timeout。
4. make run_rtl_verdi 或项目等价目标，打开 FSDB。
5. 在 Verdi hierarchy 中加入固定观察信号组。
6. 对一笔 write_32，检查地址阶段、数据阶段、wr_valid_d、bank_csn、sram_wdata。
7. 对一笔 read_32，检查 rd_valid、sram_q、hrdata、HREADYOUT/HRESP 和 TB 采样点。
```

通过标准：

```text
写：
  地址/control 在地址阶段有效
  HWDATA 在下一拍到达
  DUT 用上一拍地址/control 写 SRAM
  命中 bank 和 byte lane 与手算一致

读：
  读地址命中 SRAM
  SRAM q 在完成拍前稳定
  HRDATA 与期望值一致
  完成拍 HREADYOUT=1，HRESP=OKAY
```

失败定位表：

| 现象 | 优先怀疑点 | 波形核验 |
|---|---|---|
| 编译 `module not found` | filelist 或路径 | module 文件是否进入 `rtl.list/model.list/tb.list` |
| 写后读回旧值 | 写地址/control 没打一拍或 lane 错 | T1 是否用上一拍地址配当前 `HWDATA` |
| 读到 X | SRAM 未选中、读时序不满足、reset 未释放 | `bank*_csn/sram_w_en/sram_q/hrdata` |
| 仿真卡住 | `HREADYOUT` 未返回、TB wait 条件错 | ready/resp 是否进入完成拍 |
| 只有 32-bit 通过 | byte/halfword lane 未测 | `HSIZE/HADDR[1:0]/bank*_csn[3:0]` |

## 9. 本讲和 AI+IC/NPU 的连接

NPU 里的 weight buffer、activation buffer、scratchpad SRAM 都需要同样的工程能力：从 bus transaction 追到本地 SRAM bank，再从 bank 追到 byte lane 和读回 mux。后续做算子加速或片上存储调度时，很多性能和功耗问题不是算法公式错，而是 buffer 接口、地址映射、读写时序、filelist 集成或波形观察点错。

## 最后速记

### 本章最该记住的结论

- 工程目录先回答“谁是 DUT、谁是模型、谁驱动、谁运行”。
- `.port(signal)` 里括号内的信号才是当前层真实连接。
- AHB 写 task 生成的是地址阶段和数据阶段错一拍的协议波形。
- `HTRANS` 等协议编码要命名，不能到处裸写二进制。
- Makefile 决定仿真入口，filelist 决定哪些文件真正参与编译。
- Verdi debug 要沿 TB -> DUT -> SRAM macro 找第一处不一致。

### 复习与自测

1. 为什么 `ahb_write_32` 不能理解成普通软件函数？

   答案：它在 testbench 中按时钟生成 AHB 总线波形，包括地址阶段、数据阶段和控制信号恢复。它的结果是协议时序，不是一个立即返回的计算值。

2. AHB 写传输为什么需要 controller 保存地址/control 一拍？

   答案：AHB 写数据 `HWDATA` 在地址/control 的下一拍到达，而 SRAM macro 写入通常要求地址、片选、写使能和写数据同拍有效，所以 controller 必须把上一拍地址/control 保存下来对齐当前拍数据。

3. 编译时报 `module not found`，优先查哪里？

   答案：先找 module 所在源文件，再查是否加入对应 filelist，随后查相对路径、宏定义、库模型和编译顺序。

4. Verdi 中 `HRDATA` 读错时应该如何定位？

   答案：按 TB AHB 信号、DUT valid/read/write、SRAM 控制信号、SRAM q 输出、`sram_data_out`/`HRDATA` mux 的顺序追踪，找到第一处不符合预期的信号。

5. `make run_rtl` 报 `module not found: sram_core`，能否先改 RTL 逻辑？

   答案：不能优先改逻辑。先确认 `sram_core` 所在文件是否存在、是否加入正确 filelist、路径是否相对 `sim/` 正确、编译顺序是否满足依赖。这个错误首先是编译边界问题。

6. 为什么读 task 最好等待 `HREADYOUT` 后再采样 `HRDATA`？

   答案：`HREADYOUT` 是 AHB 数据阶段完成条件。若 DUT 插入 wait state，固定等一拍会过早采样；等待完成拍才能保证 `HRDATA` 和 `HRESP` 有协议意义。

7. 判断题：Verdi 里 `HRDATA` 最终正确，就说明 `bank*_csn`、byte lane 和写地址对齐一定正确。

   答案：错。单一用例可能刚好掩盖 bank/lane 错误。完整判定要沿 TB -> DUT -> SRAM macro 检查第一处不一致，并补 byte/halfword、边界地址和 back-to-back 用例。


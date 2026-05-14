# 任务98：eFlash 连续 program data（RTL）

## 本章知识全景图

这一讲把 eFlash 的“单 word program”改造成“一次事务内连续 program 多个 DWord”。核心不是多加几个 data 寄存器，而是重构 program FSM：外层 setup 只做一次，每个 DWord 的地址选择、数据选择、program pulse 和 hold 循环执行，直到 `program_cnt` 达到 `program_number`。

| 层级 | 核心概念 | 本讲结论 |
|---|---|---|
| 设计目标 | 连续 program | 避免每写一个 DWord 都重新走 TNVS/NVSTR/recover，提高写入效率。 |
| 寄存器接口 | `program_data0..3`、`program_number` | data 告诉硬件写什么，number 告诉 FSM 写几个。 |
| 端口传播 | interface、top、control、flash wrapper | 新信号必须从寄存器层一路传到真正使用它的控制逻辑。 |
| FSM 改造 | 外层 setup + 内层 per-word loop | program setup 只做一次；address setup、program、hold 对每个 word 重复。 |
| 计数器 | `program_cnt` | 记录当前正在写第几个 DWord，并决定循环或结束。 |
| 数据/地址选择 | data mux、YADDR increment | 同一 row 内 XADDR 不变，YADDR 随 `program_cnt` 增加；跨 row/page 需要额外边界处理。 |

最短学习路径：

```text
单 word program 为什么低效
  -> 新增 program_data0..3 和 program_number
  -> 把新寄存器穿过模块端口
  -> 找出 FSM 中哪些状态只做一次、哪些状态要循环
  -> 用 program_cnt 判断当前 word 和结束条件
  -> 用 case/mux 选择 data，用 YADDR + cnt 选择地址
  -> 交给下一讲 TB 和波形验证
```

## 全视频地图

| 时间段 | 视频块 | 视觉证据 | 学习目标 |
|---|---|---|---|
| 00:01-02:58 | 作业目标和效率问题 | `task98_00_assignment_goal_00m01s.jpg` | 理解单 word program 的重复等待为什么低效。 |
| 03:01-06:43 | 新增寄存器 | `task98_01_program_data_regs_03m01s.jpg`、`task98_02_program_number_04m39s.jpg` | 新增多份 program data 和 program number。 |
| 13:04-19:54 | 新信号穿过端口链 | `task98_03_port_chain_13m04s.jpg` | 从 interface 到 control/top/wrapper 补齐输入输出。 |
| 20:46-26:51 | FSM 循环位置 | `task98_04_state_loop_20m46s.jpg` | 判断哪些 program 状态需要循环，哪些只执行一次。 |
| 27:19-33:54 | program counter 与清零 | `task98_05_program_counter_28m10s.jpg`、`task98_06_recover_finish_clear_32m47s.jpg` | 用计数器记录 word index，并在 recover/finish 后清零。 |
| 34:31-40:18 | 数据 mux 和地址递增 | `task98_07_data_mux_case_38m05s.jpg` | 按 counter 选择 data，YADDR 随 word index 增加。 |

## 视觉证据与截图说明

| 截图 | 教学职责 |
|---|---|
| ![连续 program 作业目标](<./screenshots/任务098_eflash连续program_data_(rtl)/task98_00_assignment_goal_00m01s.jpg>) | 定位作业目标：把单次 program 改成连续 program。 |
| ![program data 寄存器](<./screenshots/任务098_eflash连续program_data_(rtl)/task98_01_program_data_regs_03m01s.jpg>) | 展示新增 `program_data0..3` 这类寄存器入口。 |
| ![program number](<./screenshots/任务098_eflash连续program_data_(rtl)/task98_02_program_number_04m39s.jpg>) | 说明连续写几个不能写死，必须由寄存器配置。 |
| ![端口链补齐](<./screenshots/任务098_eflash连续program_data_(rtl)/task98_03_port_chain_13m04s.jpg>) | 说明新信号必须从寄存器层传到控制逻辑。 |
| ![FSM 循环状态](<./screenshots/任务098_eflash连续program_data_(rtl)/task98_04_state_loop_20m46s.jpg>) | 对齐 program setup 和 per-word loop 的边界。 |
| ![program counter](<./screenshots/任务098_eflash连续program_data_(rtl)/task98_05_program_counter_28m10s.jpg>) | 显示 `program_cnt` 这类循环计数器的加入位置。 |
| ![recover finish 清零](<./screenshots/任务098_eflash连续program_data_(rtl)/task98_06_recover_finish_clear_32m47s.jpg>) | 说明一次连续事务结束后必须清掉临时计数。 |
| ![data mux case](<./screenshots/任务098_eflash连续program_data_(rtl)/task98_07_data_mux_case_38m05s.jpg>) | 展示按 counter 选择当前要写入的数据。 |

## 1. 单 word program 的低效来自重复外层等待

原来的 controller 一次只写一个 DWord。写完一个 word 后退出事务，再写下一个 word 时又要重新走 TNVS、NVSTR 起始、NVH、recover 等外层时序。连续写 4 个 DWord 时，这些外层等待被重复 4 次，吞吐明显变差。

连续 program 的目标是：

```text
原流程:
  setup -> program word0 -> recover
  setup -> program word1 -> recover
  setup -> program word2 -> recover
  setup -> program word3 -> recover

改造后:
  setup
    -> program word0
    -> program word1
    -> program word2
    -> program word3
  recover
```

但不能把所有时序都省掉。每个 DWord 仍然需要正确的地址选择、数据选择、program pulse 和 hold。真正省掉的是不必重复的外层准备和结束段。

## 2. 新增 data 寄存器和 `program_number`

连续写需要两个信息：写什么数据，以及写几个 DWord。没有 data，硬件不知道每一拍 program 哪个值；没有 number，FSM 不知道循环几次后结束。

本讲以最多连续写 4 个 DWord 为例：

```systemverilog
logic [31:0] program_data0;
logic [31:0] program_data1;
logic [31:0] program_data2;
logic [31:0] program_data3;
logic [31:0] program_number;
```

`program_number` 不应写死成 4。支持 4 个 data 寄存器，不等于每次必须写 4 个。更好的语义是：

| `program_number` | 行为 |
|---:|---|
| 1 | 只写 `program_data0` |
| 2 | 写 `program_data0..1` |
| 3 | 写 `program_data0..2` |
| 4 | 写 `program_data0..3` |

工程上还应定义非法值策略。若暂时只支持 1-4，可以把 0 和大于 4 判为 error，或在寄存器写入时 clamp，但不能让 FSM 在非法 number 下无限循环。

## 3. 新信号必须穿过完整端口链

新增寄存器后，最容易漏的是端口链。寄存器值只在 interface 层存在没有意义；真正驱动 eFlash macro 的 control/wrapper 必须拿到这些值。

需要逐层检查：

```text
register/interface
  -> eflash top
  -> control / FSM
  -> flash wrapper
  -> macro control/data pins
```

每加一个输入，都要问三件事：

1. 这个信号在哪里被软件配置？
2. 它经过哪些 module port 才能到达 FSM？
3. 它最终影响的是地址、数据、控制脚，还是状态跳转？

没有自动脚本生成端口时，手动补端口很容易漏某一层。漏端口的典型失败信号是：编译报未连接/未声明，或者波形中寄存器有值但控制逻辑侧一直是 0。

## 4. FSM 的关键是区分“只做一次”和“每个 word 都做”

连续 program 的状态机不能简单复制原状态，也不能把整个原 program 流程套进循环。要先把状态按职责分组。

| 状态/阶段 | 是否每个 DWord 重复 | 原因 |
|---|---|---|
| program setup / TNVS | 否 | 它建立外层 program 事务，连续写时只需做一次。 |
| NVSTR 拉起 | 否 | 连续事务内保持 program 模式，不必每个 word 重启。 |
| address setup | 是 | 每个 DWord 的 YADDR 不同，必须重新选中。 |
| program pulse | 是 | 每个 DWord 都要真正写入一次。 |
| address/program hold | 是 | 每个 DWord 写完后都要满足 hold。 |
| recover | 否 | 整个连续 program 完成后再恢复。 |

可读状态骨架：

```text
IDLE
  -> PROG_SETUP
  -> WORD_ADDR_SETUP
  -> WORD_PROGRAM
  -> WORD_HOLD
      if last_word: -> PROG_RECOVER
      else:         -> WORD_ADDR_SETUP
  -> IDLE
```

这个结构保留了 eFlash macro 对每个 word 的基本时序，同时避免外层等待反复出现。

## 5. `program_cnt` 决定当前 word 和结束条件

`program_cnt` 的职责不是“为了有个计数器”，而是同时服务三个判断：

1. 当前应该选哪一份 `program_data`。
2. 当前 YADDR 应该在 base address 上偏移多少。
3. 当前 word 写完后，是回到 per-word loop，还是进入 recover。

典型逻辑可以写成：

```systemverilog
logic [1:0] program_cnt;
logic       program_last;

assign program_last = (program_cnt + 1'b1) >= program_number[1:0];

always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n)
    program_cnt <= '0;
  else if (program_start)
    program_cnt <= '0;
  else if (word_program_done && !program_last)
    program_cnt <= program_cnt + 1'b1;
  else if (program_recover_finish)
    program_cnt <= '0;
end
```

实际代码要根据项目中 `program_number` 的编码确定比较方式。如果 `program_number=4` 表示写 4 个，且 counter 从 0 计数，那么最后一次通常是 `program_cnt == program_number - 1`。这个 off-by-one 是最常见 bug。

## 6. data mux 应由 `program_cnt` 选择

连续 program 不是把四个 data 同时送进 macro，而是在每个 program pulse 前选择当前 word 对应的 data。

示例：

```systemverilog
always_comb begin
  unique case (program_cnt)
    2'd0: flash_din = program_data0;
    2'd1: flash_din = program_data1;
    2'd2: flash_din = program_data2;
    2'd3: flash_din = program_data3;
    default: flash_din = program_data0;
  endcase
end
```

不要让 essential logic 只藏在截图里。这个 mux 是连续 program 的功能核心：波形中看到 `program_cnt` 递增但 `flash_din` 不变，就说明 data mux 没接对或选择条件没对。

## 7. YADDR 递增要先限定边界

本讲默认在同一个 row 内连续 program：XADDR 不变，YADDR 随 `program_cnt` 增加。

```systemverilog
assign flash_xaddr = program_xaddr;
assign flash_yaddr = program_yaddr + program_cnt;
```

这个写法只在两个前提下安全：

1. 本次连续 program 不跨 row。
2. `program_yaddr + program_number - 1` 不超过 31。

如果后续要支持跨 row 或跨 page，不能只让 YADDR 溢出。必须增加边界处理：

```text
YADDR 到 31 后:
  YADDR 回 0
  XADDR 加 1

XADDR 低两位到 page 边界后:
  需要确认是否允许跨 page program
  若不允许，必须报错或拆成两次事务
```

课程本次以 4 个 word 演示 RTL 改造，因此边界可以暂时收窄，但笔记必须把边界说清楚。

## 8. 清零点要放在一次事务结束处

连续事务结束后，`program_cnt` 这类临时状态必须清零。适合的清零点是 recover finish 或回到 idle 的确认点。

如果清零太早，最后一个 word 的 hold 或 recover 期间可能读不到正确 index；如果清零太晚，下次 program 事务可能从上次计数继续，导致第一个 word 被写到错误地址或选错 data。

推荐判断：

```text
program_start:
  program_cnt = 0

each word done and not last:
  program_cnt++

recover_finish:
  program_cnt = 0
```

这里的 `recover_finish` 是“一次连续 program 完整结束”的证据，不是“某个 word 写完”的证据。

## 9. RTL 改造完成不等于任务完成

这一讲结束时 RTL 只是“看起来改好了”。它还必须通过下一讲 TB 和波形证明：

| 需要证明的点 | 波形/仿真信号 |
|---|---|
| `program_number` 被正确写入 | 配置寄存器值稳定。 |
| `program_cnt` 从 0 到 N-1 | counter 每写完一个 word 增加一次。 |
| `flash_din` 随 counter 变化 | data mux 选择 0/1/2/3 对应数据。 |
| YADDR 递增 | 写入地址从 base 连续增加。 |
| NVSTR 外层不重复 | 连续事务内不为每个 word 重走外层 setup。 |
| recover 后清零 | 下一次事务从干净状态开始。 |

没有 TB 证明，RTL 修改只能叫“编辑完成”，不能叫“功能完成”。

## 深层理解：连续 program 是流水线，不是复制四座工厂

连续 program 的目标不是把单 word program 复制四份，而是把一条生产线改造成可以连续上料。外层 `program setup/NVSTR/recover` 像开机、预热、收尾；每个 DWord 的 data、YADDR、program pulse 像流水线上的单件加工。若每个 word 都重新开机预热，效率收益就消失；若只开一次机但不更新 data/address，就会把同一件货反复加工。

因此 RTL 设计必须分清两类状态：

| 层级 | 只做一次还是每 word 重复 | 典型信号 |
|---|---|---|
| 事务层 | 一次连续 program 做一次 | enable、global setup、NVSTR start、recover finish |
| beat/word 层 | 每个 DWord 重复 | `program_cnt`、data mux、YADDR + offset、program pulse |
| 边界层 | 每次配置前检查 | `program_number` 合法性、row/page 边界、boot protect |

`program_cnt` 是这条流水线的工位编号：它同时决定当前拿哪个 data、写哪个 YADDR、是否已经到最后一个 word。这个 counter 如果清零太早，最后一个 word 还没真正收尾；如果递增条件太松，可能跳过 data；如果没有边界检查，`program_yaddr=30, number=4` 这种配置会把事务推过 row 边界。

## AI+IC 连接

连续 program 的思路和 NPU/SoC 中的 burst transaction 是同一类问题：把多个小操作合并到一个事务里，减少外层握手、启动、恢复或总线仲裁开销。DMA burst、AXI burst、NPU tile 数据搬运、权重连续加载，都要做同样的分层判断：哪些开销是 transaction-level，哪些动作必须 per-beat/per-word 重复。

## 工程练习

1. 在原单 word program FSM 上标出“只做一次”和“每 word 重复”的状态。
2. 写一个 `program_last` 判断，要求 `program_number=1/2/3/4` 都正确。
3. 写出 `program_cnt` 清零条件，并说明为什么不能在每个 word 结束就清零。
4. 给 `program_yaddr + program_cnt` 增加不跨 row 的断言。
5. 思考如果支持 8 或 16 个 word，需要改寄存器数量、data mux，还是改成 FIFO/小 RAM 更合理。

## 常见误区和失败信号

| 误区 | 正确判断 |
|---|---|
| 连续 program 只是多加几个 data 寄存器。 | 更关键的是 FSM loop、counter、data mux、地址递增。 |
| `program_number` 固定为 4 就行。 | 连续能力要支持写 1 到最大值，否则功能反而变死。 |
| 每个 word 都重新 TNVS/NVSTR/recover。 | 这样没有连续 program 的效率收益。 |
| XADDR/YADDR 可以随便加。 | 本讲默认同 row 内递增；跨 row/page 需要额外边界设计。 |
| RTL 编译过就完成。 | 还要 TB 配置、波形和 readback 证明。 |

## 复习与自测

1. 连续 program 相比单 word program 主要省掉什么？  
   答案：省掉多个 word 之间重复的外层 program setup、NVSTR 起始和 recover 等等待；每个 word 的 program pulse 和 hold 仍要保留。

2. 为什么必须有 `program_number`？  
   答案：FSM 需要知道循环几次后结束。没有 number，就无法支持写 1/2/3/4 个 word，也容易无限循环或提前结束。

3. `program_cnt` 至少服务哪三个功能？  
   答案：选择当前 data、计算当前 YADDR 偏移、判断是否是最后一个 word。

4. 为什么 recover finish 是合理的清零点？  
   答案：它表示一次连续 program 事务完整结束；此时清零不会破坏最后一个 word 的 hold/recover，也能保证下一次事务从 0 开始。

5. 如果 `program_yaddr=30` 且 `program_number=4`，本讲的简单 YADDR 递增有什么风险？  
   答案：会跨出当前 row，YADDR 可能溢出。需要禁止该配置、拆事务，或增加 XADDR 递增和跨 row/page 处理。

## 工程核对口径

RTL 改完后，不要先问“能不能编译过”，先问“连续事务的五根骨架是否完整”：

1. 配置骨架：`program_number` 和多组 data 寄存器能从 AHB 写入并稳定到 FSM。
2. 端口骨架：新增信号从寄存器层、控制器层到 flash 控制脚没有断链。
3. 循环骨架：FSM 能在每个 word 后回到 per-word program 点，而不是重走外层 setup。
4. 选择骨架：`program_cnt` 同时驱动 data mux、YADDR offset 和 last 判断。
5. 收尾骨架：recover 完成后统一清零，下一次事务从干净状态开始。

任何一根骨架缺失，波形都可能“看起来动了”，但功能并未闭合。连续 program 的 RTL 不是堆寄存器，而是设计一条能连续、有边界、有收尾的硬件流水线。


# 45_AHB_SRAM控制器设计8

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：在 AHB SRAM 控制器项目里打开 BIST/MBIST，沿层级追到真实 SRAM macro 端口，证明 March 类内建自测试如何通过状态机、计数器、测试地址、测试数据和比较逻辑完成全存储阵列检查。
- 核心概念：BIST mode、function mode、SRAM wrapper、March test、低有效 SRAM 控制脚、`bist_done`、`bist_fail`、状态机和 counter 协同。
- 逻辑主线：先在 testbench 里只打开 `bist_en`，再从顶层波形一路下钻到 BIST wrapper 和 SRAM macro，确认 AHB 侧没有读写也能由内部测试逻辑驱动存储体；最后把波形行为反查到 RTL，读懂 test pattern、address counter、check compare 和完成条件。
- 最小主线：
  - `bist_en=1` 后，AHB function path 失去主导权。
  - 真正进入 SRAM macro 的是 BIST 生成的 `data_test/address_test/WEN/CEN/OEN`。
  - March 测试用多轮全地址遍历暴露 stuck-at、读写耦合和保持类问题。
  - `check_en` 打开时，读出值必须等于当前期望 pattern，否则置 `bist_fail`。
  - 只有最终阶段全地址比较通过，并且地址计数到末尾，`bist_done` 才能拉高。

### 2. 概念地图

| 概念层级 | 核心概念 | 前置知识 | 延伸应用 |
| :---: | :---: | :---: | :---: |
| 系统入口 | `bist_en`、testbench、AHB idle | AHB slave、仿真 task | DFT/MBIST bring-up |
| 层级结构 | top、SRAM controller、BIST wrapper、SRAM macro | Verilog instance、端口连接 | 层级化 debug |
| 模式选择 | function path 与 BIST path mux | mux、低有效 enable | 测试模式隔离 |
| 测试算法 | March 类读写序列 | SRAM 读写时序、地址遍历 | 存储器故障检测 |
| 完成判据 | `check_en`、`bist_fail`、`bist_done` | 比较器、FSM、counter | 自测试结果上报 |
| 代码范式 | 两段式/三段式 FSM、命名、状态位宽 | RTL coding style | 控制器设计与面试 |

### 3. 阅读顺序

- 先建立一个判断：BIST 不是 AHB 发起的一次普通访问，而是存储器内部自测流程。
- 再沿硬件层级追信号：顶层 function 信号没有用，必须看到 macro 端口前的 BIST mux 输出。
- 最后把 March 波形反查到 RTL：状态机负责阶段，counter 负责地址和等待，pattern 负责期望值，compare 负责失败判定。

### 4. 全讲结构地图

| 视频阶段 | 画面/操作主线 | 本阶段要学会的判断 |
|---|---|---|
| 00:00-02:38 | 在 top testbench 打开 `bist_en`，注释普通 AHB write/read task，仿真等待 `bist_done` | BIST 是独立自测流程，不能和普通 AHB 访问混在一起观察 |
| 03:22-08:31 | 从 top 和 SRAM controller 上层拉波形，发现 function path 没有真实读写 | 顶层 AHB 信号不是 BIST 的有效证据 |
| 08:45-10:47 | 进入 BIST wrapper，观察 function/BIST mux 和低有效 SRAM 控制脚 | `bist_en=1` 时 macro 由内部测试信号驱动 |
| 11:52-30:41 | 顺着波形读 March 类算法：全写 0、读比较、写反值、多轮遍历 | March 测试靠多轮全地址读写比较暴露 SRAM 故障 |
| 32:22-40:13 | 回到 RTL 层级和端口连接，确认 wrapper、BIST core、`8K x 8` macro 的关系 | 代码阅读应先找 mux、端口连接和真实 macro 输入 |
| 40:13-52:24 | 阅读 pattern、counter、check compare、done/fail 逻辑 | `check_en` 判失败，最终阶段全通过才产生 `bist_done` |
| 54:24-57:47 | 总结状态机写法、命名、状态位宽和课后复现实验 | BIST RTL 是多状态控制器和波形结合读代码的样板 |

## 1. BIST 打开后，AHB 侧读写不再是证据

打开 `bist_en` 的第一件事，是在 testbench 里停止普通 AHB 写读 task，只等待 `bist_done`；这能把验证目标从“总线功能访问”切换成“内建存储器自测试”。如果仍然同时跑 AHB 写读，波形会混入 function path 的活动，反而看不清 BIST 是否真的独立驱动 SRAM。

视觉验证：视频 00:45-02:38（testbench 中 `bist_en` 被置 1，原来的 write/read task 被注释，仿真运行后等待 `bist_done`）。

![BIST enable in testbench](<./screenshots/任务045_AHB_SRAM控制器设计8/task45_00_bist_enable_00m45s.jpg>)

顶层 AHB 信号不是判断 BIST 的主证据。课程里把顶层写信号拉进波形后，可以看到 AHB 侧并没有真实发起读写；即使某些数据线上存在复位值或遗留值，也不会决定 SRAM macro 被写入什么。BIST 的本质是绕开正常软件/总线路径，用内部生成的地址、数据和控制脚覆盖整片 SRAM。

视觉验证：视频 03:22-04:45（顶层和 SRAM controller 上层信号被拉入波形，AHB 侧没有有效 read/write，但 `bist_done` 已经能完成）。

![Top-level waveform is not enough](<./screenshots/任务045_AHB_SRAM控制器设计8/task45_01_top_wave_signals_03m22s.jpg>)

这一步的关键结论很硬：在 BIST 模式下，顶层 `HWDATA/HWRITE/HADDR` 这类 function 信号就算有值，也不是 SRAM macro 的真实刺激源；真正要看的信号一定在 BIST wrapper 输出到 macro 的那一侧。

## 2. 必须下钻到 wrapper/macro 边界，才能看见真实测试路径

BIST wrapper 的核心工作是做模式选择：`bist_en=0` 时把 function path 的地址、数据和读写控制送给 SRAM macro；`bist_en=1` 时改用 BIST 内部生成的测试地址、测试数据和控制脚。这个 mux 边界是理解本讲的第一处硬件分水岭。

视觉验证：视频 08:45-10:47（wrapper 中 function 信号被旁路，BIST 生成的 `data_test/address_test/write_in_test/CEN/OEN` 等信号成为有效路径）。

![BIST mux selects internal test path](<./screenshots/任务045_AHB_SRAM控制器设计8/task45_02_bist_mux_mode_08m45s.jpg>)

SRAM macro 常见控制脚是低有效：`CEN=0` 表示芯片选中，`OEN=0` 表示输出使能，`WEN=0` 表示写有效。BIST 模式下，wrapper 通常会让 `CEN/OEN` 保持在可访问状态，再由内部状态机决定当前 cycle 是读还是写。这里不能用软件直觉理解“enable 拉高才有效”；对低有效端口，波形上的 0 才是动作开始。

模式选择可以压成一张表：

| 信号类别 | function mode | BIST mode | 读波形时的判据 |
|---|---|---|---|
| 地址 | AHB/controller 地址 | BIST address counter | macro 端口的地址是否自动遍历 |
| 写入数据 | AHB 写数据或 controller 数据 | BIST test pattern | 是否出现全 0、全 1 等测试图样 |
| 写使能 | 正常写访问译码 | BIST FSM 读写阶段 | `WEN=0` 才是真写 |
| 读使能 | 正常读访问译码 | BIST FSM 读/比较阶段 | 读数据是否进入 compare |
| 完成状态 | AHB transfer 完成 | `bist_done/bist_fail` | 自测试是否结束和是否失败 |

视觉验证：视频 32:22-38:25（`sram_bist` wrapper 里同时例化 BIST 逻辑和 `8K x 8` SRAM macro，端口连接显示地址、数据和控制脚经过 BIST 模块后进入存储体）。

![SRAM BIST wrapper structure](<./screenshots/任务045_AHB_SRAM控制器设计8/task45_05_sram_bist_wrapper_32m22s.jpg>)

`bist_en` 还会控制 BIST clock。若测试模式没有打开，BIST clock 可以被关住，内部测试状态机不会运转；一旦 `bist_en` 或 DFT 相关使能打开，BIST clock 接入系统时钟，测试状态机开始生成地址和控制脚。这解释了为什么只改一个 `bist_en`，整条内部测试链路就被激活。

## 3. March 测试不是一个动作，而是多轮全地址读写比较

March 类算法的基本思想是按某个地址方向遍历全部存储单元，对每个单元执行“写某值、读出确认、写相反值、再读确认”等序列。它不是为了验证某一个地址能读写，而是让每个 cell 在不同历史状态下被写 0、读 0、写 1、读 1，从而暴露 stuck-at、读写耦合和状态保持类故障。

第一轮最直观：地址从 0 开始递增，`WEN=0`，测试图样为 0，把所有 SRAM 单元初始化为 0。课程里 13 bit 地址一路遍历到全地址末尾，说明测试不是抽几个点，而是覆盖整个 `8K x 8` 宏。

视觉验证：视频 11:52-13:19（`address_test` 从 0 开始累加到末尾，`WEN=0`，测试数据为 0，完成全阵列写 0）。

![March write-zero pass](<./screenshots/任务045_AHB_SRAM控制器设计8/task45_03_march_write_zero_11m52s.jpg>)

第二类阶段开始把“读、比较、写”组合起来。一次读通常要经历至少一个数据返回周期，再用下一拍或后续状态进行比较；因此波形上会看到同一地址停留多个 cycle，而不是每个时钟都换一个地址。课程里把 clock 拉回来就是为了数清读、比较、写之间的拍数关系。

视觉验证：视频 14:00-18:32（同一地址经历读 0、比较 0、写 1 等 cycle，读数据延迟返回，compare 不和地址发出完全同拍）。

![Read compare write cycles](<./screenshots/任务045_AHB_SRAM控制器设计8/task45_04_read_compare_write_cycles_14m00s.jpg>)

可以把本讲观察到的 March 行为整理成下面的学习口径。具体状态名可以因实现不同而不同，但每一类状态的职责必须能在波形中对上。

| 阶段 | 地址方向 | 对每个地址做什么 | 结束后存储内容倾向 | 主要检查什么 |
|---|---|---|---|---|
| P1 | 递增 | 全部写 0 | 全 0 | 初始化阵列 |
| P2 | 递减或反向 | 读 0，比较 0，再写 1 | 全 1 | 0 是否能保持并读出 |
| P3 | 递增 | 读 1，比较 1，写 0，读 0，比较 0，写 1 | 全 1 | 0/1 双向切换 |
| P4 | 递增或反向 | 读 1，比较 1，再写 0 | 全 0 | 1 是否能保持并被擦回 0 |
| P5 | 递增或反向 | 读 0，写 1，读 1，写 0 | 全 0 | 再次覆盖切换方向 |
| P6 | 递增 | 全部读 0 并比较 | 全 0 | 收尾确认 |

这里的“递增/反向”不需要死背，重要的是知道地址方向会变化。March 的价值正是通过不同方向和不同历史值组合，增加相邻单元、地址译码和读写路径问题被触发的概率。

## 4. `check_en` 是失败判据，`bist_done` 是全流程通过判据

BIST 不只是写一遍、读一遍，还必须比较读出值和期望 pattern。RTL 中 `check_en=1` 时，比较器检查 `data_out` 是否等于当前 `test_pattern`；不相等就置失败。`bist_fail` 一旦被置起，说明至少有一个地址在某个 March 子阶段没有读出期望值。

视觉验证：视频 46:47-47:12（代码中 `check_en` 打开后，将 test pattern 与读出值比较，不一致进入 fail 路径）。

![Check enable compare logic](<./screenshots/任务045_AHB_SRAM控制器设计8/task45_07_check_enable_compare_46m47s.jpg>)

一个合格的 BIST 完成条件至少包含两层：

1. 局部比较通过：每个需要 compare 的读周期，读出值等于当前期望 pattern。
2. 全局遍历完成：最终阶段的地址计数到全地址末尾，并且此前没有失败。

`bist_done` 不能在某个子阶段提前拉高。课程里最后阶段是持续读 0、比较 0，只有走到地址末尾且仍未失败，完成信号才成立。

视觉验证：视频 50:55-52:24（最终 compare 阶段中，只有全地址测试到末尾并通过，内部 done 信号才映射为 `bist_done`）。

![BIST done logic](<./screenshots/任务045_AHB_SRAM控制器设计8/task45_08_bist_done_logic_50m55s.jpg>)

这也给验证人员一个很实用的检查顺序：

```text
1. 先看 bist_en 是否真正打开了 BIST clock 和测试路径。
2. 再看 macro 端口是否出现自动地址遍历。
3. 再看 WEN/CEN/OEN 是否符合读写阶段。
4. 再看 test pattern 与 DOUT 是否在 check_en 时匹配。
5. 最后看 bist_done 是否只在最终地址和最终阶段后拉高。
```

如果 `bist_done=1` 但中间没有全地址遍历，说明 done 逻辑或仿真观察点错了；如果全地址遍历存在但 `bist_fail=1`，下一步要定位首次 compare mismatch 的地址和 pattern。

## 5. 代码阅读要从 mux、pattern、counter、FSM 四处入手

读 BIST RTL 时，不要从 400 多行代码的第一行顺着看。更有效的入口是四个结构：模式 mux、test pattern、address counter、FSM 跳转。

视觉验证：视频 40:13-42:29（代码中 `data_test/address_test/WEN/CEN/OEN` 根据 `bist_en` 在 function 输入与 BIST 内部信号之间选择，`test_pattern` 由 pattern select 控制）。

![BIST mux code](<./screenshots/任务045_AHB_SRAM控制器设计8/task45_06_bist_mux_code_40m13s.jpg>)

四个入口各自回答不同问题：

| RTL 入口 | 要回答的问题 | 波形对应 |
|---|---|---|
| 模式 mux | function mode 和 BIST mode 谁驱动 macro | macro 端口是否跟随内部测试信号 |
| test pattern | 当前期望写入/比较的是 0 还是 1 | `DIN` 和 compare 期望值 |
| address counter | 地址递增还是递减，何时到末尾 | `address_test` 的方向和终止 |
| FSM | 当前处于写、读、比较、等待还是完成 | `WEN/check_en/done` 的变化 |

状态机不是孤立控制块。它会产生 `count_en`、`up_down`、`test_addr_reset`、`pattern_select`、`check_en` 等控制信号；这些信号再驱动计数器和数据选择；计数器末尾条件又反馈给状态机，决定是否进入下一阶段。这个闭环比单独背状态名更重要。

## 6. 这段 BIST RTL 同时是状态机写法样板

课程最后把 BIST 代码当作 coding style 样板看，是因为这个模块包含真实工程状态机的典型结构：状态多、输出多、计数器多、反馈条件多，但命名和分层足够清楚。状态位宽用 5 bit，是因为状态数量超过 16 时，4 bit 已经不够；5 bit 可表达 32 种状态。

视觉验证：视频 54:24-56:34（状态机状态较多，状态位宽约 5 bit，状态机输出 `count_en/up_down/test_addr_reset` 等信号，再影响 counter 和后续跳转）。

![FSM coding style](<./screenshots/任务045_AHB_SRAM控制器设计8/task45_09_fsm_coding_style_54m24s.jpg>)

面试或项目里写状态机时，最小可靠模板是：

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
    unique case (state)
        IDLE: begin
            if (start) begin
                next_state = WRITE_ZERO;
            end
        end
        WRITE_ZERO: begin
            if (addr_last) begin
                next_state = READ_ZERO;
            end
        end
        default: begin
            next_state = IDLE;
        end
    endcase
end
```

真实工程里还会增加输出译码块，用当前状态生成 `wen_test`、`check_en`、`pattern_select`、`count_en`。一旦输出也很多，三段式比把所有逻辑塞进一个 always 块更容易 debug：状态跳错查 next-state，输出错查 output decode，计数错查 counter enable 和 reset。

## 7. 最小复现实验

本讲最有价值的复现实验不是重新写一个完整 MBIST，而是在现有工程里做一次信号级核对：

```text
输入条件：
  - 在 top testbench 中设置 bist_en=1。
  - 注释普通 AHB write/read task。
  - 仿真运行到 bist_done。

观察信号：
  - 顶层：bist_en、bist_done、bist_fail。
  - wrapper：function path 与 BIST path mux 输出。
  - SRAM macro：address_test、data_test、WEN、CEN、OEN、DOUT。
  - BIST core：state、test_pattern、check_en、count_en、up_down。

通过判据：
  - AHB 侧没有真实读写，BIST 仍能驱动 macro。
  - 地址完成全范围遍历。
  - 读/比较/写阶段和状态机一致。
  - check_en 时读出值等于期望 pattern。
  - 最终 bist_done=1，bist_fail=0。
```

失败定位优先级：

| 现象 | 优先怀疑 | 下一步 |
|---|---|---|
| `bist_done` 一直不高 | FSM 未走到最终阶段或 counter 未到末尾 | 查 `state/address_test/count_en` |
| `bist_fail=1` | 某次 compare mismatch | 找首次 `check_en=1` 且读值不等于 pattern 的地址 |
| macro 端口无动作 | BIST clock 或 mux 未打开 | 查 `bist_en/bist_clock_select/data_test` |
| 地址只走一小段 | counter 宽度、末尾条件或 reset 错 | 查 `up_down/test_addr_reset/addr_last` |
| function 信号有值但 macro 不响应 | 正常现象，BIST mode 隔离 function path | 继续看 macro 端口而不是顶层 AHB |

## 8. 工程检查清单：BIST 波形必须同时看三层

BIST debug 不能只看一个层级。顶层告诉你测试是否启动，wrapper 告诉你模式选择是否正确，macro 端口告诉你 SRAM 是否真的被测试。

| 层级 | 必看信号 | 通过标准 | 失败时下一步 |
|---|---|---|---|
| top/testbench | `bist_en`、`bist_done`、`bist_fail` | `bist_en=1` 后 eventually `done=1` 且 `fail=0` | 若不完成，先确认 BIST clock 是否打开 |
| wrapper mux | function 输入、BIST 内部输出、macro 输入 | `bist_en=1` 时 macro 输入跟随 BIST 内部输出 | 若仍跟随 function，查 mux select 极性 |
| SRAM macro | `address_test`、`data_test`、`WEN/CEN/OEN`、`DOUT` | 地址全遍历，读写阶段和 March 阶段一致 | 若 macro 无动作，查低有效控制脚是否被误读 |
| BIST core | `state`、`check_en`、`pattern_select`、`count_en`、`up_down` | 状态、pattern、地址方向与波形阶段一致 | 若 mismatch，找首次状态跳转或 compare 失败点 |
| done/fail | internal done、internal fail、外部映射 | fail 只由 compare mismatch 触发，done 只在最终阶段末尾触发 | 若 done 早到，查末尾地址条件和最终状态条件 |

## 9. 首次 compare mismatch 的定位决策树

BIST debug 最怕只看到 `bist_fail=1` 就到处改代码。正确做法是先抓“第一次失败”，因为后面的失败可能只是第一处错误的连锁反应。

```text
发现 bist_fail=1
  -> 找首次 check_en=1 且 compare mismatch 的时间点
  -> 记录 state / address / expected pattern / actual DOUT
  -> 回看该地址上一轮写入是否发生
  -> 检查 WEN/CEN/OEN 低有效极性和读延迟
  -> 判断是 pattern 生成错、地址计数错、写入没发生、读采样过早，还是 mux 选错路径
```

| 首次失败现象 | 更可能的问题 | 下一步证据 |
|---|---|---|
| 地址 0 第一拍就错 | test mode mux 未切换或初始写 0 未执行 | 看 macro 输入是否来自 BIST path |
| 固定某一位总错 | SRAM cell/model 或 data mux bit mapping | 对比 `DIN/DOUT` bit 位置 |
| 每到 bank 边界错 | 地址计数或 bank select | 查 address counter 高位和 bank mux |
| 读比较提前错，后一拍正确 | read latency 未等待够 | 查 `check_en` 与 `DOUT` 稳定时间 |
| done 早到但地址未遍历完 | 终止条件错误 | 查 final address/state 判断 |

BIST 像自动阅卷机。`fail` 只是红灯，真正有价值的是第一张判错的卷子：哪一题、标准答案是什么、学生答案是什么、之前有没有正确发题。

## 10. 最后速记

### 10.1 本章最该记住的结论

- BIST 模式下，AHB function 信号不是 SRAM macro 的真实刺激源；macro 前的 BIST mux 输出才是证据。
- 低有效 SRAM 控制脚必须按有效电平读波形：`WEN=0` 才表示写。
- March 类测试通过多轮全地址读写比较检测存储单元和读写路径故障。
- `check_en` 决定失败判据，`bist_done` 决定全流程完成判据。
- 波形和代码要互相验证：波形证明行为，RTL 解释行为为什么会发生。

### 10.2 复现 / 复习清单

- 能指出 `bist_en` 打开后 function path 和 BIST path 的 mux 边界。
- 能在波形里找到第一轮全地址写 0。
- 能解释为什么读比较阶段同一地址会停留多个 cycle。
- 能找到 `check_en` 对应的比较逻辑，并说出 fail 何时置位。
- 能用状态机、counter、pattern、compare 四个入口读 BIST RTL。

## 复习与自测

1. 为什么在 BIST 模式下不能只看顶层 AHB 信号判断 SRAM 是否被测试？

   答案：BIST 模式会通过 wrapper mux 选择内部生成的测试地址、数据和控制脚，正常 AHB function path 不再驱动 SRAM macro。顶层 AHB 信号即使有值，也可能只是无关值。

2. `CEN/OEN/WEN` 若都是低有效，`WEN=0` 表示什么？

   答案：表示写使能有效。若同时 `CEN=0`，SRAM 被选中并进入写操作；不能按“1 表示有效”的软件直觉读这些端口。

3. March 测试为什么要反复写 0、读 0、写 1、读 1，而不是只写一次读一次？

   答案：单次写读只能证明某个值在某个时刻可读出；多轮不同方向和不同历史值的读写能暴露 stuck-at、相邻耦合、读写干扰和保持类问题。

4. `check_en=1` 时比较失败，应该如何定位？

   答案：先记录首次失败地址、当前 state、期望 pattern 和实际 `DOUT`；再检查该地址前一轮是否按预期写入，以及读数据是否满足 SRAM 读延迟。

5. `bist_done` 合格的拉高条件是什么？

   答案：最终比较阶段通过、全地址遍历到末尾、此前没有 fail。只完成某一小段读写不能拉高 `bist_done`。

6. 为什么这段 BIST RTL 是状态机学习样板？

   答案：它包含真实工程里的多状态、多输出、多 counter、状态反馈条件；命名和分层清楚，适合学习状态寄存、次态计算、输出控制和 counter 协同。

## 工程核对口径

本章通过标准：

1. 能在波形中指出 BIST 接管 SRAM macro 的 mux 边界。
2. 能按低有效语义解释 `CEN/OEN/WEN`。
3. 能用 state、address、pattern、check_en 解释 March 阶段。
4. 能定位首次 compare mismatch，而不是只看最终 fail。
5. 能把这段 BIST RTL 当作真实状态机样板，说明每个 counter 和输出条件的职责。


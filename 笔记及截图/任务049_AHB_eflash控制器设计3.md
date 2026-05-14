# 49_AHB_eFlash控制器设计3

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：把 eFlash datasheet 的 page erase、mass erase、program、read 时序图翻译成可仿真的 FSM、counter 和波形检查方法。
- 核心概念：`TNVS`、`TERASE`、`TNVH`、`TREC`、`MAS1`、`PROG`、`NVSTR`、`YE`、`TACC`、FSM、counter、flash TB、FSDB 游标。
- 逻辑主线：每一张 eFlash 时序图都可以拆成“控制脚组合 + 等待时间 + 完成条件”；RTL 用状态机决定当前组合，用 counter 数够时间，用 testbench 和 Verdi 波形证明控制脚、地址、数据和读回结果满足 datasheet。
- 最小主线：
  - page erase 是 setup、busy、hold、recover 四段链。
  - mass erase 与 page erase 相似，但 `MAS1=1` 且 hold 时间不同。
  - program 写一个 word，但 `PROG/NVSTR/YE` 分阶段拉起，地址和数据必须稳定。
  - read 最短，但仍要等 access time 后采样 `DOUT`。
  - 波形验证不能只看读回值，还要用游标量测关键时间间隔。

### 2. 概念地图

| 概念层级 | 核心概念 | 前置知识 | 延伸应用 |
| :---: | :---: | :---: | :---: |
| 操作层 | page erase、mass erase、program、read | eFlash truth table | command decode |
| 状态层 | setup、busy、hold、recover | FSM | controller RTL |
| 时间层 | us/ms/ns 参数 | clock cycle 换算 | counter 位宽 |
| 数据层 | `XADR/YADR/DIN/DOUT` | 地址拆分、读写数据 | 读回验证 |
| 验证层 | flash TB、FSDB、Verdi cursor | 仿真、波形阅读 | IP bring-up |
| 总线层 | IP 侧控制脚 + AHB 侧 `HREADY/HRDATA` | AHB slave | 系统集成 |

### 3. 阅读顺序

- 先把 page erase 看成模板：控制脚先后关系和等待时间决定状态链。
- 再比较 mass erase 和 program 的差异，不要复制粘贴状态。
- 最后掌握波形检查顺序：先控制脚，再地址数据，再游标时间，最后读回值。

### 4. 全讲结构地图

| 视频阶段 | 画面/操作主线 | 本阶段要学会的判断 |
|---|---|---|
| 00:55-05:50 | 从 page erase timing 出发，把 `TNVS/TERASE/TNVH/TREC` 转成状态和 counter | 时序图可以直接翻译成 FSM 阶段 |
| 06:40-10:30 | 对比 mass erase 与 page erase | 相似流程不能共用错误参数，`MAS1` 和 hold 时间必须区分 |
| 15:30-26:30 | 展开 program timing：`PROG/NVSTR/YE/DIN` 的先后关系 | 写 word 要同时满足地址、数据、控制脚和时间窗口 |
| 26:30-33:30 | 展开 read timing 和 access time | read 路径最短，但仍要等 `DOUT` 稳定 |
| 33:30-39:45 | 切换 flash TB 和 filelist，生成 FSDB | 先直接驱动行为模型，可降低 controller debug 复杂度 |
| 39:45-44:40 | 在 Verdi 中检查 erase/program 波形 | 波形要用游标量时间，不只看形状 |
| 44:40-47:10 | 检查 read 波形和读回结果，收束到验证闭环 | 通过标准是时序满足加读回一致，两者缺一不可 |

## 1. page erase 是四段状态链

page erase 的控制顺序很固定：先准备地址和 `ERASE/XE`，等 `TNVS` 后拉 `NVSTR`，保持 20-40ms，随后先拉低 `ERASE`，再保持 `NVSTR` 一段时间，最后 recover。

视觉验证：视频 00:55-03:00（page erase timing 中 `ERASE` 与 `NVSTR` 不同时起落，`NVSTR` 相对 `ERASE` 后移）。

![page erase timing](<./screenshots/任务049_AHB_eflash控制器设计3/task49_00_page_erase_timing_00m55s.jpg>)

状态链：

```text
ERASE_SETUP
  控制：XADR=page row，XE=1，ERASE=1，NVSTR=0
  等待：TNVS = 5us

ERASE_BUSY
  控制：XE=1，ERASE=1，NVSTR=1
  等待：TERASE = 20-40ms

ERASE_HOLD
  控制：ERASE=0，NVSTR=1
  等待：TNVH = 5us

RECOVER
  控制：全部回到空闲
  等待：TREC = 1us
```

最容易错的是把 `ERASE` 和 `NVSTR` 同时拉起同落。datasheet 要求的建立和保持时间，是 eFlash 内部模拟电路可靠工作的条件；少等可能导致擦除不彻底，后续 program/read 才暴露异常。

## 2. 长时间等待必须用 counter，不能靠状态名表达

20ms 在 100MHz 下是 2,000,000 拍，40ms 是 4,000,000 拍。状态名只能说明“现在处于擦除阶段”，不能证明这个阶段持续了足够久；证明时间的是 counter。

视觉验证：视频 04:45-05:50（课程把“保持 20ms”转成状态内 counter 计数，FSM 管阶段，counter 管时间）。

![FSM 与 counter](<./screenshots/任务049_AHB_eflash控制器设计3/task49_01_counter_fsm_time_04m45s.jpg>)

伪代码结构：

```systemverilog
always_ff @(posedge hclk or negedge hreset_n) begin
    if (!hreset_n) begin
        cnt <= '0;
    end else if (state_enter) begin
        cnt <= '0;
    end else if (state_waiting) begin
        cnt <= cnt + 1'b1;
    end
end

assign wait_done = (cnt == target_cycles - 1);
```

不同状态的 `target_cycles` 不同：5us、20us、40ms、1us 不应混成一个常数。更好的实现是每个状态或每类动作有自己的参数。

counter 的完成条件要避免多等一拍或少等一拍。对 eFlash 来说，多等通常只是性能损失，少等可能直接破坏 program/erase。

## 3. mass erase 主要差在 `MAS1` 和 hold 时间

mass erase 擦整片或整块，不再关心具体 page。它和 page erase 的主流程相似，但 `MAS1=1`，并且 `NVSTR` 的 hold 时间更长，课程中提到约 100us。

视觉验证：视频 06:40-08:30（mass erase 波形与 page erase 对比，`MAS1=1`，后段 hold 时间不同）。

![mass erase](<./screenshots/任务049_AHB_eflash控制器设计3/task49_02_mass_erase_06m40s.jpg>)

controller 至少要区分两类命令：

```text
PAGE_ERASE:
  MAS1 = 0
  hold = TNVH
  address = page address

MASS_ERASE:
  MAS1 = 1
  hold = TNVH1
  address 可不作为 word/page 精确选择
```

不要把二者共用同一条完成条件，否则 mass erase 可能过早退出。更稳的状态机可以复用 setup/busy/hold/recover 框架，但每种命令的控制脚和等待目标必须参数化或分支明确。

## 4. program 比 erase 短，但阶段更多

program 写一个 32-bit word，需要同时定位 row 和 word，所以 `XADR/YADR/DIN` 都要有效。它先拉起 `PROG`，等待 `TNVS` 后拉 `NVSTR`，再等待 `TPGS` 后拉 `YE`，保持 `TPROG`，最后按 hold/recover 退出。

视觉验证：视频 15:30-18:30（program timing 中 `PROG`、`NVSTR`、`YE` 分阶段起落，`YE` 拉高后才进入真正写入窗口）。

![program cycle](<./screenshots/任务049_AHB_eflash控制器设计3/task49_03_program_cycle_15m30s.jpg>)

program 状态链：

```text
PROG_SETUP0: PROG=1, XE=1, XADR/YADR/DIN stable, wait TNVS
PROG_SETUP1: NVSTR=1, wait TPGS
PROG_BUSY:   YE=1, wait TPROG
PROG_HOLD0:  YE=0, wait TPGH
PROG_HOLD1:  PROG=0, wait TNVH
RECOVER:     NVSTR/XE=0, wait TREC
```

`DIN` 和地址的 setup/hold 时间是 ns 级，和 10us/20us 相比很短，但不能忽略。RTL 可以通过提前锁存地址和数据来保证它们在整个 program 阶段稳定。

## 5. read 是最短路径，但仍要识别一次读边界

read 不改变非易失内容，所以没有 `PROG/ERASE/NVSTR`。它主要拉起 `XE/YE/SE`，等待 access time，读取 `DOUT`。

视觉验证：视频 26:30-28:30（read cycle 中 `XE/YE/SE` 拉起后，`DOUT` 需要约 24ns access time 才能稳定）。

![read cycle](<./screenshots/任务049_AHB_eflash控制器设计3/task49_04_read_cycle_26m30s.jpg>)

连续读时不应只看地址变化，还要看 IP 对读触发的要求。课程里强调读完一次会把 `SE` 拉低，再读下一次时重新拉高；这让存储体明确识别新的读动作。接到 AHB 后，`HREADYOUT=0` 的窗口应该覆盖 `DOUT` 稳定前的等待，`HREADYOUT=1` 时 `HRDATA` 必须已经有效。

## 6. 先用简单 TB 直接驱动 eFlash 行为模型

在完整 controller 接入 AHB 之前，可以用一个简单 `flash_tb` 直接驱动 eFlash 行为模型。这个 TB 的目标不是完整验证 SoC，而是先确认存储体模型和时序图能对上。

视觉验证：视频 33:30-35:00（TB 文件和 filelist 被切换到 eFlash 行为模型验证路径，生成 FSDB 供 Verdi 查看）。

![flash TB 文件](<./screenshots/任务049_AHB_eflash控制器设计3/task49_05_tb_files_33m30s.jpg>)

最小实验：

```text
1. page_erase 某一页。
2. program 一个 32-bit word。
3. read 同一个 word。
4. 在 Verdi 中确认控制脚时间间隔和读回值。
```

这个实验比直接看完整 controller 更适合初学，因为它把问题缩小到“我能不能正确驱动 eFlash IP”。如果直接驱动行为模型都不通过，接上 AHB 只会增加定位难度。

## 7. FSDB 里要用游标量测真实时间

波形不是看形状相似就结束，关键时间要量出来。课程中用 Verdi 游标量测 `NVSTR` 与 `ERASE/PROG` 之间的时间差，确认 5us、20ms、20us 等是否满足。

视觉验证：视频 39:45-41:30（erase 波形中通过游标检查 setup、busy、hold、recover 时间，busy 段达到 ms 级）。

![erase 波形量测](<./screenshots/任务049_AHB_eflash控制器设计3/task49_06_wave_erase_39m45s.jpg>)

波形检查顺序：

```text
先看 command 类信号：ERASE/PROG/MAS1/NVSTR
再看地址：XADR/YADR
再看数据：DIN/DOUT
最后用游标量测 setup、busy、hold、recover
```

如果只看 `DOUT` 是否有值，可能漏掉时序边界不满足的问题。读回一致是必要证据，但不是唯一证据；时序违规可能在模型、工艺角或后续版本中才暴露。

## 8. program 波形要确认写入值和地址一起稳定

program 时，`DIN`、`XADR`、`YADR` 必须在写入窗口前稳定，并保持到要求时间后再变化。Verdi 中应把这些信号和 `YE/PROG/NVSTR` 放在一起看。

视觉验证：视频 42:30-43:40（program 波形中写入数据在 `YE` 写入窗口内保持稳定，同时 `PROG/NVSTR` 的 setup 和 hold 满足要求）。

![program 波形](<./screenshots/任务049_AHB_eflash控制器设计3/task49_07_wave_program_42m30s.jpg>)

program 成功的最小判据：

```text
地址稳定
  -> 数据稳定
  -> PROG/NVSTR/YE 时序满足
  -> program 时间数够
  -> 退出后 read 同地址得到写入值
```

若写后读不一致，不要只怀疑 read path。还要查 program 阶段的 `DIN` 是否在 `YE` 有效窗口中稳定，`TPROG` 是否数够，program 前是否已经 erase。

## 9. read 波形证明 access time 和采样点

read 的波形短，但要看准 `SE` 拉起到 `DOUT` 有效之间的间隔。若 controller 采样早了，AHB 侧可能拿到旧值、X 或不稳定值。

视觉验证：视频 44:40-45:50（read 波形中 `XE/YE/SE` 拉高后，约 24ns 后 `DOUT` 才能被采样）。

![read 波形](<./screenshots/任务049_AHB_eflash控制器设计3/task49_08_wave_read_44m40s.jpg>)

接到 AHB 后，read 波形还要多看两根总线信号：

```text
HREADYOUT = 0 期间：eFlash 还在等待 DOUT
HREADYOUT = 1 时：HRDATA 必须已经锁存或稳定
```

这就是 IP 侧时序和总线侧协议的连接点。只看 IP 侧不知道 CPU 是否被正确等待；只看 AHB 侧不知道等待期间 eFlash 是否按 datasheet 被驱动。

## 10. 最小闭环：用 TB 验证三类动作

本讲的最小闭环不是写完整 controller，而是证明行为模型可被正确驱动：

```text
page_erase(page=0)
program_word(xadr, yadr, 32'h1234_5678)
read_word(xadr, yadr, read_data)

检查：
  read_data == 32'h1234_5678
  erase/program/read 的关键时间间隔满足 datasheet
```

把这条闭环接入 controller 后，还要增加两类观测点：

| 观测侧 | 必看信号 | 证明什么 |
|---|---|---|
| eFlash IP 侧 | `XADR/YADR/DIN/DOUT/XE/YE/SE/ERASE/PROG/MAS1/NVSTR` | controller 没有违反 IP 时序 |
| AHB 总线侧 | `HADDR/HWRITE/HREADYOUT/HRESP/HRDATA` 或状态寄存器 | master 看到的是可解释的等待、完成或错误 |

只看其中一侧，都无法定位问题到底在协议转换还是 IP 驱动。

## 11. 工程检查清单：四类操作各自的通过证据

eFlash 验证要避免“一套波形看所有操作”。page erase、mass erase、program、read 的控制脚、等待时间和最终证据不同，应分开检查。

| 操作 | 必看控制脚 | 必看地址/数据 | 时间证据 | 结果证据 |
|---|---|---|---|---|
| page erase | `ERASE/XE/NVSTR/MAS1=0` | page 对应 `XADR` | `TNVS/TERASE/TNVH/TREC` 游标满足 | 该页被擦后读出擦除态 |
| mass erase | `ERASE/XE/NVSTR/MAS1=1` | 不依赖单个 word 地址 | mass erase hold 使用专属参数 | 目标块/片整体进入擦除态 |
| program | `PROG/NVSTR/YE/XE` | `XADR/YADR/DIN` 在写入窗口稳定 | `TNVS/TPGS/TPROG/TPGH/TNVH/TREC` 满足 | 同地址 readback 等于写入值 |
| read | `XE/YE/SE` | `XADR/YADR` 稳定，`DOUT` 有效后采样 | `TACC` 满足 | AHB 侧 `HRDATA` 与 IP 侧 `DOUT` 对齐 |

这张表也能用来写 testbench 断言。最小断言不是只检查最终数据，而是同时检查“控制脚组合合法、等待时间足够、结果符合预期”。

## 12. 深层理解：波形量测要升级成 checker 口径

本讲已经把 eFlash 时序图翻成了 FSM、counter、TB 和 FSDB 波形。下一步要把“我看过波形”升级成“工具能替我判定波形是否合格”。这就是 checker 或断言的价值。

可以从三类 checker 开始：

| checker 类型 | 检查什么 | 失败时说明 |
|---|---|---|
| 控制组合合法性 | read/program/erase 时控制脚组合不能互相冲突 | FSM 输出错误或状态编码错误 |
| 时间窗口 | `NVSTR/ERASE/PROG/YE/SE` 的 setup/hold/busy/recover 满足最小周期 | counter 终值不足或状态提前跳转 |
| 结果一致性 | program 后 readback 等于写入值，erase 后为擦除态 | 写入未发生、擦除粒度错、采样过早 |

一个关键原则：读回正确不一定代表 timing 合格。就像考试答案碰巧对了，但过程少写关键步骤，工程上仍不能放行。真实 IP、不同 corner、不同仿真模型可能在 timing 不足时才暴露问题。

## 13. 最小断言思路

```systemverilog
// 伪代码：表达检查意图，不绑定具体信号名
property no_program_without_setup;
    @(posedge clk)
    start_program |-> setup_state_before_prog ##[MIN_SETUP:$] prog_busy;
endproperty

property read_sample_after_access_time;
    @(posedge clk)
    read_start |-> ##[READ_WAIT:$] sample_dout;
endproperty

property no_illegal_erase_program_overlap;
    @(posedge clk)
    !(erase_active && program_active);
endproperty
```

真正落地时可以先不用完整 SVA，也可以在 TB 中用 cycle counter 和 `$error` 做检查。关键是把 datasheet timing 写成可执行判据，而不是只靠人工游标。

## 14. 最后速记

### 14.1 本章最该记住的结论

- 时序图可以系统翻译成 FSM 状态链：setup、busy、hold、recover。
- FSM 决定当前控制脚组合，counter 证明等待时间是否足够。
- mass erase 不能直接复制 page erase，`MAS1` 和 hold 时间不同。
- program 成功必须同时满足地址、数据、控制脚和时间窗口。
- 波形验证要用游标量测，不能只看“形状差不多”和最终读回值。

### 14.2 复现 / 复习清单

- 能把 page erase 写成四段状态链。
- 能计算 100MHz 下 20ms 和 5us 分别是多少 cycle。
- 能说出 mass erase 与 page erase 的差异。
- 能指出 program 波形里 `DIN`、`YADR`、`YE` 的关系。
- 能用 FSDB 游标检查 `TNVS/TERASE/TNVH/TREC`。

## 复习与自测

1. page erase 为什么适合拆成 setup、busy、hold、recover？

   答案：每一段控制脚组合和等待时间不同，拆开后 FSM 输出清楚，counter 目标也清楚。

2. 100MHz 下 20ms 需要多少 cycle？

   答案：20ms = 20,000,000ns，周期 10ns，所以是 2,000,000 cycle。

3. mass erase 和 page erase 的关键差异是什么？

   答案：mass erase `MAS1=1`，擦整块/整片，并且 `NVSTR` 后段 hold 时间更长。

4. program 时为什么要同时看 `DIN` 和 `YE`？

   答案：`YE` 拉高后进入写入窗口，`DIN` 必须在这个窗口内稳定，否则写入值可能不确定。

5. 为什么直接驱动 eFlash 行为模型有价值？

   答案：它把 AHB controller 暂时拿掉，只验证 IP 本身的时序驱动和读写行为，降低 debug 复杂度。

6. 为什么读回值正确仍不能完全替代 timing 检查？

   答案：读回正确只能证明当前仿真条件下结果对了；若 setup/hold/busy/recover 时间不足，模型可能暂时未暴露，真实 IP 或其他角落条件可能失败。

## 工程核对口径

完成本章后，应该能把时序图变成三种产物：

1. FSM 状态链：setup、busy、hold、recover。
2. counter 参数：每段最少等待多少 cycle，位宽是否足够。
3. checker 判据：控制脚合法、时间满足、读回结果正确。

只会看波形还不够，能把波形规则固化成可回归检查，才算进入工程验证。


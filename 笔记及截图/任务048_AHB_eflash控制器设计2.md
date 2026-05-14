# 48_AHB_eFlash控制器设计2

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：继续拆 eFlash IP 的地址、控制脚和 timing，把 datasheet 里的容量、page 组织、truth table、access/setup/hold 时间转换成 AHB controller 里的地址拆分、FSM 输出和 counter 等待。
- 核心概念：`XADR[9:0]`、`YADR[4:0]`、`32K x 32`、page address、`IFREN/XE/YE/SE/PROG/ERASE/NVSTR`、`HREADY` wait、setup/hold。
- 逻辑主线：先用容量反推地址位宽，再用 row/page/word 理解 `XADR/YADR`，然后把控制脚真值表变成状态输出，把 read/program/erase 的时间参数变成计数器和 AHB 等待。
- 最小主线：
  - `32K x 32` 是 32K 个 32-bit word，需要 15 bit word address。
  - `XADR` 10 bit 选 row，`YADR` 5 bit 选 row 内 word。
  - 一页 512 byte，等于 4 个 row，所以 page 地址来自 `XADR[9:2]`。
  - read 的 24ns access time 会反馈成 AHB `HREADYOUT=0` 的等待。
  - program/erase 的 us/ms 级时间必须参数化计数，不能写死小 counter。

### 2. 概念地图

| 概念层级 | 核心概念 | 前置知识 | 延伸应用 |
| :---: | :---: | :---: | :---: |
| 容量层 | `32K x 32`、word address | bit/byte/word | 地址位宽推导 |
| 阵列层 | row、word、page | 二维存储阵列 | page erase |
| 控制层 | `XE/YE/SE/PROG/ERASE/NVSTR` | eFlash 操作类型 | FSM 输出编码 |
| 协议层 | `HREADYOUT` wait | AHB transfer | 同步总线桥接异步 IP |
| 时序层 | access/setup/hold/recover | 寄存器采样窗口 | counter、STA |
| 验证层 | page 边界、片选边界、读写擦波形 | testbench、Verdi | controller 验证 |

### 3. 阅读顺序

- 先把容量换算和地址拆分算清楚，避免后面 RTL 位段全靠背。
- 再把控制脚按 read/program/erase 分类，避免“访问时全拉高”的错误模型。
- 最后把 timing 参数换算成 cycle，并用 setup/hold 直觉理解为什么不能少等。

### 4. 全讲结构地图

| 视频阶段 | 画面/讲解主线 | 本阶段要学会的判断 |
|---|---|---|
| 00:00-07:50 | 复盘 `32K x 32`，推导 `XADR` 10 位、`YADR` 5 位 | 地址位宽来自阵列结构，不来自随意命名 |
| 07:50-12:55 | 讲 page、row、word 的关系和 `XADR[9:2]` | page erase 看 page 地址，不看 word 地址 |
| 12:55-23:50 | 逐个整理 `XE/YE/SE/PROG/ERASE/NVSTR` 等控制脚 | 控制脚要按操作类型分类 |
| 23:50-28:30 | 读 truth table，把控制组合对应到 read/program/erase | FSM 每个状态都应能解释成真值表的一类 |
| 28:30-34:40 | 讲 read access time 和 AHB `HREADYOUT` 等待 | 异步 IP 的访问时间会回到同步总线协议 |
| 34:40-41:20 | 讲 timing 参数和 page erase 状态序列 | us/ms 级等待必须用 counter 实现 |
| 41:20-50:15 | 用 setup/hold 解释采样窗口和时序违例 | 时间约束少等会变成功能风险，不只是性能问题 |

## 1. `XADR + YADR` 的位宽来自存储阵列结构

一片 eFlash 有 `32K x 32-bit`。`XADR` 是 10 位，`YADR` 是 5 位，两者相乘就是 32K 个 32 位数据位置：

```text
XADR: 2^10 = 1024 row
YADR: 2^5  = 32 word per row
1024 x 32 = 32768 = 32K
```

视觉验证：视频 02:40-04:20（画面中解释 10 位 `XADR` 和 5 位 `YADR` 如何共同覆盖 `32K x 32` 的存储空间）。

![X/Y 地址宽度](<./screenshots/任务048_AHB_eflash控制器设计2/task48_00_xy_address_width_02m40s.jpg>)

这不是数学游戏，而是 RTL 地址生成的依据。AHB `HADDR` 是 byte 地址，eFlash IP 要的是 row 和 row 内 word 选择；controller 必须在两种地址表达之间转换。

如果只支持 32-bit 对齐访问，可以先按 word index 理解：

```text
word_index = HADDR 去掉低 2 位
XADR       = word_index 的高 10 位
YADR       = word_index 的低 5 位
```

低 2 位 byte offset 不进入 eFlash word 地址，因为一个 32-bit word 已经包含 4 byte。若系统还支持 byte/halfword 写，要在 controller 或软件协议层额外处理写掩码和擦写粒度，而不是直接把低 2 位塞给 `YADR`。

## 2. page 地址来自 `XADR[9:2]`

课程反复强调 page，是因为 erase 粒度与 page 相关。一行包含 32 个 32-bit word，即 128 byte；一页 512 byte，所以一页由 4 行组成。`XADR[1:0]` 选择 page 内 4 行之一，`XADR[9:2]` 选择哪一个 page。

视觉验证：视频 07:50-09:30（`XADR[9:2]` 被标成 page number，`XADR[1:0]` 对应 page 内 row）。

![page 地址拆分](<./screenshots/任务048_AHB_eflash控制器设计2/task48_01_page_address_07m50s.jpg>)

关系如下：

```text
1 row  = 32 word x 32-bit = 128 byte
1 page = 4 row             = 512 byte
一片  = 128KB / 512B       = 256 page
page address = XADR[9:2]
row in page  = XADR[1:0]
word in row  = YADR[4:0]
```

page erase 不需要 `YADR` 精确到 word，因为擦除粒度不是 word。它需要的是 page 地址，也就是 row 地址的高位。这个理解能解释后续 RTL 里为什么 erase path 和 read/program path 的地址字段不同。

从 AHB byte address 转到 eFlash 内部地址，可先按一片 `32K x 32` 推导：

```text
word_index = HADDR[16:2]
XADR       = word_index[14:5]
YADR       = word_index[4:0]
page       = XADR[9:2]
row_in_pg  = XADR[1:0]
```

如果系统用两片 eFlash 扩到 256KB，还要用更高地址位做 chip select。真正写 RTL 时，页首、页尾、跨页、片选边界都必须进 testbench。

## 3. 控制脚要按操作类型理解

eFlash 接口除了 `DOUT` 外，大多是 controller 驱动的输入。不同信号在 read、program、erase 中作用不同，不能把 enable 全部理解成“访问时都拉高”。

视觉验证：视频 12:55-15:30（接口列表中 `XE/YE/SE` 与 `PROG/ERASE/NVSTR` 被分组解释，前者偏地址/读输出，后者决定是否改变非易失阵列）。

![控制脚说明](<./screenshots/任务048_AHB_eflash控制器设计2/task48_02_control_pins_12m55s.jpg>)

核心控制脚：

| 信号 | 在 read 中 | 在 program 中 | 在 erase 中 |
|---|---|---|---|
| `XE` | 选中 row | 选中 row | 选中 page 或 block |
| `YE` | 选中 word | 选中 word | 通常不需要 |
| `SE` | 拉高以输出 `DOUT` | 通常不需要 | 通常不需要 |
| `PROG` | 0 | 拉高 | 0 |
| `ERASE` | 0 | 0 | 拉高 |
| `NVSTR` | 0 | 拉高 | 拉高 |
| `IFREN` | 选择信息区或主区 | 同左 | 同左 |

`NVSTR` 的判据最简单：只有改变非易失内容时才需要。read 不改变阵列，所以不拉。

## 4. 真值表是 FSM 输出的压缩版本

真值表不是背景信息，而是 RTL 输出编码表。FSM 处于 `READ`、`PROGRAM_SETUP`、`ERASE_BUSY` 等状态时，应该驱动哪些控制脚，必须能回到这张表。

视觉验证：视频 23:50-25:30（standby、read、program、page erase、mass erase 的控制组合被列成 truth table）。

![真值表](<./screenshots/任务048_AHB_eflash控制器设计2/task48_03_truth_table_23m50s.jpg>)

设计检查方法：

```text
对每个 FSM 状态问：
  1. 现在对应 read、program、erase 还是 recover？
  2. truth table 要求哪些信号为 1？
  3. 未使用的信号是否明确为 0？
  4. 地址和数据是否已经稳定足够时间？
```

如果回答不出来，说明状态命名和输出逻辑脱节。后续看 eFlash controller 代码时，不要只看状态名，要把每个状态的输出控制脚和 datasheet 真值表对齐。

## 5. read access time 会变成 `HREADY` 等待

eFlash read access time 约 24ns。若 AHB 时钟为 100MHz，一拍 10ns；controller 不能在下一拍就把 `HRDATA` 交给 master，而要拉低 `HREADYOUT` 等待。

视觉验证：视频 28:30-30:20（read access time 约 24ns，被换算成 AHB 至少等待数拍，`HREADY` 低表示数据阶段未完成）。

![read access 与 HREADY](<./screenshots/任务048_AHB_eflash控制器设计2/task48_04_read_access_hready_28m30s.jpg>)

读流程：

```text
T0: AHB 地址阶段进入 eFlash 区间
T1: controller 锁存地址，驱动 XADR/YADR/XE/YE/SE，HREADYOUT=0
T2: 继续等待 eFlash DOUT 稳定
T3: DOUT 已跨过 access time，采样到 HRDATA，HREADYOUT=1
```

如果时钟更慢，例如周期大于 24ns，等待拍数可以减少。controller 不应无条件写死“永远等 3 拍”，更稳的方式是用参数把时间换算成 cycle 数。

## 6. program/erase 的时间不是同一量级

read 是纳秒级，program 是微秒级，erase 是毫秒级。控制器 counter 位宽主要被 erase 决定。

视觉验证：视频 34:40-36:30（timing 参数表中同时出现 ns、us、ms 级时间，说明各操作等待量级差异很大）。

![timing 参数](<./screenshots/任务048_AHB_eflash控制器设计2/task48_05_timing_params_34m40s.jpg>)

以 100MHz 粗算：

| 时间 | 换算 cycle | 设计影响 |
|---|---:|---|
| 24ns | 3 cycle | read wait |
| 5us | 500 cycle | setup/hold counter |
| 20us | 2,000 cycle | program busy |
| 40us | 4,000 cycle | program worst case |
| 20ms | 2,000,000 cycle | page erase busy |
| 40ms | 4,000,000 cycle | counter 需要足够宽 |

若 counter 位宽不够，仿真可能提前退出状态，真实 IP 则还没完成内部操作。写擦类状态必须按 worst case 设计，不能只取 typical 值。

## 7. page erase 波形能直接翻译成状态序列

page erase 的时序可以翻译成一条状态链：setup、erase busy、hold、recover。每个状态只做一件事：保持某组控制脚，并数够对应时间。

视觉验证：视频 39:20-41:20（page erase 波形中 `ERASE` 先于 `NVSTR` 拉起，`ERASE` 先落下，`NVSTR` 后落下，最后还有 recover）。

![page erase 波形](<./screenshots/任务048_AHB_eflash控制器设计2/task48_06_erase_waveform_39m20s.jpg>)

状态序列：

```text
IDLE
  -> ERASE_SETUP: XADR/page 有效，XE=1，ERASE=1，等待 TNVS
  -> ERASE_BUSY:  NVSTR=1，保持 ERASE/XE，等待 TERASE
  -> ERASE_HOLD:  ERASE=0，NVSTR 继续保持，等待 TNVH
  -> RECOVER:     控制脚回 0，等待 TREC
  -> IDLE 或 DONE
```

这条链和 AHB 的关系是：如果软件通过寄存器启动 erase，controller 应进入 busy；如果 AHB master 访问正在 busy 的 eFlash，controller 要么返回等待，要么按设计返回错误或 busy 状态。选择哪一种属于系统架构约定，不能让 RTL 自己含糊处理。

## 8. setup/hold 直觉：信号不能贴着采样边沿乱变

课程借 eFlash 时序扩展到同步电路的 setup/hold。无论是异步 IP 的 `NVSTR`，还是寄存器间路径，核心都是采样点前后要有稳定窗口。

视觉验证：视频 43:45-45:20（寄存器 A 到寄存器 B 中间组合逻辑过长，数据到达 B 太晚，下一拍采样前 setup time 不够）。

![setup violation 直觉](<./screenshots/任务048_AHB_eflash控制器设计2/task48_07_setup_violation_43m45s.jpg>)

同步路径的直觉：

```text
Reg A 在时钟沿后输出数据
  -> 数据经过组合逻辑传播
  -> Reg B 下一次时钟沿前必须稳定至少 setup time
  -> 若组合逻辑太长或 clock 太快，就出现 setup violation
```

解决方式不是随便加寄存器，而是在功能保持正确的前提下切分组合路径。加一级 pipeline 会改变延迟，其他控制路径也要对齐；否则时序好了，协议可能错了。

## 9. 最小闭环：把 read 时间转成参数化计数

一个更稳的写法是把纳秒时间转成 cycle 参数：

```systemverilog
localparam int CLK_PERIOD_NS = 10;
localparam int TACC_NS       = 24;
localparam int READ_WAIT_CYC = (TACC_NS + CLK_PERIOD_NS - 1) / CLK_PERIOD_NS;
```

读状态机使用 `READ_WAIT_CYC` 计数，而不是写死 3。这样当目标频率变化时，等待拍数可跟着参数调整。

写擦时间也要同样参数化。以 100MHz 为例，40ms 需要 4,000,000 cycle，计数器至少要 22 bit，因为 `2^22 = 4,194,304`。

```systemverilog
localparam int ERASE_MAX_CYC = 4_000_000;
localparam int ERASE_CNT_W   = $clog2(ERASE_MAX_CYC + 1);
logic [ERASE_CNT_W-1:0] erase_cnt;
```

位宽不足的 bug 很隐蔽：counter 会回绕，FSM 可能提前退出 `ERASE_BUSY`，读回失败却不一定立刻指向“计数器太窄”。

## 10. 工程检查清单：地址拆分和 timing 参数不能靠手感

本讲最容易留下的隐患，是把地址位段和等待拍数写成“看起来对”的常数。更稳的做法是每个常数都能追溯到容量、page 组织或 datasheet timing。

| 检查项 | 通过标准 | 失败信号 |
|---|---|---|
| `HADDR` 到 word index | 明确去掉 byte offset，访问对齐规则清楚 | 读写地址错 4 倍或跨 word 错 |
| `XADR/YADR` 位段 | 15 bit word index 被拆成 10 bit row + 5 bit word | row/word 颠倒，页内地址错 |
| page 地址 | `page = XADR[9:2]`，低 2 位作为 page 内 row | page erase 擦错页 |
| chip select | 多片 eFlash 时高地址位明确选片 | 两片镜像或访问越界 |
| read wait | `TACC` 按 clock period 向上取整 | `HRDATA` 采早 |
| erase/program counter | 按 worst case timing 计算位宽 | counter 回绕或提前完成 |
| setup/hold | 地址、数据、控制脚在窗口内稳定 | 模型偶发报错或真实 IP 风险 |

## 11. 深层理解：地址拆解像把街道地址翻成仓库货架坐标

AHB 地址是系统街道地址，eFlash IP 需要的是内部货架坐标：哪一行、哪一列、哪一页。controller 不能把 `HADDR` 原样丢给 IP，而要先去掉 byte offset，再拆成 word index、`XADR`、`YADR` 和 page number。

以 32-bit word 对齐访问为例：

```text
HADDR[1:0]      -> byte offset，32-bit word 访问应为 00
word_index      -> HADDR 去掉低 2 位后的 word 编号
XADR[9:0]       -> word_index 的高/中间行地址部分
YADR[4:0]       -> word_index 的列地址部分
page            -> XADR[9:2]，用于 page erase
XADR[1:0]       -> page 内 row
```

如果这个翻译错一位，错误会非常隐蔽：单个地址 demo 可能读写正常，跨 page、跨 row 或连续访问时才发现擦错页、读错 word、地址偏移 4 倍。

## 12. 具体地址拆解练习

假设 `HADDR = base + 0x0000_0120`，且访问 32-bit word：

```text
byte_offset = HADDR[1:0] = 2'b00
word_index  = 0x120 >> 2 = 0x48
YADR        = word_index[4:0]
XADR        = word_index[14:5]
page        = XADR[9:2]
```

真正项目中不要只写公式，要在 testbench 中选几个边界点：

| 地址类型 | 目的 | 失败信号 |
|---|---|---|
| page 第一个 word | 检查 page 起点 | page 选择错会擦上一页或下一页 |
| page 最后一个 word | 检查 page 边界 | 跨页时 XADR 高位错误 |
| 相邻 word | 检查 YADR 递增 | 列地址不动或跳变异常 |
| 非 word 对齐地址 | 检查异常策略 | byte offset 被忽略导致静默错写 |
| 最大地址 | 检查地址位宽 | counter/地址截断回绕 |

## 13. counter 位宽不足的失败信号

timing 参数转 counter 时，不能只算目标 cycle，还要确认 counter 位宽能装下最大值。20ms 在 100MHz 下是 2,000,000 cycle，需要至少 21 bit。若 counter 只有 16 bit，它会提前回绕，波形看起来“等过一段时间”，但实际远远不够。

| 失败现象 | 可能原因 |
|---|---|
| erase/program 过早结束 | counter 位宽不足或终值算小 |
| 仿真中偶尔读对、偶尔读错 | setup/hold/access 裕量不足 |
| 慢操作后状态机卡住 | counter done 条件和 FSM 退出条件不一致 |
| 综合后 timing 变差 | counter 位宽过大且未分层，影响控制路径 |

## 14. 最后速记

### 14.1 本章最该记住的结论

- `XADR[9:0] + YADR[4:0]` 合计 15 bit，正好索引 32K 个 32-bit word。
- page erase 看 `XADR[9:2]`，不是看 `YADR`。
- read 的 access time 会变成 AHB `HREADYOUT` 等待。
- program/erase 的时间要按 worst case 换算成 counter。
- setup/hold 的本质是采样窗口前后信号要稳定。

### 14.2 复现 / 复习清单

- 能把 `HADDR` 拆成 word index、`XADR`、`YADR`。
- 能解释为什么一页 512 byte 对应 4 个 row。
- 能按 truth table 判断 read/program/erase 控制脚。
- 能把 24ns、5us、20ms 换算成 100MHz 下的 cycle。
- 能说出 counter 位宽不足会导致什么失败。

## 复习与自测

1. 为什么 `XADR` 10 位、`YADR` 5 位可以覆盖一片 `32K x 32`？

   答案：`2^10 x 2^5 = 1024 x 32 = 32768`，刚好是 32K 个 32-bit word。

2. 一页 512 byte，一行 128 byte，一页有几行？

   答案：4 行。对应 `XADR[1:0]` 选择 page 内 row。

3. read 时为什么要拉 `SE`？

   答案：`SE` 是 sense amplifier enable，可理解为读输出使能；不拉起时 `DOUT` 不应被当成有效读数据。

4. 100MHz 下 5us 等于多少个 clock cycle？

   答案：100MHz 周期 10ns，5us = 5000ns，所以是 500 cycle。

5. setup violation 为什么和 clock 频率有关？

   答案：clock 越快，两个采样沿之间时间越短，组合逻辑可用传播时间越少，更容易在下一拍采样前来不及稳定。

6. 为什么 page erase 不需要 `YADR`？

   答案：page erase 的粒度是整页，不是某个 word；`YADR` 只选择 row 内 word，对整页擦除没有决定作用。page 地址来自 `XADR` 高位。

## 工程核对口径

本章通过标准：

1. 能把 AHB byte address 拆成 word index、`XADR`、`YADR`、page 和 byte offset。
2. 能解释 page erase 为什么看 `XADR[9:2]`。
3. 能把 read/program/erase timing 换算成 clock cycle，并给 counter 留足位宽。
4. 能定义非对齐访问、越界访问和 busy 访问的系统响应。
5. 能用边界地址 testcase 验证地址翻译没有错一位。


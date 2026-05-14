# 47_AHB_eFlash控制器设计1

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：从 AHB SRAM 控制器切换到 AHB eFlash 控制器，先建立 eFlash 在 SoC 中的角色、IP 边界、容量组织、接口信号和读写擦时序直觉。
- 核心概念：非易失存储、boot 程序、foundry eFlash IP、`32K x 32`、main/information block、`XADR/YADR`、异步接口、truth table、read/program/page erase。
- 逻辑主线：CPU 需要上电后能读到不会丢失的程序，因此 SoC 集成 eFlash；前端不设计 eFlash cell 本身，而是设计 AHB controller，把总线访问翻译成 eFlash IP 要求的控制脚组合和保持时间。
- 最小主线：
  - SRAM 掉电丢数据，eFlash 掉电保留内容，适合保存 boot code。
  - 设计者主要写 controller，不改 foundry 提供的存储体 IP。
  - `32K x 32` 是 32K 个 32-bit word，一片约 128KB。
  - eFlash IP 没有 clock，操作由 `XE/YE/SE/ERASE/PROG/NVSTR` 等控制脚和时间窗口决定。
  - eFlash controller 比 SRAM controller 复杂，是因为 read、program、erase 的时间尺度差异巨大。

### 2. 概念地图

| 概念层级 | 核心概念 | 前置知识 | 延伸应用 |
| :---: | :---: | :---: | :---: |
| 系统角色 | boot、非易失存储 | CPU 取指、SoC memory map | 启动链路 |
| IP 边界 | foundry IP、行为模型、黑盒 | RTL 仿真、模块例化 | IP 集成 |
| 容量组织 | `32K x 32`、page、row | bit/byte/word 换算 | 地址拆分 |
| 控制接口 | `XADR/YADR/DIN/DOUT`、控制脚 | SRAM/eFlash 差异 | FSM 输出 |
| 操作时序 | read/program/page erase | setup/hold/access time | counter、`HREADY` |
| 验证入口 | datasheet、truth table、timing | 波形阅读 | controller bring-up |

### 3. 阅读顺序

- 先理解 eFlash 为什么存在：它给 CPU 一个掉电不丢的启动入口。
- 再理解设计边界：前端写 controller，存储体 IP 由厂商提供。
- 最后把 datasheet 的容量、接口、真值表和 timing 转成后续 RTL 的地址逻辑、状态机和等待策略。

### 4. 全讲结构地图

| 视频阶段 | 画面/讲解主线 | 本阶段要学会的判断 |
|---|---|---|
| 00:00-07:00 | 从 SRAM controller 切到 eFlash controller，定位 SoC 启动存储 | eFlash 的系统价值是掉电保留 boot code |
| 07:00-18:20 | 阅读 IP 资料：`32K x 32`、main block、information block、两片容量 | controller 的地址和容量判断必须从 datasheet 来 |
| 18:20-28:20 | 讨论 foundry IP、行为模型、black box 和前端设计边界 | 前端写 controller，不改 eFlash cell 阵列 |
| 28:20-35:50 | 展开 `XADR/YADR/DIN/DOUT` 和控制脚集合 | eFlash IP 是异步接口，控制器要生成操作波形 |
| 35:50-39:50 | 读 truth table 和 timing 条目 | FSM 输出必须能回到控制脚真值表 |
| 39:50-48:00 | 分析 page erase 和 program 时序 | 擦写操作是多段等待，不是 AHB 单拍写 |
| 48:00-55:59 | 分析 read access 和 AHB wait 关系 | read 最快，但仍可能需要 `HREADYOUT` 插入等待 |

## 1. eFlash 是 SoC 上电后能留下信息的存储

SRAM 和寄存器掉电后内容会丢失，eFlash 属于非易失存储，断电后数据仍能保留。它在 SoC 中最典型的用途是保存 boot 程序：CPU 上电复位后，必须从某个稳定位置读到第一段代码，否则系统不知道下一步执行什么。

视觉验证：视频 05:30-07:00（SoC 框图中 eFlash controller 位于 AHB 总线和 eFlash 存储体之间，CPU 通过总线访问它）。

![eFlash 在 SoC 中的位置](<./screenshots/任务047_AHB_eflash控制器设计1/task47_00_soc_eflash_position_05m30s.jpg>)

系统链路可以压成：

```text
CPU reset
  -> AHB 发起取指或读配置
  -> eFlash controller 接收 AHB 访问
  -> controller 驱动 eFlash IP 的地址和控制脚
  -> eFlash 输出 boot code
  -> CPU 得到第一段程序，系统开始运行
```

没有 eFlash、ROM 或外部启动介质，CPU 上电后就没有稳定指令来源。后续课程讨论的 PFlash/eFlash，本质都服务于这条“掉电后还能提供代码或配置”的链路。

## 2. 设计者做的是 controller，不是改 eFlash 存储体

课程里的 eFlash 存储体通常由代工厂或 IP 厂商提供。前端设计者一般不会修改它的 cell 阵列和模拟电路，而是使用厂家提供的行为模型、接口说明、真值表、时序参数和后端黑盒信息。

视觉验证：视频 13:35-18:20（datasheet 里展示 `32K x 32`、block 信息和 IP 规格；这些资料决定 controller 的地址和控制逻辑）。

![容量与 IP 信息](<./screenshots/任务047_AHB_eflash控制器设计1/task47_01_datasheet_size_13m35s.jpg>)

前端要处理三类交付：

| 文件/信息 | 设计者怎么用 | 不理解的后果 |
|---|---|---|
| 行为模型 | 仿真时当作真实 eFlash 使用 | controller 没有可验证对象 |
| datasheet | 提取容量、接口、真值表和时序 | 地址和控制信号写错 |
| black box / timing 信息 | 后端和 STA 识别 IP 边界 | 集成约束不清 |

IP 不开放内部实现，是为了保护工艺和版图知识产权。前端真正要实现的是协议转换：让 CPU 仍然按 AHB 访问 memory，而 eFlash IP 看到的则是它自己的异步控制波形。

视觉验证：视频 18:20-20:30（main memory block 与 information block 被区分，说明同一个 eFlash IP 内部也有不同用途区域）。

![eFlash 结构说明](<./screenshots/任务047_AHB_eflash控制器设计1/task47_02_block_description_18m20s.jpg>)

## 3. `32K x 32` 决定地址不是一根普通线

一片 eFlash 是 `32K x 32-bit`，也就是 32K 个 32 位 word。32 位等于 4 byte，所以一片 main block 容量是：

```text
32K word x 4 byte/word = 128KB
```

课程中若使用两片，则 main memory 合计约 256KB。每片还可能带 information block，用于保存设备信息、校准信息或特殊配置，不等同于普通程序数据区。

page 组织要记住：

```text
一片 main block = 32K x 32-bit = 128KB
一页 page       = 512 byte
一片 page 数    = 128KB / 512B = 256 page
```

这解释了为什么 page 地址通常可以用 8 bit 表示：`2^8=256`。后续 page erase 不是擦一个 byte 或一个 word，而是按 page 粒度擦除；这会直接影响软件驱动和 controller 状态机。

## 4. `XADR/YADR` 是 row 和 word 的两级地址

eFlash IP 的地址不是直接用 AHB `HADDR` 原样输入，而是拆成 `XADR` 和 `YADR`。课程里 `XADR` 是 10 bit，`YADR` 是 5 bit，两者合起来覆盖 `32K` 个 32-bit word：

```text
2^10 x 2^5 = 1024 x 32 = 32768 = 32K
```

`XADR` 选择 row，`YADR` 选择 row 内的 32-bit word。如果一页包含 4 行，`XADR[9:2]` 可以看成 page 地址，`XADR[1:0]` 选择 page 内某一行。下一讲会把这条地址拆分继续展开；本讲先建立一句话：AHB byte address 必须被 controller 翻译成 eFlash IP 的 row/word/page 地址。

## 5. eFlash 接口没有 clock，controller 必须自己制造时序

SRAM 常见接口由 clock 采样，而这类 eFlash IP 是异步接口。它没有一个 `clk` 输入，动作由控制脚组合和持续时间决定。controller 仍然有系统时钟，但它要用 FSM 和 counter 在规定时间内保持 eFlash 控制脚。

视觉验证：视频 28:20-31:00（eFlash 引脚列表出现 `XADR/YADR/DIN/DOUT/XE/YE/SE/IFREN/ERASE/MAS1/PROG/NVSTR` 等接口）。

![eFlash 引脚接口](<./screenshots/任务047_AHB_eflash控制器设计1/task47_03_pin_interface_28m20s.jpg>)

常用信号含义：

| 信号 | 方向 | 作用 |
|---|---|---|
| `XADR[9:0]` | controller -> eFlash | 选择 row，也参与 page 地址 |
| `YADR[4:0]` | controller -> eFlash | 选择 row 内 32-bit word |
| `DIN[31:0]` | controller -> eFlash | program 时写入数据 |
| `DOUT[31:0]` | eFlash -> controller | read 时读出数据 |
| `XE` | controller -> eFlash | X address enable |
| `YE` | controller -> eFlash | Y address enable |
| `SE` | controller -> eFlash | sense amplifier enable，可理解为读输出使能 |
| `IFREN` | controller -> eFlash | 选择 information block |
| `ERASE` | controller -> eFlash | 进入擦除 |
| `MAS1` | controller -> eFlash | 选择整片或 mass erase |
| `PROG` | controller -> eFlash | 进入写入 |
| `NVSTR` | controller -> eFlash | 非易失写/擦周期启动 |

关键区别：read 不改变存储内容，所以不需要 `NVSTR`；program 和 erase 会改变非易失阵列，因此必须按 datasheet 要求拉起并保持 `NVSTR`。

## 6. 真值表定义“什么控制组合代表什么操作”

异步接口不能靠 clock 简化理解，必须读真值表。真值表告诉你 standby、read、program、page erase、mass erase 各自要求哪些控制脚为 1，哪些必须为 0。

视觉验证：视频 35:50-37:30（truth table 与 timing 条目同屏出现，read/program/erase 的控制组合被逐项对应）。

![真值表与 timing 条目](<./screenshots/任务047_AHB_eflash控制器设计1/task47_04_truth_table_timing_35m50s.jpg>)

可以把操作压成：

| 操作 | 主要控制组合 | 地址需求 | 时间尺度 |
|---|---|---|---|
| standby | 大多数 enable 为 0 | 无 | 空闲 |
| read | `XE=1, YE=1, SE=1` | 需要 `XADR/YADR` | ns 级 access |
| program | `PROG=1, NVSTR=1`，配合 `XE/YE` | 需要 `XADR/YADR/DIN` | us 级 |
| page erase | `ERASE=1, MAS1=0, NVSTR=1`，配合 `XE` | 需要 page 地址 | ms 级 |
| mass erase | `ERASE=1, MAS1=1, NVSTR=1` | 通常不关心具体 word | ms 级且 hold 更长 |

controller 的状态不是凭经验命名，而是从真值表和时序图推出来。每个 FSM 状态都应该能解释成“保持某组控制脚并等待某段时间”。

## 7. page erase 是最慢的基本动作

page erase 需要先指定 page，拉起 `ERASE/XE`，等待 `TNVS` 后再拉起 `NVSTR`，保持 20-40ms 的擦除时间，再按 hold/recover 要求退出。

视觉验证：视频 39:50-42:20（page erase 波形中 `ERASE` 先建立，`NVSTR` 后拉起；擦除完成后 `ERASE` 先落，`NVSTR` 继续保持一段时间）。

![page erase 波形](<./screenshots/任务047_AHB_eflash控制器设计1/task47_05_erase_waveform_39m50s.jpg>)

按 100MHz AHB clock 粗算：

```text
1 cycle = 10ns
20ms    = 20,000,000ns = 2,000,000 cycles
40ms    = 40,000,000ns = 4,000,000 cycles
```

这说明擦除不能用“等几拍”处理，必须有足够宽的 counter。软件也不能把 erase 当成普通寄存器写一拍完成，而要通过 busy/status/interrupt 或轮询机制等待完成。

## 8. program 是写 32-bit word，但也要按微秒级时序

program 操作写入一个 32-bit word。它需要 `XADR/YADR/DIN` 定位和给数，同时拉起 `PROG` 与 `NVSTR`，再按 IP 时序拉起 `YE` 完成写入动作。

视觉验证：视频 45:30-48:00（program 波形中 `PROG`、`NVSTR`、`YE` 不同时起落，地址和数据要在写入窗口内稳定）。

![program 波形](<./screenshots/任务047_AHB_eflash控制器设计1/task47_06_program_waveform_45m30s.jpg>)

program 比 erase 快，但仍远慢于普通 AHB 单拍写：

```text
setup:   us 级或 ns/us 混合
program: 20-40us
hold:    ns/us 级混合
recover: 约 1us
```

因此 AHB 写 eFlash 不能简单当成“写数据后立即完成”。一种设计是让 controller 拉低 `HREADY` 等待；另一种设计是软件写 command 寄存器启动操作，再通过 status/interrupt 确认完成。具体协议要在设计文档里固定。

## 9. read 相对快，但也可能让 AHB 插入等待

read cycle 不需要 `NVSTR`，主要是给出 `XADR/YADR`，拉起 `XE/YE/SE`，等待 access time 后读取 `DOUT`。

视觉验证：视频 52:55-54:30（read cycle 的关键时间是 access time，控制脚有效后 `DOUT` 需要一段时间才稳定）。

![read cycle](<./screenshots/任务047_AHB_eflash控制器设计1/task47_07_read_cycle_52m55s.jpg>)

从 AHB 角度看：

```text
CPU 发起读访问
  -> controller 锁存 HADDR
  -> 生成 XADR/YADR 和 XE/YE/SE
  -> HREADYOUT 拉低，等待 eFlash DOUT 稳定
  -> HRDATA 返回，HREADYOUT 拉高完成传输
```

这就是 eFlash controller 比 SRAM controller 复杂的根本原因：它要把 AHB 的同步总线世界和 eFlash IP 的异步时序世界对齐。

## 10. 最小闭环：从 datasheet 推出 read 控制流程

读 eFlash 的最小控制流程：

```text
输入：AHB read，HADDR 指向 eFlash main block。
步骤：
  1. 锁存 HADDR，计算 XADR/YADR。
  2. 拉高 XE、YE、SE，IFREN=0。
  3. HREADYOUT=0，等待 access time 对应的 cycle 数。
  4. 采样 DOUT 到 HRDATA。
  5. 拉低 XE/YE/SE，HREADYOUT=1。
输出：AHB 读传输完成，CPU 得到 32-bit 数据。
```

验证这个闭环时，波形至少要同时看 `HADDR/HREADYOUT/HRDATA` 和 `XADR/YADR/XE/YE/SE/DOUT`。只看总线侧能知道 CPU 拿到了什么，却不知道 eFlash IP 是否被正确驱动。

## 11. 工程检查清单：eFlash controller 规格先问这几件事

写 eFlash controller 之前，先把这些问题写进设计说明。答不出来就不要急着写 RTL，因为后续 bug 会出现在地址边界、等待策略和软件协议上。

| 检查项 | 必须明确的内容 | 不明确的后果 |
|---|---|---|
| memory map | eFlash 起始地址、大小、片选方式、information block 是否映射 | AHB decode 和片选边界错 |
| 访问粒度 | 支持 word/halfword/byte 哪些访问 | 写掩码、读回对齐和异常处理混乱 |
| erase 粒度 | page erase 还是 mass erase，page 大小是多少 | 软件误擦同页其他数据 |
| 写协议 | AHB 写直接等待完成，还是写 command 后轮询 status | `HREADY`、busy、interrupt 行为不清 |
| read wait | access time 对应多少 cycle，是否参数化 | `HRDATA` 采样过早 |
| IP 区域 | main block 与 information block 如何选择 | `IFREN` 和地址空间混用 |
| 错误返回 | busy 时访问如何处理，是否返回 `HRESP` error | master 行为不可预测 |

## 12. 深层理解：controller 是“同步总线”和“慢速 eFlash 仪式”的翻译器

AHB master 说的是同步总线语言：一拍地址、一拍数据、用 `HREADY/HRESP` 管理等待和响应。eFlash IP 说的是存储体仪式语言：先选地址，再按 read/program/erase 的固定控制脚组合和时序窗口执行，某些操作还要等待很久。controller 的价值就是把“总线事务”翻译成“IP 控制脚仪式”。

这个翻译器必须同时回答三类问题：

| 问题 | AHB 侧答案 | eFlash 侧动作 |
|---|---|---|
| 读请求来了 | master 期望 `HRDATA` 和 `HREADYOUT` | 拉 read 控制脚，等 access time 后采样 |
| program 请求来了 | master 可能只写寄存器或命令 | 准备地址/数据，执行 program 序列，置 busy/status |
| erase 请求来了 | master 可能发 page 或 mass erase command | 按 erase 粒度和长等待执行，期间拒绝或延迟新请求 |

如果没有这个翻译层，AHB 会把 eFlash 当成 SRAM 一样访问；结果就是读采早、写不稳、擦除粒度不清、busy 时还接新单。

## 13. 系统行为失败信号

| 失败现象 | 深层原因 | 第一检查动作 |
|---|---|---|
| 读 eFlash 偶尔返回 X 或旧值 | read access time 未等够 | 查 `HREADYOUT` 和 read counter |
| program 后立即读不对 | program busy 未结束或未做 readback | 查 status/busy 和验证流程 |
| erase 时还能接新写请求 | controller 没有屏蔽 busy 期间访问 | 查 busy 状态下的 AHB 响应策略 |
| page 内其他 word 被清掉 | erase 粒度理解错误 | 查 page buffer 或软件读改写策略 |
| AHB master 卡住 | `HREADYOUT` 拉低后状态机无退出条件 | 查 timeout 和最终状态 |
| HRESP 不一致 | 错误访问/非法命令没有统一响应 | 定义 busy、越界、未对齐访问的返回策略 |

eFlash controller 的成熟度不只看“能读一个 word”，还要看慢操作期间系统会怎样表现：等待、报错、中断、轮询，还是 timeout。

## 14. 最后速记

### 14.1 本章最该记住的结论

- eFlash 是非易失存储，适合保存 boot 程序；SRAM 掉电丢内容。
- 前端设计者主要写 controller，用 datasheet 驱动厂商 eFlash IP。
- `32K x 32-bit` 表示 32K 个 32 位 word，一片约 128KB。
- eFlash IP 没有 clock，controller 必须用 FSM/counter 生成控制脚时序。
- read、program、erase 的时间尺度差异决定了 `HREADY`、busy/status 和 counter 设计。

### 14.2 复现 / 复习清单

- 能把 `32K x 32-bit` 换算成 byte 容量。
- 能说出 `XE/YE/SE/ERASE/PROG/NVSTR` 的基本作用。
- 能解释 read 为什么不需要 `NVSTR`。
- 能从 page erase 波形看出 setup、busy、hold、recover。
- 能说明 AHB controller 为什么需要插入 wait state。

## 复习与自测

1. 为什么 eFlash 可以保存 boot 程序，而 SRAM 不适合保存掉电后的 boot 程序？

   答案：eFlash 是非易失存储，断电后内容保留；SRAM 掉电后数据丢失，不能作为稳定启动程序存储。

2. `32K x 32-bit` 等于多少 byte？

   答案：32K 个 word，每个 word 4 byte，所以是 128KB。

3. 为什么 read 操作不需要 `NVSTR`？

   答案：`NVSTR` 用于改变非易失存储内容的 program/erase 周期；read 不改变内容，只需要地址和 sense amplifier 输出。

4. 如果 eFlash read access time 是 24ns，AHB clock 是 100MHz，为什么通常不能单周期返回？

   答案：100MHz 周期是 10ns，24ns 超过两个周期，通常要等到第三个周期数据才足够稳定。

5. page erase 为什么会影响软件驱动设计？

   答案：如果只想改 page 内部分 word，也必须处理整页内容；软件可能需要先读旧页、修改目标 word、擦页、再写回整页。

6. controller 和 eFlash 存储体 IP 的边界是什么？

   答案：controller 接 AHB、产生地址/控制脚/等待/状态；eFlash IP 按这些控制脚执行读、写、擦，并输出数据或内部状态。前端通常不修改 IP 内部 cell 阵列。

## 工程核对口径

学完本章后，至少能回答：

1. eFlash 和 SRAM 在掉电保持、访问时间、写入/擦除粒度上有什么本质差异。
2. controller 与 eFlash IP 的边界在哪里。
3. read/program/erase 各自需要哪些控制脚和等待策略。
4. AHB 侧 `HREADYOUT/HRESP/status/interrupt` 应如何反映慢操作和错误访问。
5. 为什么 page erase 会影响软件驱动和 page buffer 设计。


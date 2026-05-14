# 任务52：AHB eFlash控制器设计5

## 本章知识全景图

这一讲从“eFlash 怎么工作”推进到“controller 规格怎么写、寄存器怎么定义、软件怎么用”。如果 47-50 解决的是存储体时序，那么 52 解决的是软硬件接口：CPU 通过哪些寄存器启动 erase/program，timing 参数如何配置，状态和中断如何回报，boot 区写保护如何阻止误擦写。

| 层级 | 核心概念 | 本章要形成的判断 | 连接到前端交付 |
|---|---|---|---|
| 功能规格 | 32-bit AHB slave、不支持 BUSY、多周期读写擦 | RTL 必须实现规格列出的 feature，不是只会驱动 IP | datasheet、设计需求 |
| 模块划分 | `flash_ahb_slave_if`、`flash_ctrl` | 左边接 AHB 和寄存器，右边产生 eFlash 控制波形 | 架构图、RTL 分工 |
| 配置寄存器 | timing、WEN/PEN、page、address/data | CPU 写寄存器来启动操作和配置等待时间 | memory map、驱动 |
| 状态寄存器 | program done、page erase done、write error | 硬件完成后置位，软件读状态并清除 | 中断、polling |
| timing 配置 | `TNVS/TNVH/TPGS/TPROG/TACC/TERASE/TREC` | 等待时间用寄存器保存，兼容不同 eFlash IP | FSM counter |
| boot 保护 | write protect、boot offset | boot 区默认不允许被擦写 | 系统可靠性 |

最短学习路径：

```text
先读 controller feature
  -> 看 AHB interface 和 flash_ctrl 两个模块怎么分工
  -> 明确 read/program/erase 的地址来自哪里
  -> 读 timing 和 command 寄存器
  -> 读 status、中断和写一清零
  -> 最后看软件操作顺序
```

## 全视频地图

| 时间段 | 教学块 | 必须保留的知识动作 |
|---|---|---|
| 00:00-10:00 | datasheet 与 controller feature | 把 eFlash controller 的功能边界钉住 |
| 10:00-20:00 | AHB interface / flash_ctrl 模块划分 | 区分总线寄存器层和存储体时序层 |
| 20:00-34:00 | timing value 与配置寄存器 | 把 IP 时序参数变成可配置寄存器 |
| 34:00-48:00 | register list 与状态中断 | 读懂 CPU 如何启动操作、硬件如何回报完成 |
| 48:00-61:12 | 软件操作顺序与 boot 保护 | 把寄存器写序列转成 page erase / program 的工程闭环 |

## 视觉核对清单

本讲的截图要按“合同文本 -> 柜台分工 -> 作业流程”的顺序读。datasheet 是合同，寄存器表是 CPU 和硬件共用的申请单，`flash_ctrl` 是后场工段；软件写错顺序，就像单据没填完就按下启动按钮，后场只能拿旧地址、旧数据或旧 timing 去工作。

| 时间段 | 截图 | 看图要点 | 漏看后果 |
|---|---|---|---|
| 00:30 | `task52_00_datasheet_intro_00m30s.jpg` | feature list 直接约束 RTL、寄存器和验证项 | 写代码时凭感觉加功能，软件接口对不上 |
| 08:35 | `task52_01_controller_arch_08m35s.jpg` | AHB interface 与 `flash_ctrl` 是前台/后场分工 | 把总线协议和 eFlash 脉冲混进一个模块 |
| 16:35 | `task52_02_address_sources_16m35s.jpg` | program、read、page erase 的地址口径不同 | 用 word address 去擦 page，或用 page number 去 program |
| 23:25 | `task52_03_timing_values_23m25s.jpg` | timing value 是可配置等待周期，不是装饰字段 | 换频率或换 IP 后时序失效 |
| 33:40 | `task52_04_register_list_33m40s.jpg` | register map 是软件驱动和 RTL 的共同语言 | 驱动写错偏移，RTL 看似正常但系统不可用 |
| 43:50 | `task52_05_register_detail_43m50s.jpg` | 字段位宽、W1C、enable、interrupt enable 要分清 | 状态清不掉、命令误触发或中断误报 |
| 53:55 | `task52_06_program_guide_53m55s.jpg` | 软件操作顺序必须先参数后启动 | FSM 使用旧地址/旧数据 |
| 57:50 | `task52_07_software_sequence_57m50s.jpg` | boot 保护要由硬件拒绝非法写擦 | 软件 bug 可能擦掉启动程序 |

## 1. datasheet 先把“这个 IP 要做什么”钉住

eFlash controller 的 datasheet 第一屏要回答：这个 IP 用来保存 boot 命令和数据，普通运行时多为读操作，系统升级时才进行擦写；为了防止软件误改 boot 区，controller 需要写保护机制。

![datasheet 功能介绍](<./screenshots/任务052_AHB_eflash控制器设计5/task52_00_datasheet_intro_00m30s.jpg>)

> 图注：00:30 左右。这里要看功能描述：main block 和 information block 保存不同内容，boot 区默认需要保护，擦写通常只在升级或维护场景发生。

这个判断会影响 controller 行为：

- read 是最常用路径，应能把 AHB 读转成 eFlash read，并处理 access wait。
- program/erase 是低频但高风险路径，要有显式命令和 busy/status。
- boot 区不是普通数据区，写保护打开时不能让 program/page erase 真的落到存储体。

如果规格没有写清这些点，RTL 后面会出现“软件以为能写，硬件以为不能写”的接口歧义。

## 2. controller 分成 AHB 接口和 flash 控制两块

课程中的控制器不是一个大文件包打天下，而是拆成两类职责：`flash_ahb_slave_if` 负责 AHB 访问、寄存器、状态和中断；`flash_ctrl` 负责把 read/program/erase 命令变成 eFlash IP 控制脚波形。

![controller 架构](<./screenshots/任务052_AHB_eflash控制器设计5/task52_01_controller_arch_08m35s.jpg>)

> 图注：08:35 左右。这里要看左侧 AHB interface、寄存器和中断，右侧 flash control 与两片 eFlash 存储体。两个模块之间传的是命令、地址、数据、timing 和状态。

分工可以压成：

| 模块 | 输入 | 输出 | 核心工作 |
|---|---|---|---|
| `flash_ahb_slave_if` | AHB 信号、flash done/busy/read data | WEN/PEN、page、program address/data、timing、interrupt、HRDATA/HREADY | 解析 AHB 访问和寄存器 |
| `flash_ctrl` | 命令、地址、数据、timing | `XADR/YADR/DIN/XE/YE/SE/PROG/ERASE/NVSTR` | FSM + counter 生成 IP 时序 |

这样拆的好处是：AHB 协议和 eFlash 异步时序不会混在一个状态机里。debug 时可以先看命令是否正确，再看 IP 波形是否正确。

## 3. program/read 的地址和 page erase 的地址不是同一个入口

program 和 read 需要定位某个 32-bit word，因此地址来自 flash address；page erase 只需要知道擦哪一页，因此地址来自 page number 寄存器。

![地址来源](<./screenshots/任务052_AHB_eflash控制器设计5/task52_02_address_sources_16m35s.jpg>)

> 图注：16:35 左右。这里要看两类地址入口：program/read 使用 flash address 拆成 `XADR/YADR`；page erase 使用 page number 形成 page 地址。

三类操作的地址口径：

| 操作 | 地址来自哪里 | 为什么 |
|---|---|---|
| read | AHB 读地址，可能叠加 boot offset | CPU 直接按 memory map 读 eFlash 内容 |
| program | program address 寄存器 | 软件先写目标地址，再写数据和 WEN |
| page erase | page number 寄存器 | erase 粒度是 page，不是 word |
| mass erase | command/模式选择 | 擦整块，不依赖 word 地址 |

这解释了为什么 `flash_ctrl` 不能只接一根“地址”：不同操作需要的地址粒度不同。

## 4. timing value 是把 eFlash 时序做成可配置

如果把 `TNVS=5us`、`TPROG=20us` 这些时间全部写死，换一颗 eFlash IP 就可能不能用。更稳的做法是把各段等待时间放进寄存器，由 CPU 或 reset 默认值提供。

![timing value 信号](<./screenshots/任务052_AHB_eflash控制器设计5/task52_03_timing_values_23m25s.jpg>)

> 图注：23:25 左右。这里要看 `TNVS/TNVH/TPGS/TPROG/TACC/TERASE/TREC` 这类 timing value。它们进入 `flash_ctrl` 后决定各状态维持多少 cycle。

换算原则：

```text
target_cycles = ceil(required_time / clock_period)
```

规格里按 120MHz 估算，比 100MHz 更保守。因为 120MHz 周期约 8.33ns，按它算出来的 cycle 数在 100MHz 下只会等待更久，不会等待更短。

例如：

```text
5us / 8.33ns ≈ 601 cycle
1us / 8.33ns ≈ 121 cycle
20us / 8.33ns ≈ 2401 cycle
```

这不是随便加裕量，而是在保证时钟可能偏快时仍满足 IP 最小时间。

## 5. 寄存器列表是 CPU 和 IP 的共同语言

寄存器 map 告诉软件：往哪个地址写什么值，硬件会做什么动作；读哪个地址，能得到什么状态。

![寄存器列表](<./screenshots/任务052_AHB_eflash控制器设计5/task52_04_register_list_33m40s.jpg>)

> 图注：33:40 左右。这里要看 timing、page number、program address/data、interrupt enable、status/error 等寄存器。RTL 的 AHB slave 需要逐项实现这些地址译码和读写属性。

常见寄存器类别：

| 类别 | 例子 | 读写属性 | 用途 |
|---|---|---|---|
| timing | `TNVS`、`TNVH`、`TPGS`、`TERASE` | RW | 配置等待周期 |
| command | `WEN`、`PEN` | RW 或写触发 | 启动 program/page erase |
| address/data | page number、program address、program data | RW | 指定目标和写入数据 |
| interrupt enable | program done enable、PE done enable | RW | 决定完成后是否中断 |
| status/error | program done、PE done、boot write error | RO/W1C | 上报完成或非法操作 |

`W1C` 表示 write-one-clear：软件写 1 清掉对应状态位。不要把它当成普通 RW 寄存器，否则会误清或清不掉状态。

## 6. 一个寄存器可以把多个短 timing 合并

课程里提到某个寄存器把 `ADS/ADH/PGH` 这类 20ns 级时间合在一起，每个字段用几个 bit 表示。原因很简单：它们都很短，单独占一个 32-bit 寄存器浪费。

![寄存器字段细节](<./screenshots/任务052_AHB_eflash控制器设计5/task52_05_register_detail_43m50s.jpg>)

> 图注：43:50 左右。这里要看字段位宽和 reset value。读寄存器表时不能只看寄存器名，还要看每个字段占几位、默认值是多少、对应哪段时序。

寄存器表要读四个维度：

```text
offset: CPU 访问地址
field: 哪些 bit 有意义
type: RW、RO、W1C
reset: 复位后默认值
```

如果 reset value 已经按目标 eFlash 配好，软件可以不每次都重配 timing；但驱动仍应能在调试或替换 IP 时覆盖这些值。

## 7. 软件操作顺序决定硬件状态机如何启动

read、program、page erase 的软件流程不同。read 可以直接用 AHB 地址访问 eFlash 存储空间；program 和 erase 需要先配置寄存器，再写启动位。

![软件操作指南](<./screenshots/任务052_AHB_eflash控制器设计5/task52_06_program_guide_53m55s.jpg>)

> 图注：53:55 左右。这里要看 program 和 page erase 的步骤：先配 timing/地址/数据/中断，再置位 WEN 或 PEN，最后查询 status 并清除。

program 典型流程：

```text
1. 配置 program address。
2. 配置 program data。
3. 可选配置 timing 和 interrupt enable。
4. 写 WEN=1，启动 program FSM。
5. 轮询 status 或等待 interrupt。
6. 读 status/error。
7. 写 1 清除完成状态。
```

page erase 典型流程：

```text
1. 配置 page number。
2. 选择 main block 或 information block。
3. 写 PEN=1，启动 page erase。
4. 等待 done。
5. 清除 status。
```

启动位要在地址和数据之后写，否则 FSM 可能拿到旧地址或旧数据。

## 8. boot 区保护把非法擦写变成可诊断状态

boot 区默认不希望被随意擦写。如果写保护有效，软件仍尝试擦写 boot 区，硬件应阻止操作，并通过 status/error 告诉 CPU。

![软件序列与写保护](<./screenshots/任务052_AHB_eflash控制器设计5/task52_07_software_sequence_57m50s.jpg>)

> 图注：57:50 左右。这里要看软件示例：操作完成后要读状态并写 1 清除；boot 区误操作要能返回 error，而不是静默失败。

保护机制的工程意义：

```text
非法擦写 boot 区
  -> controller 不启动真实 program/erase
  -> 设置 boot write/PE error
  -> 可选触发状态相关中断
  -> 软件读取错误并清除状态
```

不要让非法操作“看起来成功但没写进去”，也不要让它真的写坏 boot 区。最好的行为是明确拒绝，并留下可读状态。

## 9. 最小闭环：用寄存器启动一次 page erase

```text
输入：CPU 要擦除 page P。
步骤：
1. 写 page number = P。
2. 写 main/information select。
3. 写 PEN=1。
4. `flash_ahb_slave_if` 输出 PEN 和 page number。
5. `flash_ctrl` 进入 erase FSM，busy=1。
6. erase 完成，PE done=1。
7. 若 interrupt enable 打开，interrupt=1。
8. CPU 读 status，写 1 清除 PE done。
输出：page erase 命令闭环完成。
```

这条链覆盖了 AHB 写寄存器、FSM 启动、状态回报和软件清除，比只看 eFlash 波形更接近真实 IP 使用。

## 本讲在 50-54 链条中的位置

任务52 是从“概念和场景”进入“规格落地”的一讲：把任务50 的存储体 timing、任务51 的软件访问模型，压成寄存器、字段、timing value、启动位、状态位和错误位。它是后面读 RTL 时判断代码是否合理的标准答案。

| 本讲输入 | 本讲输出 | 后续使用 |
|---|---|---|
| eFlash erase/program/read timing | `TNVS/TNVH/TPROG/TACC/TERASE/TREC` 等配置字段 | 任务53 的 counter/FSM |
| memory/register space 区分 | command、address、data、status 寄存器 | 任务54 的寄存器读写逻辑 |
| boot 区保护需求 | write protect、error status | 后续异常测试和软件驱动 |

验收口径：读者必须能给出一次 page erase 的寄存器写序列，并说明启动位为什么必须在地址、block select 和 timing 配好之后再写。

## 工程练习

1. 写出一次 page erase 的最小寄存器序列。

   合格答案：配置 timing；写 page number 或 block/chip select；确认 write protect/boot protect 条件；写 page erase enable；等待 `pe_done` 或 error/interrupt；读 status；W1C 清状态。启动位必须最后写，因为它像产线的启动拉杆，拉下后 FSM 会立即读取已经锁存的参数。

2. 判断一个 timing 字段应该写死还是做寄存器。

   合格答案：和 eFlash IP 工艺、时钟频率、PVT 或 datasheet 参数相关的等待时间应做成寄存器或参数；纯协议常量可以写成 localparam。否则 controller 像只适配一台机器的夹具，换芯片或换频率就要改 RTL。

3. 给 boot 保护补一个负向测试。

   合格答案：先使能 write protect 或 boot protect，再对 boot 区地址发 program/page erase；期望真实 eFlash 控制脚不启动，status/error 置位，命令位被清除，interrupt 按 enable 产生。

## 常见误区和失败信号

| 误区 | 正确判断 | 失败信号 |
|---|---|---|
| datasheet 只是说明书 | 它直接决定 RTL feature 和寄存器 map | RTL 功能和软件预期不一致 |
| timing 写死最简单 | 可配置 timing 才能适配不同 IP 和频率 | 换 IP 后时序不满足 |
| 启动位可以先写 | 启动位应在地址/数据配置完成后写 | FSM 使用旧地址或旧数据 |
| status 是普通 RW | 完成位常是硬件置位、软件写 1 清除 | 状态残留或误清 |
| boot 保护只靠软件自觉 | 硬件必须阻止非法擦写 | boot 程序被误擦 |

## 复习与自测

1. 为什么 eFlash controller 要把 timing 做成寄存器配置？

   参考答案：不同 eFlash IP 或不同目标频率需要不同等待周期，寄存器配置能避免 RTL 写死时间。

2. program 和 page erase 的地址来源有什么区别？

   参考答案：program 定位 32-bit word，使用 program address；page erase 定位 page，使用 page number。

3. `W1C` 状态位是什么意思？

   参考答案：硬件置位，软件写 1 清除对应位；写 0 不清除。

4. 为什么启动 WEN 前要先写 program address 和 data？

   参考答案：WEN 启动 FSM 后会使用当前寄存器值；若地址或数据尚未更新，可能写到旧目标。

5. boot 区保护触发时，硬件应该怎么处理？

   参考答案：阻止真实擦写，设置错误状态，必要时通知 CPU，等待软件读取并清除。


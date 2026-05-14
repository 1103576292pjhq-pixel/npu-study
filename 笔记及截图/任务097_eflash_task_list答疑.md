# 任务97：eFlash task list 答疑

## 本章知识全景图

这一讲把 eFlash controller 的作业题重新压成一条工程主线：先算清 eFlash 的 page、row、DWord 和 X/Y 地址，再把 erase、program、read 的时序映射成 RTL 状态机，最后落到 CPU 通过寄存器启动硬件、硬件完成后用 status/interrupt 反馈。

| 层级 | 核心概念 | 必须掌握的判断 |
|---|---|---|
| 存储组织 | page、row、DWord、XADDR、YADDR | erase 按 page，program/read 精确到 DWord。 |
| Erase | page erase、mass erase、TNVS、NVSTR、NVH、recover | erase 不需要 YADDR，核心是选 page 后按 macro 时序拉控制脚。 |
| Program | X/Y/data、PGS、program time、hold | program 必须绑定地址、数据和多段时序。 |
| Read | SENSE/output enable、access time | read 不改非易失存储，不需要 NVSTR，但采样点必须正确。 |
| 仿真 | `+notimingcheck`、`+nospecify`、SDF | 当前 pass 是功能正确，不等于门级时序已经安全。 |
| 软硬件交互 | AHB register、memory space、boot protect、interrupt | CPU 写寄存器启动，FSM 执行，status/interrupt 闭环反馈。 |

最短学习路径：

```text
先算 32K x 32 的 page/row/DWord
  -> 分清 erase/program/read 的地址来源
  -> 把 page erase、program、read 写成状态机
  -> 理解 +notimingcheck/+nospecify 的仿真边界
  -> 区分寄存器地址空间和 eFlash 存储地址空间
  -> 用 status/interrupt 建立 CPU 和硬件闭环
  -> 引出 98/99 的连续 program RTL 与 TB
```

## 全视频地图

| 时间段 | 视频块 | 视觉证据 | 学习目标 |
|---|---|---|---|
| 00:35-06:13 | eFlash 存储组织 | `task97_00_flash_concepts_00m35s.jpg`、`task97_01_page_erase_timing_06m13s.jpg` | 算清 page、row、DWord、X/Y 位宽。 |
| 06:13-16:30 | Page erase / mass erase | `task97_02_erase_fsm_10m14s.jpg` | 用状态机表达 TNVS、erase active、NVH、recover。 |
| 17:26-24:31 | Program timing | `task97_03_program_timing_17m26s.jpg` | 掌握 X/Y/data、PGS、program pulse、hold 的顺序。 |
| 25:10-28:22 | Read timing | `task97_04_read_timing_25m10s.jpg` | read 只需选中、打开输出、等待 access time、采样。 |
| 29:04-31:41 | 仿真选项和地址空间 | `task97_05_vcs_timing_options_29m04s.jpg`、`task97_06_address_sources_31m41s.jpg` | 区分功能仿真、SDF、寄存器地址、存储地址。 |
| 31:41-40:22 | boot protect 与软硬件交互 | `task97_07_fsm_sw_hw_37m18s.jpg` | 建立 CPU 寄存器配置、FSM、interrupt/status 闭环。 |

## 视觉证据与截图说明

| 截图 | 教学职责 |
|---|---|
| ![eFlash 基本概念](<./screenshots/任务097_eflash_task_list答疑/task97_00_flash_concepts_00m35s.jpg>) | 对齐 page、row、DWord 与 32K x 32 的存储组织。 |
| ![page erase timing](<./screenshots/任务097_eflash_task_list答疑/task97_01_page_erase_timing_06m13s.jpg>) | 说明 XADDR 高位对应 page，YADDR 只对 DWord 有意义。 |
| ![erase FSM](<./screenshots/任务097_eflash_task_list答疑/task97_02_erase_fsm_10m14s.jpg>) | 把 erase timing 转成可写 RTL 的状态机。 |
| ![program timing](<./screenshots/任务097_eflash_task_list答疑/task97_03_program_timing_17m26s.jpg>) | 定位 program 需要配置的时序寄存器和控制信号。 |
| ![read timing](<./screenshots/任务097_eflash_task_list答疑/task97_04_read_timing_25m10s.jpg>) | 展示 read FSM 比 program 简单，关键是 access time 与采样。 |
| ![VCS timing options](<./screenshots/任务097_eflash_task_list答疑/task97_05_vcs_timing_options_29m04s.jpg>) | 说明 `+notimingcheck/+nospecify` 的功能仿真边界。 |
| ![地址来源](<./screenshots/任务097_eflash_task_list答疑/task97_06_address_sources_31m41s.jpg>) | 区分 read、program、erase 的 X/Y 地址来源。 |
| ![软硬件 FSM 闭环](<./screenshots/任务097_eflash_task_list答疑/task97_07_fsm_sw_hw_37m18s.jpg>) | 说明寄存器、FSM、interrupt/status 如何形成软件可控事务。 |

## 1. eFlash 地址粒度必须先算清

eFlash 不像 SRAM 那样随便按 byte 改写；它有擦除粒度、编程粒度和读取粒度，三者对应不同地址字段。

本项目的基本关系：

```text
1 DWord = 32 bit = 4 Byte
1 row = 32 DWord = 128 Byte
1 page = 4 row = 128 DWord = 512 Byte
32K x 32 bit = 32K DWord = 128 KB
128 KB / 512 Byte = 256 page
```

地址推导：

| 字段 | 含义 | 位宽 | 用途 |
|---|---|---:|---|
| `XADDR` | row address | 10 bit | 1024 row 中选一行。 |
| `XADDR[9:2]` | page address | 8 bit | 256 page 中选一页。 |
| `XADDR[1:0]` | page 内 row | 2 bit | 一页内 4 个 row。 |
| `YADDR[4:0]` | row 内 DWord | 5 bit | 一行内 32 个 DWord。 |

这个表决定 RTL 地址 mux。erase 只关心 page，program/read 必须精确到某个 DWord。

## 2. Page erase 是“选 page + 按时序拉控制脚”

Page erase 不需要 `YADDR`，也不需要 page 内 row 的低两位。它只要知道擦哪一页，然后按 macro 要求保持 TNVS、NVSTR、erase active、NVH 和 recover。

Page erase 的流程：

```text
配置:
  page_number
  main/info block select
  setup/hold/recover/erase count

启动:
  X enable = 1
  erase enable = 1

执行:
  wait TNVS
  NVSTR = 1
  keep erase active for erase time
  erase enable = 0
  wait NVH
  NVSTR = 0
  wait recover
  return idle
```

状态机骨架可以压成：

```text
IDLE
  -> TNVS
  -> ERASE_ACTIVE
  -> NVH
  -> RECOVER
  -> IDLE
```

Mass erase 和 page erase 的最大差异不是“多擦几页”这么简单。mass erase 通常要拉起 `MASS` 类控制信号，并且某些 hold time 更长。用 page erase timing 直接套 mass erase，功能仿真可能看起来能过，但真实 macro 时序会不满足。

## 3. Program 必须绑定 X/Y/data 和多段时间

Program 会改变非易失存储内容，因此需要 NVSTR；它还要知道写哪个 DWord、写什么 data、每段 setup/hold 要维持多久。

单 word program 的高密度流程：

```text
1. 配置 XADDR、YADDR、program data
2. 拉起 XE 和 program enable
3. 等 TNVS
4. 拉起 NVSTR
5. 等 program setup time
6. 拉起 YE，进入 program pulse
7. 保持 program time
8. 放下 YE，等待 address/program hold
9. 放下 program enable
10. 等 NVH 和 recover
11. 返回 idle
```

状态机不能只写成一个笼统 `busy`。每个时间段都应该能追到状态或计数器，否则后面做连续 program 时无法判断哪一段只做一次、哪一段要对每个 DWord 重复。

## 4. Read 不需要 NVSTR，但采样点必须正确

Read 不改 eFlash 内部内容，所以不需要 NVSTR。它的关键是：给出 X/Y，打开 sense/output enable，等 access time 后采样 `DOUT`。

最小流程：

```text
1. 送入 XADDR/YADDR
2. 拉起 XE/YE/SE
3. 等 read access time
4. 采样 DOUT
5. 放下 XE/YE/SE
6. 回到 idle
```

两个常见错误：

| 错误 | 后果 |
|---|---|
| access time 未到就采样 | macro 数据还没稳定，读到旧值或 X。 |
| 先关 enable 再采样 | 输出已经无效，TB 可能读到 0 或不确定值。 |

因此 TB 中的 `read_word` 必须先读数据，再释放 `XE/YE/SE`。

## 5. `+notimingcheck` 和 `+nospecify` 只说明当前在做功能仿真

`+notimingcheck` 用来关闭时序检查，`+nospecify` 用来屏蔽 specify block。加上这些选项后，仿真重点是 RTL 逻辑功能，而不是门级真实延时。

| 验证层级 | 关注点 | 能证明什么 | 不能证明什么 |
|---|---|---|---|
| RTL 功能仿真 | 状态机、寄存器、数据通路是否按逻辑运行 | 理想延时下功能正确 | 真实 setup/hold 和门级延时安全 |
| Gate/SDF 仿真 | 网表加延时后 testcase 是否仍通过 | 部分动态时序行为 | 不能替代完整 STA |
| STA | 所有约束路径是否满足 timing | 静态时序收敛 | 功能语义是否正确 |

所以功能仿真跑通后，还要综合、STA、后仿或相应签核流程。不要把 `+notimingcheck` 下的 pass 当成完整芯片交付。

## 6. Read、program、erase 的地址来源不同

eFlash controller 同时面对寄存器地址空间和存储地址空间。CPU 写配置寄存器、CPU 读 eFlash 内容、硬件启动 program/erase，这三类地址不是一回事。

| 操作 | eFlash X/Y 地址来源 | 原因 |
|---|---|---|
| Read | AHB memory read address | CPU 直接读取某个 eFlash 存储位置。 |
| Program | program address register | CPU 先写寄存器，硬件再按寄存器值执行 program。 |
| Page erase | page number register | erase 按 page，不按 DWord。 |
| Boot read | AHB address + boot offset | boot 区通常映射在特定高地址区域。 |

Boot protect 是硬件边界，不是软件自觉。若 boot 区处于保护状态，非法擦写必须由 RTL 拦截并上报 error，不能让 macro 真进入 erase/program。

## 7. 软件和硬件通过寄存器、中断、状态形成闭环

CPU 不直接拉 eFlash macro 控制脚。CPU 写 controller 寄存器，硬件 FSM 执行事务，完成后通过 status/interrupt 告诉 CPU。

闭环如下：

```text
CPU:
  写 timing count / address / data / block select
  写 enable/start

Hardware:
  FSM 进入 erase/program/read
  count 维持 macro timing
  驱动 XE/YE/NVSTR/PROG/ERASE/SENSE

Finish:
  done/error/status 更新
  interrupt 拉起

CPU:
  读 status
  清 interrupt
  决定下一步
```

这也是 eFlash controller 和普通寄存器模块的差异。它不是“写一个寄存器立即生效”这么简单，而是有长延时、内部状态、错误保护和软件可观察状态。

## 8. 连续 program 作业检验是否真正理解 RTL

课程末尾引出后续作业：原设计一次只 program 一个 DWord；连续 program 要在一次外层 program 事务中写多个 DWord，避免每个 word 都重复 TNVS、NVSTR 起始和 recover。

要支持连续 program，至少要新增或改造：

```text
program_data0..3
program_number
program_count
data mux
YADDR increment
program FSM loop
```

真正难点不是多复制几个寄存器，而是区分：

| 只做一次 | 每个 DWord 重复 |
|---|---|
| 外层 program setup、NVSTR 起始、全局 recover | YADDR 选择、data mux、program pulse、address/program hold |

任务 98 讲 RTL 修改，任务 99 讲 TB 和波形验证，二者共同闭合这个作业。

## 深层理解：eFlash 是按粒度签合同的非易失存储

eFlash 不能按 SRAM 的直觉理解。SRAM 像白板，某个 word 想改就改；eFlash 更像一本需要按页擦除、按字编程的账本：先把一页恢复到可写初态，再在指定 DWord 上按严格时序写入。账本的每个操作都有粒度合同，擦除按 page，program 按 DWord，read 按地址读出；合同粒度错了，后面 RTL 再漂亮也会写错对象。

| 操作 | 粒度 | 关键地址 | 控制重点 | 错用后果 |
|---|---|---|---|---|
| Page erase | page | page number / XADDR 相关字段 | erase 时序、保护区拦截、done/error | 误用 YADDR，擦错页或错误建模 |
| Program | DWord | XADDR + YADDR + data | NVSTR、program pulse、hold/recover | 地址或 data 对不上，写入不可恢复 |
| Read | word/DWord 读出 | AHB memory address 或读地址 | 采样点、输出有效、状态上报 | 读到旧值或无效窗口 |

`+notimingcheck` 和 `+nospecify` 只能说明现在把显微镜调到功能层面看逻辑，它不会替你证明真实时序余量。功能仿真像看地图，timing check 像实地测路宽；地图能告诉你路通不通，但不能证明货车能不能按速度限制安全通过。

## AI+IC 连接

eFlash controller 是典型“软件寄存器 + 硬件长事务 + 状态机 + 中断”的 IP。NPU 中的 DMA、配置加载器、权重搬运模块、片上 SRAM 初始化模块也常有同样结构：软件下发配置，硬件跨很多 cycle 执行，完成后上报状态。学习 eFlash 的价值不是只会一个 flash macro，而是掌握这类控制器的通用设计口径。

## 工程练习

1. 重新推导 32K x 32 eFlash 的 page 数、row 数、X/Y 位宽。
2. 分别画出 page erase、program、read 的最小状态机。
3. 写出 CPU 做一次 page erase 需要配置的寄存器列表。
4. 解释 read 地址、program 地址、erase page number 为什么来自不同来源。
5. 给 boot 区写一个非法擦写 error 条件。

## 常见误区和失败信号

| 误区 | 正确口径 |
|---|---|
| Page erase 需要 YADDR。 | erase 按 page，不关心 row 内 DWord。 |
| Program 只要写 data。 | 还必须配置 X/Y address、timing count 和 enable。 |
| Read 和 program 地址来源一样。 | read 可来自 AHB memory address，program 来自寄存器配置。 |
| 功能仿真跑通就是 timing 没问题。 | `+notimingcheck/+nospecify` 下只验证逻辑功能。 |
| Boot protect 靠软件别乱写。 | RTL 必须硬件拦截非法擦写并上报错误。 |

## 复习与自测

1. 32K x 32 eFlash、page=512B 时共有多少 page？  
   答案：32K x 32 bit = 128KB；128KB / 512B = 256 page。

2. Page erase 为什么不需要 `YADDR`？  
   答案：erase 的最小粒度是 page，一页内所有 row 和 DWord 都会被擦除。

3. Program 为什么需要 NVSTR，而 read 不需要？  
   答案：program 改变非易失存储内容，需要启动内部编程过程；read 只是输出存储数据，不改变内容。

4. `+notimingcheck` 的作用是什么？  
   答案：关闭时序检查，让当前仿真主要验证逻辑功能，而不是 setup/hold 或门级延时。

5. 软件如何知道一次 erase/program 完成？  
   答案：硬件完成后更新 done/error/status 并触发 interrupt，CPU 读取状态寄存器判断结果。

## 工程核对口径

做 eFlash controller 设计评审时，先问四个粒度问题：

1. 当前命令按 page、row 还是 DWord 生效？
2. XADDR/YADDR/page number 分别由哪个寄存器或 AHB 地址字段提供？
3. read、program、erase 的 done/error/interrupt 是否都能被软件读到并清除？
4. boot protect、越界地址、非法 number 这类硬件禁区是否由 RTL 拦截，而不是只靠软件自觉？

如果这四问答不清，后续连续 program 很容易变成“看似在循环写，实际在循环踩雷”。eFlash 的控制器设计，第一原则是先把存储粒度和软件可见状态对齐，再谈优化吞吐。


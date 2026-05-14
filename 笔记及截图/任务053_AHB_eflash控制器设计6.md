# 任务53：AHB eFlash控制器设计6

## 本章知识全景图

这一讲把规格推进到架构和微架构：一个 IP 不能先写 RTL 再补文档，而要先明确功能、模块划分、接口、状态机、寄存器和集成边界，再进入代码。eFlash controller 的核心结构是两层：AHB slave interface 管寄存器和总线，flash control 管 eFlash 存储体时序；两者之间通过命令、地址、数据、timing、busy/done 信号连接。

| 层级 | 核心概念 | 本章要形成的判断 | 连接到前端交付 |
|---|---|---|---|
| 文档流程 | architecture、micro-architecture、integration | 先定功能和边界，review 后再写 RTL | 设计评审 |
| 模块划分 | AHB interface + flash control | 总线协议和存储体时序分开处理 | 可维护 RTL |
| 命令入口 | read、program、page erase、mass erase | CPU 配寄存器决定 FSM 走哪条路径 | command decode |
| 片选/block 选择 | flash0/flash1、main/information | 高地址位选片，block select 选区域 | 地址译码 |
| timing value | 各状态保持周期 | 状态维持多久由配置值决定 | counter |
| FSM | IDLE、read、NVS、erase、program、NVH、recover | 状态机是 eFlash 控制波形的骨架 | `flash_ctrl` |

最短学习路径：

```text
先分清 AHB interface 和 flash_ctrl
  -> 明确 CPU 如何启动 read/program/erase
  -> 看片选、block select、地址和数据怎么进入 flash_ctrl
  -> 用 timing value 驱动 counter
  -> 读 FSM：每条路径代表一种 eFlash 操作
  -> 最后把架构文档、微架构文档、集成文档区分开
```

## 全视频地图

| 时间段 | 教学块 | 必须保留的知识动作 |
|---|---|---|
| 00:00-07:00 | 设计文档与模块拆分 | 先定架构、微架构和集成边界，再写 RTL |
| 07:00-18:00 | AHB interface 与寄存器边界 | 明确 CPU 和 controller 的命令/状态边界 |
| 18:00-28:00 | 片选、block select 和信号列表 | 把两片 eFlash、main/info block 和地址译码讲清 |
| 28:00-39:00 | FSM 总览与 page erase 路径 | 把 NVS/NVH/recover 等等待段落归入状态机 |
| 39:00-44:46 | program 路径与文档交付 | 把 command 到 done 的设计闭环写成可评审材料 |

## 视觉核对清单

本讲的图像要当作一张“施工图纸”来读：模块拆分图规定墙在哪里，信号列表规定水电管线走哪里，FSM 图规定机器每一步按什么节拍动作。缺任何一张，后面写 RTL 都容易变成凭记忆拉线。

| 时间段 | 截图 | 看图要点 | 漏看后果 |
|---|---|---|---|
| 02:45 | `task53_00_module_split_02m45s.jpg` | 先分 AHB interface 与 flash control，再谈 RTL | 边界不清，debug 时无法归责 |
| 05:35 | `task53_01_ahb_regs_interrupt_05m35s.jpg` | CPU 只看寄存器、status、interrupt，不直接操纵 eFlash 脉冲 | 软件接口和硬件时序混在一起 |
| 13:30 | `task53_02_chip_select_arch_13m30s.jpg` | flash0/flash1 与 main/info block 是两层选择 | 多片存储体读写 mux 冲突 |
| 17:25 | `task53_03_signal_list_17m25s.jpg` | 每根信号都要有方向、来源和使用者 | 顶层连接时靠名字猜，位宽或语义错接 |
| 25:30 | `task53_04_fsm_overview_25m30s.jpg` | FSM 是 timing 和控制脚的节拍表 | 只会背状态名，不会解释控制脚何时变化 |
| 30:35 | `task53_05_pe_state_path_30m35s.jpg` | page erase 共用 NVS/NVH/recover 等等待段 | erase 路径漏等待，真实 IP 时序不满足 |
| 35:30 | `task53_06_program_state_path_35m30s.jpg` | program 多了 address/data setup 与 hold | 把 program 简化成一个 enable 脉冲 |
| 41:40 | `task53_07_doc_types_41m40s.jpg` | 架构、微架构、接口文档分别服务不同评审 | 文档只剩截图堆砌，无法指导 RTL/验证 |

## 1. 先写清架构，再写 RTL

IP 设计的顺序不是“先把代码敲出来”。正确顺序是先确定功能、模块划分、接口、数据格式、控制信号和验证入口，再经过 review，最后写 RTL。

![模块划分入口](<./screenshots/任务053_AHB_eflash控制器设计6/task53_00_module_split_02m45s.jpg>)

> 图注：02:45 左右。这里要看设计自然拆成两块：左侧接 AHB 和寄存器，右侧驱动 eFlash 异步接口。

三类文档的工作不同：

| 文档 | 关注点 | 读者 |
|---|---|---|
| 架构文档 | IP 做什么、模块怎么分、数据怎么流 | 架构、设计、验证 |
| 微架构文档 | 每个模块的信号、状态机、寄存器、时序细节 | RTL 设计、验证 |
| 集成文档 | top-level 端口、时钟复位、接线要求、特殊模式 | SoC 集成 |

没有微架构就写 RTL，容易把临时想法写进代码；没有集成文档，别人 instance 你的 IP 时会不知道哪些信号必须接、哪些有默认行为。

## 2. AHB interface 是 CPU 和 controller 的寄存器边界

AHB interface 接收 `HADDR/HWRITE/HWDATA/HTRANS/HSIZE/HSEL` 等信号，解析寄存器写读，输出 command、地址、数据和 timing。它还接收 `program_done/pe_done/busy/read_data`，产生状态寄存器和中断。

![AHB、寄存器和中断](<./screenshots/任务053_AHB_eflash控制器设计6/task53_01_ahb_regs_interrupt_05m35s.jpg>)

> 图注：05:35 左右。这里要看配置寄存器、状态寄存器和中断使能寄存器的关系：CPU 写配置，硬件写状态，interrupt 只负责通知 CPU 来读状态。

交互链：

```text
CPU 写 WEN/PEN/page/address/data/timing
  -> AHB interface 转成 flash_ctrl 输入
  -> flash_ctrl FSM 工作
  -> done/busy/error 回到 AHB interface
  -> 状态寄存器置位
  -> 中断使能打开时输出 interrupt
```

中断不是状态本身。中断只是一根提醒线，真正发生什么要靠 CPU 读状态寄存器。

## 3. 两片 eFlash 通过片选分流

课程里的 eFlash 有两片存储体。`flash_ctrl` 可以先生成一套控制信号，再通过片选决定送到 flash0 还是 flash1；读数据也要从两片输出中 mux 回来。

![片选和 block 选择](<./screenshots/任务053_AHB_eflash控制器设计6/task53_02_chip_select_arch_13m30s.jpg>)

> 图注：13:30 左右。这里要看 flash0/flash1 的分流：控制状态机不需要为两片各写一套逻辑，片选层负责把信号送到目标存储体。

选择维度有两层：

| 选择 | 决定什么 | 常见依据 |
|---|---|---|
| chip select | flash0 还是 flash1 | 地址最高位或 page number 高位 |
| block select | main block 还是 information block | `IFREN` 或寄存器配置 |

不要把这两个选择混成一个信号。片选决定哪颗存储体动，block select 决定这颗存储体内部访问哪块区域。

## 4. 微架构要列清每一根信号

架构图只画方向，微架构必须列出信号名、位宽、方向和作用。写 RTL 时，一个 bit 都不能靠“差不多”。

![信号列表](<./screenshots/任务053_AHB_eflash控制器设计6/task53_03_signal_list_17m25s.jpg>)

> 图注：17:25 左右。这里要看命令、block select、page number、timing value、program address/data、flash read data、busy/done 等信号。每根信号都对应 RTL 端口或内部寄存器。

需要特别区分：

| 信号类 | 例子 | 作用 |
|---|---|---|
| command | `read_en`、`program_en`、`pe_en`、`me_en` | 决定 FSM 走哪条路径 |
| address/data | `pe_number`、`flash_addr`、`flash_data_in` | 提供操作目标 |
| timing | `tnvs`、`tnvh`、`tprog`、`terase` | 决定 counter 终点 |
| status | `flash_busy`、`program_done`、`pe_done` | 回报操作进度 |
| IP pins | `XE/YE/SE/PROG/ERASE/NVSTR/XADR/YADR` | 直接驱动存储体 |

信号越多，越要靠命名和表格把语义固定住。否则后续看代码只能靠猜。

## 5. FSM 是 eFlash controller 的核心

`flash_ctrl` 的状态机从 `IDLE` 出发，根据 command 进入 read、program、page erase 或 mass erase 路径。每条路径本质上都在复刻前面 datasheet 的时序图。

![FSM 总览](<./screenshots/任务053_AHB_eflash控制器设计6/task53_04_fsm_overview_25m30s.jpg>)

> 图注：25:30 左右。这里要看从 `IDLE` 分出的多条路径：read 最短，erase/program 共享 NVS、NVH、recover 等状态。

状态机的判断：

```text
IDLE:
  read_en    -> READ_ACCESS
  pe_en      -> NVS -> PE_ERASE -> NVH -> RECOVER
  program_en -> NVS -> PGS -> PROGRAM -> PGH/ADH -> NVH -> RECOVER
  no command -> IDLE
```

只要不在 `IDLE`，通常就应认为 flash busy。busy 的意义是告诉 AHB interface 或软件：当前操作未完成，不要启动冲突命令。

## 6. page erase 路径共享 NVS/NVH/recover

page erase 进入 `NVS` 后，等待 setup 时间，再进入 erase busy 状态。erase 完成后进入 `NVH`，最后 recover 回到 IDLE。

![PE 状态路径](<./screenshots/任务053_AHB_eflash控制器设计6/task53_05_pe_state_path_30m35s.jpg>)

> 图注：30:35 左右。这里要看 PE 路径只有 erase busy 是自己独有的；`NVS/NVH/recover` 和 program 路径共享。

这种共享状态能减少重复：

```text
NVS:   PROG 或 ERASE 先建立，等待 NVSTR 拉起前时间
NVH:   PROG 或 ERASE 落下后，NVSTR 继续保持
RECOV: 所有控制脚回到空闲，等待下一次操作
```

共享状态的条件是输出逻辑能根据当前操作类型驱动正确信号。若输出逻辑写得不清楚，共享状态反而容易混乱。

## 7. program 路径比 PE 多了 word 写入阶段

program 也走 `NVS`，但之后还要经过 `PGS`、地址/数据 setup、真正 program、hold，再进入 `NVH` 和 recover。

![program 状态路径](<./screenshots/任务053_AHB_eflash控制器设计6/task53_06_program_state_path_35m30s.jpg>)

> 图注：35:30 左右。这里要看 program 路径中 `YE` 拉起前后的几段等待。写入 word 必须同时保证地址、数据和控制脚稳定。

program 路径的关键检查：

- `flash_addr` 和 `flash_data_in` 在进入 program 前已经锁存。
- `PROG/NVSTR/YE` 的先后顺序符合 datasheet。
- `TPROG` 用 worst case counter。
- 退出后设置 `program_done`，并清掉 `program_en`。

这条路径最容易因为“多段时间都很短”而写成一坨逻辑。正确做法是把短时间也明确成状态或字段，至少在波形上能定位。

## 8. 文档最终要服务 RTL、验证和集成

课程最后区分了架构、微架构和集成文档。对初学者来说，先把文档当作“写代码前的硬约束”更容易理解。

![文档类型](<./screenshots/任务053_AHB_eflash控制器设计6/task53_07_doc_types_41m40s.jpg>)

> 图注：41:40 左右。这里要看三类文档的粒度：架构说模块和功能，微架构说端口、状态机和寄存器，集成文档说 top-level 接线。

一个可交付 IP 至少要让三类人读懂：

| 读者 | 需要什么 |
|---|---|
| RTL 设计 | 状态机、寄存器、信号位宽、时序参数 |
| 验证 | testcase、可观测状态、非法操作、完成条件 |
| SoC 集成 | top 端口、clock/reset、interrupt、DFT、memory map |

如果文档只写“支持 eFlash 读写擦”，验证无法写用例，集成无法接线，软件无法写驱动。

把文档写成可验证的形式，至少要能推出下面这种检查表：

| 文档条目 | RTL 要实现 | 验证要观察 | 软件/集成要知道 |
|---|---|---|---|
| program 命令 | `program_en` 触发 program 状态链 | 地址、数据、`PROG/NVSTR/YE` 时序 | 先写 address/data，再写 WEN |
| page erase 命令 | `pe_en` 触发 erase 状态链 | page number、`ERASE/NVSTR` 和 done | 先写 page，再写 PEN |
| read memory | `read_en` 触发 read access | `HREADYOUT` 等待和 `HRDATA` 返回 | 读 memory space 可能等待 |
| status/interrupt | done/error 置位 status，interrupt 受 enable 控制 | W1C 清除、interrupt 释放 | 读 status 判断完成类型 |

如果某个条目不能从文档推到 RTL 信号和验证观察点，说明文档还停在口号层。

## 9. 最小闭环：从 command 到 done

以 program 为例：

```text
CPU 写 program address/data。
CPU 写 WEN=1。
AHB interface 输出 program_en、flash_addr、flash_data_in。
flash_ctrl 从 IDLE 进入 program 状态链。
counter 逐段计满。
flash_ctrl 输出 program_done。
AHB interface 设置 status bit。
中断使能打开时 interrupt=1。
CPU 读 status 并写 1 清除。
```

这条链就是 architecture 到 RTL 的主干。每一段都能在波形里找到对应信号，才算真正理解。

四个视角同时看会更稳：

| 阶段 | 软件动作 | AHB interface | flash_ctrl | 可观察结果 |
|---|---|---|---|---|
| 配置 | 写 program address/data | 锁存 address/data 寄存器 | 仍在 IDLE | 寄存器读回正确 |
| 启动 | 写 `WEN=1` | 输出 `program_en` 和参数 | 从 IDLE 跳入 program 路径 | `flash_busy=1` |
| 执行 | 轮询或等待中断 | command 位等待硬件清除 | counter 逐段驱动 eFlash 控制脚 | `PROG/NVSTR/YE` 波形满足 timing |
| 完成 | 读 status | 置 `program_done`，必要时 interrupt=1 | 回到 IDLE | 软件能读到完成事件 |
| 清除 | 写 1 清 status | 清除对应 status bit | 等待下一命令 | status 回 0，interrupt 释放 |

这张表也是验证用例的雏形：每一行都能变成一个断言或波形检查点。

## 本讲在 50-54 链条中的位置

任务53 把任务52 的规格拆成微架构。它回答“这些寄存器字段、timing value、片选和 command 到底由谁保存、由谁消费、由谁回报状态”。这一步做好，任务54 读 `flash_ahb_slave_if.v` 时就不会陷在端口列表里迷路。

| 本讲输入 | 本讲输出 | 后续使用 |
|---|---|---|
| 寄存器和 timing 规格 | AHB interface 与 flash_ctrl 的模块边界 | 任务54 的文件职责判断 |
| 两片 eFlash 与 block select | chip select、main/info select、地址译码 | 后续片选和地址路径 debug |
| command/status 语义 | FSM 路径、busy/done、interrupt 回传 | 后续波形断言和 testcase |

验收口径：读者必须能把 `WEN/PEN/address/data/timing/busy/done/status` 分别归到 AHB interface 或 flash_ctrl，并能说清它们跨模块传递的方向。

## 工程练习

1. 给每类信号找归属。

   合格答案：`HADDR/HWRITE/HTRANS/HWDATA` 属于 AHB interface 输入；`program_addr/program_data/timing/page_num` 是 interface 保存后送给 `flash_ctrl` 的参数；`XE/YE/SE/NVSTR/PROG/ERASE` 属于 `flash_ctrl` 输出；`busy/done/error/read_data` 从控制或存储体返回 interface，再变成 status/interrupt/HRDATA。

2. 画一条 program 状态路径并标出“为什么不能省”。

   合格答案：`IDLE -> TNVS -> PROG_SETUP -> ADDR_SETUP -> PROG_PROC -> ADDR_HOLD -> PROG_HOLD -> TNVH -> RECOVER -> IDLE`。这些状态像生产线的预热、定位、加工、保压和冷却，省掉任何一段都可能违反 eFlash datasheet 的 setup/hold/recover 要求。

3. 从文档反推验证点。

   合格答案：有 register map 就要测寄存器读写；有 chip/block select 就要测 flash0/flash1、main/info；有 FSM 路径就要测 read/program/page erase；有 status/interrupt 就要测 done、error 和 W1C 清除。

## 常见误区和失败信号

| 误区 | 正确判断 | 失败信号 |
|---|---|---|
| 文档是代码写完后补的 | 文档先定义边界和约束 | RTL 和软件接口对不上 |
| AHB 和 eFlash 时序写进一个大状态机更简单 | 分模块能降低协议耦合 | debug 找不到问题归属 |
| 两片 eFlash 要写两套 FSM | FSM 可共用，片选分流 | 代码重复且易不一致 |
| status 等同 interrupt | interrupt 只是通知，status 才是信息 | CPU 不知道完成类型 |
| busy 可有可无 | busy 防止命令重入或访问冲突 | 操作重叠导致状态错乱 |

## 复习与自测

1. 为什么 eFlash controller 至少自然拆成两个模块？

   参考答案：AHB interface 处理总线和寄存器，flash_ctrl 处理 eFlash 异步时序；二者职责不同，分开更清楚。

2. chip select 和 block select 有什么区别？

   参考答案：chip select 选 flash0/flash1，block select 选 main/information block。

3. 为什么 `NVS/NVH/recover` 可以被 program 和 erase 共享？

   参考答案：两类操作都需要 `NVSTR` 前 setup、操作后 hold 和恢复时间，只是中间 busy 状态不同。

4. program_done 为什么要回到 AHB interface？

   参考答案：AHB interface 负责状态寄存器和中断，CPU 需要通过它知道 program 完成。

5. 微架构文档至少要比架构文档多说明什么？

   参考答案：信号位宽、端口方向、状态机细节、寄存器字段、计数参数和模块级接口。


# 任务38：AHB SRAM 控制器设计1

## 本章知识全景图

### 一眼看懂这讲在讲什么

- **本章主题**：从 SoC memory map 出发，定义 AHB SRAM controller 的系统位置、地址窗口、SRAM 宏组织和主功能需求。
- **核心概念**：memory-mapped slave、AHB SRAM controller、memory compiler、SRAM macro、`8K x 8`、bank、byte lane、single port、dual port、low power、PVT、DFT/BIST。
- **逻辑主线**：前端要写的不是 SRAM cell，而是 AHB 与 SRAM macro 之间的控制器；它把 AHB 地址、宽度和读写方向转换成 SRAM 片选、地址、写使能和数据。
- **最短学习路径**：先在 SoC 图上定位 SRAM 地址窗口，再理解 controller 与 memory macro 的边界，最后把 64KB、8/16/32-bit、低功耗和 BIST 需求落到后续 RTL 信号。

| 概念层级 | 核心概念 | 前置知识 | 延伸应用 |
|---|---|---|---|
| 系统位置 | AHB slave、memory map | AHB master/slave、地址译码 | SRAM 访问、default slave、边界测试 |
| IP 来源 | memory compiler、hard macro、behavior model | RTL 仿真模型 | SRAM core 集成 |
| 存储组织 | `8K x 8`、8 个 macro、64KB | byte、word、地址位宽 | bank select、byte enable |
| 端口模型 | single port / dual port | 读写端口、clock | 读写冲突、异步 FIFO |
| 设计需求 | 8/16/32-bit、单周期、低功耗 | `HSIZE/HADDR[1:0]` | byte lane、bank gating |
| 测试边界 | DFT/BIST | 制造测试、功能验证 | BIST done/fail、测试模式 |

**AHB SRAM controller 的核心身份是协议转换层：AHB 侧看地址和传输，SRAM 侧看片选、地址、写使能和数据。**

## 1. SRAM controller 先从 SoC 位置理解

SRAM controller 挂在 AHB 总线上，是一个可寻址 slave。CPU、DMA 或其他 master 只知道访问某段地址；controller 负责判断地址是否命中 SRAM，并把访问转成 SRAM core 能执行的读写。

![SoC 总线地图中的 SRAM](<./screenshots/任务038_AHB_SRAM控制器设计1/task38_00_soc_bus_map_00m03s.jpg>)

🔍 视觉核验：视频 00:03-15:00（SoC 总线图：应看到 SRAM 与 pflash、DMA、SD host、USB 等 IP 一样挂在系统地址空间里。）
- **教学职责**：这张图负责把 SRAM controller 定位成 SoC 地址空间里的一个 AHB slave，而不是孤立的 memory cell。
- **看图要点**：顺着 master、bus、slave 的连线找 SRAM，确认 CPU/DMA 访问 SRAM 时走的是地址译码和总线传输。
- **看不懂会漏什么**：后面所有 `HSEL/HADDR/HREADY` 讨论都会失去系统位置，容易把 controller 误解成“主动读写 SRAM 的 master”。

可以把 memory map 理解成 SoC 的门牌系统：`0x0040_0000` 不是“数据本身”，而是 SRAM 这栋楼的门牌号。AHB decoder 像门禁，先判断这张访问单该送到哪栋楼；SRAM controller 像楼内管理员，再把楼号内的房间号、货架号和读写动作翻译给 SRAM 宏。

课程顺带区分了几类 IP：

| 类型 | 交付形态 | 前端关注点 |
|---|---|---|
| 自研数字 IP | RTL | 规格、微架构、验证、综合 |
| soft IP | 可配置 RTL | 集成、配置、约束、验证 |
| hard/analog IP | 硬宏或版图 | 行为模型、接口时序、电源/测试脚 |
| memory compiler IP | 按容量/宽度生成 SRAM/ROM 宏 | 宏模型接入、控制器验证 |

SRAM 通常由 memory compiler 生成，真实芯片里是硬宏；前端仿真时使用行为模型。你要设计的是 controller，不是从晶体管级别设计 SRAM。

## 2. 地址窗口把“访问谁”变成硬件判断

课程给出的 SRAM 地址窗口是 `0x0040_0000` 到 `0x0040_FFFF`，大小 64KB。master 发出地址后，decoder 判断是否落在这个窗口；命中才让 SRAM controller 响应。

![SRAM 地址空间](<./screenshots/任务038_AHB_SRAM控制器设计1/task38_01_sram_address_map_15m54s.jpg>)

🔍 视觉核验：视频 15:54-18:20（memory map 表：应看到 SRAM 的 `Space Size=64K`、起始地址和结束地址。）
- **教学职责**：这张图负责把“SRAM 有 64KB”落成可比较的地址闭区间。
- **看图要点**：同时读起始地址、结束地址和 size，三者必须互相一致；64KB 表示 byte 地址范围共有 `2^16` 个位置。
- **看不懂会漏什么**：只记容量不记边界，testbench 很容易漏测 `0x0040_FFFF` 和 `0x0041_0000` 这种决定 decoder 正确性的地址。

概念判断：

```systemverilog
assign hit_sram = (haddr >= 32'h0040_0000) &&
                  (haddr <= 32'h0040_FFFF);
```

地址译码分两层：先判断“是不是 SRAM”，再把系统地址变成 SRAM 内部地址。若 base address 是 `0x0040_0000`，内部 offset 可以先写成：

```systemverilog
logic [15:0] sram_offset;

assign sram_offset = haddr[15:0];  // base 对齐到 64KB 时成立
```

如果按两个 32KB bank、每个 bank 由 4 个 `8K x 8` byte lane 组成来推导，常见切片是：

```text
sram_offset[15]    -> bank select
sram_offset[14:2]  -> 8K 深度的 word 地址
sram_offset[1:0]   -> byte lane
```

位号不是背出来的，而是由容量和访问粒度推出的：64KB 需要 16 个 byte offset 位；32-bit word 低 2 位只负责选 byte lane；`8K = 2^13`，所以 macro 深度地址需要 13 位。

边界测试至少覆盖：

```text
0x0040_0000  -> 起始地址命中
0x0040_FFFC  -> 最后一个 32-bit 对齐 word
0x0040_FFFF  -> 最后一个 byte
0x003F_FFFF  -> 前一地址，不应命中
0x0041_0000  -> 后一地址，不应命中
```

memory map、decoder 和 testbench 必须一致。否则 CPU 读写同一个地址时，可能选中错误 IP；这类 bug 表面像“读回值不对”，根因其实是地址契约错了。

## 3. controller 是 AHB 与 SRAM core 的翻译层

AHB 侧有 `HSEL/HADDR/HTRANS/HWRITE/HSIZE/HWDATA/HREADYIN`；SRAM core 侧通常只有片选、写使能、地址、写数据、读数据和时钟。两边不是同一种协议，不能简单改名直连。

![SRAM 作为 AHB slave](<./screenshots/任务038_AHB_SRAM控制器设计1/task38_02_sram_as_ahb_slave_18m31s.jpg>)

🔍 视觉核验：视频 18:31-20:30（接口转换图：应看到左侧 AHB slave 信号、右侧 SRAM core 端口。）
- **教学职责**：这张图负责说明 controller 不是信号改名器，而是协议语义和 SRAM 宏端口之间的翻译层。
- **看图要点**：左侧找 `HSEL/HADDR/HTRANS/HWRITE/HSIZE/HWDATA`，右侧找 `csn/wen/addr/wdata/q`，两侧缺口就是 controller 要补的逻辑。
- **看不懂会漏什么**：会把 `HWRITE` 直接接 `WEN`、把 `HADDR` 直接接宏地址，忽略有效传输、低有效控制、byte lane 和地址/数据阶段错拍。

controller 的四个基本动作：

```text
地址命中：判断 HADDR 是否在 SRAM 窗口
方向判断：用 HWRITE 决定读或写
宽度选择：用 HSIZE 和地址低位生成 byte lane
时序对齐：让 AHB 地址/数据阶段匹配 SRAM 宏读写要求
```

SRAM 宏不知道 `HTRANS/HRESP/HREADY`，它只知道当前是否被选中、地址是多少、是否写入、写哪几个 byte。controller 的职责正是把总线语义变成宏端口语义。

寄存器读写和 SRAM 读写也要分清。memory-mapped register 的地址通常选中一个控制/状态寄存器，写入可能触发 side effect，例如清中断、启动 BIST、切换低功耗模式；SRAM 地址选中的是存储单元，正常读写的主要效果是数据内容变化。二者都能挂在 AHB 地址空间里，但 RTL 处理方式不同：

| 访问对象 | 地址含义 | 写入效果 | 读出效果 | 失败信号 |
|---|---|---|---|---|
| 控制寄存器 | 选择某个寄存器字段 | 可能改变模式或触发动作 | 返回状态或配置值 | 非法字段、只读字段写入、保留地址 |
| SRAM memory | 选择存储位置和 byte lane | 改变指定 byte/word 内容 | 返回对应地址的数据 | 越界、未对齐、时序未满足、读到 X |

最小 AHB 响应策略也要写清。简单 SRAM controller 常把合法访问做成 `HREADYOUT=1`、`HRESP=OKAY`，表示不插入等待且访问成功；一旦设计要拒绝未对齐访问、越界访问或不支持的 `HSIZE`，就必须在规格中声明 `HRESP=ERROR` 的条件，并让 testbench 检查它。`HREADYOUT` 解决“什么时候完成”，`HRESP` 解决“这次完成是成功还是错误”，二者不是同一个信号。

一个足够清晰的控制时序可以先抽象成四个状态：

```text
IDLE          : 没有被 AHB 选中，SRAM 片选关闭
ACCEPT        : HSEL && HREADYIN && HTRANS[1] 成立，锁存地址/方向/宽度
WRITE_DATA    : 写事务的数据阶段到来，用上一拍地址/control 写 SRAM
READ_RETURN   : 读事务返回 HRDATA；若 SRAM 数据未稳定，则进入 WAIT
```

这不是要求本章马上写完整状态机，而是提醒：AHB 地址阶段、写数据阶段、SRAM 访问阶段不能混成一个“组合大块”。一旦阶段切分错，最典型失败信号就是写到错误地址、读到旧值、`HREADYOUT` 卡住或 `HRDATA` 长时间为 X。

## 4. single port 与 dual port 看的是“端口组数”

port 是一组地址、读写控制、数据和时钟。single port SRAM 同一时刻只有一组访问；dual port SRAM 有两组端口，可能允许并行访问，甚至两个端口属于不同 clock。

![single port 与 dual port](<./screenshots/任务038_AHB_SRAM控制器设计1/task38_03_single_dual_port_20m47s.jpg>)

🔍 视觉核验：视频 20:47-24:00（single/dual port 图：应看到 single port 一组端口，dual port 两组端口。）
- **教学职责**：这张图负责把“端口”解释成一整组访问通道，而不是一根信号线。
- **看图要点**：single port 只有一组地址/控制/数据；dual port 有两组端口，才可能讨论两个访问同时发生。
- **看不懂会漏什么**：后续遇到读写冲突、双时钟 FIFO 或多 master buffer 时，会分不清冲突来自总线仲裁还是 SRAM 端口资源不足。

本章先按 single port 理解：

```text
AHB 一次有效访问
  -> controller 判断读或写
  -> SRAM core 在唯一端口执行一次操作
  -> 读数据返回 AHB HRDATA
```

如果换成 dual port，问题会立刻变多：两个端口同时写同一地址怎么办？两个 clock 是否异步？读写冲突返回旧值还是新值？这些问题后续会连接到 FIFO、CDC 和多端口 memory 设计。

## 5. 规格要落成可验证 feature

“能读写 SRAM”不是规格。课程里的 SRAM controller 需求至少包含 64KB 地址空间、AHB slave、8/16/32-bit 访问、单周期读写、低功耗和 DFT/BIST。

![SRAM 需求](<./screenshots/任务038_AHB_SRAM控制器设计1/task38_04_sram_requirements_34m00s.png>)

🔍 视觉核验：视频 34:00-36:40（SRAM controller 需求页：应看到支持 8/16/32-bit、单周期读写、低功耗、DFT/BIST 等需求；右侧手写标注把 `8K x 8bit`、bank 和 64KB 关系连起来。）
- **教学职责**：这张图负责把需求从口号拆成 RTL 必须支持的 feature。
- **看图要点**：逐项把需求翻译成信号或验证点，例如 8/16/32-bit 对应 `HSIZE + HADDR[1:0]`，单周期对应 `HREADYOUT` 策略。
- **看不懂会漏什么**：会把“需求页”当背景材料，结果代码只实现 32-bit 读写，漏掉 byte/halfword、低功耗和测试入口。

| 需求 | 硬件含义 | 验证要看什么 |
|---|---|---|
| 64KB 地址空间 | SRAM 占用 `0x0040_0000-0x0040_FFFF` | 起止地址和越界地址 |
| AHB slave | 被 master 访问，本身不主动发事务 | `HSEL/HTRANS/HREADYIN` 有效条件 |
| 8/16/32-bit 访问 | `HSIZE` 和 `HADDR[1:0]` 决定 byte lane | byte/halfword/word 写读回 |
| 单周期读写 | 理想情况下不插入 wait state | back-to-back 访问 |
| 低功耗 | 只打开被访问 bank 或 standby | 未选 bank 片选关闭 |
| DFT/BIST | 生产测试入口 | `bist_done/bist_fail` 语义 |

“单周期”对后续任务很关键：AHB 写地址和数据错一拍，SRAM 写又希望地址和数据同拍；读路径还要在下一数据阶段给出 `HRDATA`。任务39会把这个时序难点展开。

这页还有一个容易被忽略的约束：需求不是只写“支持低功耗”，而是把低功耗落到可实现动作。8-bit/16-bit 访问可以只打开部分 byte lane；不同地址落到不同 bank 时，只打开命中的 bank，未命中的 bank 进入 deselected 或 standby。后续 RTL 如果每次访问都打开所有 SRAM 宏，即使功能读写正确，也没有满足这个低功耗需求。

## 6. 8 个 `8K x 8` 宏拼出 64KB

`8K x 8` 中第一个 8K 是深度，表示 8192 个地址；第二个 8 是宽度，表示每个地址 8 bit。一个宏容量是 8KB，8 个宏合起来是 64KB。

![bank 低功耗组织](<./screenshots/任务038_AHB_SRAM控制器设计1/task38_05_bank_low_power_34m38s.jpg>)

🔍 视觉核验：视频 34:38-36:40（需求页手写标注：应看到 `8K x 8bit`、64KB 与多块 SRAM 的关系，讲解把低功耗需求落到 bank/byte lane 选择。）
- **教学职责**：这张图负责把宏容量、bank 数量和低功耗片选连成一条推导链。
- **看图要点**：先算一个宏是 8KB，再看几个宏拼成一个 32-bit bank，最后看地址高位如何只打开命中的 bank。
- **看不懂会漏什么**：会以为低功耗是后端或电源域问题，忽略 controller 中最直接的节能动作：未命中 bank 不选中、未写 byte lane 不翻转。

容量计算：

```text
单个 macro:
8K x 8 bit = 8192 byte = 8KB

8 个 macro:
8 x 8KB = 64KB
```

32-bit 访问需要 4 个 8-bit 宏同时工作，因为 32 bit = 4 byte：

```text
bank0: byte0 + byte1 + byte2 + byte3 -> 32-bit data
bank1: byte0 + byte1 + byte2 + byte3 -> 32-bit data
```

高位地址选择 bank，低位地址选择 bank 内部位置和 byte lane。一次访问只打开命中的 bank 和需要的 byte lane，其他 SRAM 宏保持未选中；这才是“低功耗工作”在 controller RTL 里的具体含义。

设计时可以先把 64KB 拆成一个可检查的地址模型：

```text
64KB SRAM window = 2^16 byte
32-bit AHB data  = 4 byte lane
8K x 8 macro     = 2^13 byte

若每个 bank 用 4 个 8K x 8 macro 拼成 32-bit 宽度：
  1 个 bank 容量 = 8K x 32 bit = 32KB
  2 个 bank 容量 = 64KB
  bank 选择      = SRAM offset 的高位
  macro 地址     = bank 内部的 13-bit 深度地址
  byte lane      = HSIZE + HADDR[1:0]
```

这里的位号要从系统 offset 推导，不能死背某一张图。先把 `HADDR - 0x0040_0000` 变成 SRAM 内部 offset，再决定哪几位选 bank、哪几位进 macro address、哪几位生成 byte lane。

## 7. 低功耗首先是片选策略

低功耗不是在 RTL 里写一句 `low_power_en`。本章最具体的低功耗手段是 bank 切分：每次只选中被访问的 bank，未命中的 SRAM 宏不翻转或进入 standby。

bank 更多不一定更好。切成 4 个 bank 可以让每次打开的范围更小，但也会增加片选译码、互连、验证和可用宏规格压力。工程上要在功耗、面积、时序和 memory compiler 支持之间取舍。

这一点对 AI 芯片尤其重要：NPU 的 SRAM/line buffer/weight buffer 占大量面积和功耗，真正的节能常常来自“少打开、少翻转、少搬运”，不是事后加一个开关。

## 8. PVT 和 standby 说明速度、功耗、温度互相牵制

PVT 是 process、voltage、temperature。课程里 fast/typical/slow corner 和 standby 电流的表，不要求你背数值，但要建立边界感：功能仿真通过不等于真实芯片在所有角落都能跑。

![PVT 与功耗表](<./screenshots/任务038_AHB_SRAM控制器设计1/task38_06_pvt_power_table_37m18s.jpg>)

🔍 视觉核验：视频 37:18-40:00（PVT/功耗表：应看到 fast/typical/slow 与 standby 电流等规格。）
- **教学职责**：这张图负责提醒 controller 不是只在理想仿真模型里工作，真实 SRAM 宏有速度、温度、电压和功耗边界。
- **看图要点**：把 fast/typical/slow 看成同一电路在不同制造和环境条件下的三种速度/功耗约束。
- **看不懂会漏什么**：会误以为 RTL 功能仿真通过就等于芯片可用，忽略 slow corner 下读数据可能赶不上单周期返回。

基本判断：

```text
fast corner：晶体管快，功耗/泄漏可能更高
slow corner：晶体管慢，时序更紧
standby：不访问时关闭部分活动，电流远低于读写状态
```

RTL 仿真验证逻辑正确，综合和 STA 证明时序可达，功耗分析证明系统能耗可接受。学习 SRAM controller 时要把这些交付阶段分清。

## 9. DFT/BIST 是生产测试路径

DFT 和 BIST 服务的是芯片制造后的测试筛选，不是 CPU 正常读写 SRAM 的替代路径。它们用于发现 stuck-at、短路、断路、存储单元异常等制造缺陷。

![DFT/BIST 入口](<./screenshots/任务038_AHB_SRAM控制器设计1/task38_07_dft_bist_40m28s.jpg>)

🔍 视觉核验：视频 40:28-41:10（DFT/BIST 入口页：应看到测试信号与正常 AHB 读写路径并列存在。）
- **教学职责**：这张图负责把生产测试路径和正常 AHB 功能路径分开。
- **看图要点**：观察 BIST/DFT 信号通常从侧边进入 SRAM 或 controller，它们不是普通软件读写数据的替代接口。
- **看不懂会漏什么**：容易在 RTL 中让测试模式和正常读写同时驱动 SRAM 控制线，造成多源控制、X 传播或测试模式无法退出。

最小语义：

```text
bist_en    -> 启动内建自测试
bist_done  -> BIST 流程结束
bist_fail  -> 发现存储体或测试路径异常
dft_en     -> 进入测试模式
```

先把正常读写路径做清楚，再接 BIST/DFT，是正确顺序。否则测试路径、正常路径、低功耗路径混在一起，初学阶段很容易把主线打散。

## 最小闭环：AHB 地址到 SRAM 宏

```text
AHB master 发起访问
  -> HADDR 命中 0x0040_0000-0x0040_FFFF
  -> decoder 拉高 SRAM HSEL
  -> controller 判断 HTRANS/HREADYIN/HWRITE/HSIZE
  -> 地址高位选择 bank，低位选择 byte lane
  -> 写：HWDATA 对齐后进入对应 byte 宏
  -> 读：SRAM q0-q7 拼成 HRDATA 返回
```

## 可复现检查：手算一笔地址到宏端口

用一笔 32-bit 写事务检查本章机制是否真的会用：

```text
输入：
  HADDR  = 0x0040_8004
  HWRITE = 1
  HSIZE  = word
  HWDATA = 0xA5A5_5A5A

推导：
  sram_offset = 0x8004
  bank_sel    = sram_offset[15] = 1，选择 bank1
  macro_addr  = sram_offset[14:2] = 13'h0001
  byte_lane   = word，所以 4 个 lane 全选

期望：
  bank1_csn = 4'b0000
  bank0_csn = 4'b1111
  sram_w_en = 写有效
  sram_wdata = 0xA5A5_5A5A
  HRESP = OKAY
```

再用一笔 byte 写检查 lane：

```text
HADDR = 0x0040_0003, HSIZE = byte
期望只选 byte3；如果 4 个 lane 都写，说明 byte enable 逻辑不合格。
```

这类手算不是形式题，而是 debug 波形时的判定口径。波形上 bank、macro address、lane、write enable、`HREADYOUT/HRESP` 任一项和手算不一致，都说明地址译码或协议阶段切分有问题。

## 常见误区和失败信号

- 把 SRAM controller 当成 SRAM 本体；前端主要写协议转换和控制逻辑。
- 把 `8K x 8` 算成 8K bit，导致容量和地址位宽全错。
- 只测 32-bit，不测 byte/halfword，byte lane bug 会漏掉。
- 不做地址边界测试，`0x0040_FFFF` 和 `0x0041_0000` 可能误判。
- 把低功耗理解成口号，实际没有做 bank select 或 standby。
- 把 BIST 当正常功能路径，导致测试模式和普通读写控制混乱。

## 和 AI+IC / NPU 学习的连接

NPU 的本地 SRAM、weight buffer、activation buffer 都会遇到类似问题：地址窗口、bank 组织、byte/word lane、低功耗、测试模式、读写延迟。学这个 controller，是在建立“存储资源如何被总线访问、如何被 RTL 控制”的底层能力。

最小练习：给一个 16KB buffer 设计 memory map，假设由 4 个 `4K x 8` 宏组成，写出 bank/byte lane 的选择思路。

## 复习与自测

1. **判断题**：AHB SRAM controller 是 master，因为它控制 SRAM 宏。  
   **答案**：错。它在 AHB 侧是 slave，被 CPU/DMA 等 master 访问；它只是在 SRAM 侧驱动宏端口。

2. **计算题**：一个 `8K x 8` 宏多大？8 个合起来多大？  
   **答案**：一个宏是 8192 byte = 8KB；8 个合起来 64KB。

3. **解释题**：为什么一次 32-bit 访问通常需要 4 个 8-bit 宏同时工作？  
   **答案要点**：32 bit 等于 4 byte，每个 `8K x 8` 宏提供一个 byte lane，四个宏拼成一个 32-bit word。

4. **工程题**：DFT/BIST 和正常 AHB 读写有什么区别？  
   **答案要点**：正常路径服务软件/总线功能访问；DFT/BIST 服务生产测试，用专门模式检测制造缺陷，不能替代普通读写。

5. **推导题**：`HADDR=0x0040_8004`、32-bit 写访问时，若采用两个 32KB bank，应该选哪个 bank？宏内部地址是多少？  
   **答案**：`sram_offset=0x8004`，`sram_offset[15]=1`，选 bank1；`sram_offset[14:2]=13'h0001`，word lane 全选。

6. **判断题**：如果 SRAM controller 对所有访问都固定 `HREADYOUT=1`、`HRESP=OKAY`，就不需要考虑未对齐访问或不支持的 `HSIZE`。  
   **答案**：错。固定 OKAY 只在规格保证访问全合法、读数据能单周期稳定时成立；否则必须声明错误处理或 wait state 策略，并在 TB 中检查。



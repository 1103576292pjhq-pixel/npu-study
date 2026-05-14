# 任务54：AHB eFlash控制器设计8

## 本章知识全景图

这一讲开始正式读 `flash_ahb_slave_if.v`。它不是 eFlash 存储体控制状态机，而是 AHB slave interface：接收 AHB 输入、解析寄存器空间和 memory 空间、产生 command/timing/address/data 给 `flash_ctrl`，同时把 `flash_ctrl` 的读数据、busy、done 和 ready 信息转回 AHB 输出。

| 层级 | 核心概念 | 本章要形成的判断 | 连接到前端交付 |
|---|---|---|---|
| 工程目录 | `model/rtl/tb/sim` | 先知道模型、设计、TB、仿真入口分别在哪 | 项目导航 |
| 模块风格 | 一个 `.v` 一个 module、端口先列再声明 | 文件名和 module 名一致，便于查找和编译 | coding style |
| AHB 输入 | `HSEL/HREADYIN/HWRITE/HSIZE/HBURST/HTRANS/HADDR/HWDATA` | slave 只有在被选中且总线 ready 时才接收访问 | AHB 协议 |
| flash 返回 | read data、program done、PE done、busy、ready flag | interface 要把 `flash_ctrl` 状态转成寄存器和 AHB ready | 状态回传 |
| 输出命令 | WEN/PEN/timing/page/address/data/select | CPU 写寄存器后输出给 `flash_ctrl` | 命令寄存器 |
| 地址处理 | register select、flash address、boot offset | 读 memory 和写寄存器的地址路径不同 | 地址译码 |
| 信号声明 | `reg/wire`、过程赋值、连续赋值 | 是否成为寄存器要看赋值位置，不只看声明关键字 | RTL 阅读 |

最短学习路径：

```text
先定位工程目录和 RTL 文件
  -> 读 module 端口
  -> 区分 AHB 输入、flash_ctrl 输入、AHB 输出、flash_ctrl 输出
  -> 看 HREADYIN/HSEL 如何保护访问有效性
  -> 看 timing 和 command 寄存器如何输出
  -> 看 flash address 如何从 HADDR 或 program address 得到
```

## 全视频地图

| 时间段 | 教学块 | 必须保留的知识动作 |
|---|---|---|
| 00:00-08:00 | 工程目录与 module header | 定位 model/rtl/tb/sim，确认当前读的是 AHB slave interface |
| 08:00-16:00 | AHB 输入信号与访问有效性 | 用 HSEL/HREADYIN/HTRANS 判断 slave 是否接收访问 |
| 16:00-25:00 | flash_ctrl 返回与软件置位输出 | 把 busy/done/ready 转成 AHB 输出和寄存器状态 |
| 25:00-36:00 | timing 寄存器与 reg/wire 阅读 | 按赋值位置判断寄存器和组合线网 |
| 36:00-52:04 | HREADYOUT 与 flash_address 路径 | 读一次 eFlash memory space 的完整数据返回链 |

## 视觉核对清单

本讲的截图像一次从 AHB 柜台进入 eFlash 后场的实地走访：先看门牌和入口条件，再看柜台如何登记命令，最后看后场完成后怎样把数据和 ready 信号递回总线。读图重点是“哪一拍采样、哪一层保存、哪一路返回”。

| 时间段 | 截图 | 看图要点 | 漏看后果 |
|---|---|---|---|
| 00:55 | `task54_00_project_dirs_00m55s.jpg` | 从工程目录定位当前读的是 `flash_ahb_slave_if` | 误把 top、model、slave_if 的职责混在一起 |
| 05:05 | `task54_01_module_header_05m05s.jpg` | module header 先给出端口边界 | 没看方向和位宽就进入内部逻辑 |
| 08:35 | `task54_02_hselect_hreadyin_08m35s.jpg` | `HSEL && HREADYIN && HTRANS` 才构成有效访问 | 在总线未推进时提前锁存地址 |
| 11:30 | `task54_03_hsize_hburst_htrans_11m30s.jpg` | AHB 控制信号有协议语义，不是普通枚举值 | 把 burst 次数、size、transfer type 读错 |
| 14:00 | `task54_04_flash_status_inputs_14m00s.jpg` | `flash_ctrl` 返回 busy/done/ready/read data | AHB 层不知道何时等待或回状态 |
| 18:50 | `task54_05_sw_set_outputs_18m50s.jpg` | AHB 写寄存器产生软件置位命令 | 把 command 当成外部引脚 |
| 22:20 | `task54_06_timing_regs_22m20s.jpg` | timing 由寄存器输出给后级 FSM | 只看默认值，不看软件能否改写 |
| 30:10 | `task54_07_reg_wire_style_30m10s.jpg` | `reg/wire` 要结合赋值块判断真实硬件 | 只按声明关键字判断触发器或组合逻辑 |
| 40:25 | `task54_08_hready_hresp_40m25s.jpg` | eFlash read 用 `HREADYOUT` 等待数据返回 | read 还没完成就采样 `HRDATA` |
| 45:35 | `task54_09_flash_address_45m35s.jpg` | program 地址和 AHB read 地址来源不同 | 读写共用错误地址源 |

## 1. 工程目录决定你先看哪里

`model` 放 eFlash 行为模型，`rtl` 放设计源码，`tb` 放 testbench，`sim` 放仿真脚本和 filelist。读代码前先分清目录，否则很容易把模型、设计和验证文件混在一起。

![工程目录](<./screenshots/任务054_AHB_eflash控制器设计8/task54_00_project_dirs_00m55s.jpg>)

> 图注：00:55 左右。这里要看各目录职责：`model` 是第三方模型，`rtl` 是本次设计，`tb` 是验证环境，`sim` 是运行入口。

当前讲解对象是 `flash_ahb_slave_if.v`。从名字就能判断：它是 eFlash controller 的 AHB slave 接口层，不是直接驱动 eFlash 存储体的底层 FSM。

## 2. module 名最好和文件名一致

课程先强调 Verilog 文件风格：一个 `.v` 文件最好只放一个 module，module 名和文件名一致。语法允许一个文件放多个 module，但工程上不好查找、也容易让编译脚本和层级阅读变复杂。

![module 头部](<./screenshots/任务054_AHB_eflash控制器设计8/task54_01_module_header_05m05s.jpg>)

> 图注：05:05 左右。这里要看 module 名、端口列表和后续 input/output 声明。端口先集中列出，再按方向和类型声明，阅读更稳定。

这个风格和任务46 的 coding style 对上了：结构清楚的 RTL 让后续 review 更容易，也让自动脚本更容易按文件名找到 module。

## 3. `HSEL` 和 `HREADYIN` 共同决定本 slave 是否接收访问

`HSEL` 表示地址 decoder 选中了这个 slave；`HREADYIN` 表示总线当前数据阶段可以推进。即使 `HSEL=1`，如果别的 slave 还在拉低 ready，当前访问也不能随意采样推进。

![HSEL 与 HREADYIN](<./screenshots/任务054_AHB_eflash控制器设计8/task54_02_hselect_hreadyin_08m35s.jpg>)

> 图注：08:35 左右。这里要看 `HREADYIN` 的意义：它不是当前模块自己的输出，而是总线层面 ready 汇总后给 slave 的输入。

有效访问常需要满足：

```text
valid_access = HSEL && HREADYIN && HTRANS 有效
```

如果忽略 `HREADYIN`，这个 slave 可能在总线还没准备好时提前锁存地址或控制信号，导致和 AHB 流水阶段错位。

## 4. `HSIZE/HBURST/HTRANS` 要按协议语义读

`HSIZE` 表示一次传输的数据大小，不是 burst 长度；`HBURST` 表示 burst 类型和传输次数；`HTRANS` 表示当前传输状态，如 IDLE、BUSY、NONSEQ、SEQ。

![AHB 控制信号](<./screenshots/任务054_AHB_eflash控制器设计8/task54_03_hsize_hburst_htrans_11m30s.jpg>)

> 图注：11:30 左右。这里要看 `HSIZE/HBURST/HTRANS` 的分工。`INCR4/8/16` 的数字表示传输次数，不是 bit 数。

本控制器的约束：

| 信号 | 关键判断 |
|---|---|
| `HWRITE` | 1 为写，0 为读 |
| `HSIZE` | 当前系统主要支持 8/16/32-bit 中的有效子集，eFlash program 以 32-bit word 为核心 |
| `HBURST` | burst 信息可用于检查传输类型 |
| `HTRANS` | `NONSEQ/SEQ` 是有效传输，`IDLE/BUSY` 不应启动普通访问 |

任务52 已说明不支持 BUSY 传输类型；所以 RTL 里要避免把 BUSY 当成有效写读命令。

## 5. flash_ctrl 返回的 done/busy/ready 决定 AHB 输出

`flash_ahb_slave_if` 不直接知道 eFlash 何时读出数据或写擦完成，它依赖 `flash_ctrl` 返回的 read data、program done、PE done、busy、ready flag。

![flash_ctrl 返回信号](<./screenshots/任务054_AHB_eflash控制器设计8/task54_04_flash_status_inputs_14m00s.jpg>)

> 图注：14:00 左右。这里要看从 `flash_ctrl` 回来的信号：读数据、program done、PE done、busy 和 read ready flag 都要进入 AHB interface。

这些返回信号的用途：

| 信号 | 用途 |
|---|---|
| `flash_read_data` | 最终送到 AHB `HRDATA` |
| `program_done` | 置 program status，可能触发中断 |
| `pe_done` | 置 page erase status，可能触发中断 |
| `flash_busy` | 阻止新命令或读写冲突 |
| `hready_flag` | read 数据可返回时拉高 `HREADYOUT` |

读路径和写擦路径不同：read 会占住 AHB 数据阶段等待数据；program/erase 多半只是写 command 寄存器，内部慢慢执行。

## 6. 软件置位信号由 AHB 写寄存器产生

`WEN/PEN` 等输出给 `flash_ctrl` 的命令信号，是 CPU 通过 AHB 写寄存器得到的。它们不是 AHB 原生信号，而是寄存器解析后的控制结果。

![软件置位输出](<./screenshots/任务054_AHB_eflash控制器设计8/task54_05_sw_set_outputs_18m50s.jpg>)

> 图注：18:50 左右。这里要看 `program_en`、`pe_en` 等信号是给 `flash_ctrl` 的启动命令。一次同一时刻只能有一种命令有效。

命令位要防止两个问题：

- 同时启动多个互斥操作，例如 program 和 page erase 同时为 1。
- flash busy 时又启动新操作，造成状态机重入。

因此 command decode 通常要结合 `flash_busy`、地址合法性、boot 保护等条件。

## 7. timing 寄存器从 AHB 写入，再输出给 flash_ctrl

`TNVS/TNVH/TREC/TPGS/TPROG/TACC/TERASE` 等 timing 值是寄存器值。AHB interface 负责接收写入并保持，`flash_ctrl` 只拿这些值作为 counter 目标。

![timing 输出](<./screenshots/任务054_AHB_eflash控制器设计8/task54_06_timing_regs_22m20s.jpg>)

> 图注：22:20 左右。这里要看每个 timing 值对应 eFlash 时序的一段等待。它们作为 output 传给 `flash_ctrl`。

这种设计的好处是职责清楚：

```text
AHB interface:
  负责寄存器默认值、写入、读回。

flash_ctrl:
  不关心 CPU 怎么配置，只按 timing value 计数。
```

若后续要换 eFlash IP，软件或 reset 默认值更新 timing 即可，FSM 结构不必大改。

## 8. `reg/wire` 要结合赋值位置读，不能只按名字判断硬件

课程中解释了 `reg` 和 `wire`。对初学者来说，最稳的读法不是看到 `reg` 就断定“这里一定是触发器”，而是继续看它在哪里赋值：时序 always 块中跨时钟保存的变量会综合成寄存器；组合 always 块或连续赋值里的结果更接近组合逻辑或连线。现代 SystemVerilog 可以用 `logic` 统一很多声明，但硬件结构仍然要从赋值位置和时钟边界判断。

![reg/wire 风格](<./screenshots/任务054_AHB_eflash控制器设计8/task54_07_reg_wire_style_30m10s.jpg>)

> 图注：30:10 左右。这里要看内部信号先按 `reg`、`wire` 分类声明，并配注释说明作用。这是可读 RTL 的基本功。

判断口径：

```text
时序 always 中在时钟沿更新并保持的值 -> 触发器/寄存器
组合 always 或 assign 推导出的值       -> 组合逻辑/连线
同一个信号被多个过程赋值               -> 多驱动风险
```

不要因为变量名叫 `*_r` 就自动认为它一定是寄存器，要看它在哪里赋值；但好的命名会让这种判断更快。

## 9. `HREADYOUT` 由 flash read ready 决定

代码里 `HREADYOUT` 直接跟随来自 `flash_ctrl` 的 ready flag。读 eFlash 时，只有 `flash_ctrl` 确认数据已经可用，AHB slave 才能让 master 完成本次读。

![HREADY/HRESP](<./screenshots/任务054_AHB_eflash控制器设计8/task54_08_hready_hresp_40m25s.jpg>)

> 图注：40:25 左右。这里要看 `HREADYOUT` 和 `HRESP`：当前设计通常返回 OKAY，read 是否完成主要看 ready flag。

`HRESP` 一直 OKAY 的含义是：只要访问落在设计支持范围内，本模块不使用 ERROR/RETRY/SPLIT 报告。错误类信息更多通过内部 status/error 寄存器让软件读取。这种设计简单，但也意味着非法寄存器访问或 boot 保护错误不一定表现为 AHB `ERROR`。

## 10. `flash_address` 可能来自 program 寄存器，也可能来自 AHB 读地址

`flash_address` 是给后级 `flash_ctrl` 的地址。program 时，它来自 program address 寄存器；boot/read 时，它来自 AHB `HADDR`，并可能叠加 boot offset。

![flash address 生成](<./screenshots/任务054_AHB_eflash控制器设计8/task54_09_flash_address_45m35s.jpg>)

> 图注：45:35 左右。这里要看不同场景的地址来源：program 走寄存器，read/boot 走 AHB 地址或 offset 处理。

地址路径：

```text
program_en:
  flash_address = program_address_reg

boot_en:
  flash_address = HADDR + boot_offset

normal read:
  flash_address = HADDR
```

AHB 写数据 `HWDATA` 不应随意打一拍，因为 AHB 写数据阶段本来比地址阶段晚一拍；若再打一拍，地址和数据可能错开。课程强调这一点，是为了让读者把代码和 AHB 两阶段流水对应起来。

## 11. 最小闭环：读一次 eFlash memory space

```text
AHB master 发读访问，HSEL=1、HWRITE=0、HTRANS=NONSEQ。
AHB interface 判断访问是 memory space，不是 register space。
生成 read_en 和 flash_address。
flash_ctrl 驱动 eFlash read。
HREADYOUT 拉低等待。
flash_ctrl 返回 hready_flag 和 flash_read_data。
AHB interface 输出 HRDATA，HREADYOUT 拉高。
```

这条链同时经过 AHB 协议判断、地址生成、后级 read FSM 和 AHB 返回，是理解本文件的主线。

## 本讲在 50-54 链条中的位置

任务54 是本批第一次把前面的规格和微架构落到具体 RTL 文件。读 `flash_ahb_slave_if.v` 时，不能把它误认为 eFlash 时序 FSM；它负责的是 AHB slave、寄存器、命令输出、状态回收和 ready/response。真正驱动 `PROG/ERASE/NVSTR/XE/YE/SE` 的细节在 `flash_ctrl`。

| 本讲输入 | 本讲输出 | 后续使用 |
|---|---|---|
| 任务53 的模块边界 | `flash_ahb_slave_if` 的端口分组 | 后续读 `flash_ctrl` 不混层 |
| AHB 访问规则 | `HSEL/HREADYIN/HTRANS/HWRITE` 的有效访问判断 | AHB testcase 和协议断言 |
| command/status 寄存器 | WEN/PEN、timing、address/data、done/busy 回传 | 后续联调软件访问和波形 |

验收口径：读者必须能从一次 AHB read 追到 `flash_address`、`read_en`、`hready_flag`、`HRDATA/HREADYOUT`，并知道哪里属于总线层，哪里属于 flash_ctrl 层。

## 工程练习

1. 写出 AHB register write 的采样路径。

   合格答案：地址阶段检查 `HSEL/HREADYIN/HTRANS/HWRITE/HADDR`，锁存或打一拍得到目标寄存器选择；数据阶段 `HWDATA` 到来时写入对应寄存器。AHB 像两节车厢，前一节送地址控制，后一节送数据，不能把两节车厢错接。

2. 写出 eFlash memory read 的等待路径。

   合格答案：有效 AHB read 命中 memory space，生成 `read_en` 和 `flash_address`；`flash_ctrl` 进入 read access，`hready_flag/HREADYOUT` 拉低；read data 返回后释放 ready，`HRDATA` mux 选择 eFlash data。

3. 检查 `HRESP=OKAY` 是否足够证明写擦成功。

   合格答案：不够。`HRESP` 只能说明 AHB 传输层没有报协议错误；program/page erase 是否成功要看 status/error/done。它像快递前台“收件成功”，不是仓库“货物加工成功”。

## 常见误区和失败信号

| 误区 | 正确判断 | 失败信号 |
|---|---|---|
| `HREADYIN` 可忽略 | 它表示总线当前是否能推进 | 地址控制提前采样 |
| `HBURST=4/8/16` 表示 bit 数 | 表示传输次数 | burst 理解错误 |
| command 是 AHB 原生信号 | command 是寄存器解析结果 | 软件写寄存器后无动作 |
| read 和 write 地址都同一路 | program 地址来自寄存器，read 多来自 AHB | 写错目标或读错 boot 地址 |
| `HRESP=OKAY` 代表无内部错误 | 内部错误可能通过 status 上报 | 软件只看 AHB response 漏错 |

## 复习与自测

1. `flash_ahb_slave_if` 和 `flash_ctrl` 的职责区别是什么？

   参考答案：前者处理 AHB、寄存器、状态和中断；后者生成 eFlash IP 控制时序。

2. 为什么 slave 要看 `HREADYIN`？

   参考答案：如果总线其他数据阶段未完成，本 slave 不能提前采样或推进新访问。

3. program 时 `flash_address` 来自哪里？

   参考答案：来自 program address 寄存器，由 CPU 先通过 AHB 写入。

4. eFlash read 时为什么要等 `hready_flag`？

   参考答案：eFlash 读数据有 access time，只有 `flash_ctrl` 确认数据可用后 AHB 才能完成读。

5. 为什么不建议随意打一拍宽数据 bus？

   参考答案：宽 bus 打拍消耗大量触发器；只有协议或时序确实需要时才应打拍。


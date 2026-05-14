# 任务58：AHB eFlash控制器设计12

## 本章知识全景图

这一讲离开单个 RTL 文件，开始看 eFlash 控制器的层级集成。`flash_ahb_slave_if.v` 和 `flash_ctrl.v` 是核心设计，但单有这两个文件不能形成完整 IP。`flash_control_top` 把 AHB interface 和 control FSM 连起来，`flash_call` 包住两片 eFlash 存储体和 DFT/write-protect 选择，`flash_c_top` 再把控制侧和存储体侧合成一个对外只暴露 AHB、系统配置和测试端口的顶层。

| 层级 | 文件或模块 | 本章要形成的判断 | 关键风险 |
|---|---|---|---|
| 控制顶层 | `flash_control_top` | 连接 `slave_if` 和 `flash_ctrl` | 端口方向和 wire 名错接 |
| 存储体封装 | `flash_call` | 包住 flash0/flash1，处理 DFT 与写保护 | test path 与功能 path 混淆 |
| IP 顶层 | `flash_c_top` | 对外主要暴露 AHB 与系统配置 | 顶层接口不该泄露内部细节 |
| AHB ready | `hready_flag/hready_out` | read 会拉低 ready，program/PE 不应长时间拖住总线 | 总线被错误阻塞 |
| busy 节流 | `flash_busy` | busy 期间写配置会被屏蔽 | 软件连续写导致丢配置 |
| DFT/保护 | `test_en`、`write_protect_n` | 测试模式直连存储体，功能模式受保护门控 | 生产测试和功能读写冲突 |

最短学习路径：

```text
先看 RTL 文件层级
  -> 再看 flash_control_top 如何连 slave_if 和 flash_ctrl
  -> 再看 hready 与 busy 的真实作用
  -> 再看 flash_call 如何处理 DFT 与 write protect
  -> 最后把 flash_c_top 理解成 AHB 到 eFlash 协议的翻译器
```

## 全视频地图

| 时间段 | 视频内容 | 这一段真正要学会什么 |
|---|---|---|
| 00:00-02:20 | RTL 文件清单与 top 结构 | 核心设计要被 top 包起来才能成为 IP |
| 02:20-07:50 | `flash_control_top` 端口与对齐阅读 | AHB、boot、DFT、read data、interrupt 都要向上冒端口 |
| 07:50-16:50 | instance 连接规则 | `.child_port(local_wire)` 左右两边含义不同 |
| 17:30-25:30 | `hready_flag` 产生和 read 等待 | read access 拉低 HREADY，避免 CPU 采到无效数据 |
| 25:30-37:50 | `flash_busy` 产生和使用 | busy 不一定拖住 AHB，但会禁止寄存器写入 |
| 40:00-42:40 | `flash_call`、DFT、write protect mux | 功能路径和生产测试路径共用存储体端口 |
| 42:40-45:10 | `flash_c_top` 封装 | 顶层把 AHB 信号翻译成 eFlash 存储体信号 |

## 视觉核对清单

| 视频时间段 | 截图 | 核对点 |
|---|---|---|
| 00:30-00:50 | `task58_00_rtl_file_topology_00m40s.jpg` | RTL 文件层级：control top、flash call、IP top |
| 02:20-02:40 | `task58_01_control_top_ports_02m30s.jpg` | AHB、boot、DFT、read data、interrupt 端口 |
| 08:00-08:20 | `task58_02_slave_if_instance_08m10s.jpg` | `.child_port(local_wire)` 的连接写法 |
| 15:10-15:30 | `task58_03_read_data_path_15m20s.jpg` | flash0/flash1 read data 回到控制侧 |
| 20:40-21:00 | `task58_04_hready_flag_read_wait_20m50s.jpg` | read access 期间 `hready_flag` 拉低 |
| 27:40-28:00 | `task58_05_busy_blocks_writes_27m50s.jpg` | `flash_busy` 屏蔽寄存器写入 |
| 41:30-41:55 | `task58_06_dft_write_protect_mux_41m40s.jpg` | DFT 路径与 write protect 门控 |
| 43:20-43:40 | `task58_07_flash_c_top_wrapper_43m30s.jpg` | `flash_c_top` 同时包住 control top 与 flash call |

这组图的价值在于把“模块代码”还原成“系统装配”。`flash_control_top` 是翻译层，`flash_call` 是存储体封装，DFT/write protect 是穿过正常功能路径的特殊门控。集成图像像装配图：每一根线都要回答“从谁来、到谁去、功能模式和测试模式下是否同路”。

## 1. RTL 集成要解决“谁包谁、谁连谁”

核心 RTL 只有 `flash_ahb_slave_if.v` 和 `flash_ctrl.v` 还不够，因为它们只是两个子模块。一个能被系统使用的 IP 需要顶层把控制、存储体、DFT、boot 和 AHB 接口连成一个整体。

![RTL 文件拓扑](<./screenshots/任务058_AHB_eflash控制器设计12/task58_00_rtl_file_topology_00m40s.jpg>)

层级关系：

```text
flash_c_top
  ├─ flash_control_top
  │   ├─ flash_ahb_slave_if
  │   └─ flash_ctrl
  └─ flash_call
      ├─ flash0 storage body
      └─ flash1 storage body
```

这也是芯片前端交付里的常见结构：单个功能模块写完只是中间态，真正交付要有清晰 top、端口和实例连接。

## 2. `flash_control_top` 把 AHB 侧和控制 FSM 连起来

`flash_control_top` 的输入输出分三类：一类是 AHB 接口，一类是系统配置和模式信号，一类是和存储体相连的数据/控制信号。

![control top 端口](<./screenshots/任务058_AHB_eflash控制器设计12/task58_01_control_top_ports_02m30s.jpg>)

端口分类：

| 类型 | 代表信号 | 去向 |
|---|---|---|
| AHB | `HCLK/HRESETn/HSEL/HADDR/HTRANS/HWRITE/HWDATA/HRDATA/HREADYOUT` | 接 SoC 总线 |
| 系统配置 | `dft_en`、`boot_in`、`write_protect_n`、`boot_offset` | 接系统顶层或测试控制 |
| 存储体数据 | flash0/flash1 `DOUT`、control outputs | 接 `flash_call` |
| 软件反馈 | `interrupt`、`HRESP`、`HRDATA` | 回 CPU/总线 |

`flash_control_top` 本身不是新算法，它的价值是把前面两个核心模块的接口对齐。

## 3. instance 连接时左边是子模块端口，右边是本模块 wire

视频里多次用列操作对齐 instance 连接。对齐不是为了好看而已，而是为了降低端口错接概率。

![slave_if instance](<./screenshots/任务058_AHB_eflash控制器设计12/task58_02_slave_if_instance_08m10s.jpg>)

Verilog 命名连接的判断口径：

```verilog
child_module u_child (
  .child_port_name(local_signal_name)
);
```

左边 `.child_port_name` 必须和子模块端口名一致；右边 `local_signal_name` 必须在当前模块中声明。右边可以和左边同名，也可以不同名，但位宽、方向和语义必须一致。

常见错误不是语法不会写，而是把 `program address` 接到 `read address`，或把 flash0/flash1 的信号对调。

## 4. `flash_ctrl` 的输出直连到两片存储体控制口

两片 eFlash 存储体结构相同，所以 flash0/flash1 两套控制信号几乎一模一样。top 只是把 `flash_ctrl` 产生的控制口传给 `flash_call`。

读数据方向相反：数据从 storage body 出来，经过 `flash_call`、`flash_control_top`，再回到 `flash_ctrl/slave_if` 做 mux 和 `HRDATA` 输出。

![读数据路径](<./screenshots/任务058_AHB_eflash控制器设计12/task58_03_read_data_path_15m20s.jpg>)

数据路径可以写成：

```text
flash0/flash1 DOUT
  -> flash_call
  -> flash_control_top
  -> flash_ctrl 选择当前 chip read data
  -> slave_if read data mux
  -> AHB HRDATA
```

如果 flash0 和 flash1 同时被选中，read data mux 就没有唯一答案。所以片选互斥是结构约束。

## 5. `hready_flag` 只应在 read access 中拉低

`HREADYOUT=1` 表示 AHB slave 可以结束当前传输；`HREADYOUT=0` 表示当前传输还要等待。eFlash read 需要等待存储体 access time，因此 read access 会拉低 ready。

![hready read wait](<./screenshots/任务058_AHB_eflash控制器设计12/task58_04_hready_flag_read_wait_20m50s.jpg>)

program/page erase 不应长期拉低 `HREADYOUT`。原因很直接：program 和 erase 是微秒甚至毫秒级长操作，AHB 协议不适合让一个 slave 长时间把总线锁住。正确做法是：

```text
CPU 写 command 寄存器
AHB 写周期结束
eFlash 内部 busy
完成后 status/interrupt 通知软件
```

read 才是同步等待数据的路径，所以 read 对 `HREADYOUT` 精度最敏感。

## 6. `flash_busy` 会禁止写配置，但不会让 AHB 写自动报错

`busy` 的作用主要在 `slave_if` 内部：当 eFlash FSM 正在运行时，新写入的 program address/data/timing/command 不应再更新寄存器。

![busy blocks writes](<./screenshots/任务058_AHB_eflash控制器设计12/task58_05_busy_blocks_writes_27m50s.jpg>)

这带来一个软件层面的陷阱：

```text
AHB 写周期可能看起来已经完成
但如果 flash_busy=1，内部寄存器没有真正更新
所以软件必须等 done/status/interrupt 后再写下一条命令
```

这不是总线错误，而是设计选择。它要求驱动严格按“写命令 -> 等完成 -> 清状态 -> 再写下一条”的顺序执行。

## 7. busy 期间可以读寄存器，但不能改正在被使用的配置

read 和 write 的风险不同。busy 期间读状态寄存器或读返回数据通常是允许的，因为读不会改变正在执行的地址、数据或 timing。busy 期间写寄存器则可能破坏正在执行的操作。

典型风险：

```text
program 正在使用 program address/data
CPU 又写 program data
若不屏蔽，当前 program 的数据会被中途改掉

page erase 正在使用 page number
CPU 又写 page number
若不屏蔽，擦除目标页可能变化

FSM 正在按 timing counter 跳转
CPU 又改 timing 寄存器
若不屏蔽，状态可能提前或永远跳不出
```

所以 `busy` 的关键作用不是“让软件知道忙”，而是“保护当前硬件操作不被新配置破坏”。

## 8. `flash_call` 同时处理 DFT 路径和写保护门控

`flash_call` 包住两片存储体，同时在功能路径和测试路径之间做选择。DFT 模式下，存储体端口可以被测试引脚直接驱动，便于生产测试判断存储阵列是否正常。

![DFT 与 write protect mux](<./screenshots/任务058_AHB_eflash控制器设计12/task58_06_dft_write_protect_mux_41m40s.jpg>)

功能模式下，`write_protect_n` 会参与门控：

```text
write_protect_n = 1 -> 允许 PROG/NVSTR/ERASE/MASS 等写擦相关信号通过
write_protect_n = 0 -> 写擦相关信号被与门压成 0
```

这里的保护不是软件提示，而是硬件门级拦截。即使上游产生了 program 或 erase 控制，写保护无效时也不能真正进入存储体。

## 9. `flash_c_top` 是 AHB 到 eFlash 协议的翻译器

![flash_c_top wrapper](<./screenshots/任务058_AHB_eflash控制器设计12/task58_07_flash_c_top_wrapper_43m30s.jpg>)

站在 SoC 角度，外面只看到一个 AHB slave 和少量系统配置端口；站在 eFlash 存储体角度，里面看到的是 `XADR/YADR/PROG/NVSTR/ERASE/IFREN` 等阵列控制信号。

这个顶层的本质是翻译：

```text
AHB 地址、写数据、读请求、控制寄存器
  -> 寄存器配置与状态机
  -> eFlash 存储体协议波形
```

前端工程师交付 IP 时，最怕的不是单个子模块能不能跑，而是 top 级端口、实例、片选、DFT、保护、ready/busy 语义不一致。任务58 的价值就在于把这些边界讲清楚。

## 工程练习

1. 画出最小层级树。

   合格答案：`flash_c_top` 顶层下有 `flash_control_top` 和 `flash_call`；`flash_control_top` 下有 `flash_ahb_slave_if` 与 `flash_ctrl`；`flash_call` 下有 flash0/flash1 两片存储体。

2. 检查一条 instance 连接。

   合格答案应同时说明：左侧 `.port` 是子模块端口名，必须和子模块声明一致；右侧括号中是当前模块 signal，必须在本模块声明并保证位宽、方向和语义正确。若右侧未声明，编译会报错；若语义错接，编译可能过但功能会错。

3. 写出软件连续发 program 的正确节流策略。

   合格答案：每次写 program address/data/enable 后，等待 `program_done` 或 interrupt；读 status/error 判断是否成功；W1C 清除状态；确认不 busy 后再发下一条。不能只看 AHB 写周期完成。

4. 做一次 top 级连线核查。

   合格答案：从 `flash_c_top` 入口列 AHB、DFT、boot/write protect、flash read data、interrupt；沿 instance 确认 AHB 信号只进入 `flash_control_top`，flash 控制脚经 `flash_call` 到两片存储体；功能模式下 DFT 选择关闭；write protect 有效时写擦控制脚被门控；`flash_busy` 期间配置寄存器写入被屏蔽但寄存器读仍可观察状态。

## 常见误区和失败信号

| 误区 | 正确判断 | 失败信号 |
|---|---|---|
| 两个核心 RTL 文件就是完整 IP | 还需要 top、storage wrapper、DFT/保护连接 | 仿真无法实例化完整设计 |
| `.port(signal)` 左右含义一样 | 左边是子模块端口，右边是当前模块信号 | 端口名对不上或语义错接 |
| program/erase 要一直拉低 HREADY | 长操作后台执行，用 status/interrupt 通知 | AHB 总线被微秒级锁住 |
| busy 只是给软件看的提示 | busy 还会屏蔽寄存器写入 | 连续写配置丢失 |
| DFT 信号和功能信号可以混用 | DFT 是测试直连路径，功能模式要关闭 | 生产测试路径干扰正常工作 |
| write protect 只在寄存器层判断 | 存储体入口也要硬件门控 | 保护区仍可能被写擦 |

## 复习与自测

1. `flash_control_top` 主要包住哪两个模块？

   答案：`flash_ahb_slave_if` 和 `flash_ctrl`。

2. `flash_call` 的作用是什么？

   答案：包住两片 eFlash 存储体，并处理 DFT 测试路径、写保护门控和存储体端口连接。

3. 为什么 program/page erase 不应长时间拉低 AHB `HREADYOUT`？

   答案：它们是长操作，持续微秒或毫秒级，若拖住 AHB 会阻塞系统；应后台执行，完成后用 status/interrupt 通知。

4. busy 期间软件写寄存器可能出现什么现象？

   答案：AHB 写周期看似完成，但内部寄存器因 busy 屏蔽没有更新，导致配置丢失。

5. DFT 模式为什么要把存储体端口拉到芯片引脚？

   答案：生产测试需要直接驱动存储体，判断存储阵列制造后是否正常。


# 任务57：AHB eFlash控制器设计11

## 本章知识全景图

这一讲继续展开 `flash_ctrl.v` 的三段式 FSM。任务56 已经说明了状态名、计数器和 `finish` 信号从哪里来；任务57 把这些信号接成真正的状态跳转和输出控制：`IDLE` 根据命令进入 read/program/page erase，read 期间拉低 `HREADY`，program/erase 期间按 eFlash 时序拉 `NVSTR/PROG/ERASE/XE/YE/SE/IFREN` 等信号，最后用 busy、done 和 read data 把结果送回 `slave_if`。

| 层级 | 核心概念 | 本章要形成的判断 | 对应 RTL |
|---|---|---|---|
| 状态跳转 | `flash_current_st -> flash_next_st` | 命令只在 IDLE 接收，后续靠 finish 推进 | second always block |
| read path | `READ_ACCESS`、`hready_flag`、地址输出 | read 要等待存储体数据，所以会占住 AHB | read branch |
| erase path | `TNVS -> PE_ERASE -> TNVH -> RCV` | page erase 只关心页和 block/chip 选择 | page erase branch |
| program path | `TNVS -> PROG_SETUP -> ADDR_SETUP -> PROG_PROC -> ADDR_HOLD -> PROG_HOLD -> TNVH -> RCV` | program 是最细的波形链 | program branch |
| 输出 next | `_r_next` 默认保持或清零 | 状态跳转和输出控制要同步更新 | output logic |
| 总线反馈 | `busy`、`hready`、`done` | program/erase 不拖住总线，read 会拖住总线 | feedback signals |

最短学习路径：

```text
先看 IDLE 如何选择 read / program / page erase
  -> 再看每条路径如何靠 finish 信号向后跳
  -> 再看输出逻辑如何把状态翻译成 eFlash 控制口
  -> 最后把 hready、busy、done 三个软件可见反馈串起来
```

## 全视频地图

| 时间段 | 视频内容 | 这一段真正要学会什么 |
|---|---|---|
| 00:00-06:00 | 组合逻辑状态跳转开头，`IDLE`、`TNVS` 分支 | 新命令只在 IDLE 被接收，program/PE 先共用 TNVS |
| 06:00-12:00 | finish 信号、read access 跳转 | read 等 `rd_finish` 后回 IDLE，并释放 HREADY |
| 12:00-20:00 | page erase 和 program 状态链 | page erase 短，program 状态更多 |
| 20:00-28:00 | 输出 next 默认值与 read 输出 | 输出逻辑要先给默认值，再按状态覆盖 |
| 28:00-36:00 | flash0/flash1、main/information 控制信号 | block/chip select 决定哪一组存储体口被拉起 |
| 36:00-43:00 | busy、hready、done、read data | 软件能否继续写命令取决于 busy/done，而不是只看 AHB 写周期 |
| 43:00-50:00 | 收尾与代码阅读方法 | 状态跳转和输出控制要配合读，不能只看其中一个 |

## 视觉核对清单

| 视频时间段 | 截图 | 核对点 |
|---|---|---|
| 00:35-00:55 | `task57_00_fsm_comb_logic_start_00m45s.jpg` | FSM 组合逻辑入口，`IDLE` 接收新命令 |
| 04:50-05:10 | `task57_01_idle_branch_05m00s.jpg` | read access 中 `hready_flag` 拉低并等待返回 IDLE |
| 09:50-10:10 | `task57_02_read_access_branch_10m00s.jpg` | finish 信号由 counter 与 timing 比较生成 |
| 14:50-15:10 | `task57_03_nvs_erase_path_15m00s.jpg` | page erase 与 program 在 `TNVS` 后分叉 |
| 19:50-20:10 | `task57_04_program_path_20m00s.jpg` | program 细分为 setup、process、hold 等阶段 |
| 24:50-25:10 | `task57_05_output_logic_25m00s.jpg` | 输出 `_r_next` 默认值与状态覆盖 |
| 29:50-30:10 | `task57_06_flash_signals_30m00s.jpg` | read/program/erase 控制口进入 flash0/flash1 |
| 34:50-35:10 | `task57_07_hready_busy_logic_35m00s.jpg` | `busy` 和 `hready` 在 read 结束附近的关系 |
| 39:50-40:10 | `task57_08_data_mux_done_logic_40m00s.jpg` | main/information 与 chip select 共同决定输出口 |
| 44:50-45:10 | `task57_09_final_logic_45m00s.jpg` | 后半段输出逻辑收束到 done/busy/read data |

这组图要按“车间流水线”理解：`IDLE` 是接单口，`TNVS` 是开工前预热，read 是短工序但占着 AHB 通道，page erase 是整页处理，program 是最细的多工位加工。`busy` 表示车间正在干活，`hready` 表示前台是否还能让总线继续走；二者有关联，但不是同一张指示灯。

## 1. `IDLE` 是唯一接收新命令的入口

状态机在 `IDLE` 时先判断 program/page erase，再判断 read。也就是说，如果写擦命令和 read 同时出现，写擦路径优先进入 `FLASH_TNVS`；只有没有写擦命令时，read 才进入 `READ_ACCESS`。

![FSM 组合逻辑入口](<./screenshots/任务057_AHB_eflash控制器设计11/task57_00_fsm_comb_logic_start_00m45s.jpg>)

核心结构：

```verilog
case (flash_current_st)
  FLASH_IDLE:
    if (pe_en || prog_en)
      flash_next_st = FLASH_TNVS;
    else if (read_en)
      flash_next_st = READ_ACCESS;
    else
      flash_next_st = FLASH_IDLE;
```

这个优先级很重要。program/page erase 是改变存储体内容的长操作，read 是短操作；如果 busy 控制做得不好，同时请求可能导致存储体口冲突。

## 2. `TNVS` 是 program 和 page erase 的共同前奏

`TNVS` 对应 `NVSTR` 建立阶段。program 和 page erase 都需要先把 `NVSTR` 拉到正确状态，所以它们先走同一个状态，等 `tnvs_finish` 后再分叉。

状态分叉口径：

```text
TNVS finish
  -> pe_en   : 进入 PE_ERASE
  -> prog_en : 进入 PROG_SETUP
```

如果没有命令仍进入了 `TNVS`，状态机应回到 IDLE。这种防御分支不是主流程，但能降低异常条件下的失控概率。

## 3. read path 短，但对 HREADY 最敏感

read 路径只有 `IDLE -> READ_ACCESS -> IDLE`，但它直接影响 AHB 总线等待。`READ_ACCESS` 中 `hready_flag` 拉低，地址计数器递增，直到读数据满足 access time 后再回到 IDLE。

![read access 与 hready](<./screenshots/任务057_AHB_eflash控制器设计11/task57_01_idle_branch_05m00s.jpg>)

![read access finish](<./screenshots/任务057_AHB_eflash控制器设计11/task57_02_read_access_branch_10m00s.jpg>)

第二张图要盯住 `rd_finish` 的来源：它不是“状态进入 READ_ACCESS 就完成”，而是 counter 和 `rd_access_timing` 比较后产生。漏看这一点，会把 read path 误读成单拍返回，后面 TB 就容易不等 `HREADYOUT` 直接采 `HRDATA`。

read 输出要做几件事：

```text
拉低 hready_flag，告诉 AHB 当前 read data 还没准备好
输出 XADR/YADR
拉起 XE/YE/SE/IFREN
根据 flash0/flash1 read select 只选择一片
等待 rd_finish
回 IDLE 时释放 hready，清 busy 和 chip select
```

read 的危险点是“数据还没准备好但总线已经采样”。所以 TB 后面读 task 会等待 `HREADY` 重新拉高，再取 `HRDATA`。

## 4. page erase path 用 page number 选择页和存储体

page erase 不关心 `YADR`，它以 page 为单位擦除。状态路径比 program 短：

```text
FLASH_IDLE
  -> FLASH_TNVS
  -> PE_ERASE
  -> FLASH_TNVH
  -> FLASH_RCV
  -> FLASH_IDLE
```

![page erase 分支](<./screenshots/任务057_AHB_eflash控制器设计11/task57_03_nvs_erase_path_15m00s.jpg>)

page erase 输出控制要同时回答三件事：

```text
擦 main block 还是 information block
擦 flash0 还是 flash1
page number 的哪些位送到存储体地址口
```

在 main block 下，高位 `pe_num[8]` 常用于选择 flash0/flash1；在 information 或局部场景下，还要结合 block select。只记“PE 有 page number”不够，必须记住 page number 同时承载页号和片选。

## 5. program path 是最细的波形链

program 要满足多个 setup、process 和 hold 阶段，所以状态更多：

```text
FLASH_IDLE
  -> FLASH_TNVS
  -> PROG_SETUP
  -> ADDR_SETUP
  -> PROG_PROC
  -> ADDR_HOLD
  -> PROG_HOLD
  -> FLASH_TNVH
  -> FLASH_RCV
  -> FLASH_IDLE
```

![program path](<./screenshots/任务057_AHB_eflash控制器设计11/task57_04_program_path_20m00s.jpg>)

这条链的设计目标是把 datasheet 中的 program 时序变成状态机：

| 状态 | 作用 |
|---|---|
| `PROG_SETUP` | program 前的控制建立 |
| `ADDR_SETUP` | 地址与数据稳定到存储体端口 |
| `PROG_PROC` | 真实 program 脉冲或处理时间 |
| `ADDR_HOLD` | program 后地址保持 |
| `PROG_HOLD` | program 控制保持 |
| `TNVH/RCV` | NVSTR hold 与恢复 |

如果某段 hold 时间少了，仿真可能偶尔能过，但 silicon 上会变成典型时序裕量问题。

## 6. 输出逻辑用 `_next` 控制下一拍寄存器值

状态跳转只决定“下一状态是什么”，输出逻辑决定“下一拍各控制信号是什么”。课程画面中大量信号写成 `flash0_xaddr_r_next`、`flash1_nvstr_r_next`、`flash_busy_r_next`，这说明输出口是寄存后的，而不是纯组合直出。

![输出逻辑默认值](<./screenshots/任务057_AHB_eflash控制器设计11/task57_05_output_logic_25m00s.jpg>)

读输出例子：

```text
READ_ACCESS:
  xaddr/yaddr <= flash_addr 拆分结果
  xe/ye/se    <= read main 或 read information select
  ifren       <= read information select
  busy        <= 1
  chip select <= flash0_rd_cs 或 flash1_rd_cs
```

这里使用 `_next` 的好处是所有输出和状态在同一个时钟边沿更新，波形更稳定，也更接近同步设计规范。

![flash signals](<./screenshots/任务057_AHB_eflash控制器设计11/task57_06_flash_signals_30m00s.jpg>)

这张图负责把状态机文字落到真实 eFlash 控制脚：`XADR/YADR` 是地址，`XE/YE/SE/IFREN` 是读选择，`PROG/ERASE/NVSTR` 是写擦控制。状态名像工序名称，控制脚才是实际按下的开关；只看状态名，不看控制脚，无法证明存储体真的收到正确动作。

## 7. main/information 和 flash0/flash1 共同决定输出哪组口

read、program、page erase 都要避免同时驱动两片存储体。正常情况下，flash0/flash1 片选最多只有一个为 1。

![读路径地址与 block select](<./screenshots/任务057_AHB_eflash控制器设计11/task57_08_data_mux_done_logic_40m00s.jpg>)

控制口径可以压缩成：

```text
block select 决定 main 还是 information
chip select 决定 flash0 还是 flash1
operation state 决定 read/program/erase 哪类控制信号有效
```

这三个条件缺一不可。只看 operation state 会导致两片 flash 同时被拉起；只看 chip select 又无法区分 main 和 information。

## 8. `busy` 和 `hready` 不是同一个信号

`busy` 表示 eFlash 控制状态机不在可接收新命令的稳定状态；`hready_flag` 表示 AHB 当前能否结束这次传输。program/page erase 期间通常 `busy=1`，但 `hready_flag` 不会长时间拉低。read 期间两者会同时体现等待。

![busy 与 hready](<./screenshots/任务057_AHB_eflash控制器设计11/task57_07_hready_busy_logic_35m00s.jpg>)

区别如下：

| 信号 | 主要服务对象 | 什么时候关键 |
|---|---|---|
| `hready_flag` | AHB 总线 | read access 等数据时 |
| `flash_busy` | `slave_if` 和软件命令节流 | program/PE/read 正在执行时 |
| `prog_done/pe_done` | status 和 interrupt | recover 结束且命令类型匹配时 |

所以 CPU 写 program 命令后，AHB 写周期可能已经结束，但 eFlash 内部仍 busy。软件不能因为 AHB 写看起来完成，就马上写下一条 program 配置。

## 9. done 来自 recover finish，而不是来自命令置位瞬间

program 和 page erase 都要经过 recover。只有 `rcv_finish` 且本次命令类型匹配时，才产生 `flash_prog_done` 或 `flash_pe_done`。

判断口径：

```text
flash_prog_done = rcv_finish && prog_en
flash_pe_done   = rcv_finish && pe_en
```

![final done logic](<./screenshots/任务057_AHB_eflash控制器设计11/task57_09_final_logic_45m00s.jpg>)

这张收尾图要看 done、busy、read data 如何汇合到软件可见结果。done 不是命令启动的回声，而是 recover 结束后的签收章；busy 不是错误，而是“当前工单还没完”；read data 不是凭空出现，而是前面的 chip/block select 和存储体输出共同选择出来。

read 没有同类 done，因为 read 的完成由 `HREADY` 和 read data 返回体现。这个差异会影响软件驱动：read 走总线握手，program/PE 走状态或中断通知。

## 工程练习

1. 给 `IDLE` 写一个状态跳转优先级表。

   | 条件 | 下一状态 | 解释 |
   |---|---|---|
   | `pe_en || prog_en` | `FLASH_TNVS` | 写擦类命令先走 NVSTR setup |
   | 无写擦且 `read_en` | `READ_ACCESS` | read 是短路径，但要等 access time |
   | 都无效 | `FLASH_IDLE` | 保持空闲 |

2. 写出 read 期间输出控制最少要做的事。

   合格答案：拉低 `hready_flag`；输出 `XADR/YADR`；根据 main/information 拉 `ifren` 和 `XE/YE/SE`；根据 flash0/flash1 select 只选一片；等 `rd_finish` 后回 IDLE 并释放 `hready_flag`。

3. 判断 `busy=1` 是否意味着 AHB 一定不能完成当前写周期。

   答案：不一定。program/PE 期间 `busy=1`，但 AHB 写周期可以结束；`busy` 主要阻止新的配置写入。read 期间 `busy` 与 `hready_flag` 都可能体现等待，因为 read 数据需要同步返回给总线。

4. 写一条端到端验证用例。

   合格答案：先用 AHB task 写 program address/data/timing/enable；在波形里确认 `slave_if` 锁存寄存器并发出 `prog_en`；确认 FSM 离开 IDLE，按 program 路径拉起控制脚；recover finish 后 `program_done` 置位，status/interrupt 可见；W1C 清状态；最后对同地址 read，等待 `HREADYOUT` 后比较 `HRDATA`。这条链中任意一段断开，都不能说 program 通过。

## 常见误区和失败信号

| 误区 | 正确判断 | 失败信号 |
|---|---|---|
| 任何状态都能接新命令 | 新命令只应在 IDLE 接收 | 操作中途被新地址/数据覆盖 |
| read 和 program 的等待方式一样 | read 占 AHB，program/PE 后台执行 | 总线被长时间锁住或读到无效数据 |
| page erase 需要 YADR | page erase 以页为单位，不按 word | 擦除粒度错误 |
| 状态跳转就是全部逻辑 | 还要看输出 `_next` 如何拉存储体口 | 状态对了但波形不对 |
| busy 等同 hready | busy 是内部命令节流，hready 是 AHB 握手 | 软件连续写丢配置 |
| done 在启动后立即产生 | done 要等 recover finish | status/interrupt 过早 |

## 复习与自测

1. `IDLE` 中 program/PE 和 read 同时有效时，哪类命令优先？

   答案：代码结构中 `pe_en || prog_en` 优先进入 `FLASH_TNVS`，read 在后续 `else if` 分支。

2. 为什么 program 和 page erase 都先进入 `TNVS`？

   答案：二者都需要建立 `NVSTR`，所以先共用 `TNVS`，再根据 `pe_en/prog_en` 分叉。

3. read 为什么没有 `read_done` 状态位？

   答案：read 通过 AHB `HREADY` 和 `HRDATA` 完成握手；program/PE 是后台长操作，才需要 done/status/interrupt。

4. `_r_next` 这类信号的作用是什么？

   答案：先在组合逻辑中计算下一拍寄存器值，再在时钟边沿寄存到真实输出，保证输出同步更新。

5. 如果 program 期间 CPU 连续写下一组 program address/data，会发生什么风险？

   答案：AHB 写周期可能看似完成，但 `flash_busy` 会阻止寄存器真实更新，导致新配置丢失或无效。


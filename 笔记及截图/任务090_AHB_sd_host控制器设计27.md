# 任务90：AHB sd host控制器设计27

## 本章知识全景图

本节开始讲 SD Host 的 AHB DMA。DMA 的任务是在 AHB 总线上作为 master，把一个 block 的数据在外部内存和 SD FIFO 之间搬运。读 SD 卡时，SD 侧先把 block 写入 FIFO，DMA 再把 FIFO 数据写到 AHB 目标地址；写 SD 卡时，DMA 从 AHB 源地址读数据写入 FIFO，供 SD data send shift 连续发送。

| 学习块 | 核心问题 | 结论 |
|---|---|---|
| DMA 角色 | 为什么 SD Host 需要 DMA | CPU 配置地址/方向/长度，DMA 自动搬 block 数据 |
| block 换算 | 512 byte block 对应多少 FIFO word | FIFO 宽 32 bit，512 byte = 128 个 32 bit word |
| AHB master | DMA 和 slave 接口有什么不同 | `HREADY/HRESP/HRDATA/HGRANT` 是输入，`HADDR/HTRANS/HWRITE/HWDATA/HBUSREQ` 是输出 |
| 仲裁 | `HBUSREQ/HGRANT/HLOCK` 怎么配合 | DMA 先 request，arbiter grant 后占用总线；lock 可保持一段 burst 不被抢 |
| 配置寄存器 | DMA 需要哪些软件配置 | enable、direction、address、transfer_size |
| FIFO 接口 | DMA 如何读写 FIFO | 根据方向产生 FIFO read 或 write，并处理 full/empty/interrupt |
| 参数保护 | transfer size 为什么检查 >1024 | FIFO 最大 1024 byte，超过会装不下 |
| 代码阅读 | 为什么后续要结合波形看 | DMA 时序条件多，valid/finish 需要波形验证 |

最短学习路径：先把 DMA 读/写两个方向画清楚，再看 AHB master 信号，最后理解 DMA 状态机和 size/error/valid/finish 只是为了把一次 block 搬运对齐到总线时序。

![DMA 角色回顾](<./screenshots/任务090_AHB_sd_host控制器设计27/task90_01_dma_role_recap.jpg>)

视频核对：00:01-05:12，截图用于核对“DMA 角色回顾”这个知识点。

## 全视频地图

| 时间 | 视频内容 | 学习任务 |
|---|---|---|
| 00:01-05:12 | 回顾 SDIF、FIFO、DMA 的数据搬运角色 | 建立 DMA 在 SD Host 中的位置 |
| 06:36-16:05 | 分析 AHB master interface | 区分 master/slave 信号方向 |
| 16:05-20:36 | DMA 配置寄存器：enable、direction、address、transfer_size | 理解软件如何驱动 DMA |
| 21:03-26:27 | FIFO 和 interrupt interface | 建立 DMA 与 FIFO/SDIF 的连接 |
| 27:07-30:24 | DMA 状态 define、H prot/size/burst | 识别状态机和 AHB 控制常量 |
| 30:24-34:11 | DMA size error | 理解超过 FIFO 最大容量的保护 |
| 34:11-41:39 | DMA load、request、fifo read/write data | 理解早期组合信号 |
| 42:23-45:27 | address valid、read data valid、finish 条件 | 为后续波形分析建立观察点 |

## 二轮重读：DMA 要按 AHB 两相位读，不按普通函数读

本节开始读 `sd_dma.v`。它的难点不是“DMA 会搬数据”这句话，而是 AHB master 的地址相位、数据相位、仲裁 grant、HREADY stall、FIFO full/empty 之间要同时对齐。只看组合赋值会觉得信号很多；按四条线读，结构会清楚很多。

| 线索 | 关键截图 | 必须看懂什么 |
|---|---|---|
| 数据路径 | `task90_01`、`task90_02` | SD 读方向是 FIFO 到 AHB，SD 写方向是 AHB 到 FIFO |
| AHB master | `task90_04`、`task90_05`、`task90_06` | DMA 输出地址/控制，输入 ready/grant/response/read data |
| 软件配置 | `task90_07` | 只有一个外部地址，因为另一端固定是本地 FIFO |
| 控制状态 | `task90_09`、`task90_10`、`task90_12` | 状态机负责 request、读写、last、finish 和 error |
| FIFO 接口 | `task90_08`、`task90_11` | 根据 direction 产生 FIFO read/write，且无效数据不必额外清零 |

这一节要把 `address_valid` 和 `read_data_valid` 分开：AHB 是流水式两相位协议，地址发出不等于数据已经回来，最后一个地址发完也不等于最后一个数据相位完成。

## 截图证据链：每张图在证明什么

| 截图 | 证据职责 | 如果这张图看不懂，会漏掉什么 |
|---|---|---|
| `task90_01` | SD Host 架构里的 DMA 位置 | DMA 是 AHB master，不是 SD data shift 的一部分 |
| `task90_02` | block length 到 FIFO word 的换算 | 512 byte 为什么是 128 个 32 bit word |
| `task90_03` | `sd_dma.v` 模块入口 | 文件规模和接口分组 |
| `task90_04` | AHB master interface | `HREADY/HGRANT/HRDATA` 对 DMA 是输入 |
| `task90_05` | request、lock、address | DMA 先请求总线，拿 grant 后访问 |
| `task90_06` | HTRANS/HSIZE/HBURST | 传输类型、宽度、burst 不是随便常量 |
| `task90_07` | DMA 配置寄存器 | enable、direction、address、size 如何由 SDIF 配置 |
| `task90_08` | FIFO 与 interrupt 接口 | 搬运完成/空满事件要反馈给 CPU/SDIF |
| `task90_09` | DMA 状态定义 | 状态名就是读状态机的索引 |
| `task90_10` | size error | 超过 FIFO 容量必须提前拒绝 |
| `task90_11` | FIFO read/write data | 无效周期 data bus 不必加 32 bit 清零 mux |
| `task90_12` | valid/finish 信号 | finish 必须等最后数据相位完成 |


## 1. DMA 的位置：它负责把 FIFO 中一个 block 搬进或搬出 AHB 空间

SD Host 的 FIFO 只缓存一个 block。DMA 把这个 block 和系统内存连接起来。

![block length 与 FIFO word 换算](<./screenshots/任务090_AHB_sd_host控制器设计27/task90_02_block_length_fifo_words.jpg>)

视频核对：02:12-05:12，截图用于核对“block length 与 FIFO word 换算”这个知识点。

读 SD 卡：

```text
SD card -> DATA line -> data_receive_shift -> SD FIFO
SD FIFO -> DMA -> AHB target address
```

写 SD 卡：

```text
AHB source address -> DMA -> SD FIFO
SD FIFO -> data_send_shift -> DATA line -> SD card
```

若 block length 为 512 byte，FIFO 数据宽度 32 bit，即每个 word 4 byte，那么需要搬运：

```text
512 byte / 4 byte per word = 128 word
```

DMA 的 transfer size 和 FIFO word count 必须对齐，否则会多搬或少搬。

## 2. AHB master interface：信号方向和 slave 相反

DMA 在 AHB 上是 master。它主动发地址、控制、写数据；slave 返回 ready、response 和读数据。

![DMA module 入口](<./screenshots/任务090_AHB_sd_host控制器设计27/task90_03_dma_module_entry.jpg>)

视频核对：06:36-07:00，截图用于核对“DMA module 入口”这个知识点。

![AHB master interface](<./screenshots/任务090_AHB_sd_host控制器设计27/task90_04_ahb_master_interface.jpg>)

视频核对：07:00-16:05，截图用于核对“AHB master interface”这个知识点。

| AHB 信号 | 对 DMA 的方向 | 作用 |
|---|---|---|
| `HREADY` | 输入 | 目标 slave 是否完成当前传输 |
| `HGRANT` | 输入 | arbiter 是否允许 DMA 使用总线 |
| `HRESP` | 输入 | slave response，指示 OKAY/ERROR 等 |
| `HRDATA` | 输入 | DMA 读 AHB 时返回的数据 |
| `HBUSREQ` | 输出 | DMA 请求总线 |
| `HLOCK` | 输出 | 请求锁住一段传输，不被中途抢走 |
| `HADDR` | 输出 | 当前访问地址 |
| `HTRANS` | 输出 | IDLE/NONSEQ/SEQ/BUSY |
| `HWRITE` | 输出 | 1 写 slave，0 读 slave |
| `HSIZE` | 输出 | 传输宽度，本设计主要用 32 bit |
| `HBURST` | 输出 | burst 类型，例如 INCR |
| `HWDATA` | 输出 | DMA 写 AHB 时的数据 |

slave 课程里 `HREADY` 往往是输出；到 master 这里它变成输入。这是读 AHB 代码时最容易混淆的地方。

## 3. request、grant、lock：DMA 不能想用总线就直接用

AHB 系统可能有多个 master。DMA 要先拉 `HBUSREQ`，由 arbiter 返回 `HGRANT`。只有拿到 grant 后，DMA 才能发起有效传输。

![request/lock/address](<./screenshots/任务090_AHB_sd_host控制器设计27/task90_05_request_lock_address.jpg>)

视频核对：10:57-12:55，截图用于核对“request/lock/address”这个知识点。

`HLOCK` 的作用是告诉 arbiter：当前 DMA 传输希望连续完成，不要传到一半就把 grant 收走。对 block 搬运来说，连续性有利于简化控制和提高吞吐。

AHB 控制字段：

![HTRANS/HSIZE/HBURST](<./screenshots/任务090_AHB_sd_host控制器设计27/task90_06_htrans_hsize_hburst.jpg>)

视频核对：12:55-16:05，截图用于核对“HTRANS/HSIZE/HBURST”这个知识点。

| 信号 | 本节口径 |
|---|---|
| `HTRANS` | 表示 IDLE、NONSEQ、SEQ 等传输类型 |
| `HSIZE` | 本设计搬 32 bit word 时为 2 |
| `HBURST` | 使用 INCR，地址连续递增，长度由 DMA 自己停 |
| `HPROT` | 固定普通用户/数据访问属性 |

## 4. DMA 配置寄存器：一头固定是本地 FIFO，所以只需一个外部地址

DMA 需要软件配置：

| 配置 | 含义 |
|---|---|
| `dma_enable` | 启动 DMA |
| `dma_direction` | 决定从 AHB 到 FIFO，还是从 FIFO 到 AHB |
| `dma_address` | 外部 AHB 地址 |
| `transfer_size` | 本次搬多少 byte/word，具体单位以 RTL 定义为准 |

![DMA 配置寄存器](<./screenshots/任务090_AHB_sd_host控制器设计27/task90_07_dma_config_registers.jpg>)

视频核对：16:05-20:36，截图用于核对“DMA 配置寄存器”这个知识点。

通用 DMA 常有 source address 和 destination address。这里 SD Host DMA 只有一个外部 address，是因为另一端固定是 SD FIFO。方向位告诉 DMA 是“去外部地址取数据写入 FIFO”，还是“从 FIFO 取数据写到外部地址”。

## 5. FIFO 与 interrupt interface：搬运状态要反馈给 SDIF/CPU

DMA 还连接 FIFO 和中断状态：

![FIFO 和 interrupt interface](<./screenshots/任务090_AHB_sd_host控制器设计27/task90_08_fifo_and_interrupt_interface.jpg>)

视频核对：21:03-26:27，截图用于核对“FIFO 和 interrupt interface”这个知识点。

| 信号组 | 用途 |
|---|---|
| `fifo_read_data`、`fifo_read_en` | 从 FIFO 读出数据写到 AHB |
| `fifo_write_data`、`fifo_write_en` | 从 AHB 读回数据写入 FIFO |
| `fifo_empty` | 读 FIFO 前检查是否有数据 |
| `fifo_full` | 写 FIFO 前检查是否还有空间 |
| clear interrupt | CPU 已处理状态后清除旧中断 |
| interrupt enable | 允许 full/empty/DMA finish 等事件产生中断 |
| DMA finish interrupt | 搬运完成后通知 CPU/SDIF |

中断状态必须可清。否则下一次事件到来时，软件无法区分旧状态和新状态。

## 6. DMA 状态定义：用名字替代裸数字

代码用 parameter 定义状态，例如 idle、bus request、read HB、write HB、last、finish、wait 等。

![DMA 状态定义](<./screenshots/任务090_AHB_sd_host控制器设计27/task90_09_dma_state_define.jpg>)

视频核对：27:07-30:24，截图用于核对“DMA 状态定义”这个知识点。

这样写的直接价值是可读性。看到 `READ_HB` 能知道正在从 AHB 读；看到数字 `3` 需要回查定义。状态机越复杂，命名越不是风格问题，而是降低审查成本的工程要求。

## 7. size error：超过 FIFO 最大容量必须提前拦住

本项目 FIFO 最大约 1024 byte。若 `transfer_size` 大于 1024，DMA 无法一次把这么多数据安全搬进/搬出这个 block FIFO，因此代码生成 `dma_error`。

![DMA size error](<./screenshots/任务090_AHB_sd_host控制器设计27/task90_10_dma_size_error.jpg>)

视频核对：30:24-34:11，截图用于核对“DMA size error”这个知识点。

代码没有直接用大比较器，而是用高位判断：

```text
transfer_size > 1024
  等价于
  高于 bit10 的位有 1，或 bit10 为 1 且低位也有 1
```

这种写法可能比通用比较器面积更小。对初学者来说，不必过度追求这种微优化，但要理解它背后的硬件含义：比较器不是免费资源，能用简单逻辑表达边界时可以更省。

## 8. FIFO read/write data：不要为无效写加无意义 mux

视频指出一个代码优化点：`fifo_write_data = fifo_we ? dma_write_data : 0` 这种写法可能引入 32 bit mux。实际上当 `fifo_we = 0` 时，FIFO 不会写入，data bus 上是什么值不影响功能。

![FIFO read/write data 组合信号](<./screenshots/任务090_AHB_sd_host控制器设计27/task90_11_fifo_read_write_data.jpg>)

视频核对：34:11-41:39，截图用于核对“FIFO read/write data 组合信号”这个知识点。

更直接的写法可以是：

```verilog
assign fifo_write_data = dma_write_data;
```

只要写使能正确，数据总线无需在无效时清 0。这个例子提醒读者：RTL 里的“看起来更干净”可能变成真实面积和功耗开销。无效周期的数据值如果不会被采样，就不要为它额外构造大 mux。

## 9. valid 和 finish：后续必须用波形确认

DMA 控制里出现 `address_valid`、`read_data_valid`、`address_finish`、`dma_finish` 等信号。这些信号和 AHB 的地址相位、数据相位、HREADY 以及最后一次传输强相关。

![valid/finish 信号](<./screenshots/任务090_AHB_sd_host控制器设计27/task90_12_valid_finish_signals.jpg>)

视频核对：42:23-45:27，截图用于核对“valid/finish 信号”这个知识点。

单看组合条件容易迷失，后续应结合波形检查：

| 信号 | 波形上应确认什么 |
|---|---|
| `address_valid` | HADDR/HTRANS 何时真正有效 |
| `read_data_valid` | HRDATA 或 FIFO read data 何时可采 |
| `address_finish` | 最后一个地址是否已经发出 |
| `dma_finish` | 数据相位是否也真正完成 |
| `HREADY` | stall 时状态和计数是否保持 |

这也是本节最后的工程建议：读复杂总线控制器，不要只看代码。代码给条件，波形给时序事实。

## 10. 本节到此为止的 DMA 读法

第一遍读 DMA，不必一上来追完所有状态跳转。先锁定四条线：

1. 软件配置线：enable、direction、address、transfer size。
2. AHB master 线：request/grant/address/control/data/ready/response。
3. FIFO 线：read/write data、read/write enable、empty/full。
4. 完成/错误线：size error、finish、interrupt、clear。

下一节继续状态机时，把每个 state 放到这四条线里判断，就不会变成裸看 if/else。

## 工程验证闭环

DMA 验证要把 AHB 和 FIFO 两边同时拉进波形。只看 `dma_finish` 会漏掉最后一个数据相位、HREADY stall 和 FIFO 边界错误。

| 验证对象 | 波形上应看到的正确结果 | 常见失败信号 | 定位方向 |
|---|---|---|---|
| bus request | `HBUSREQ` 拉起后等待 `HGRANT`，grant 前不发有效访问 | 未 grant 就 `HTRANS=NONSEQ/SEQ` | 查 bus request state |
| address phase | `HADDR/HTRANS/HWRITE/HSIZE/HBURST` 在 HREADY 允许时推进 | HREADY 低时地址计数继续加 | 查 `addr_valid` 和 counter enable |
| data phase | 读 AHB 时 `HRDATA` 晚于地址相位；写 AHB 时 `HWDATA` 对应上一地址 | 地址和数据错拍 | 查 `read_data_valid` / `address_valid` 区分 |
| FIFO 方向 | SD 读：FIFO read -> AHB write；SD 写：AHB read -> FIFO write | direction 反，数据搬到错误方向 | 查 `dma_dir` 分支 |
| transfer size | 512 byte 对应 128 个 32 bit transfer | 多搬/少搬一个 word | 查 byte/word 换算和 last bit |
| size error | 超过 1024 byte 直接 error，不启动搬运 | FIFO 装不下仍继续 DMA | 查 `dma_error` 和 `dma_load` gate |
| finish | 最后一个数据相位完成后才置 `dma_finish` | 最后一个 word 丢失但 finish 提前 | 查 `addr_finish` 与 `dma_finish` 差异 |

最小实验：设置 512 byte 传输，分别跑 SD 读方向和写方向；中间人为拉低 `HREADY` 两拍，确认地址、word counter、FIFO enable 都保持；最后检查第 128 个 word 的数据相位完成后才产生 finish interrupt。

## 深层理解：DMA 是懂规矩的搬运工

SD Host 的 DMA 不是一段“把 A 复制到 B”的软件循环，而是站在两个世界中间的搬运工：一边是本地 SD FIFO，另一边是 AHB 总线仓库。它不能推着车就冲进仓库，必须先举手请求 `HBUSREQ`，拿到 `HGRANT`，再按 `HREADY` 这盏交通灯前进；红灯时即使货已经在车上，也不能把地址计数往前挪。

这个比喻要精确映射到 RTL：

| 直觉对象 | RTL/总线对象 | 错用后果 |
|---|---|---|
| 搬运工申请通道 | `HBUSREQ/HGRANT` | 未授权就发地址，和别的 master 抢总线 |
| 仓库交通灯 | `HREADY` | wait state 中地址或数据错拍 |
| 货物批次 | `transfer_size` 与 word counter | 少搬最后一个 word 或多搬越界 |
| 固定装卸口 | SD FIFO 端 | direction 写反，数据从错误方向流动 |
| 装不下报警 | `size_error` | FIFO 容量不够仍启动事务 |

真正的理解不是会背这些信号名，而是能在波形里判断“车有没有在没拿通行证时开动”“红灯时车轮有没有继续转”“最后一箱货是否真放到了仓库”。AHB 的地址相位和数据相位像两节错半拍的车厢：第一节到站不代表第二节已经卸完，所以 `addr_finish` 不能直接等价于 `dma_finish`。


## 自测题

1. SD Host DMA 为什么只需要一个外部地址？
2. 512 byte block 在 32 bit FIFO 中是多少个 word？
3. `HGRANT` 对 DMA 是输入还是输出？
4. `HBUSREQ` 的作用是什么？
5. `HSIZE = 2` 通常表示什么？
6. 为什么 `transfer_size > 1024` 要报 error？
7. 为什么 `fifo_write_data` 无效周期不一定要 mux 成 0？

## 自测参考答案与判分点

1. 答：另一端固定是本地 SD FIFO，direction 决定是 FIFO 到外部地址，还是外部地址到 FIFO。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

2. 答：512 / 4 = 128 个 32 bit word。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

3. 答：输入。arbiter 给 DMA grant，表示 DMA 可以使用总线。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

4. 答：DMA 向 arbiter 请求使用 AHB 总线。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

5. 答：32 bit 传输宽度。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

6. 答：FIFO 最大容量约 1024 byte，本次搬运超过容量会装不下或读不出。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

7. 答：写使能为 0 时 FIFO 不采样数据，data bus 值不影响功能，加 mux 反而增加面积和功耗。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

## 工程核对口径

读完本讲后，至少要能用一张纸画出 `SD FIFO -> DMA -> AHB` 和 `AHB -> DMA -> SD FIFO` 两条方向相反的搬运链。画不出方向，后面看状态机时会把 `fifo_rd/fifo_we`、`HWRITE` 和软件命令名混在一起。

实操检查按四问执行：

1. 没有 `HGRANT` 时，`HADDR/HTRANS` 是否保持非有效访问？
2. `HREADY=0` 时，地址、word counter、FIFO enable 是否都停住？
3. 512 byte 是否严格换成 128 个 32-bit word？
4. 最后一拍数据相位完成后，`dma_finish` 和中断才出现吗？

如果这四问有任何一问答不上来，本讲不能算学完；它说明你只认识了 DMA 的“岗位名称”，还没有掌握它在总线红绿灯里怎样安全搬运。


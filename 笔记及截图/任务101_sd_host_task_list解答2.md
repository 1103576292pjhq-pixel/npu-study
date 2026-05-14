# 任务101：sd host task list解答2

## 本章知识全景图

这一讲不是简单回答几道 task list，而是把 SD Host 项目的三条主线拧在一起：CPU 怎样发起一次 SD 写，FIFO 为什么会成为吞吐瓶颈，DMA 作为 AHB master 遇到 grant 被撤销时怎样保存现场。

| 主线 | 要解决的问题 | 直接结论 |
|---|---|---|
| 写操作 task list | CPU 到底按什么顺序启动一次 block 写 | 先确认卡状态，再配置 timeout/block/位宽/命令参数，再搬 FIFO/DMA，最后等中断并清状态 |
| SD 写时序 | CMD24 之后 data 线上发生什么 | command、response、NWR、data block、CRC status、busy 是不同驱动方接力，不是一个连续 enable |
| command/data FSM | 状态机为什么分成两套 | command FSM 管命令和 response；data FSM 管 start bit、block 数据、CRC、busy、timeout |
| FIFO 设计 | 为什么当前方案效率不高 | 单 FIFO 按 block 工作会产生空档，乒乓 FIFO 才能让 DMA 和 SD data path 更接近并行 |
| AHB master | DMA 和前面学的 AHB slave 差在哪 | master 要 request/grant/ready，不能像 slave 一样被访问就响应 |
| `grant_low_again` | grant 中途掉了为什么不能简单回初始地址 | DMA 可能已经搬到 block 中间，必须保存未完成地址并在重新 grant 后接着走 |

最短学习路径：先按 task list 把“软件如何启动硬件”画出来，再按 CMD24 时序把“线上谁在驱动”分清，最后用 FIFO 和 DMA master 解释为什么一个 SD Host 控制器不是几个寄存器加状态机就完事。

![SD 写 task list 起点](<./screenshots/任务101_sd_host_task_list解答2/task101_dense_0000s_00h00m00s.png>)

## 本课主线地图

| 时间 | 画面证据 | 本笔记吸收点 |
|---|---|---|
| 00:00-02:00 | SD Host 写 task list 的 1-7 步 | 软件配置链路 |
| 04:00-06:00 | CMD24 写时序图 | response、data、CRC status、busy 的驱动方切换 |
| 08:00-14:00 | command/data 状态机图 | timeout、CRC error、all block done 的退出条件 |
| 16:00-22:00 | FIFO 改进题、block size、dual port | 单 FIFO 与乒乓 FIFO的吞吐差异 |
| 24:00-28:00 | AHB master 接口与 arbiter 说明 | master 先申请总线，grant+ready 才能推进 |
| 30:00-34:00 | SD identification/transfer 状态图 | host 只实现自己会发的必要命令 |
| 36:00-40:00 | GVim 中 `grant_low_again` 代码 | grant 中途撤销后的地址保持和单拍脉冲 |

## 1. CPU 发起写操作是一条软件到硬件的控制链

一次 SD block 写的第一步不是“让 data 状态机开始”，而是让 CPU 先把硬件所需上下文全部配置好。

视频开头的 task list 可以整理成这条链：

```text
1. CMD13 或等价查询：确认卡当前状态
2. 配置 READ_TIMEOUT_CONTROL、BLOCK_SIZE、BLOCK_COUNT
3. 配置 TRANSFER_MODE：方向、位宽、block 模式
4. 配置 COMMAND/ARGUMENT：准备 CMD24 单块写
5. 等待 INTERRUPT_STATUS 中的 ready/response 相关状态
6. FIFO 可接收后配置 DMA_ADDR、DMA_CTRL，启动 DMA 把数据搬到 FIFO
7. 等待 DMA 完成和 data path 完成
8. 清 FIFO、DMA、data interrupt/status
```

这条链的关键是“命令路径”和“数据路径”不是同一件事。CMD24 负责告诉卡“我要写一个 block”；FIFO/DMA 负责让这一整个 block 的数据在正确时间到达 SD data path。

如果 CPU 只发了 CMD24，却没有把 block size、block count、位宽、DMA 地址和 FIFO 条件配对，硬件会进入一种最难调的状态：命令响应看起来正常，数据路径却在等数据、发错长度或最后卡在 busy/interrupt。

## 2. CMD24 时序要按“谁驱动总线”来读

CMD24 写时序不是 host 从头驱动到尾。真正的时序是 host 和 card 交替占用 command/data 线。

![CMD24 时序图](<./screenshots/任务101_sd_host_task_list解答2/task101_dense_0360s_00h06m00s.png>)

看这张 CMD24 图时先分清两条线的所有权：command 阶段主要是 host 发命令、card 回 response；data 阶段才轮到 host 送 payload、card 回 CRC status 并用 busy 告诉 host“我还在内部写入”。response 像订单被收下，busy 释放才像货真正入库，二者不能混成一个成功信号。

```text
host  -> CMD24 + argument + command CRC
card  -> response
host  -> 等 NWR，开始发送 data block
host  -> data payload + CRC16 + end bit
card  -> CRC status
card  -> busy low while internal program
card  -> release data line high when ready
```

读这个图有三个检查点：

- `NCR` 是 command 到 response 的等待窗口；超时应报 response timeout。
- `NWR` 是 response 后到开始写 data 的间隔；不能假设 response 一回来就立刻写数据。
- `busy` 是 card 内部 program 的状态；CRC status OK 只是收包正确，不等于写入内部存储完成。

工程上最容易误判的是最后一点。data0 被 card 拉低时，host 不能继续把卡当作 ready；只有 data0 回到高电平，才说明 busy 释放。

## 3. command FSM 和 data FSM 的边界不能混

command FSM 只处理命令发出和 response 回来；data FSM 才处理 start bit、payload、CRC、busy 和 block 计数。

![command/data 状态机](<./screenshots/任务101_sd_host_task_list解答2/task101_dense_0600s_00h10m00s.png>)

command FSM 的核心路径：

```text
STOP
  -> WAIT_SEND    等 command_ready
  -> SEND         发 command
  -> WAIT_RECEIVE 如果需要 response
  -> RECEIVE      收 48-bit response
  -> STOP
```

data FSM 的核心路径按方向分开：

| 方向 | 等待条件 | 数据阶段 | 退出/错误 |
|---|---|---|---|
| 读 SD | 等 card data start bit | 收 block data 和 CRC16 | read timeout 或 all block received |
| 写 SD | 等 FIFO 有数据且 card 不 busy | 发 block data 和 CRC16 | CRC status error 或 all block sent |

视频里对读状态机有一个口头纠错：read timeout 和 all block received 应是“或”关系。只要超时或全部 block 接收完成，都应该退出当前等待路径；写成“且”会让状态机在错误条件下无法离开。

状态机设计的验收信号不是“状态名字齐全”，而是每条等待路径都有退出条件，每个错误条件都有上报对象，每个 block 完成后知道是继续下一 block 还是回到 stop。

## 4. FIFO 的争议点：能工作不等于吞吐好

当前设计用一个 FIFO 在 AHB/DMA 和 SD data path 之间缓冲 block 数据。它能工作，但效率不是最优。

![FIFO block 边界](<./screenshots/任务101_sd_host_task_list解答2/task101_dense_1080s_00h18m00s.png>)

数据路径可以画成：

```text
写 SD:
AHB memory -> DMA -> FIFO -> data_send_shift -> SD card

读 SD:
SD card -> data_receive_shift -> FIFO -> DMA -> AHB memory
```

当前 FIFO 的特点是按 block 产生满/空边界。即使物理深度有更多空间，设计也只希望一个 block 到位就触发当前传输粒度的 `full`。这种写法的好处是控制简单，坏处是每个 block 之间容易出现等待空档。

视频里明确提到一个更好的方向：乒乓 FIFO。

```text
buffer A 被 SD data path 读/写
buffer B 同时被 DMA/AHB 读/写
一个 block 完成后 A/B 交换角色
```

乒乓 FIFO 的意义是把“DMA 搬运”和“SD 线上传输”重叠起来。NPU/AI 芯片里同样常见：一个 buffer 被 compute 消费，另一个 buffer 被 DMA 预取，二者交替才能减少流水线空泡。

用吞吐视角看，单 FIFO 像只有一个装卸口：DMA 装货时 SD 侧等，SD 侧卸货时 DMA 又等；乒乓 FIFO 像两个周转箱，一个在卡侧排队发货，另一个在 AHB 侧提前装货。它不会改变 SD 协议本身，却能减少 block 与 block 之间的空拍。

## 5. 异步 FIFO 的 empty/full 本质是跨域指针比较

FIFO empty/full 不是单纯看计数器，而是看读写指针在对方时钟域同步后的关系。

![FIFO 指针代码](<./screenshots/任务101_sd_host_task_list解答2/task101_dense_1200s_00h20m00s.png>)

| 信号 | 产生位置 | 判断口径 |
|---|---|---|
| empty | 读端 | 写指针 Gray 码同步到读端后，与读指针 Gray 码相等 |
| full | 写端 | 读指针 Gray 码同步到写端后，与写指针满足“高位翻转、低位相同” |
| block-full | 写端 | 在普通 full 比较基础上，按 block length 提前触发 |

Gray 码的作用是减少跨域采样多 bit 同时变化的风险。这里不是为了“写法高级”，而是为了让读端/写端在不同 clock 下仍能稳定判断“对方走到哪里了”。

## 6. DMA 作为 AHB master 的第一课：grant 不是 ready

前面项目里多数模块是 AHB slave：别人访问到你的地址，你响应即可。DMA 是 master，它要主动申请总线。

![AHB master 接口](<./screenshots/任务101_sd_host_task_list解答2/task101_dense_1440s_00h24m00s.png>)

master 传输至少要看三层：

```text
HBUSREQ: 我想用总线
HGRANT : arbiter 允许我成为 master
HREADY : 当前传输可以推进/完成
```

`HGRANT=1` 只是仲裁结果，不代表当前数据相位已经结束。`HGRANT` 被拉低，也不代表当前拍所有相关动作都必须立刻丢弃。AHB 有地址相位和数据相位，状态机必须知道自己处在“新传输开始前”“地址已发出”“数据未完成”哪一种阶段。

所以 DMA master 的代码不能写成：

```text
if (!HGRANT) stop_everything;
```

更准确的口径是：没有 grant 不能开始新的总线占用；但已经发出的相位、已保存的地址、已等待的数据返回，都要按协议收尾。

## 7. `grant_low_again` 是中途丢总线后的恢复点

`grant_low_again` 描述的是“已经获得过 grant，正在读/写 block，中途 grant 又掉了”。它不是初次没拿到总线。

![grant_low_again 代码](<./screenshots/任务101_sd_host_task_list解答2/task101_dense_2160s_00h36m00s.png>)

读这段代码时不要只盯 `grant_low_again` 这个名字，而要盯它保存的是“中断后从哪里继续”。它不是让 DMA 重新下单，而是在总线通道被仲裁器临时收回后，把未完成地址像书签一样夹住，下一次拿回 grant 时从书签处续读/续写。

假设 DMA 正在写 512 byte，已经写了 128 byte，arbiter 暂时撤销 grant。此时如果重新回到初始地址，下次恢复会覆盖前 128 byte；如果简单继续加地址，又可能跳过未完成的地址相位。正确做法是保存“下一次应该继续的地址/状态”。

视频里最后解释了一个 RTL 时序细节：某个寄存器在当前 always 块里被安排清零，不等于当前组合判断已经看不到旧值。寄存器新值要到下一个时钟沿后才生效，因此某些 one-cycle pulse 可以在同一拍被用来保存地址，然后下一拍再清掉。

```text
第一次从 BUS_REQUEST 进入读/写:
  address <= dma_address

传输中 grant 变低:
  grant_low_again <= 1
  saved_address <= current_unfinished_address

重新获得 grant:
  address <= saved_address
  continue transfer
```

这个点是本讲最有工程价值的部分。写 DMA、AXI bridge、NPU 权重搬运、片上 SRAM block mover 时，只要总线可能被仲裁打断，就必须回答同一个问题：重新获得通道后，从哪里继续。

## 8. Host 设计只实现必要 command，但要理解卡状态

SD 状态图那一段不是要求你背完所有状态，而是让你知道 host 和 card 的职责不同。

![SD 状态图](<./screenshots/任务101_sd_host_task_list解答2/task101_dense_1920s_00h32m00s.png>)

作为 host，你只需要发自己设计里会用到的 command，比如初始化、选卡、设置位宽、读写 block、停止传输。作为 card/slave，则必须能响应 host 可能发来的更多命令。

这会影响 RTL 范围：host 控制器可以做“必要命令子集”，但每个被支持的命令都必须把状态前提和退出条件写清楚。不能因为只做子集，就把状态检查、timeout 和错误上报省掉。

## 本章收束与检查

- SD 写操作是一条 CPU 配置链，CMD24 只是其中一个环节。
- CMD24 时序要看驱动方：host 发 command/data，card 发 response/CRC status/busy。
- command FSM 管 response，data FSM 管 payload、CRC、busy、timeout。
- 单 FIFO 能工作但吞吐差；乒乓 FIFO 能让 DMA 与 SD data path 重叠。
- DMA master 要处理 request/grant/ready，不能套用 slave 思维。
- `grant_low_again` 的价值是保存中途丢总线时的恢复地址。
- Host 只实现必要 command 可以，但每个 command 的状态和错误出口必须完整。

## 自测题

1. 为什么 CMD24 response 正常仍不能说明一次写完成？  
   答：response 只说明卡接受了命令；之后还要发送 data block、CRC16，接收 CRC status，并等待 card busy 释放。
2. 当前单 FIFO 方案的主要吞吐问题是什么？  
   答：DMA 搬运和 SD data path 传输容易串行等待，block 之间有空档；乒乓 FIFO 可以一个 buffer 被 SD 使用，另一个 buffer 被 DMA 填/取。
3. `HGRANT=1` 和 `HREADY=1` 的区别是什么？  
   答：`HGRANT` 是仲裁允许当前 master 使用总线；`HREADY` 表示当前传输相位可以推进或完成。
4. `grant_low_again` 为什么不能只清状态重新开始？  
   答：DMA 可能已经搬到 block 中间，重新开始会重复或覆盖数据；必须从未完成地址继续。
5. Gray 码在 FIFO 指针同步中的作用是什么？  
   答：相邻计数只变一位，降低跨时钟域采样多 bit 同时变化造成错误比较的风险。


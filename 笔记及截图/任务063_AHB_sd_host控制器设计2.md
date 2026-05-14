# 任务63：AHB SD Host 控制器设计2

## 本章知识全景图

**这一讲解决 SD Host 数据通路的第一个硬问题：AHB 侧看见的是寄存器和 FIFO，SD 卡侧真正执行的是 CMD 线命令、DAT 线数据包、CRC、busy 和 stop command。**如果只按普通存储器的“地址加数据”直觉设计，写路径会漏掉 CRC status 和 busy，读路径会把等待周期当成 payload，4-bit 模式还会把 DAT lane 拼错。

| 层级 | 核心概念 | 本章要形成的判断 | RTL 设计落点 |
|---|---|---|---|
| 写操作链 | command、response、data block、CRC、busy、stop | 写完成不是 Host 发完数据，而是卡接受、忙结束、停止边界清楚 | write data FSM、status/error |
| 数据包边界 | start bit、payload、CRC、end bit | payload 只是 packet 的中间段，不能把整包当裸数据 | bit counter、CRC checker |
| 1-bit 总线 | DAT0 | 所有 bit 串行经过 DAT0 | 单线 shift register |
| 4-bit 总线 | DAT3-DAT0 | 每拍四条 lane 各传一个 bit，CRC 也按 lane 独立 | lane de-mux/mux、4 路 CRC |
| 状态模式 | identification mode、data transfer mode | 只有卡处在可传输状态，读写命令才有意义 | command legality、card state tracking |

最短学习路径：

```text
先看 block write 的 CMD/DAT 时间关系
  -> 再看 data packet 的 start/payload/CRC/end
  -> 再比较 DAT0 单线和 DAT3-DAT0 宽总线
  -> 最后把位宽、CRC、busy 和 stop command 映射到 data FSM
```

一个有用的比喻：SD 写数据像“先提交发货单，再把货送到仓库门口，最后等仓库验货和入库完成”。`CMD24/CMD25` 是发货单，data block 是货物，CRC status 是验货结果，DAT0 busy 是仓库正在入库。这个比喻的边界是：SD 协议不是人工流程，所有边界都由时钟、bit counter 和线方向严格定义。
同一个比喻还能解释读路径：`CMD17/CMD18` 像取货单，response 只说明仓库收到了取货请求，真正的货物要等 `NAC` 后从 DAT 线出来；Host 还要检查每箱货的封条 CRC。读写共同点是“命令成功不等于数据成功”，差异是 DAT 线驱动者相反：读时卡驱动，写时 Host 驱动。

## 1. 写操作由 command 打开，由 data block、CRC status 和 busy 收束

SD 写块不是 AHB 里“地址阶段 + 数据阶段”两拍就结束。Host 先在 CMD 线上发写命令，卡返回 response；随后 Host 在 DAT 线上发送 data block 和 CRC；卡检查 CRC 后返回 CRC status，并可能通过 DAT0 busy 表示内部 programming 尚未完成。多块写还需要 stop command 结束数据传输。

![多块写操作关系](<./screenshots/任务063_AHB_sd_host控制器设计2/task63_01m00s.jpg>)

视觉核验：
- 教学职责：这张图负责把写操作拆成 CMD 链和 DAT 链，说明写事务不是一条 AHB 写寄存器能闭合的事。
- 看图要点：先看 CMD 线上 command 和 response，再看 DAT 线上 data block、CRC、busy，最后看 multiple block write 由 stop command 收束。
- 漏看后果：控制器会在 data block 发完后提前置 done，软件继续发下一笔写时，卡可能仍在 busy 或刚刚拒收 CRC。

这一张图要转成 RTL 语言：

```text
command phase:
  send CMD24/CMD25 -> release CMD -> wait response

data phase:
  wait write window -> drive DAT -> send start/payload/CRC/end

card feedback:
  release DAT -> receive CRC status -> wait DAT0 busy release

multi-block stop:
  current block complete -> send CMD12 -> wait stop response -> return transfer-ready
```

失败信号要分开记：

| 失败信号 | 表面现象 | 优先排查 |
|---|---|---|
| command response timeout | CMD 发出后没有 R1/R1b | CMD 方向释放、NCR 计数、卡状态是否合法 |
| data CRC rejected | 卡返回 reject status | lane mapping、CRC16 输入顺序、payload bit order |
| busy timeout | DAT0 长时间低 | 卡 programming 未结束、stop 过早、写入地址/块错误 |
| stop 后仍有数据残留 | 多块写最后一块坏 | block 完整性和 CMD12 发起边界 |

## 2. data packet 的边界必须由 bit counter 识别

SD data packet 不是裸 payload。每个包都有 start bit、payload、CRC 和 end bit。Host 的 data FSM 必须知道当前处在包的哪一段，否则无法判断什么时候把 DAT 线采样进 FIFO，什么时候送入 CRC checker，什么时候结束一个 block。

![标准总线和宽总线数据包](<./screenshots/任务063_AHB_sd_host控制器设计2/task63_15m00s.jpg>)

视觉核验：
- 教学职责：这张图负责把 data packet 的空间结构讲清楚：标准总线只走 DAT0，宽总线走 DAT3-DAT0，但每条线都有 start、payload、CRC、end。
- 看图要点：不要只数绿色 payload 区，要把左侧 start bit、右侧 CRC 和 end bit 都纳入 block 边界；再看 4-bit 模式下四条 DAT 线并行推进。
- 漏看后果：bit counter 会只按 payload 长度结束，CRC 位被错当下一包 start，或者 end bit 检查被跳过。

从图上转成 RTL 时，packet 边界至少要产生四个内部事件：`data_start_seen`、`payload_cnt_done`、`crc_window_done`、`end_bit_ok`。这些事件分别喂给 FIFO 写使能、CRC checker、错误寄存器和 transaction done；不要用一个笼统的 `data_done` 直接跳过中间判定。
典型单块接收状态可以压成：

```text
WAIT_START:
  等待 DAT start bit

RECV_PAYLOAD:
  只在 payload 区把 bit 拼入 FIFO word

RECV_CRC:
  停止写 FIFO，进入 CRC 比较窗口

CHECK_END:
  end bit 必须为 1

DONE/ERROR:
  根据 CRC/end/timeout 上报状态
```

最容易错的是把 512 byte payload 当作整个 packet 长度。实际传输还包括 start、CRC 和 end；4-bit 模式下每条 lane 都有自己的 CRC 流，不能只在合并后的 32-bit FIFO word 上粗略算一次。

## 3. 4-bit 宽总线不是 4 个 byte 并排，而是 4 条 bit lane 交织

4-bit 模式每个 SD clock 采样四条 DAT 线，得到一个 4-bit slice。它不是把 DAT3 当成一个完整 byte 通道、DAT2 当成另一个 byte 通道，而是按 bit 位置交织。

| DAT 线 | 前几个 payload bit | 末尾几个 payload bit |
|---|---|---|
| DAT3 | b511、b507、b503、b499... | b7、b3 |
| DAT2 | b510、b506、b502、b498... | b6、b2 |
| DAT1 | b509、b505、b501、b497... | b5、b1 |
| DAT0 | b508、b504、b500、b496... | b4、b0 |

逐拍理解：

```text
第 1 拍：{DAT3,DAT2,DAT1,DAT0} = {b511,b510,b509,b508}
第 2 拍：{DAT3,DAT2,DAT1,DAT0} = {b507,b506,b505,b504}
...
最后一拍：{DAT3,DAT2,DAT1,DAT0} = {b3,b2,b1,b0}
```

可以把 4-bit DAT 总线理解成四条并排的检票通道：每个时钟同时放行四个相邻 bit，但它们仍属于同一个队列，最后要按原始顺序重新排回 payload。这个比喻的边界是，SD lane 的顺序由协议定义，不由你在 FIFO 里喜欢的 byte endian 决定。

## 4. CRC 在 4-bit 模式下按 lane 独立处理

标准总线只有 DAT0，因此只有一条数据流需要 CRC。宽总线有 DAT3-DAT0 四条数据流，每条 lane 的 payload 序列不同，CRC 也必须按 lane 对应计算或检查。图中每条 DAT 线后面都单独跟着 CRC 和 end bit，说明 CRC 不是全局 4-bit 合成后才算一个。

| 模式 | payload 采样 | CRC 处理 |
|---|---|---|
| 1-bit | 每拍采 DAT0 一位 | 一个 CRC checker/generator |
| 4-bit | 每拍采 DAT3-DAT0 四位 | 四路 CRC checker/generator 或等价并行逻辑 |

如果 CRC 只按 FIFO 合成数据计算，而没有对应到 SD lane 顺序，就可能出现 payload 拼接看似正确、CRC 却一直错。debug 时要同时看 lane mapping 和 CRC 输入序列：

```text
DAT3 payload stream -> CRC16_3
DAT2 payload stream -> CRC16_2
DAT1 payload stream -> CRC16_1
DAT0 payload stream -> CRC16_0
```

## 5. data FSM 要同时处理数据方向、位宽、CRC、busy 和 stop

SD Host 的 data path 至少要区分读和写：

| 场景 | DAT 方向 | Host 主要动作 | 完成判断 |
|---|---|---|---|
| 单块读 | card -> host | 等 start bit，采 payload，查 CRC/end | 一个 block 收完且 CRC 正确 |
| 单块写 | host -> card | 发送 start/payload/CRC/end，等待 CRC status 和 busy | CRC status 接受，busy 结束 |
| 多块读 | card -> host | 连续接收多个 block，必要时发 stop | block count 到达，CMD12 收束 |
| 多块写 | host -> card | 连续发送多个 block，监控每块 CRC status/busy | 当前块完整，stop command 完成，busy 释放 |

所以 data FSM 不能只由 `start_data` 和 `data_done` 两个状态构成。实际状态至少要覆盖：等待 data start、传 payload、传/收 CRC、检查 end、等待 busy、处理 stop、上报 done/error。

最小状态骨架：

```text
IDLE
  -> WAIT_DATA_START
  -> TRANSFER_PAYLOAD
  -> TRANSFER_OR_CHECK_CRC
  -> CHECK_END_OR_STATUS
  -> WAIT_BUSY_RELEASE
  -> STOP_OR_DONE
  -> ERROR
```

## 6. 状态模式决定当前能不能发数据命令

SD 卡在不同 operation mode 下允许的命令和行为不同。识别阶段主要完成复位、识别、分配地址和读取能力；数据传输阶段才执行块读写等数据操作。Host 如果在 card 尚未进入 transfer state 时发 block read/write，协议上就是非法或不可预期的。

![Card state 与 operation mode](<./screenshots/任务063_AHB_sd_host控制器设计2/task63_35m00s.jpg>)

视觉核验：
- 教学职责：这张图负责把 SD card state 分成识别相关阶段和 data transfer mode，给 command legality 提供边界。
- 看图要点：看 Inactive、Idle、Ready、Identification 与 Stand-by、Transfer、Sending-data、Receive-data、Programming、Disconnect 的分组；读写命令只应在合适的数据传输状态下出现。
- 漏看后果：Host 会在未选卡、未进入 transfer state 或卡正 programming 时发数据命令，表现为 response error、timeout 或 DAT 线长期无数据。

对 Host 设计来说，至少要维护一个软件或硬件可见的 card state 认识：

```text
识别阶段：
  低速 clock，发送初始化/识别命令，读取卡能力和地址

传输阶段：
  选择目标卡，配置位宽和速度，执行 block read/write

错误/断开：
  timeout、CRC error、非法命令或卡移除时退出当前数据流程
```

## 7. 最小闭环：设计一个 4-bit read data 接收器

本讲可以落成一个小练习：只做 4-bit 模式下单块读的接收路径。

```text
输入：
  sd_clk
  dat[3:0]
  bus_width = 4
  block_len = 512 byte

状态：
  WAIT_START -> RECV_PAYLOAD -> RECV_CRC -> CHECK_END -> DONE/ERROR

关键检查：
  WAIT_START：四条 DAT 线上是否出现合法 start
  RECV_PAYLOAD：按 {DAT3,DAT2,DAT1,DAT0} 拼回 payload 顺序
  RECV_CRC：每条 lane 独立校验
  CHECK_END：end bit 应为 1
```

可写断言口径：

```systemverilog
assert property (@(posedge sd_clk) recv_payload |-> !dat_oe);
assert property (@(posedge sd_clk) bus_width_4 && recv_payload |-> crc16_lane_en == 4''b1111);
assert property (@(posedge sd_clk) data_done |-> crc_ok && end_bit_ok);
```

这些断言把本讲的三条主线固定住：读路径必须释放 DAT，4-bit 模式必须四路 CRC 都参与，done 必须晚于 CRC 和 end bit。

失败信号：

| 失败 | 可能原因 |
|---|---|
| payload 位序反了 | 把 DAT0 当成最高位，或按 byte lane 拼接 |
| CRC 一直错 | lane mapping 和 CRC 输入顺序不一致 |
| block 长度不对 | bit counter 没把 1-bit/4-bit 模式区分开 |
| 读写方向冲突 | Host 没有在 read phase 释放 DAT 线 |
| 多块传输尾块坏 | `CMD12` 发出太早，当前 block 没完整结束 |

## 复习与自测

1. SD block write 为什么不能在 data block 发完后立刻认为完成？  
   答案：data block 后还有 CRC status 和 DAT0 busy。卡需要确认 block 是否通过 CRC，并完成内部 programming；busy 释放前 Host 不能认为写完成。

2. 标准总线和宽总线的数据包结构共同包含哪些部分？  
   答案：都有 start bit、payload、CRC、end bit。区别是标准总线只用 DAT0，宽总线用 DAT3-DAT0 四条线并行传 payload 和 CRC。

3. 4-bit 模式下，第一拍 DAT3-DAT0 分别承载哪些 bit？  
   答案：第一拍 `{DAT3,DAT2,DAT1,DAT0} = {b511,b510,b509,b508}`。

4. 为什么 4-bit 模式下 CRC 不能只按一个合并后的数据流粗略处理？  
   答案要点：每条 DAT lane 承载不同 bit 序列，CRC 也按 lane 对应。合并顺序错会导致 payload 看似能拼，但 CRC 校验失败。

5. data FSM 至少要处理哪些阶段？  
   答案要点：等待 start、传/收 payload、传/收 CRC、检查 end、接收 CRC status、等待 busy、处理 stop command、done/error 上报。

6. 为什么 card state 会影响 Host 是否能发 block read/write？  
   答案：block read/write 属于 data transfer mode。卡还在 identification、stand-by 或 programming 等不合适状态时，Host 直接发数据命令可能违反协议或得不到合法响应。



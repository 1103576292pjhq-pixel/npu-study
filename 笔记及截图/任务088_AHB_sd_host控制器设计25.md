# 任务88：AHB sd host控制器设计25

## 本章知识全景图

本节进入 SD Host 的双向异步 FIFO。这个 FIFO 连接 HCLK/DMA 域与 SDCLK/data 域，内部用 dual-port SRAM 存一个 block 的数据，用读写指针、Gray code、双拍同步和 empty/full 判断保证跨时钟域读写不出 underflow/overflow。

| 学习块 | 核心问题 | 结论 |
|---|---|---|
| FIFO 角色 | 为什么 SD Host 需要异步 FIFO | DMA 和 SD data path 在不同 clock domain，block 数据要跨域缓冲 |
| 顶层接口 | FIFO 两边各有哪些信号 | HB 侧和 SD 侧都有 read/write data、inc、empty/full |
| soft reset | 为什么 operation finish 后清 FIFO | 一个 block 事务结束后复位地址/指针，下一次从 0 重新开始 |
| 同步模块 | `sync_two_stage` 做什么 | 把对端指针或状态双拍同步到当前 clock 域 |
| 指针比较 | empty/full 为什么能在本域比较 | 对端指针同步后已属于当前域 |
| read empty | empty 怎么生成 | 本地读指针 Gray code 等于同步后的对端写指针 Gray code |
| Gray code | 为什么不用二进制指针跨域 | Gray code 每次只变 1 bit，降低多 bit 同步错误风险 |

最短学习路径：先认清 FIFO 有两个 clock domain，再看每侧读写指针如何跨域同步，最后理解 empty 是“读追上写”，full 是“写追上读一圈”。

![SD top 中的 FIFO instance](<./screenshots/任务088_AHB_sd_host控制器设计25/task88_01_sd_top_fifo_instance.jpg>)

视频核对：00:13-06:25，截图用于核对“SD top 中的 FIFO instance”这个知识点。

## 全视频地图

| 时间 | 视频内容 | 学习任务 |
|---|---|---|
| 00:13-06:25 | 从 `sd_top` 找 FIFO instance 和接口 | 建立双端口 FIFO 全局位置 |
| 07:06-12:05 | 追溯 operation finish 和 soft reset | 理解事务结束清空 FIFO 的原因 |
| 12:05-16:25 | `sd_sync_hb` 将 SD 域信号同步到 HB 域 | 掌握双拍同步 |
| 18:17-22:44 | FIFO 内部 reset、block length、sync stage、empty/full instance | 建立 FIFO 子模块结构 |
| 23:35-26:32 | 指针同步后才能比较 | 理解跨域指针比较的合法性 |
| 27:00-34:49 | `read_empty` interface、读指针二进制累加 | 理解读地址和读指针 |
| 34:49-37:10 | 二进制转 Gray code | 理解跨域指针编码 |
| 37:10-40:54 | empty 比较与 underflow 保护 | 理解保守 empty 的安全性 |

## 二轮重读：这个 FIFO 的本质是 CDC 协议，不是普通队列

本节最重要的判断是：FIFO 的“空”和“满”不是在同一个时钟域里自然出现的，它们是本地指针与同步过来的对端 Gray 指针比较出来的保守结论。只要把这个点吃透，`sync_two_stage`、Gray code、read empty、write full 就不再是零散代码。

| 线索 | 关键截图 | 必须看懂什么 |
|---|---|---|
| 系统位置 | `task88_01`、`task88_02` | FIFO 位于 HB/DMA 域和 SD data 域之间 |
| 清空策略 | `task88_03` | 本项目按一个 block 事务组织，operation finish 后清指针 |
| CDC 基础 | `task88_04`、`task88_05` | 对端状态/指针进入本域前必须双拍同步 |
| empty 生成 | `task88_07`、`task88_08`、`task88_09` | binary 用于地址，Gray 用于跨域，读追写就是 empty |

这一节要避免两个错误直觉：第一，不能把二进制指针直接跨域比较；第二，empty/full 的延迟不是 bug，而是 CDC 设计为了安全付出的吞吐代价。

## 截图证据链：每张图在证明什么

| 截图 | 证据职责 | 如果这张图看不懂，会漏掉什么 |
|---|---|---|
| `task88_01` | 顶层文件列表和 FIFO instance 位置 | FIFO 不是孤立模块，而是 SD Host 数据路径核心桥 |
| `task88_02` | data FSM 图与双向数据路径 | 读卡/写卡两种方向为何复用同一个 FIFO |
| `task88_03` | operation finish 到 soft reset | block 事务结束后为什么指针归零 |
| `task88_04` | SD 到 HB 同步模块 | 普通信号跨域也要同步，不只指针 |
| `task88_05` | 指针同步实例 | 对端 Gray 指针在比较前先进入本域 |
| `task88_06` | empty/full 子模块总览 | 每侧读写都有自己的空满判断 |
| `task88_07` | 读指针累加 | empty 时读指针不能继续前进 |
| `task88_08` | binary 到 Gray | 地址与跨域比较使用两套编码 |
| `task88_09` | empty 比较 | 读 Gray 等于同步写 Gray 即空 |


## 1. 异步 FIFO 的位置：DMA 和 SD data path 的跨域桥

SD Host 的数据方向有两种：

| 操作 | FIFO 数据流 |
|---|---|
| 读 SD 卡 | SD data receive shift 写 FIFO，DMA/HB 侧读 FIFO 搬到内存 |
| 写 SD 卡 | DMA/HB 侧写 FIFO，SD data send shift 读 FIFO 发到卡 |

这就是为什么课程里称它为“双向”的 FIFO。它不是同时双向传同一份数据，而是同一个 FIFO 结构可被两种方向复用。

![双 clock FIFO 接口](<./screenshots/任务088_AHB_sd_host控制器设计25/task88_02_dual_clock_fifo_interface.jpg>)

视频核对：01:46-06:25，截图用于核对“双 clock FIFO 接口”这个知识点。

HCLK 与 SDCLK 属于不同 clock domain，因此 FIFO 必须处理跨域指针、empty/full 和 reset/clear。

## 2. block length：这个 FIFO 只按一个 block 的容量判断满

这个 FIFO 的存储体可能大于当前 block，但功能上只想存一个 block。`block_length` 告诉 FIFO 当前 block 有多大；写满一个 block 后就可以认为 full。

例如 block length 为 512 byte，FIFO 数据宽度为 32 bit，即 4 byte，一个 block 需要 128 个 FIFO word。写到第 128 个 word 后就应认为当前 block full，而不是等整个物理 FIFO 深度都写满。

这个设计服务 SD data 协议：一个 block 准备好之后，另一侧就可以连续读走，不必等更大的 FIFO 全部填满。

## 3. operation finish 触发 soft reset：事务结束后指针归零

视频追溯了 `operation_finish` 的来源：写方向可能来自 `transfer_complete`，读方向可能来自 DMA end 的上升沿。事务结束后，对 FIFO 做 soft reset/clear，使读写指针回到初始状态。

![operation finish 到 soft reset](<./screenshots/任务088_AHB_sd_host控制器设计25/task88_03_operation_finish_soft_reset.jpg>)

视频核对：07:06-12:05，截图用于核对“operation finish 到 soft reset”这个知识点。

这样做的效果是：

```text
一个 block 事务完成
  -> FIFO 数据已被另一侧消耗或不再需要
  -> clear 指针/状态
  -> 下一次事务从地址 0 重新写、重新读
```

这不是通用 FIFO 必须这样做，而是这个 SD Host block buffer 的项目约束：它围绕一个 block 事务组织，事务结束后清空更简单。

## 4. 跨域同步：对端信号先打两拍，再在本域使用

`sd_sync_hb` 这类模块把 SDCLK 域的 soft reset、full、empty 等信号同步到 HCLK 域。基本结构是两级触发器。

![SD 到 HB 的同步](<./screenshots/任务088_AHB_sd_host控制器设计25/task88_04_sd_to_hb_sync.jpg>)

视频核对：12:05-16:25，截图用于核对“SD 到 HB 的同步”这个知识点。

`sync_two_stage` 的本质：

```verilog
stage1 <= async_input;
stage2 <= stage1;
sync_output <= stage2;
```

![双拍同步模块](<./screenshots/任务088_AHB_sd_host控制器设计25/task88_05_sync_two_stage.jpg>)

视频核对：18:17-22:44，截图用于核对“双拍同步模块”这个知识点。

双拍同步不能保证“没有延迟”，它保证的是亚稳态传播概率被大幅降低。同步后的信号会晚两拍左右，因此 empty/full 判断往往是保守的：宁可暂时认为不能读/写，也不要 underflow/overflow。

## 5. FIFO 顶层结构：四个指针同步，四个空满判断

这个 FIFO 有 HB 侧和 SD 侧，两边都可能读、写。因此会有：

| 子模块/逻辑 | 作用 |
|---|---|
| HB read empty | HB 侧读时判断空 |
| SD read empty | SD 侧读时判断空 |
| HB write full | HB 侧写时判断满 |
| SD write full | SD 侧写时判断满 |
| sync stage | 把对端读/写指针 Gray code 同步到本域 |
| memory | dual-port SRAM 存放 32 bit word |

![empty/full 子模块结构](<./screenshots/任务088_AHB_sd_host控制器设计25/task88_06_empty_full_instances.jpg>)

视频核对：22:44-23:35，截图用于核对“empty/full 子模块结构”这个知识点。

关键原则：在某个 clock 域里做比较时，两个参与比较的指针都必须已经属于这个域。本地指针天然属于本域；对端指针必须先同步过来。

## 6. read empty：读指针追上写指针就是空

`read_empty` 模块负责读侧指针和 empty 判断。读指针的二进制值既是读地址，也用于生成 Gray code 指针。

![读指针累加](<./screenshots/任务088_AHB_sd_host控制器设计25/task88_07_read_pointer_increment.jpg>)

视频核对：27:00-34:49，截图用于核对“读指针累加”这个知识点。

读指针更新条件：

```text
read_inc == 1 且 read_empty == 0
  -> read_pointer = read_pointer + 1
否则
  -> read_pointer 保持
```

如果 FIFO 已经 empty，再读会造成 underflow，所以 empty 时读指针必须不再前进。

## 7. Gray code：跨域传指针时减少多 bit 同步风险

二进制指针加 1 时可能多个 bit 同时翻转，例如 `0111 -> 1000`。如果直接跨域同步，对端可能采到混合状态。Gray code 相邻值只变化 1 bit，更适合跨域同步。

![二进制转 Gray code](<./screenshots/任务088_AHB_sd_host控制器设计25/task88_08_binary_to_gray.jpg>)

视频核对：34:49-37:10，截图用于核对“二进制转 Gray code”这个知识点。

常见转换：

```verilog
gray = binary ^ (binary >> 1);
```

本地会保留二进制指针用于地址，输出 Gray code 指针给对端同步和比较。这两个表示各有用途：binary 适合寻址和加法，Gray 适合跨域比较。

## 8. empty 判断：本地读 Gray 等于同步后的对端写 Gray

empty 条件：

```text
read_pointer_gray_next == synced_write_pointer_gray
```

当读指针追上写指针，说明已经没有可读数据。由于对端写指针同步有两拍延迟，本侧可能保守地提前或暂时认为 empty，即“实际可能已经有新数据，但同步过来前先不读”。

![empty 比较](<./screenshots/任务088_AHB_sd_host控制器设计25/task88_09_empty_compare.jpg>)

视频核对：37:10-40:54，截图用于核对“empty 比较”这个知识点。

这种保守性是可接受的，因为它牺牲一点吞吐，不会 underflow。异步 FIFO 的安全目标优先级是：

1. 不读不存在的数据。
2. 不写覆盖未读数据。
3. 在安全前提下尽量提高吞吐。

## 9. 读本节代码的检查线

| 检查线 | 关键问题 |
|---|---|
| clock domain | 当前模块比较发生在哪个 clock 下 |
| 指针形式 | binary 用于地址，Gray 用于跨域 |
| 同步方向 | 对端指针是否先双拍同步 |
| empty 条件 | read pointer 是否追上 write pointer |
| clear 条件 | operation finish 是否清掉事务内指针 |
| 保守延迟 | empty/full 由于同步延迟是否偏安全方向 |

这套异步 FIFO 方法是数字 IC 基础能力。AI 芯片中的 DMA buffer、NoC 异步桥、外设跨域、debug trace buffer 都会出现同类结构。

## 工程验证闭环

异步 FIFO 的验证不能只用同频同相 clock。必须让 HCLK 和 SDCLK 不同频、不同相，并观察同步延迟下 empty/full 是否偏安全。

| 验证对象 | 波形上应看到的正确结果 | 常见失败信号 | 定位方向 |
|---|---|---|---|
| pointer binary | 本域读写地址按 inc 顺序前进 | empty/full 后仍继续前进 | 查 inc 与 empty/full gate |
| pointer Gray | 每次只变化 1 bit | 相邻值多 bit 翻转 | 查 `gray = bin ^ (bin >> 1)` |
| sync stage | 对端 Gray 指针经过两级触发器后进入本域 | 直接使用异步对端指针 | 查 `sync_two_stage` 实例方向 |
| read empty | 读指针追上同步写指针时置 empty | empty 后继续读，发生 underflow | 查 empty 比较和 read pointer enable |
| soft reset | operation finish 后清当前事务指针 | 下一事务从旧地址开始 | 查 clear 来源和 reset 域同步 |
| 保守延迟 | 对端刚写入后，本域可能晚两拍才解除 empty | 为追吞吐绕过同步延迟 | 查是否有异步捷径 |

最小实验：HCLK 设 100 MHz，SDCLK 设非整数相关频率；写入 4 个 word 后读出 4 个 word，检查读出顺序、empty 拉起拍点、empty 后读指针是否保持。再改变 block length，确认 clear 后下一次事务从地址 0 开始。


## 自测题

1. 为什么这个 FIFO 需要异步设计？
2. `block_length` 在 FIFO 中有什么作用？
3. 为什么 operation finish 后要 soft reset FIFO？
4. 为什么跨域指针用 Gray code？
5. empty 判断为什么可能保守？
6. 保守 empty 为什么可接受？

## 自测参考答案与判分点

1. 答：HB/DMA 侧和 SD data 侧工作在不同 clock domain，数据和指针要跨域。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

2. 答：让 FIFO 按当前 block 大小判断 full，而不是必须写满物理深度。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

3. 答：一个 block 事务结束后，FIFO 内容不再需要，清指针后下一次事务可从地址 0 开始。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

4. 答：Gray code 相邻状态只变 1 bit，降低多 bit 同步采样错误风险。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

5. 答：对端写指针同步到本域有延迟，本域看到的是几拍前的写位置，可能实际已有新数据但暂时仍报空。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

6. 答：它最多降低吞吐，不会读不存在的数据，能避免 underflow。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。


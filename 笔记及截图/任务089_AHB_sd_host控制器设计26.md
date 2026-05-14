# 任务89：AHB sd host控制器设计26

## 本章知识全景图

本节继续异步 FIFO，重点从 read empty 转到 write full 和 memory。write full 的本质是写指针追上读指针一圈，必须用扩展指针区分“空”和“满”；由于本项目 FIFO 只存一个 block，还要用 `block_length` 调整满水位。最后课程把指针生成的地址接到 dual-port SRAM，说明 empty 不进 memory、full 必须进 write enable 的原因。

| 学习块 | 核心问题 | 结论 |
|---|---|---|
| underflow/overflow | 读空和写满分别是什么错误 | 空了还读是 underflow，满了还写是 overflow |
| 扩展指针位 | 为什么指针比真实地址多 1 bit | 区分读写指针相等时是空还是写追读一圈后的满 |
| block length | 为什么 full 不是物理 FIFO 全满 | 本 FIFO 只要求存一个 block，block 小时满水位提前 |
| Gray full 判断 | Gray code 怎么判断满 | 高两位取反、低位相等是常见异步 FIFO full 条件 |
| 子模块总览 | FIFO 内部由哪些部分组成 | sync、read_empty、write_full、memory |
| dual-port SRAM | memory 怎么承载双 clock 读写 | A 口给 SD 域，B 口给 HB 域，各自地址/使能 |
| empty 不进 memory | 为什么 memory 写要看 full，读不直接看 empty | 满后继续写会覆盖数据；空后读旧值但外部不用，风险较低 |

最短学习路径：先用“跑圈”理解满，再看 `block_length` 如何提前满水位，最后把 full/empty 和 SRAM 读写使能的必要性区分开。

![underflow 与 overflow](<./screenshots/任务089_AHB_sd_host控制器设计26/task89_01_underflow_overflow.jpg>)

视频核对：00:00-02:49，截图用于核对“underflow 与 overflow”这个知识点。

## 全视频地图

| 时间 | 视频内容 | 学习任务 |
|---|---|---|
| 00:00-02:49 | 回顾 read empty，引出 write full 和 underflow/overflow | 建立错误类型 |
| 02:49-07:42 | `write_full` interface 和扩展指针 | 理解满判断需要多一位 |
| 07:42-13:37 | 写指针累加、`block_length` 调整满水位 | 掌握 block 级 full |
| 14:17-16:54 | Gray code full 判断 | 记住高两位取反、低位相等 |
| 17:57-21:24 | FIFO 子模块与地址生成 | 理解 FIFO 是用 SRAM 加顺序地址实现 |
| 22:27-30:45 | dual-port SRAM interface | 映射 SD/HB 两个 port |
| 31:31-38:17 | memory 的 WEN/CEN/address 和 empty/full 使用差异 | 理解为什么 full 必须进入写使能 |
| 38:17-41:26 | FIFO 总结 | 整合输入、指针、SRAM 和 reset |

## 二轮重读：full 判断要同时满足“跑圈”和“block 水位”

上一节解决 read empty，这一节解决 write full。full 比 empty 更难，因为读写低位地址相等时可能是“空”，也可能是“写指针绕了一圈追上读指针”。所以 RTL 需要扩展指针位、Gray full 比较，以及本项目特有的 `block_length` 满水位修正。

| 线索 | 关键截图 | 必须看懂什么 |
|---|---|---|
| 错误边界 | `task89_01` | underflow 是读空，overflow 是写满还写 |
| 指针模型 | `task89_02`、`task89_03` | 指针比地址多 1 bit，用来区分空/满 |
| block 水位 | `task89_04` | 本项目只需要缓存一个 block，写够 block 就 full |
| memory 接口 | `task89_07`、`task89_08`、`task89_09` | SRAM 只负责存储，FIFO 顺序性由指针保证 |

不要把 full 公式当作死记。更稳的直觉是：写指针比读指针多跑了一圈，就满；在这个项目里，“一圈”可以被 block length 提前截短，因为 SD data path 只要求一个 block ready。

## 截图证据链：每张图在证明什么

| 截图 | 证据职责 | 如果这张图看不懂，会漏掉什么 |
|---|---|---|
| `task89_01` | read empty / write full 模块位置 | underflow/overflow 分别由谁防 |
| `task89_02` | write full 接口 | `wptr`、`waddr`、`rptr_s2_reg`、`blk_len` 的角色 |
| `task89_03` | 扩展指针与地址 | 为什么低位地址相同还不能直接判空或满 |
| `task89_04` | `blk_len` 调整水位 | block 小于 FIFO 深度时 full 要提前出现 |
| `task89_05` | Gray full 比较 | 高两位取反、低位相等的标准 full 判断 |
| `task89_06` | FIFO 子模块连接 | 指针同步、空满判断、memory 三者如何拼成 FIFO |
| `task89_07` | dual-port SRAM 文件 | FIFO 的存储实体是双口 SRAM |
| `task89_08` | SRAM WEN/CEN/address | full 必须 gate 写使能，防止覆盖数据 |
| `task89_09` | memory 读口不 gate empty | empty 时旧数据可留在 bus 上，只要外部不用 |


## 1. write full 的目标：避免 overflow

读侧只关心 empty，写侧只关心 full。写满后继续写，会覆盖还没被读走的数据，这就是 overflow。

![write full interface](<./screenshots/任务089_AHB_sd_host控制器设计26/task89_02_write_full_interface.jpg>)

视频核对：02:49-07:42，截图用于核对“write full interface”这个知识点。

`write_full` 模块的输入输出和 `read_empty` 对称：

| 信号 | 含义 |
|---|---|
| `write_inc` | 当前 clock 域写使能 |
| `write_addr` | 本域写地址，送到 memory |
| `write_ptr_gray` | 本域写指针 Gray code，送到对端同步 |
| `read_ptr_sync_gray` | 对端读指针同步到本域后的 Gray code |
| `block_length` | 当前 block 大小，用于提前 full |
| `write_full` | 写满标志 |

## 2. 指针多一位：相等不一定是空，也可能是绕了一圈

真实 memory 地址可能是 8 bit，能寻址 0-255；FIFO 指针常扩展成 9 bit。低 8 bit 作为 memory 地址，高 1 bit 用来区分是否绕圈。

![扩展一位指针](<./screenshots/任务089_AHB_sd_host控制器设计26/task89_03_extra_pointer_bit.jpg>)

视频核对：04:14-07:42，截图用于核对“扩展一位指针”这个知识点。

不扩展时，读写地址都等于 5 有两种可能：

| 场景 | 低位地址关系 | 真实含义 |
|---|---|---|
| 读追上写 | 相等 | FIFO 空 |
| 写绕一圈追上读 | 相等 | FIFO 满 |

扩展高位后：

```text
读指针 = 0_00000101
写指针 = 1_00000101
```

低位相同，高位不同，表示写指针比读指针多跑了一圈，FIFO 满。这个“多跑一圈”的直觉比死记公式更可靠。

## 3. `block_length` 调整满水位：只装一个 block 就算 full

本项目的 FIFO 不是等物理深度全满才 full，而是写够一个 block 就 full。代码里通过 `FIFO_DEPTH - block_length` 调整写指针比较用的临时值。

![block_length 调整 full 水位](<./screenshots/任务089_AHB_sd_host控制器设计26/task89_04_block_length_threshold.jpg>)

视频核对：07:42-13:37，截图用于核对“block_length 调整 full 水位”这个知识点。

例子：

| FIFO 物理深度 | block length | full 应在何时出现 |
|---:|---:|---|
| 256 word | 256 word | 写满 256 word |
| 256 word | 128 word | 写满 128 word |
| 256 word | 1 word | 写 1 word 后即 full |

本质上是把“写指针追上读指针一圈”的条件提前到“写满当前 block”。这符合 SD Host 的 block buffer 设计：另一侧只需要等一个完整 block ready，而不是等整个 FIFO 全容量 ready。

## 4. Gray code full 判断：高两位取反，低位相等

异步 FIFO full 的常见 Gray code 判断条件是：

```verilog
full_next =
    (wgray_next[ADDR:ADDR-1] == ~rgray_sync[ADDR:ADDR-1]) &&
    (wgray_next[ADDR-2:0] == rgray_sync[ADDR-2:0]);
```

![Gray full 比较](<./screenshots/任务089_AHB_sd_host控制器设计26/task89_05_gray_full_compare.jpg>)

视频核对：14:17-16:54，截图用于核对“Gray full 比较”这个知识点。

为什么是高两位而不是只看最高位？因为 Gray code 的高位翻转关系和二进制不完全一样。对使用 Gray 指针的异步 FIFO，full 判断要用这一套标准形式。

学习时可记住两条：

1. empty：读 Gray 等于同步后的写 Gray。
2. full：写 Gray 的高两位等于同步读 Gray 高两位取反，低位相等。

## 5. FIFO 子模块：指针、空满、SRAM 三部分拼起来

![FIFO 子模块总览](<./screenshots/任务089_AHB_sd_host控制器设计26/task89_06_fifo_submodules.jpg>)

视频核对：17:57-21:24，截图用于核对“FIFO 子模块总览”这个知识点。

异步 FIFO 顶层可以拆成：

| 部分 | 作用 |
|---|---|
| read_empty x2 | HB 读和 SD 读各一份 |
| write_full x2 | HB 写和 SD 写各一份 |
| sync_two_stage x4 | 两侧读/写 Gray 指针互相同步 |
| memory | dual-port SRAM，存真实 32 bit 数据 |

FIFO 的“先进先出”不是 SRAM 自带属性，而是读写地址按顺序累加实现的。SRAM 本身是随机访问存储器；FIFO 通过指针让写入和读出都按 0、1、2、3... 的顺序进行。

## 6. dual-port SRAM：A 口 SD 域，B 口 HB 域

memory 子模块内部使用 dual-port SRAM，一边接 SD clock，一边接 HCLK。

![dual-port SRAM](<./screenshots/任务089_AHB_sd_host控制器设计26/task89_07_dual_port_sram.jpg>)

视频核对：22:27-30:45，截图用于核对“dual-port SRAM”这个知识点。

| SRAM port | clock | 连接对象 |
|---|---|---|
| Port A | SD clock | SD receive 写 FIFO，SD send 读 FIFO |
| Port B | HCLK | DMA 写 FIFO，DMA 读 FIFO |

每个 port 都有地址、写使能、写数据、读数据。地址由对应方向的 read/write pointer 低位提供。写入时用 write address，读取时用 read address。

## 7. memory 写使能必须看 full，读出不必在 memory 内部看 empty

memory 的写使能通常类似：

```text
write_enable_to_sram = write_inc && !write_full
```

满了还写会覆盖未读数据，所以 full 必须挡住写。

![memory WEN/CEN/address](<./screenshots/任务089_AHB_sd_host控制器设计26/task89_08_memory_wen_cen_addr.jpg>)

视频核对：31:31-35:13，截图用于核对“memory WEN/CEN/address”这个知识点。

读侧为什么不一定把 empty 接进 memory？因为 empty 时 read pointer 不再前进，memory 可能还在输出旧地址上的旧数据，但外部读控制会根据 empty 不使用这个数据。旧数据留在 read data bus 上不会破坏 SRAM 内容。

![empty 不必进入 memory 读口](<./screenshots/任务089_AHB_sd_host控制器设计26/task89_09_empty_not_needed_in_memory.jpg>)

视频核对：35:13-38:17，截图用于核对“empty 不必进入 memory 读口”这个知识点。

区别在后果：

| 情况 | 如果不拦 | 后果 |
|---|---|---|
| full 后继续写 | 覆盖正确数据 | 破坏 FIFO 内容，严重 |
| empty 后继续读旧地址 | bus 上重复旧值 | 外部不用即可，SRAM 内容不变 |

当然，更清晰的系统设计仍然应让读控制源头遵守 empty，不发无效读；这里只是在解释 memory 内部为什么不必用 empty gate 住 SRAM 读口。

## 8. 本节完整数据路径

写入路径：

```text
write_inc && !full
  -> write pointer +1
  -> write address 送 SRAM
  -> write data 写入 SRAM
  -> write pointer Gray 输出给对端同步
```

读取路径：

```text
read_inc && !empty
  -> read pointer +1
  -> read address 送 SRAM
  -> read data 从 SRAM 输出
  -> read pointer Gray 输出给对端同步
```

空满判断路径：

```text
本地指针 Gray
  -> 输出到对端
  -> 对端 clock 双拍同步
  -> 与对端本地指针比较
  -> 得到 empty/full
```

这就是异步 FIFO 的核心闭环。

## 工程验证闭环

write full 的验证要故意逼近满水位，尤其要测 block length 小于物理 FIFO 深度的情况。只用最大 block 很容易漏掉水位修正 bug。

| 验证对象 | 波形上应看到的正确结果 | 常见失败信号 | 定位方向 |
|---|---|---|---|
| 扩展指针 | 低位给地址，高位标记绕圈 | 指针相等时 full/empty 混淆 | 查 `ADDRSIZE:0` 指针宽度 |
| `blk_len` 修正 | block 写满即 full，不等物理 FIFO 全满 | 小 block 继续写到物理满 | 查 `FIFO_DEPTH - blk_len` 或等效水位逻辑 |
| Gray full | full 条件使用同步读指针 Gray | 用未同步读指针比较 | 查 `rptr_s2_reg` 来源 |
| SRAM WEN | `write_inc && !full` 才写 | full 后 SRAM 仍写入 | 查 memory write enable gate |
| read old data | empty 时 read data bus 可保持旧值，但 read pointer 不前进 | 外部把 empty 时旧值当有效数据 | 查上层 read enable 与 empty 的关系 |

最小实验：物理 FIFO 深度保持不变，分别设置 block length 为 1 word、128 word、256 word；写到 full 后继续给 write_inc，确认写指针和 SRAM WEN 均不继续前进。再读出数据，确认顺序不被覆盖。


## 自测题

1. underflow 和 overflow 分别是什么？
2. FIFO 指针为什么要比实际地址多一位？
3. `block_length` 为什么影响 full？
4. Gray code full 的典型判断是什么？
5. 为什么 full 必须进入 SRAM 写使能？
6. empty 不进入 memory 读口为什么通常可接受？

## 自测参考答案与判分点

1. 答：empty 时继续读是 underflow；full 时继续写是 overflow。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

2. 答：多一位用于区分读写低位相等时是空，还是写指针绕一圈追上读指针导致满。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

3. 答：本项目 FIFO 只需要缓存一个 block，写满当前 block 就应 full，不必等物理 FIFO 全深度满。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

4. 答：写 Gray 的高两位等于同步读 Gray 高两位取反，低位相等。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

5. 答：full 后继续写会覆盖未读数据，破坏 FIFO 内容。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。

6. 答：empty 时读地址不前进，读出的旧值外部不会使用，SRAM 内容不被破坏。
   判分点：能说清核心机制、边界条件和工程后果；只背术语不给原因不得满分。


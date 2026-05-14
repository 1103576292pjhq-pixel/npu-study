# 任务59：AHB eFlash控制器设计13

## 本章知识全景图

这一讲进入 TB 文件夹，重点不是再讲 eFlash 存储体协议，而是讲如何用 testbench 站在 CPU/AHB 侧驱动整个 `flash_c_top`。前面的存储体小 TB 直接用 task 拉 `PROG/NVSTR/ERASE` 等阵列信号；这一讲的大 TB 通过 AHB write/read task 写寄存器、等待 `HREADY` 或 interrupt，再观察 page erase、program、readback 波形。

| 层级 | 核心概念 | 本章要形成的判断 | 直接用处 |
|---|---|---|---|
| TB 层级 | `flash_c_top_sim_tb` 包住完整 DUT | TB 模拟 CPU，不直接碰内部 eFlash 端口 | 系统级仿真 |
| AHB write task | 地址阶段 + 数据阶段 | `HADDR/HTRANS/HWRITE/HSEL` 与 `HWDATA` 分两拍 | 写寄存器 |
| AHB read task | 地址阶段 + 等 `HREADY` + 采样 `HRDATA` | read 不能固定等一拍，要看 ready | 读 memory/register |
| page erase sequence | 写 interrupt enable、page number、PEN | 擦除要等 done/interrupt 后清状态 | PE 验证 |
| program sequence | 写 program address、data、WEN | 每个 word 都要等完成后再发下一条 | program 验证 |
| 完整 TB 缺口 | compare/reference/pass-fail | 课程 TB 能驱动波形，但不是完备自检平台 | 后续改进 |
| 连续 program 作业 | 多 word 连续写 | 当前设计效率低，作业要求扩展 RTL/TB | 性能优化 |

最短学习路径：

```text
先分清直接驱动 storage body 的小 TB 和驱动 AHB 的大 TB
  -> 再读 AHB write/read task 的两阶段时序
  -> 再看 initial 中 page erase 和 program 的寄存器写序列
  -> 最后理解为什么当前单 word program 效率低，以及连续 program 要改哪些东西
```

## 全视频地图

| 时间段 | 视频内容 | 这一段真正要学会什么 |
|---|---|---|
| 00:00-04:50 | TB 文件夹、旧 `flash_tb`、task 与可综合 RTL 的区别 | TB task 适合造激励，不适合综合成硬件 |
| 04:50-10:40 | `flash_c_top_sim_tb` 实例化完整 DUT | 大 TB 站在 CPU/AHB 侧驱动设计 |
| 10:40-14:20 | TB 简化程度、DFT/test/write protect 设置 | 课程 TB 主要看波形，不是完整 compare 平台 |
| 14:20-18:50 | AHB write task | 写寄存器要区分地址阶段和数据阶段 |
| 19:00-22:10 | AHB read task | read 必须等 `HREADY` 拉高后采样 |
| 22:10-31:50 | 用 write task 完成 page erase | 写 page number、PEN、等 interrupt、W1C 清状态 |
| 33:00-39:30 | program 两个 word | 写地址、写数据、写 WEN，等待并清中断 |
| 39:30-45:40 | 连续 program 的效率问题和作业 | 当前设计每个 word 重走完整流程，连续 program 可显著省时间 |

## 视觉核对清单

| 视频时间段 | 截图 | 核对点 |
|---|---|---|
| 00:30-00:50 | `task59_00_tb_folder_and_flash_tb_00m40s.jpg` | TB 文件夹与旧存储体 `flash_tb` |
| 05:30-05:50 | `task59_01_flash_c_top_tb_instance_05m40s.jpg` | `flash_c_top_sim_tb` 实例化完整 DUT |
| 08:40-09:00 | `task59_02_hready_in_read_task_08m50s.jpg` | read task 等待 `HREADY` 的原因 |
| 14:50-15:10 | `task59_03_ahb_write_task_address_phase_15m00s.jpg` | AHB write task 地址阶段信号 |
| 19:20-19:40 | `task59_04_ahb_read_task_wait_hready_19m30s.jpg` | read task 地址阶段后等待 ready 再采样 |
| 27:40-28:00 | `task59_05_page_erase_sequence_27m50s.jpg` | page erase 的寄存器写序列 |
| 34:35-34:55 | `task59_06_program_address_data_sequence_34m45s.jpg` | program address/data/enable 配置序列 |
| 40:20-40:45 | `task59_07_continuous_program_assignment_40m30s.jpg` | 连续 program 作业与效率瓶颈 |

这组图要把 TB 看成一台协议波形发生器，而不是可综合控制器。`ahb_write_32` 和 `ahb_read_32` 像测试人员按步骤操作总线按钮：先摆地址控制，再给数据，再等待 ready，再记录返回值。它能造出 CPU 会发的事务，但不能替代 RTL 里的 FSM；真正的硬件行为仍要在 DUT 内部完成。

## 1. TB task 能造波形，但不能替代可综合控制器

前面的小 `flash_tb` 直接驱动 eFlash 存储体端口，用 task 和 delay 造出 program/read/erase 波形。这种方式适合验证模型和理解协议，但不能作为硬件实现。

![TB 文件夹与 flash_tb](<./screenshots/任务059_AHB_eflash控制器设计13/task59_00_tb_folder_and_flash_tb_00m40s.jpg>)

原因很简单：

```text
TB task:
  用 delay 和过程语句直接造激励
  只在仿真中运行
  不综合成硬件

flash_ctrl:
  用状态机和计数器生成同类波形
  可综合
  timing 可由寄存器配置
```

这也是验证学习里的重要分界：TB 可以“像软件一样”写激励，RTL 必须能变成触发器、组合逻辑和连线。

## 2. 大 TB 模拟 CPU，通过 AHB 驱动完整 DUT

`flash_c_top_sim_tb` 实例化的是完整 `flash_c_top`，而不是只实例化存储体。它站在 CPU 视角，通过 AHB 接口写寄存器、读数据和等待状态。

![flash_c_top TB instance](<./screenshots/任务059_AHB_eflash控制器设计13/task59_01_flash_c_top_tb_instance_05m40s.jpg>)

层级关系：

```text
flash_c_top_sim_tb
  -> flash_c_top
       -> flash_control_top
            -> flash_ahb_slave_if
            -> flash_ctrl
       -> flash_call
            -> flash0/flash1 storage body
```

这个 TB 的关键价值是验证“AHB 命令能不能真正穿过整个控制器，最后变成存储体动作”。

## 3. 课程 TB 是驱动型 TB，不是完整自检 TB

完整 TB 通常应包含：

```text
stimulus：产生输入
reference model：预期结果
monitor：采集 DUT 输出
scoreboard/compare：比较实际与预期
pass/fail：自动判定
```

本讲 TB 主要是教学驱动型。它能产生读写、擦除、中断等波形，但没有完整 reference compare，也没有最终自动 PASS/FAIL。因此它能帮助理解设计，却不能算工业级回归平台。

## 4. 功能模式下固定关闭 DFT、boot，并打开写保护允许路径

TB 中很多配置被固定：

```text
test_en = 0       -> 不走 DFT 直连路径
boot_in = 0       -> 不测 boot 路径
offset  = 固定值或无效
write_protect_n = 1 -> 允许正常写擦路径
HREADYIN = 1     -> 假设上游总线不阻塞
```

这些固定值说明本讲只验证 function mode 的基本读写擦，不覆盖 DFT、boot protect、异常响应等复杂场景。

## 5. AHB write task 必须体现地址阶段和数据阶段

AHB 写不是“地址和数据同一拍全有效”。它至少分成地址阶段和数据阶段。

![AHB write task](<./screenshots/任务059_AHB_eflash控制器设计13/task59_03_ahb_write_task_address_phase_15m00s.jpg>)

写 task 的核心动作：

```text
等待 HCLK 上升沿
地址阶段：
  HSIZE   = 2        // 32-bit word
  HTRANS  = NONSEQ
  HWRITE  = 1
  HSEL    = 1
  HREADYIN= 1
  HADDR   = addr
下一拍进入数据阶段：
  地址阶段控制撤掉或置 IDLE
  HWDATA  = data
再等一拍，让 slave 采到写数据
```

`HSEL` 在 TB 中直接置 1，是因为这里没有完整 SoC address decoder。真实 SoC 中，`HSEL` 应由总线译码逻辑产生。

## 6. AHB read task 必须等 `HREADY`，否则会读到无效数据

read task 和 write task 的差异在于 read data 来自 eFlash 存储体，需要等待 `READ_ACCESS` 完成。控制器会拉低 `HREADYOUT`，直到数据有效。

![HREADY in read task](<./screenshots/任务059_AHB_eflash控制器设计13/task59_02_hready_in_read_task_08m50s.jpg>)

![AHB read task wait HREADY](<./screenshots/任务059_AHB_eflash控制器设计13/task59_04_ahb_read_task_wait_hready_19m30s.jpg>)

读 task 的核心动作：

```text
地址阶段：
  HWRITE = 0
  HADDR  = addr
  HSEL   = 1
  HTRANS = NONSEQ
撤掉地址阶段控制
wait(HREADYOUT == 1)
在后续 HCLK 上升沿采样 HRDATA
```

如果固定等一拍就采样，短读可能偶然通过，真实 read access 一长就会读到旧值或无效值。

## 7. page erase 用多次 AHB write task 完成

page erase 本质上是写寄存器序列：

```text
写 interrupt enable，允许 PE done 产生中断
写 PE number，指定 flash 和 page
写 PEN=1，启动 page erase
等待 interrupt 或 done
写 status/interrupt clear，W1C 清除完成状态
```

![page erase sequence](<./screenshots/任务059_AHB_eflash控制器设计13/task59_05_page_erase_sequence_27m50s.jpg>)

`PE number` 的最高位可参与 flash0/flash1 选择，低位表示 page index。注意这里的“第 0 页”和后面 program 的“地址 0”不是同一层含义：一个是 page 粒度，一个是 word/byte 地址粒度。

## 8. program 一个 word 至少要写地址、数据和 enable

program 比 page erase 多一个数据寄存器，因此最小序列通常是：

```text
写 program interrupt enable
写 program address
写 program data
写 WEN/program_en = 1
等待 interrupt 或 done
写 1 清 status/interrupt
```

![program address/data sequence](<./screenshots/任务059_AHB_eflash控制器设计13/task59_06_program_address_data_sequence_34m45s.jpg>)

本讲示例写了两个 32-bit word：

```text
address 0x0 -> data 0x11223344
address 0x4 -> data 0xAABBCCDD
```

`0x4` 表示 byte address 加 4，也就是下一个 32-bit word。它不是第 4 个 word，而是 byte 地址中的第 4 个 byte 边界。

## 9. 每次写下一条 program 前必须等完成并清状态

任务58 已经强调 busy 期间写配置可能被屏蔽。任务59 在 TB 里体现为：每次 program 后都等待 interrupt，再清状态，之后才开始下一次 program。

正确节奏：

```text
写 address/data/WEN
等待 interrupt
必要时读取 status 确认完成类型
W1C 清状态
再写下一组 address/data/WEN
```

课程 TB 为了简化，清 interrupt 前不一定先读 status；更规范的做法是先读 status/error，再清除，避免把异常路径当成正常完成。

## 10. 当前设计单 word program 效率低，连续 program 是自然优化方向

当前设计每 program 一个 32-bit word，都要完整走：

```text
TNVS -> PROG_SETUP -> ADDR_SETUP -> PROG_PROC -> ADDR_HOLD -> PROG_HOLD -> TNVH -> RECOVER
```

这意味着每个 word 都要重复付出 `NVSTR setup`、`NVSTR hold`、program setup 等长时间开销。

![连续 program 作业](<./screenshots/任务059_AHB_eflash控制器设计13/task59_07_continuous_program_assignment_40m30s.jpg>)

而 eFlash 存储体本身支持连续 program 的思路：`NVSTR` 不必每个 word 都重新完整建立和恢复，中间切换地址/数据只需要满足较短 setup/hold 时间。课程布置的作业就是把 RTL 和 TB 改成支持至少 4 次连续 program。

可能需要改的内容：

```text
新增连续 program 的数据/地址寄存器或缓冲
新增 word count 或 burst count
修改 program FSM，让中间 word 不回到完整 recover 流程
修改 done/interrupt 产生时机，等一组连续 program 结束再通知
修改 TB task，支持输入连续写次数和多组 data/address
增加 readback 或 compare 验证每个 word 是否写对
```

这已经从“功能能跑”进入“性能和协议能力扩展”。对数字前端学习来说，这类作业比单纯看代码更能训练真实设计能力。

## 工程练习

1. 写出 AHB write task 的最小伪代码。

   合格答案：

   ```text
   wait posedge HCLK
   HADDR=addr, HWRITE=1, HTRANS=NONSEQ, HSIZE=word, HSEL=1, HREADYIN=1
   wait posedge HCLK
   撤掉地址阶段控制，驱动 HWDATA=data
   wait posedge HCLK
   task 结束或保持空闲
   ```

2. 给课程 TB 补一个最小 compare 方案。

   合格答案：每次 program 后把期望数据写入 reference memory；read task 返回 `HRDATA` 后与 reference memory 对应地址比较；若 mismatch，打印地址、expected、actual 并计 error；所有测试结束且 error 为 0 时打印 PASS，否则 FAIL。

3. 规划一个 4-word 连续 program 改造。

   合格答案应包含四类修改：RTL 增加多组 address/data 或小缓冲；FSM 增加连续 word 计数和中间 word 切换路径；done/interrupt 改成一组连续 program 完成后产生；TB 增加连续 program task，并读回 4 个 word 做 compare。

4. 给 page erase 和 program 增加自动判定。

   合格答案：page erase 后读回被擦页内若干 word，应等于模型规定的 erased value；program 后 readback 应等于 expected；若 mismatch，打印 `addr/expected/actual/current_state/status/error` 并计数。最终 error count 为 0 打印 PASS，否则 FAIL。TB 只打印波形不比较，最多算“能跑”，不算“能验收”。

## 常见误区和失败信号

| 误区 | 正确判断 | 失败信号 |
|---|---|---|
| TB task 可以直接作为 RTL 实现 | task 适合仿真激励，RTL 要可综合 | 综合失败 |
| AHB 写地址和数据同拍有效 | 写有地址阶段和数据阶段 | 寄存器写不到或写错 |
| read 固定等一拍即可 | read 要等 `HREADYOUT` 高 | 读到旧值或 X |
| 课程 TB 已经是完整验证平台 | 它主要驱动波形，没有完整 compare | 不能自动判定 pass/fail |
| page 0 和 address 0 是同一概念 | page 是擦除粒度，address 是读写粒度 | 擦写对象混淆 |
| 连续写 program 不需要改 FSM | 连续 program 要改寄存器、FSM、done 和 TB | 仍然每 word 付一次完整开销 |

## 复习与自测

1. 为什么 `flash_c_top_sim_tb` 要通过 AHB 驱动，而不是直接拉 `PROG/NVSTR`？

   答案：它要验证完整控制器从 CPU/AHB 寄存器访问到 eFlash 存储体控制信号的整条路径。

2. `HSIZE=2` 在 AHB write task 中表示什么？

   答案：表示 32-bit word 传输。

3. read task 为什么要 `wait(HREADYOUT == 1)`？

   答案：eFlash read access 需要等待存储体数据有效，控制器会用 `HREADYOUT` 告诉 AHB 什么时候可以采样。

4. page erase 最少需要写哪两类寄存器？

   答案：写 `PE number` 指定页，再写 `PEN/page erase enable` 启动。若要中断通知，还要配置 interrupt enable。

5. program 地址 0 和地址 4 的关系是什么？

   答案：它们是相邻的两个 32-bit word 的 byte address，地址 4 不是第 4 个 word，而是下一个 word 的起始 byte 地址。

6. 连续 program 为什么能提高效率？

   答案：它可以减少每个 word 都重复支付 `NVSTR setup/hold` 和恢复等长开销，中间只需较短的地址/数据切换时间。


# 任务55：AHB eFlash控制器设计9

## 本章知识全景图

这一讲把 `flash_ahb_slave_if.v` 后半段闭合起来：CPU 通过 AHB 写寄存器产生 program/page erase/read 命令，接口模块把 byte address 转成 eFlash word address，再用地址译码、boot 保护、状态寄存器、中断和读数据 mux 把软件动作翻译成硬件可执行的控制闭环。

| 层级 | 核心概念 | 本章要形成的判断 | 前端实现落点 |
|---|---|---|---|
| 地址转换 | byte address -> 32-bit word address | eFlash 按 word 操作，低 2 bit 不能送入存储阵列地址 | `flash_address_out[16:2]` |
| 寄存器命令 | program data/address、timing、page number、enable | 软件先配置参数，再置位命令位 | AHB register space |
| 地址译码 | register/main/information/flash0/flash1 | 读寄存器和读 eFlash memory 不是同一条路径 | select signals |
| read 握手 | read_en、HREADYOUT、read data mux | 读 eFlash 要等待，读寄存器不应触发存储体 | read path |
| boot 保护 | write protect、boot offset、boot region | 受保护区域的写擦要拒绝并上报 error | boot safety |
| 状态与中断 | done/error、W1C、interrupt enable | 硬件置位，软件写 1 清除，命令位必须结束生命周期 | driver visible status |

最短学习路径：

```text
先看 flash_address_out 为什么丢低两位
  -> 再看 program address/data 与 timing 寄存器如何由 AHB 写入
  -> 再看 register/main/information/flash0/flash1 如何译码
  -> 再看 read_en 为什么不额外打一拍
  -> 最后看 boot 保护、W1C status、中断和命令清除如何形成闭环
```

## 全视频地图

| 时间段 | 视频内容 | 这一段真正要学会什么 |
|---|---|---|
| 00:00-05:30 | `flash_address_out`、program data/address 寄存器 | AHB 地址和 eFlash word 地址不是同一个单位 |
| 05:30-09:30 | timing 寄存器、page number | timing 由寄存器配置，page number 还承担 flash0/flash1 选择 |
| 09:30-18:30 | register/memory/main/information/chip 译码、read_en | 读寄存器不启动 eFlash，读 memory 才进入存储体 read 流程 |
| 18:30-31:30 | boot protect、boot offset、非法写擦判断 | boot 区保护靠地址范围和写擦命令共同判断 |
| 31:30-38:30 | status W1C、中断使能 | done 和 interrupt 之间隔着 status 与 enable |
| 38:30-52:30 | HRDATA mux、boot offset、命令位清除 | 正常完成和错误拒绝都要让命令生命周期结束 |
| 52:30-58:00 | 汇总与收尾 | 软件视角必须读状态、清状态、再发下一条命令 |

## 视觉核对清单

| 视频时间段 | 截图 | 核对点 |
|---|---|---|
| 00:40-00:55 | `task55_00_flash_addr_out_00m45s.jpg` | `flash_address_out` 取 `[16:2]`，低 2 bit 被丢弃 |
| 02:35-02:55 | `task55_01_program_data_reg_02m45s.jpg` | AHB 写 program data 寄存器时，`HWDATA` 被锁存 |
| 06:45-07:05 | `task55_02_timing_config_regs_06m55s.jpg` | timing 配置寄存器写入后输出给 `flash_ctrl` |
| 08:00-08:20 | `task55_03_page_number_08m10s.jpg` | page number 高位承担 flash0/flash1 选择 |
| 13:10-13:30 | `task55_04_select_signals_13m20s.jpg` | register/main/information/chip select 的层级关系 |
| 16:20-16:40 | `task55_05_read_enable_16m30s.jpg` | read enable 只在 memory read 且非 busy 时产生 |
| 22:20-22:50 | `task55_06_boot_protect_select_22m35s.jpg` | boot write/PE select 如何识别保护区 |
| 32:20-32:50 | `task55_07_status_w1c_32m35s.jpg` | done 置位、软件写 1 清零 |
| 36:45-37:05 | `task55_08_interrupt_logic_36m55s.jpg` | status 与 interrupt enable 共同生成中断 |
| 41:15-41:45 | `task55_09_read_data_mux_41m30s.jpg` | 寄存器读和 memory read 的 `HRDATA` mux |
| 48:15-48:45 | `task55_10_offset_boot_protect_48m30s.jpg` | boot offset 在保护判断中继续使用 |
| 51:45-52:15 | `task55_11_enable_clear_52m00s.jpg` | 正常 done 和 boot error 都会清命令位 |

这组图要连成一条“前台受理到后台回执”的链路：AHB byte address 先被翻译成 eFlash word index，寄存器像工单栏保存 address/data/timing/page number，译码逻辑决定工单发往 register 还是 memory，boot 保护像门禁拦截非法工单，status 和 interrupt 是任务完成后的回执。只看单张图会觉得字段很多；连成链后，所有字段都在回答同一个问题：软件的一次写擦请求，硬件是否安全、准确、可诊断地执行。

## 1. `flash_address_out` 去掉低两位，因为 eFlash 按 32-bit word 操作

AHB `HADDR` 和 program address 寄存器通常是 byte address，而 eFlash 的 program/read 单位是 32-bit word。低两位只表示一个 word 内部的 byte 位置，对 eFlash 的 `XADR/YADR` 没有意义。

![flash_address_out](<./screenshots/任务055_AHB_eflash控制器设计9/task55_00_flash_addr_out_00m45s.jpg>)

图中 00:45 左右应关注 `flash_address_out` 对地址 `[16:2]` 的截取。它把 byte address 转成 15-bit word index，正好拆成 `XADR[9:0] + YADR[4:0]`。

换算关系：

```text
byte_address[1:0]  -> 32-bit word 内 byte 位置，eFlash word 操作不用
byte_address[16:2] -> 15-bit word index
word_index[14:5]   -> XADR
word_index[4:0]    -> YADR
```

如果把 byte address 原样送给 eFlash，软件写第 1 个 word，硬件可能按偏移 4 倍后的 word 解释，地址会整体错位。

## 2. program 地址和数据都先写寄存器，再启动命令

program 不是 AHB 当前写周期直接把 `HWDATA` 写入 eFlash。正确流程是 CPU 先写 program address 寄存器，再写 program data 寄存器，最后写 command/enable 寄存器启动 `program_en`。

![program data 寄存器](<./screenshots/任务055_AHB_eflash控制器设计9/task55_01_program_data_reg_02m45s.jpg>)

AHB 写有地址阶段和数据阶段：

```text
地址阶段：HADDR/HWRITE/HTRANS/HSEL 有效
数据阶段：HWDATA 有效
```

因此代码会把地址阶段的 decode 或控制打一拍，让它和下一拍的 `HWDATA` 对齐。不能随便再把 `HWDATA` 也打一拍，否则目标寄存器和数据会错开。

## 3. timing 寄存器是 `slave_if` 给 `flash_ctrl` 的时间合同

`NVSTR setup/hold`、recover、program setup、program process、read access、page erase time 等值都通过 AHB 寄存器配置。`flash_ahb_slave_if` 只负责保存这些值，真正使用这些时间值计数的是后面的 `flash_ctrl`。

![timing 配置寄存器](<./screenshots/任务055_AHB_eflash控制器设计9/task55_02_timing_config_regs_06m55s.jpg>)

有些短 timing 会合并在一个 32-bit 寄存器里，例如：

```text
program_addr_setup
program_addr_hold
program_hold
```

它们通常是几十 ns 级，字段位宽小，合并能减少寄存器地址占用。这里的关键不是背地址，而是记住职责分工：AHB interface 保存软件配置，control FSM 按配置产生真实波形。

## 4. page number 是 9 bit，因为还要选择 flash0 或 flash1

单片 eFlash 有 256 page，8 bit 可以表示页号。系统里有两片 eFlash，所以 page number 还需要额外 1 bit 选择存储体。

![page number](<./screenshots/任务055_AHB_eflash控制器设计9/task55_03_page_number_08m10s.jpg>)

page erase 的地址口径：

```text
pe_number[8]   -> flash chip select
pe_number[7:0] -> page index inside selected chip
```

page erase 不需要 `YADR`，因为它擦的是整页，不是页内某个 word。这里容易混淆的是：program/read 用 word address，page erase 用 page number。

## 5. 地址译码先分 register space，再分 eFlash memory space

本模块对外暴露的地址空间至少有两类：一类是控制寄存器，另一类是 eFlash memory。memory space 内部还继续分 main block、information block、flash0、flash1。

![地址选择信号](<./screenshots/任务055_AHB_eflash控制器设计9/task55_04_select_signals_13m20s.jpg>)

译码层次：

```text
先判断是否 register space
  -> 是：读写内部寄存器
  -> 否：判断是否 eFlash memory space
        -> 再判断 main/information
        -> 再判断 flash0/flash1
```

读寄存器时 `HRDATA` 来自内部寄存器，不应启动 eFlash read。读 eFlash memory 时才需要 `flash_read_en`，并等待存储体读数据有效。

## 6. `read_en` 用当前 AHB 读条件生成，避免白白多等一个周期

read 是总线在线等待路径。若 `read_en` 再打一拍，会让 `HREADYOUT` 多低一个 cycle，功能仍可能正确，但总线被无意义占用。

![read enable](<./screenshots/任务055_AHB_eflash控制器设计9/task55_05_read_enable_16m30s.jpg>)

判断口径：

```text
flash_read_en =
    HSEL
 && HREADYIN
 && HWRITE == 0
 && HTRANS 是有效传输
 && 访问 eFlash memory space
 && flash_busy == 0
```

这里的边界很重要：读寄存器不能触发 `flash_read_en`，否则一个普通状态寄存器读也会误进入 eFlash read 流程。

## 7. boot 保护不是提示，而是硬件拦截

boot 区可能是末尾 8K 或 16K，由 boot offset 和配置决定。写保护有效时，如果 program address 或 page number 命中 boot 区，硬件必须阻止真实 program/page erase，并记录 error。

![boot 保护选择](<./screenshots/任务055_AHB_eflash控制器设计9/task55_06_boot_protect_select_22m35s.jpg>)

保护判断链：

```text
write_protect 有效
  -> 判断 program address 是否命中 boot 区
  -> 或判断 page number 是否命中 boot 区
  -> 命中：产生 boot_write_down/boot_pe_down 或 error
  -> 不启动真实 flash program/page erase
```

这里的 `down` 不是“写擦成功”，而是“这条命令被硬件处理完了”。处理结果可能是正常完成，也可能是被保护逻辑拒绝。软件必须读 error 区分这两类结论。

## 8. status 使用硬件置位、软件写一清零

program done、page erase done 等状态由硬件置位。软件读到状态后，向对应 bit 写 1 清除，也就是 W1C。

![status W1C](<./screenshots/任务055_AHB_eflash控制器设计9/task55_07_status_w1c_32m35s.jpg>)

W1C 能让多个状态位独立清除：

```text
status = 2'b11
CPU 写 2'b01 -> 清 bit0，保留 bit1
CPU 写 2'b10 -> 清 bit1，保留 bit0
```

如果写 0 也清状态，软件做读改写时很容易误清另一个尚未处理的事件。

## 9. interrupt 由 status 和 interrupt enable 共同决定

中断不是 done 的简单直连。只有完成状态已经置位，并且对应 interrupt enable 为 1，才向外产生 interrupt。

![中断逻辑](<./screenshots/任务055_AHB_eflash控制器设计9/task55_08_interrupt_logic_36m55s.jpg>)

典型逻辑：

```text
interrupt =
    (program_done_status && program_done_int_en)
 || (pe_done_status      && pe_done_int_en);
```

error 是否走同一套中断条件取决于规格，但课程里最重要的判断是：`done/status` 表示事件存在，`interrupt_enable` 表示软件是否允许这个事件打断 CPU。

## 10. 读数据 mux 同时服务寄存器读和 memory 读

AHB `HRDATA` 可能来自内部寄存器，也可能来自 eFlash read data。地址译码决定返回哪一路。

![读数据 mux](<./screenshots/任务055_AHB_eflash控制器设计9/task55_09_read_data_mux_41m30s.jpg>)

组合逻辑必须覆盖所有分支：

```text
if register read:
    case register offset:
        return selected register
        default return invalid value
else:
    return flash_read_data
```

`case default` 和外层 `else` 都不能漏，否则组合逻辑可能推 latch。RTL 里很多 bug 不是来自公式错，而是来自“某个地址分支没有给值”。

## 11. boot offset 会在后续保护判断中继续使用

`boot_in` 有效时，offset 被锁存并参与 boot 读地址计算。boot 结束后，offset 仍要保留，因为后续写擦保护还需要知道哪段区域属于 boot 区。

![boot offset 与保护](<./screenshots/任务055_AHB_eflash控制器设计9/task55_10_offset_boot_protect_48m30s.jpg>)

这解释了为什么 boot 相关输入不是一次性临时信号。系统启动后，硬件仍需要用 offset 识别受保护区域，防止软件误写 boot 程序。

## 12. 命令位在 done 或 error 后都要清除

正常 program/PE 完成时要清除 `WEN/PEN`；boot 区非法写擦被拒绝时，也要清除对应命令位。否则软件看到命令还挂着，FSM 也可能被旧命令卡住。

![enable 清除](<./screenshots/任务055_AHB_eflash控制器设计9/task55_11_enable_clear_52m00s.jpg>)

命令清除条件：

```text
WEN 清除：
  flash_program_done || boot_write_down

PEN 清除：
  flash_pe_done || boot_pe_down
```

这和前面“软件置位、硬件清零”的命令寄存器模型一致。错误路径也是一条已结束的命令路径，不能因为没有真实写擦就不清命令位。

## 13. 最小闭环：boot 保护下的软件误写

```text
前提：write protect 有效，boot offset 已锁存。
CPU 配 program address，目标落在 boot 区。
CPU 写 WEN=1。
AHB interface 判断 boot write select=1。
不启动真实 program_en。
产生 boot write down 和 boot write error。
清除 WEN。
软件读 status/error，确认是保护错误。
软件写 1 清状态。
```

这条链体现了本文件后半段的核心：寄存器命令、地址判断、保护、状态、error 和清除必须形成闭环。

## 工程练习

1. 地址换算练习：把下面 byte address 转成 eFlash word index。

   | byte address | word index | 说明 |
   |---|---:|---|
   | `0x0000_0000` | `0x0000` | 第 0 个 32-bit word |
   | `0x0000_0004` | `0x0001` | 下一个 32-bit word |
   | `0x0000_0080` | `0x0020` | `0x80 / 4 = 0x20` |
   | `0x0001_0000` | `0x4000` | 低两位丢弃，等价右移 2 bit |

2. 写一次 program 的寄存器顺序。

   合格答案：写 program address，写 program data，写 `WEN/program_en`，等待 `program_done` 或 interrupt，读 status/error 判断结果，最后 W1C 清状态。address 和 data 先后可交换，但启动命令必须在二者都有效之后。

3. 解释 boot 区非法 program 的信号链。

   合格答案：`write_protect` 有效且 program address 命中 boot 区时，`slave_if` 不应向 `flash_ctrl` 发真实 program；它应产生 boot write error/down，清 `WEN`，让软件通过 status/error 看到这次命令被拒绝。

4. 给 boot 区误写补一组波形判定。

   合格答案：AHB register write 能命中 program address/data/enable；boot protect 判断为真；`program_en` 或真实 `PROG/NVSTR/ERASE` 不应进入有效操作；error/status 置位；`WEN` 被硬件清掉；W1C 后 error/status 和 interrupt 释放；同地址 readback 仍保持原数据。这个用例的重点不是“报错了”，而是“保护门真的挡住了后台控制脚”。

## 常见误区和失败信号

| 误区 | 正确判断 | 失败信号 |
|---|---|---|
| byte address 可直接送给 eFlash | 32-bit word 操作要去掉低两位 | 地址整体偏移 4 倍 |
| 读寄存器也应触发 flash read | 寄存器读在 interface 内完成 | 无谓等待或错误拉低 `HREADYOUT` |
| boot error 和正常 done 一样 | error 表示命令被拒绝，不是 IP 写擦成功 | 软件误判升级成功 |
| status 写 0 清除 | W1C 要写 1 清对应位 | 状态清不掉或误清 |
| interrupt 只看 done | 还要看 interrupt enable | 软件关闭中断后仍被打断 |
| 错误路径不用清命令位 | 错误也要结束命令生命周期 | `WEN/PEN` 卡住 |

## 复习与自测

1. 为什么 `flash_address_out` 要取 `[16:2]`？

   答案：AHB 是 byte address，eFlash 按 32-bit word 操作，低两位只表示 word 内 byte 位置，不属于 word index。

2. program data 寄存器什么时候更新？

   答案：当 AHB 写访问命中 program data 寄存器地址、且写条件有效时，用数据阶段的 `HWDATA` 更新。

3. 为什么 read enable 不宜打一拍？

   答案：read 会用 `HREADYOUT` 等待 eFlash 数据，打一拍会额外增加总线等待周期。

4. boot 区非法写擦为什么还会产生 down？

   答案：down 表示这次命令生命周期结束；非法路径被拒绝后也要通知软件并清命令位。

5. status 和 error 的关系是什么？

   答案：status 表示完成类事件，error 表示异常原因。软件要结合两者区分正常完成和保护拒绝。


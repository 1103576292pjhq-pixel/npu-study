# 任务56：AHB eFlash控制器设计10

## 本章知识全景图

这一讲从 `flash_ahb_slave_if.v` 切到 `flash_ctrl.v`。`slave_if` 面向 AHB 和软件寄存器，负责产生 `prog_en`、`pe_en`、`read_en`、选择信号、地址、数据和 timing 配置；`flash_ctrl` 面向 eFlash 存储体，负责把这些配置翻译成可综合的状态机、计数器和存储体控制波形。

| 层级 | 核心概念 | 本章要形成的判断 | 连接到后续 |
|---|---|---|---|
| 模块边界 | `slave_if` 与 `flash_ctrl` | 一个接 AHB，一个接 eFlash array protocol | top 级集成 |
| 地址维度 | `XADR=10`、`YADR=5` | main block 32K word 需要 15 bit 地址 | read/program address |
| 端口合同 | enable、select、address、data、timing | `flash_ctrl` 不重新译码 AHB，只消费上游结果 | FSM 输入 |
| 输出合同 | flash0/flash1 两套控制口 | 两片存储体结构相同，输出信号成对出现 | storage body |
| FSM 命名 | IDLE、READ、TNVS、ERASE、PROGRAM、TNVH、RECOVER | 状态名就是 eFlash 波形阶段 | 任务57 |
| hold/count/finish | 每个状态有停留条件 | timing 寄存器决定计数器终点 | 状态跳转 |

最短学习路径：

```text
先分清 slave_if 和 flash_ctrl 的职责
  -> 再把 main/info block 的地址位宽算清楚
  -> 再读 flash_ctrl 的输入输出端口
  -> 再看 FSM 状态名如何对应 eFlash 操作波形
  -> 最后理解 hold/count/finish 三件套如何让状态机停够时间
```

## 全视频地图

| 时间段 | 视频内容 | 这一段真正要学会什么 |
|---|---|---|
| 00:00-02:20 | 从 `slave_if` 过渡到 `flash_ctrl` | `flash_ctrl` 是可综合版的 flash 波形产生器 |
| 02:20-09:30 | module、parameter、`XADR/YADR`、main/info 地址规模 | 32K main 与 256 word information 的地址拆分不同 |
| 10:00-13:40 | 用 `grep` 追 `flash_clk/flash_rst_n` | 端口疑问要沿 top 连接回查，不能只看当前文件 |
| 14:20-21:10 | 输入输出端口：enable、select、address、data、timing、done/busy | `flash_ctrl` 的端口就是模块间合同 |
| 24:00-30:30 | 状态参数、读/擦/program 流程 | 状态列表就是 eFlash 时序图的 RTL 化 |
| 33:20-41:50 | `hold`、counter、`finish`、read 精确等待 | 每个状态靠计数停留，read 因为占 AHB 要更精确 |
| 41:50-46:50 | 三段式 FSM 第一、二段开头 | `current -> next` 和默认保持避免组合逻辑缺省 |

## 视觉核对清单

| 视频时间段 | 截图 | 核对点 |
|---|---|---|
| 00:35-00:55 | `task56_00_flash_control_role_00m45s.jpg` | `slave_if` 输出命令，`flash_ctrl` 生成存储体控制 |
| 03:40-04:05 | `task56_01_xadr_yadr_params_03m50s.jpg` | `XADR=10`、`YADR=5` 与 32K word 地址对应 |
| 14:25-14:50 | `task56_02_inputs_selects_14m35s.jpg` | enable、select、address、data、timing 输入分类 |
| 24:20-24:45 | `task56_03_fsm_states_24m30s.jpg` | 状态参数覆盖 read、erase、program 全路径 |
| 33:40-34:05 | `task56_04_hold_counter_33m50s.jpg` | `hold` 触发对应 counter 计数 |
| 40:05-40:30 | `task56_05_read_finish_precision_40m15s.jpg` | read finish 使用更精确的等待条件 |
| 45:20-45:45 | `task56_06_next_state_default_45m30s.jpg` | 组合逻辑段默认 `next_state=current_state` |

这组图的主线是“可综合的节拍发生器”。`slave_if` 像前台把工单参数整理好，`flash_ctrl` 像后场节拍器，按 datasheet 要求把一个命令拆成 setup、hold、process、recover。counter 不是简单延时，它是把 ns 级时序合同换算成 clock 周期后的尺子；FSM 则决定这把尺子在哪个阶段开始量、量到哪里结束。

## 1. `flash_ctrl` 是可综合的存储体波形发生器

`slave_if` 解决“CPU 怎么写寄存器”，`flash_ctrl` 解决“eFlash 存储体要看到什么波形”。课程前面用 TB task 直接造过 flash 波形，但 task 不能综合，所以正式 RTL 必须用 FSM 和 counter 实现。

![flash_ctrl 角色](<./screenshots/任务056_AHB_eflash控制器设计10/task56_00_flash_control_role_00m45s.jpg>)

这就是本讲的模块边界：

```text
AHB/CPU
  -> flash_ahb_slave_if：寄存器、地址译码、命令位、状态位
  -> flash_ctrl：状态机、计数器、flash0/flash1 控制信号
  -> eFlash storage body
```

学习时不要把两个文件混成一团。`slave_if` 里看到的是软件接口；`flash_ctrl` 里看到的是硬件协议执行。

## 2. `XADR=10`、`YADR=5` 来自 32K word 的地址拆分

main block 是 `32K x 32-bit`，也就是 32768 个 32-bit word。32768 等于 `2^15`，所以一个 main block 的 word index 需要 15 bit。

![XADR/YADR 参数](<./screenshots/任务056_AHB_eflash控制器设计10/task56_01_xadr_yadr_params_03m50s.jpg>)

拆分方式：

```text
main block:
  word_index[14:5] -> XADR[9:0]
  word_index[4:0]  -> YADR[4:0]

information block:
  只有 256 word，需要 8 bit
  YADR 仍取低 5 bit
  XADR 只需要低若干位，高位补 0
```

`XADR/YADR` 不是随便起的端口名，它们对应 eFlash 存储体内部行列寻址。前端写 RTL 时，地址位宽要先从存储容量反推，否则后面读写、page erase 和 boot protect 都会错。

## 3. 用 `grep` 追端口来源，是读 RTL 的基本动作

课程中对 `flash_clk`、`flash_rst_n` 的来源提出疑问，然后用 `grep` 沿文件连接去查。结果是它们在 `flash_control_top` 里接到了 `HCLK/HRESETn`。

这一步的学习价值不在命令本身，而在 RTL 阅读方法：

```text
当前文件只告诉你“我有这个端口”
top 级连接才告诉你“这个端口实际接到哪里”
```

如果设计层级更多，应限制搜索范围，例如只搜 `*.v` 或指定目录。芯片项目里文件量很大，盲目全盘搜索会浪费大量时间。

## 4. 输入端口分成命令、选择、地址、数据和 timing 五类

`flash_ctrl` 的输入不是 AHB 原始信号，而是 `slave_if` 已经整理好的控制信息。

![输入选择信号](<./screenshots/任务056_AHB_eflash控制器设计10/task56_02_inputs_selects_14m35s.jpg>)

| 输入类别 | 代表信号 | 作用 |
|---|---|---|
| 命令 | `prog_en`、`pe_en`、`read_en` | 决定状态机从 IDLE 进入哪条路径 |
| block/chip 选择 | `rd_infr0_sel`、`prog_mainarea1_sel` 等 | 决定访问 flash0/flash1、main/information |
| 地址 | `flash_addr`、`pe_num` | program/read 用 word address，page erase 用 page number |
| 数据 | `flash_wdata`、flash0/1 read data | program 写入数据，read 返回数据 |
| timing | `nvstr_set_timing`、`read_access_timing` 等 | 决定每个状态停留多少拍 |

`flash_ctrl` 不应该再去判断 `HADDR` 是否命中某个寄存器。那是 `slave_if` 的工作。边界清楚，后续顶层连线和 debug 才不会乱。

## 5. 输出端口分成存储体控制和软件可见反馈

`flash_ctrl` 的输出有两组：一组给 eFlash 存储体，一组回给 `slave_if`。

给存储体的信号通常成对出现：

```text
flash0_xaddr / flash1_xaddr
flash0_yaddr / flash1_yaddr
flash0_xe    / flash1_xe
flash0_ye    / flash1_ye
flash0_se    / flash1_se
flash0_ifren / flash1_ifren
flash0_prog  / flash1_prog
flash0_nvstr / flash1_nvstr
flash0_erase / flash1_erase
flash0_mass  / flash1_mass
flash0_din   / flash1_din
```

回给 `slave_if` 的信号包括：

```text
flash_prog_done
flash_pe_done
flash_busy
flash_rdata
hready_flag
```

`done` 用来置状态位和产生中断，`busy` 用来禁止新的写配置，`hready_flag` 用来在 read access 期间拉低 AHB ready。

## 6. 状态参数就是 eFlash 波形阶段的名字

![FSM 状态参数](<./screenshots/任务056_AHB_eflash控制器设计10/task56_03_fsm_states_24m30s.jpg>)

`flash_ctrl` 的状态名不是抽象标签，它们直接对应 eFlash 操作波形：

| 操作 | 状态路径 | 含义 |
|---|---|---|
| read | `IDLE -> READ_ACCESS -> IDLE` | 拉起读选择，等待 read access time |
| page erase | `IDLE -> TNVS -> PE_ERASE -> TNVH -> RECOVER -> IDLE` | 先建立 NVSTR，再擦除，再保持，再恢复 |
| program | `IDLE -> TNVS -> PROG_SETUP -> ADDR_SETUP -> PROG_PROC -> ADDR_HOLD -> PROG_HOLD -> TNVH -> RECOVER -> IDLE` | 按 program 时序逐段拉控制信号 |

状态机写得长，不等于逻辑复杂。很多行只是把 eFlash datasheet 中的时序阶段变成 RTL 状态名。

## 7. `hold/counter/finish` 是状态停留时间的三件套

每个需要停留的状态都会形成类似结构：

```text
state_hold  = (current_state == 某状态)
state_count = state_hold ? state_count + 1 : 0
state_finish = (state_count == configured_timing)
```

![hold 与 counter](<./screenshots/任务056_AHB_eflash控制器设计10/task56_04_hold_counter_33m50s.jpg>)

`hold` 只是 wire 命名，不会额外增加寄存器资源。它的价值是可读性：读者一眼知道某个 counter 是由哪个状态驱动。

`finish` 的来源是计数器达到 timing 配置值。timing 配置值来自 AHB 寄存器，所以软件可以改变每段 eFlash 波形持续时间。

## 8. read 的 finish 要更精确，因为它占着 AHB 总线

多数长时间操作，例如 program 和 page erase，不需要一直拉低 AHB `HREADYOUT`。CPU 发出命令后可以去做别的事，等 done 或 interrupt。

read 不一样。read access 期间总线在等数据，如果多等一个 cycle，就是白白占住 AHB。

![read finish 精确等待](<./screenshots/任务056_AHB_eflash控制器设计10/task56_05_read_finish_precision_40m15s.jpg>)

因此 read 的 finish 常用类似：

```text
rd_finish_pre = (addr_access_cnt == read_access_timing - 1)
```

功能上多等一拍也可能读到正确数据，但效率变差。读路径的时序优化优先级高，是因为它直接影响总线占用。

## 9. 三段式 FSM 的默认保持是组合逻辑保护

![next state 默认保持](<./screenshots/任务056_AHB_eflash控制器设计10/task56_06_next_state_default_45m30s.jpg>)

组合逻辑段开头先写：

```verilog
flash_next_st = flash_current_st;
```

这句不是多余。它保证如果 `case` 分支没有命中，状态不会变成未知，也避免组合逻辑缺省造成 latch 或不可预期跳转。

三段式 FSM 的节奏是：

```text
第一段：时序寄存 current_state 和各类寄存器
第二段：组合逻辑计算 next_state
第三段：组合逻辑或 next 逻辑计算各输出下一值
```

任务56 讲到第二段开头，任务57 会继续把状态跳转和输出控制展开。

## 工程练习

1. 从容量反推地址位宽。

   合格答案：main block 有 `32K = 32768 = 2^15` 个 32-bit word，所以需要 15 bit word index；若低 5 bit 给 `YADR`，高 10 bit 给 `XADR`。information block 只有 256 word，需要 8 bit，仍可低 5 bit 给 `YADR`，其余给 `XADR` 低位，高位补 0。

2. 写出三条状态路径。

   合格答案：read 是 `IDLE -> READ_ACCESS -> IDLE`；page erase 是 `IDLE -> TNVS -> PE_ERASE -> TNVH -> RECOVER -> IDLE`；program 是 `IDLE -> TNVS -> PROG_SETUP -> ADDR_SETUP -> PROG_PROC -> ADDR_HOLD -> PROG_HOLD -> TNVH -> RECOVER -> IDLE`。

3. 判断 `read_access_timing - 1` 是否一定必要。

   合格答案：功能上不一定，晚一拍通常也能读到稳定数据；但 read 会拉低 `HREADYOUT` 占住 AHB，总线效率敏感，所以 read path 更值得精确到少等一拍。program/erase 是后台长操作，不必为每个长 timing 都额外引入减法逻辑。

4. 给三条路径列出最小波形检查组。

   合格答案：read 看 `read_en`、`flash_current_st`、`rd_access_cnt/rd_finish`、`XE/YE/SE/IFREN`、`DOUT`、`hready_flag`；program 看 `prog_en`、program address/data、`TNVS/PROG_SETUP/PROG_PROC/PROG_HOLD/RECOVER`、`PROG/NVSTR/DIN`、`program_done`；page erase 看 `pe_en`、page number、`TNVS/PE_ERASE/TNVH/RECOVER`、`ERASE/NVSTR`、`pe_done`。三组都要确认回到 IDLE 后 command 清除。

## 常见误区和失败信号

| 误区 | 正确判断 | 失败信号 |
|---|---|---|
| `flash_ctrl` 还要解析 AHB 地址 | 地址译码已在 `slave_if` 完成 | 控制模块边界混乱 |
| TB task 可以直接搬进 RTL | task 通常不可综合，RTL 要用 FSM/counter | 综合失败或不可配置 |
| 32K 地址需要 16 bit | 32K word 是 `2^15`，需要 15 bit | X/Y 地址多一位或少一位 |
| 两片 flash 可同时选中 | 正常读写应最多选中一片 | read data mux 冲突 |
| 所有 finish 都应减一 | 长时间状态不必为一拍多加减法器，read 例外 | read 多占总线 |
| `next_state=current_state` 可省略 | 它是组合逻辑默认保持 | case 漏分支导致 latch 或 X |

## 复习与自测

1. `flash_ahb_slave_if` 和 `flash_ctrl` 的分工是什么？

   答案：`slave_if` 面向 AHB 和软件寄存器，产生整理后的命令、地址、选择、timing 和状态寄存器逻辑；`flash_ctrl` 面向 eFlash 存储体，用 FSM 和计数器产生真实控制波形。

2. 为什么 main block 的地址可拆成 `XADR[9:0] + YADR[4:0]`？

   答案：main block 有 32K 个 word，需 15 bit 地址；课程中用高 10 bit 做 XADR，低 5 bit 做 YADR。

3. `hold` 信号会不会增加寄存器资源？

   答案：通常不会。它只是 wire 级命名，用来表达某个状态是否正在保持。

4. 为什么 read finish 比 program/erase finish 更讲究精确？

   答案：read 期间 AHB `HREADYOUT` 被拉低，总线被占住；program/erase 可后台执行，CPU 等 done 或 interrupt。

5. `flash_prog_done = rcv_finish && prog_en` 的含义是什么？

   答案：recover 状态结束且本次命令原本是 program，才说明 program 命令完成；同一个 recover 状态也可能服务 page erase。


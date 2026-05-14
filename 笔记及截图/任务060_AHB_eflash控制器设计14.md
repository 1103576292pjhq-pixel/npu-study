# 任务60：AHB eflash控制器设计14

## 本章知识全景图

**章节标题：任务60：AHB eFlash 控制器设计14。** 这一讲不是再讲某一段 eFlash 功能代码，而是把 eFlash controller 的仿真工程真正跑起来，并用 Verdi 从 `sim` 目录、filelist、FSDB、层级树、顶层端口和波形一路追到可验证的设计边界。学完这一讲，要能回答一个工程问题：看到一份 AHB eFlash 控制器工程时，怎样判断“仿真跑过、层级连对、波形能证明 RTL 行为”。

| 层级 | 核心对象 | 本章要形成的判断 | 如果判断错了会怎样 |
|---|---|---|---|
| 仿真入口 | `sim/Makefile`、`rtl.list`、`tb.list`、`model.list`、`verdi.f` | `sim` 目录是编译、运行、看波形的入口 | 找不到文件来源，误把模型、RTL、TB 混成一类 |
| 编译产物 | `simv`、`simv.daidir`、`flash.fsdb`、`sim.log` | FSDB 是后续 Verdi 调试的证据，不只是一个输出文件 | 只能说“跑过”，不能定位信号和层级 |
| Verdi 层级 | `flashc_top_sim_tb`、`U_flashc_top_sim`、`U_flash_ctrl_top`、`U_flash_ahb_slave_if`、`U_flash_ctrl` | 层级树是从 testbench 追到真实 RTL 的地图 | 波形里拉错层级，看到的值不能证明设计行为 |
| 顶层端口 | AHB 输入、AHB 输出、eFlash 控制辅助输入、中断输出 | 顶层边界说明 CPU 侧和 eFlash 侧怎样被包装 | 不知道哪些信号由 TB 驱动，哪些由 DUT 产生 |
| 波形闭环 | AHB task -> slave interface -> flash control -> 状态/计数/输出 | 仿真不是截图展示，而是要证明一条访问链路走通 | 看很多信号却没有结论，debug 失去方向 |

最短学习路径：

```text
先确认 sim 目录和 filelist
  -> 再用 make / FSDB 证明仿真有结果
  -> 打开 Verdi 后沿层级树找到 testbench 和 DUT
  -> 读 flashc_top_sim 的 AHB 端口边界
  -> 把 TB task、AHB 总线、slave_if、flash_ctrl 和波形连成一条证据链
```

## 全视频地图

| 时间段 | 教学块 | 必须学会的动作 |
|---|---|---|
| 00:50-05:00 | `sim` 目录、Makefile、filelist、clean | 从仿真入口确认编译对象和旧产物是否清理 |
| 08:50-12:00 | Verdi 打开 FSDB 与层级树 | 分清 TB、DUT、controller top、slave_if、flash_ctrl、模型 |
| 14:45-18:00 | `flashc_top_sim` 顶层端口 | 把 AHB 输入、输出反馈、interrupt 和 testbench task 对上 |
| 18:00-35:00 | AHB task 与寄存器写读路径 | 追地址阶段、数据阶段、寄存器选择、command latch |
| 39:40-44:50 | timing 寄存器、FSM、counter、done | 用源码和波形共同证明 eFlash 操作完成条件 |

## 视觉核对清单

本讲的四张图像要按“证据链”读，而不是按截图顺序收藏。`sim` 目录是证据仓库，Verdi 层级树是地图，顶层端口是边界合同，波形窗口是现场记录。四者合在一起，才能把一句“仿真通过了”拆成可检查的工程结论。

| 时间段 | 截图 | 看图要点 | 漏看后果 |
|---|---|---|---|
| 01:00 | `task60_01m00s.jpg` | `Makefile/rtl.list/tb.list/model.list/verdi.f/flash.fsdb` 共同定义仿真入口 | 不知道当前 FSDB 是哪一版 RTL 跑出来的 |
| 09:00 | `task60_09m00s.jpg` | Verdi 同时展示 TB、DUT、controller、模型和标准单元 | 在 `tsmc18.v` 等模型文件里迷路 |
| 15:00 | `task60_15m00s.jpg` | 顶层端口把 AHB task 与真实 DUT 边界连接起来 | 只看 task 名，不知道它驱动了哪些引脚 |
| 40:00 | `task60_40m00s.jpg` | timing 寄存器、FSM state、counter 和 finish 要放在一组波形里看 | 只看到状态跳转，却无法证明等待时间正确 |

## 1. `sim` 目录是仿真证据的中心，不是临时垃圾目录

仿真工程的入口通常不在 `rtl/`，而在 `sim/`。`rtl/` 存设计代码，`tb/` 存 testbench，`model/` 存 eFlash 行为模型或工艺模型；真正把这些文件按顺序编译起来的是 `sim` 里的 Makefile 和 filelist。读 eFlash 控制器时，先站到 `sim` 目录看文件，比直接冲进某个 `.v` 文件更稳。

![sim 目录与仿真产物](<./screenshots/任务060_AHB_eflash控制器设计14/task60_01m00s.jpg>)

看图要点：00:50-01:20，终端停在 `~/design/ahb_flashc/sim`，能看到 `flash.fsdb`、`Makefile`、`model.list`、`rtl.list`、`tb.list`、`verdi.f`、`simv`、`simv.daidir` 等文件；随后执行 `make clean` 清理 `simv`、`.vpd`、`.daidir`、日志和 FSDB。

这一屏要抓住三个证据点：

| 文件或目录 | 作用 | 调试时怎么用 |
|---|---|---|
| `Makefile` | 固定 VCS 编译、运行、dump 波形、打开 Verdi 的命令 | 先读它，知道仿真命令到底用了哪些选项 |
| `rtl.list` | 列出设计 RTL 文件 | RTL 编译缺文件、顺序错、module 找不到时先查它 |
| `tb.list` | 列出 testbench 文件 | AHB task、clock/reset、初始激励一般从这里进入 |
| `model.list` | 列出 eFlash 行为模型、工艺单元或外部模型 | 不要把厂家模型当成自己要改的 RTL |
| `flash.fsdb` | Verdi 波形数据库 | 后续所有“看到信号变化”的证据都从这里来 |
| `sim.log` | 仿真日志 | 查编译警告、运行结束、`$finish` 位置和错误信息 |

`make clean` 不是形式动作。旧的 `flash.fsdb` 或 `simv` 可能来自上一版 RTL，继续用它看波形会把旧结果误当成新设计结果。最小可靠流程是：先清理，再编译运行，再打开新生成的 FSDB。

## 2. Verdi 里先看层级，再看信号

波形调试的第一步不是把所有信号拖进去，而是确认层级树正确展开。课程里打开 FSDB 后，左侧能看到 testbench 和设计实例：`flashc_top_sim_tb` 包住 `U_flashc_top_sim`，后者再包 `U_flash_core` 和 `U_flash_ctrl_top`；`U_flash_ctrl_top` 里面继续包含 `U_flash_ahb_slave_if` 和 `U_flash_ctrl`。这条链路说明 testbench 没有直接驱动 eFlash 内部引脚，而是通过 AHB 顶层边界进入控制器。

![Verdi 层级与模型文件](<./screenshots/任务060_AHB_eflash控制器设计14/task60_09m00s.jpg>)

看图要点：08:50-09:20，Verdi 打开 `flash.fsdb`，左侧层级树同时出现 `flashc_top_sim_tb`、`U_flash_ctrl_top`、`U_flash_ahb_slave_if`；源码窗显示 `model/tsmc18.v` 里的标准单元 `BENCX1`，波形窗还未加入有效信号。

这里有一个常见坑：Verdi 会同时显示 RTL、testbench、行为模型、标准单元模型。看到 `tsmc18.v` 或 `BENCX1` 不代表你正在读 eFlash 控制器功能代码，它可能只是编译进来的工艺单元模型。真正要追 controller 行为，应从 `flashc_top_sim_tb -> U_flashc_top_sim -> U_flash_ctrl_top` 往下走，而不是在标准单元库里迷路。

建议把层级按职责记成下面这张表：

| 层级 | 它是谁 | 主要问题 |
|---|---|---|
| `flashc_top_sim_tb` | 最外层 testbench | clock/reset 怎么产生，AHB task 怎么发起 |
| `U_flashc_top_sim` | 仿真包装顶层 | AHB 信号、DFT/boot/protect 信号如何进入 DUT |
| `U_flash_core` | eFlash 存储体或模型侧 | read/program/erase 最终是否进入模型 |
| `U_flash_ctrl_top` | controller 顶层 | slave interface 和 control FSM 如何相连 |
| `U_flash_ahb_slave_if` | AHB 寄存器与地址译码层 | CPU 写寄存器如何变成控制命令 |
| `U_flash_ctrl` | eFlash 时序控制 FSM | 命令如何变成 `XE/YE/SE/NVSTR/PROG/ERASE` 等波形 |

## 3. 顶层端口告诉你 testbench 能控制什么、DUT 会返回什么

`flashc_top_sim.v` 的端口列表把工程边界讲得很清楚：输入侧有 `hclk`、`hresetn`、`hsel`、`hready_in`、`hwrite`、`hsize`、`htrans`、`hburst`、`hwdata`、`haddr`，这些就是 testbench 模拟 CPU/AHB master 发出的信号；输出侧有 `hready_out`、`hresp`、`hrdata`、`flash_ctrl_int`，这些是 controller 返回给 AHB 或软件侧观察的结果。

![flashc_top_sim 顶层端口](<./screenshots/任务060_AHB_eflash控制器设计14/task60_15m00s.jpg>)

看图要点：14:45-15:20，Verdi 打开 `rtl/flashc_top_sim.v`，源码窗列出 AHB 输入 `hclk/hresetn/hsel/hready_in/hwrite/hsize/htrans/hburst/hwdata/haddr`，输出 `hready_out/hresp/hrdata/flash_ctrl_int`，左侧层级显示 testbench 里有 `ahb_read_32`、`ahb_write_32`、`page_erase`、`prog_word`、`read_word` 等 task。

这一屏的学习价值在于把“TB task”和“真实端口”连起来：

```text
ahb_write_32(addr, data)
  -> 驱动 HSEL/HWRITE/HTRANS/HADDR/HWDATA/HSIZE
  -> slave_if 在有效 AHB 传输下锁存地址和写数据
  -> register select 命中某个配置寄存器
  -> flash_ctrl 收到 program / page erase / read 命令
  -> hready_out / hrdata / interrupt 把结果返回给 TB
```

所以后面看波形时，不要只问“某个寄存器有没有变”。更完整的问题是：这一拍 AHB 访问是否有效、地址是否译码到目标寄存器、写数据是否被正确锁存、命令是否被 `flash_ctrl` 接收、完成后有没有 ready 或 interrupt 反馈。

## 4. AHB eFlash 调试要从“访问链路”而不是“单个信号”开始

这一讲后半段的关键动作，是把源码窗和波形窗绑定起来：选中 `flash_ahb_slave_if` 或 `flash_ctrl` 里的某段代码，再在下面看相应寄存器和计数器的波形。这样做的目的不是展示 Verdi 操作，而是建立 RTL 判断方式：每个寄存器写入、每个 timing 计数、每个 done 条件，都必须能在波形中找到对应时刻。

![寄存器写入与 timing 波形](<./screenshots/任务060_AHB_eflash控制器设计14/task60_40m00s.jpg>)

看图要点：39:40-40:20，Verdi 停在 `flash_ahb_slave_if.v` 的寄存器写入代码，复位默认值包括 `prog_proc_timing`、`rd_acces_timing`、`pe_timing`、`pe_num_r`、`int_en_r` 等；波形窗显示 `flash_current_st`、`flash_next_st`、`tnvs_finish`、`pe_finish`、`nvstr_set_cnt`、`nvstr_hold_cnt`、`nvstr_hold_timing` 等信号。

这一屏说明两个层次：

1. `flash_ahb_slave_if` 负责保存软件可配置的 timing、命令、地址和中断寄存器。
2. `flash_ctrl` 根据这些寄存器值走状态机，并用计数器判断 `setup/hold/process/recover` 等阶段是否结束。

如果只看源码，容易把这些 timing 当成普通常量；如果只看波形，容易不知道某个计数器为什么数到这个值。正确读法是：在源码里找到寄存器默认值或写入路径，在波形里看该值是否被计数器作为终止条件使用。

## 5. 最小闭环：从清理仿真到证明一次访问

这一讲可以整理成一条可复现的 eFlash 仿真闭环：

```text
1. 进入 sim 目录，确认 Makefile、rtl.list、tb.list、model.list、verdi.f 都存在。
2. 执行 clean，清掉旧的 simv、FSDB 和日志。
3. 重新编译运行，确认日志中没有 fatal error，且生成新的 flash.fsdb。
4. 用 Verdi 打开 FSDB，沿层级进入 flashc_top_sim_tb/U_flashc_top_sim/U_flash_ctrl_top。
5. 找到 testbench task，例如 ahb_write_32、page_erase、prog_word、read_word。
6. 把 AHB 有效访问、地址、写数据、寄存器选择、flash_ctrl 状态、timing 计数和 done/interrupt 放到同一组波形里。
7. 用源码解释每个关键波形变化，而不是只凭视觉猜测。
```

判断通过的最低标准：

| 检查项 | 通过信号 | 失败信号 |
|---|---|---|
| 仿真入口 | clean 后重新生成 `simv` 和 `flash.fsdb` | 还在看旧 FSDB 或日志里有 fatal |
| 层级完整 | TB、DUT、slave_if、flash_ctrl、model 都能展开 | module 找不到，层级被优化掉或 filelist 缺文件 |
| AHB 访问 | `hsel/hready_in/htrans/hwrite/haddr/hwdata` 时序符合 AHB | 地址阶段和数据阶段错位 |
| 寄存器写入 | `haddr_r[7:0]` 命中后目标寄存器更新 | 写到了错误寄存器或 `ahb_wr_en` 没有拉起 |
| 控制状态 | `flash_current_st` 按命令进入 read/program/erase 路径 | 一直停在 idle 或跳到非法状态 |
| 完成反馈 | timing counter 到终值后 done/ready/int 出现 | counter 到了但 done 不起，或 done 过早 |

## 6. 本讲和前面 eFlash 课程的连接

任务47-55 主要回答“eFlash 控制器为什么这样设计”：容量、地址拆分、register space、timing、boot protect、interrupt、read/program/page erase 的 RTL 结构。任务60开始回答“设计写完后怎样证明它真的工作”：通过 testbench 驱动 AHB，通过 VCS 产生 FSDB，通过 Verdi 把 AHB 访问、寄存器更新、状态机和 eFlash 模型连成证据链。

这也是数字前端工程的关键习惯：RTL 不是写完就结束，能在波形里解释清楚“输入怎样变成输出”，才算具备基本交付能力。

## 工程练习

1. 给一次寄存器写失败建立排查顺序。

   合格答案：先看 `ahb_write_32` 是否在地址阶段拉起 `hsel/hwrite/htrans/haddr`；再看数据阶段 `hwdata` 是否与上一拍地址对齐；再看 `haddr_r[7:0]`、`reg_sel`、`ahb_wr_en` 是否命中；最后看目标寄存器赋值条件和 `flash_busy` 是否屏蔽写入。

2. 给一次 program 完成建立波形证据。

   合格答案：同一组波形至少放入 `program_en`、program address/data、`flash_current_st/flash_next_st`、主要 timing counter、`PROG/NVSTR/XE/YE/SE`、`program_done`、status、interrupt。它像查一张物流轨迹：下单、分拣、运输、签收、回执都要有时间戳。

3. 判断 `make clean` 后没有新 FSDB 应该查哪里。

   合格答案：先查 Makefile 目标是否实际运行 VCS；再查 `rtl.list/tb.list/model.list` 路径；再查 compile log 是否有 fatal；最后查仿真是否提前 `$finish` 或未打开 dump。不能拿旧 `flash.fsdb` 继续证明新 RTL。

## 常见误区和失败信号

| 误区 | 正确判断 | 失败信号 |
|---|---|---|
| 有 FSDB 就代表当前 RTL 跑过 | FSDB 必须由 clean 后本次编译运行生成 | 文件时间早于 RTL 修改或日志不匹配 |
| Verdi 打开哪个源码就说明在看功能逻辑 | Verdi 可能打开模型或标准单元库 | 长时间停在 `tsmc18.v`，没有追到 DUT 层级 |
| AHB write task 一拍完成 | AHB 写有地址阶段和数据阶段 | 目标寄存器写入旧数据或空数据 |
| 只看 `flash_current_st` 就能判断正确 | 还要看 counter、finish、控制脚和 done/status | 状态跳了但等待时间或输出脚错误 |
| read、program、erase 调试路径一样 | read 占用 AHB ready，program/erase 多为后台操作 | 总线等待策略和 status 策略混淆 |

## 自测题

1. 为什么看 eFlash 控制器仿真时要先进入 `sim` 目录，而不是直接打开 `rtl/flash_ctrl.v`？
2. `rtl.list`、`tb.list`、`model.list` 三者分别解决什么问题？
3. Verdi 中看到 `model/tsmc18.v` 和标准单元名时，为什么不能马上认为那就是 eFlash 控制器功能代码？
4. `flashc_top_sim.v` 顶层里哪些端口属于 AHB 输入？哪些端口属于 AHB 输出或反馈？
5. 如果一次 `ahb_write_32` 没有更新目标寄存器，你应该按什么顺序查？
6. 为什么 timing 寄存器必须同时看源码默认值/写入路径和波形计数器？

## 自测参考答案与判分点

1. `sim` 目录保存编译入口、filelist、运行脚本和 FSDB 产物；先看它才能知道 RTL、TB、模型怎样被组合起来。只看单个 RTL 文件无法证明仿真是否按当前工程配置跑过。
2. `rtl.list` 列设计 RTL，`tb.list` 列 testbench，`model.list` 列 eFlash 行为模型、工艺模型或外部模型。三者缺一都会导致仿真对象不完整。
3. `tsmc18.v` 属于工艺/标准单元模型，可能只是被编译进工程的依赖文件。功能行为应沿 `flashc_top_sim_tb -> U_flashc_top_sim -> U_flash_ctrl_top -> U_flash_ahb_slave_if/U_flash_ctrl` 追。
4. AHB 输入包括 `hclk`、`hresetn`、`hsel`、`hready_in`、`hwrite`、`hsize`、`htrans`、`hburst`、`hwdata`、`haddr`；输出/反馈包括 `hready_out`、`hresp`、`hrdata`、`flash_ctrl_int`。
5. 先查 AHB 地址阶段是否有效，再查数据阶段 `HWDATA` 是否对齐，再查 `haddr_r[7:0]` 是否命中目标寄存器，再查 `ahb_wr_en/reg_sel`，最后查目标寄存器赋值条件。
6. 源码告诉你计数器终值来自哪个寄存器，波形证明计数器是否真的按该终值停止并产生 finish/done。两者缺一，无法判断是配置错、计数错还是观察点错。


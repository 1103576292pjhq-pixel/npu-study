# 任务27：Clock_Swith_Glitch_Free_Verdi 调试方法和 Makefile

## 本章知识全景图

时钟切换不能按普通数据 mux 思维处理，因为任何窄脉冲都可能被后级寄存器当成真实边沿。本章主线是：先理解 glitch-free clock switch 的硬件约束，再用 Makefile 固化仿真入口，用 FSDB 保存证据，用 Verdi 把 source、schematic 和 waveform 串起来证明切换窗口没有窄脉冲和重叠使能。

| 层级 | 核心对象 | 本章要掌握的判断 |
|---|---|---|
| 时钟结构 | `clk0`、`clk1`、`sel`、clock gating cell | 不能直接 `sel ? clk1 : clk0` 切时钟 |
| 安全切换 | old enable、new enable、gated clock、`clk_out` | 旧时钟先退出，新时钟再进入，两个 gated clock 不重叠 |
| 仿真入口 | filelist、Makefile、VCS、FSDB | 命令可复现，波形可重新打开 |
| Verdi debug | source、schematic、waveform、annotation | 从选择信号一路追到内部 enable 和最终输出 |
| TB 质量 | dump、finish、forever delay、reference model | 随机激励必须能比较结果，死循环必须有时间推进 |

最短学习路径：

```text
直接 mux 时钟为什么会产生 glitch
  -> glitch-free switch 如何先关旧时钟、再开新时钟
  -> Makefile 如何跑 compile / sim / wave
  -> Verdi 如何用 source + schematic + waveform 定位信号链
  -> 用切换窗口证明 clk_out 无窄脉冲
```

## 全视频地图

| 时间段 | 教学块 | 必须保留的知识动作 |
|---|---|---|
| 00:00-12:00 | clock switch glitch 问题 | 看到 `sel` 切换时输出可能被截成半截周期或额外边沿 |
| 12:00-25:00 | glitch-free 结构和 Verdi 波形 | 追踪 `sel -> enable -> gated clock -> clk_out` |
| 25:00-38:00 | Makefile、FSDB、Verdi 打开方式 | 建立 `compile -> sim -> fsdb -> verdi` 的可复现闭环 |
| 38:00-55:00 | source / schematic / waveform 交叉调试 | 从源码跳结构，从结构跳波形，用游标定位切换窗口 |
| 55:00-72:00 | TB 写法、随机激励和 reference model | `forever` 必须推进时间；随机输入必须有 expected 比较 |
| 72:00-91:44 | 代码风格和后续课程衔接 | 把 debug 方法收束成工程检查表 |

## 1. 时钟 mux 的危险：毛刺会变成真实触发边沿

普通数据 mux 出现短毛刺，很多时候会被下一级时序逻辑隔离；时钟 mux 出现短毛刺，后级寄存器可能直接把它当成一个 clock edge。时钟线上的错误不是“值错一下”，而是“系统多走了一拍”。

![clock switch 问题波形](<./screenshots/任务027_Clock_Swith_Glitch_Free_Verdi调试方法和Makefile/clock_switch_problem_200s.jpg>)

截图核对：视频 03:00-05:00，画面应展示两路时钟和选择信号切换；重点看 `sel` 变化后 `clk_out` 是否出现半截高电平或额外跳变。

直接写法的风险：

```systemverilog
assign clk_out = sel ? clk1 : clk0;
```

问题在于：

- `sel` 不一定同步于 `clk0` 或 `clk1`。
- `clk0` 与 `clk1` 可能频率、相位不同。
- mux 的组合延迟会把选择变化和时钟电平变化叠在一起。
- 输出窄脉冲可能被时钟树和触发器当成真实边沿。

所以 clock switch 的设计目标不是“最后选到正确时钟”，而是“切换过程中不产生多余边沿”。

## 2. Glitch-free 的本质：旧时钟退出，新时钟进入

安全时钟切换要把“选择”拆成两个动作：先让旧时钟的 enable 在安全相位撤销，再让新时钟的 enable 在安全相位打开。两个 gated clock 不能重叠，也不能在高电平中间硬切。

这就是时钟版的 break-before-make 开关：先断开旧通路，进入一个可控空窗，再接上新通路。普通数据 mux 像切换水龙头，短暂水花可能还能被后级过滤；时钟 mux 像切换节拍器，多敲一下或少敲半下都会让后级寄存器多走一步或误走一步。

```text
sel 改变
  -> 旧时钟域确认退出
  -> 输出进入可控空窗
  -> 新时钟域确认进入
  -> clk_out 跟随新时钟
```

这类结构通常会使用同步打拍链和 clock gating cell。gating cell 的意义是让 enable 在安全相位被采样，而不是让 enable 直接闯入持续翻转的时钟路径。

## 3. TB 先生成 FSDB：没有波形文件就没有 Verdi 证据

Verdi 调试依赖可打开的波形。testbench 里要明确 dump 文件、dump 层次和仿真结束条件。

![FSDB dump 语句](<./screenshots/任务027_Clock_Swith_Glitch_Free_Verdi调试方法和Makefile/fsdb_dump_testbench_640s.jpg>)

截图核对：视频 10:00-12:00，画面应看到 `$fsdbDumpfile` 和 `$fsdbDumpvars`；检查文件名和 dump 层次是否覆盖内部信号。

常见写法：

```systemverilog
initial begin
    $fsdbDumpfile("glitch_free_tb.fsdb");
    $fsdbDumpvars(0, glitch_free_tb);
end
```

仿真结束也要可控：

```systemverilog
initial begin
    repeat (1000) @(posedge clk0);
    $finish;
end
```

如果 FSDB 没生成，先查三件事：dump 语句是否编译进 TB；仿真是否真的跑到触发切换；`$finish` 是否太早。

## 4. Makefile 是可复现实验入口，不是可选装饰

EDA 调试不能靠手敲记忆。Makefile 把编译、仿真、清理和打开波形固定成命令入口，让别人能在同一目录重跑出同一类结果。

![Makefile 与仿真产物](<./screenshots/任务027_Clock_Swith_Glitch_Free_Verdi调试方法和Makefile/makefile_verdi_flow_945s.jpg>)

截图核对：视频 15:00-17:00，画面应能对应 `make compile`、`make sim`、FSDB 产物和 Verdi 打开流程。

最小 Makefile 形态：

```makefile
compile:
	vcs -full64 -sverilog -f filelist.f -debug_access+all -l compile.log

sim:
	./simv -l sim.log

wave:
	verdi -f filelist.f -ssf glitch_free_tb.fsdb &

clean:
	rm -rf simv* csrc *.log *.fsdb novas.*
```

配套的最小 `filelist.f` 至少要让 VCS 和 Verdi 看到同一批 RTL/TB：

```text
./rtl/glitch_free_clk_switch.sv
./rtl/cell_clock_gating.sv
./tb/glitch_free_tb.sv
```

TB 顶层、FSDB 名称和 Makefile 要一致。例如 TB 里写 `$fsdbDumpfile("glitch_free_tb.fsdb")`，`wave` target 就不要再打开另一个文件名。`sim` 最好依赖 `compile`，这样从干净目录执行 `make sim` 不会因为缺 `simv` 直接失败。

验收不是“我能打开 Verdi”，而是：

```text
make compile
make sim
make wave
```

三步能从干净目录跑到可读波形。

## 5. Verdi 调试要交叉定位，不是只看最终波形

Verdi 的强项是把源码、结构图和波形联动起来。clock switch debug 不能只把 `clk_out` 加进波形窗口；必须沿着选择信号追到内部 enable、gating cell 和 gated clock。

![Verdi 打开波形](<./screenshots/任务027_Clock_Swith_Glitch_Free_Verdi调试方法和Makefile/verdi_open_wave_1240s.jpg>)

截图核对：视频 20:00-22:00，画面应显示 Verdi 打开 source 和 waveform；检查源码层次和 FSDB 是否匹配。

推荐追踪顺序：

```text
sel / cgm_sel
  -> old_enable
  -> new_enable
  -> gated_clk_old
  -> gated_clk_new
  -> clk_out
```

如果某个内部 enable 看不到，先查 `$fsdbDumpvars` 层次、VCS debug 选项、优化是否把信号折叠掉，再查 filelist 是否读到正确 RTL。

## 6. Schematic 看结构，waveform 看时序

Schematic 用来确认硬件连接，waveform 用来确认时间关系。二者缺一不可：结构图正确不代表时序切换安全；波形看起来对也不代表内部结构没有偷接第一拍或组合路径。

![Verdi schematic 中的 clock gating](<./screenshots/任务027_Clock_Swith_Glitch_Free_Verdi调试方法和Makefile/verdi_schematic_clock_gating_1420s.jpg>)

截图核对：视频 23:00-27:00，画面应展示 clock gating cell 和寄存器链；重点找 enable 是否经过对应时钟域同步后才控制 gating cell。

检查结构时看四点：

| 检查点 | 通过标准 |
|---|---|
| 选择信号同步 | `sel` 不直接驱动时钟 mux |
| 旧 enable 退出 | 旧时钟 gated enable 先稳定撤销 |
| 新 enable 进入 | 新时钟 gated enable 在安全相位打开 |
| 输出汇合 | gated clocks 汇合到 `clk_out` 时没有组合选择毛刺 |

## 7. 波形判定：把游标放到切换窗口

判断 glitch-free 不能只看切换前后 `clk_out` 最终跟随哪一路时钟。要把游标放到 `sel` 翻转附近，放大切换窗口，检查是否出现重叠使能、半截周期、窄脉冲和额外边沿。

![切换窗口 debug](<./screenshots/任务027_Clock_Swith_Glitch_Free_Verdi调试方法和Makefile/clock_switch_transition_debug_2360s.jpg>)

截图核对：视频 38:00-41:00，画面应显示切换窗口；重点比较 old/new enable 的先后关系和 `clk_out` 的周期完整性。

这张图是“找问题”的图：游标要压到 `sel` 翻转附近，先看 old enable 是否撤销，再看 new enable 是否延迟进入，最后看 `clk_out` 有没有被截成窄高电平、窄低电平或多出一个 posedge。不要只看最右侧稳态波形，稳态选对不能证明切换窗口安全。

合格波形应满足：

- 切换前 `clk_out` 跟随旧时钟。
- 旧 enable 先撤销。
- 新 enable 后打开。
- 两路 gated clock 没有同时输出有效时钟。
- `clk_out` 没有比正常周期更窄的高电平或低电平。
- 没有多出来的额外边沿。

![修复后波形](<./screenshots/任务027_Clock_Swith_Glitch_Free_Verdi调试方法和Makefile/wave_after_fix_2120s.jpg>)

截图核对：视频 34:00-36:00，画面应对应修复后的输出；验证点是切换窗口稳定，而不是只看最终选路正确。

这张图是“验收修复”的图：它不负责重新解释结构，只负责证明前一张图里暴露的风险已经消失。合格结论要写出具体观察，例如“old/new enable 没有重叠，`clk_out` 切换期间没有小于正常高/低宽的脉冲，也没有额外 posedge”。

## 8. Source annotation 把运行时证据贴回代码

Source annotation 可以把波形中的运行时值贴回源码。它的价值是让 debug 从“我猜这行代码影响了信号”变成“这行代码在这个时刻确实产生了这个值”。

![source annotation](<./screenshots/任务027_Clock_Swith_Glitch_Free_Verdi调试方法和Makefile/source_annotation_2750s.jpg>)

截图核对：视频 45:00-47:00，画面应显示源码旁的运行时信号值；使用时要把游标固定在切换窗口内。

使用口径：

```text
先在 waveform 放游标
  -> cross-probe 到源码
  -> 打开 annotation
  -> 检查分支条件、enable、输出值是否与预期一致
```

它适合定位条件分支、enable 打拍和状态转移，不适合替代完整波形判读。

## 9. `forever` 和随机激励必须有可验证结果

TB 中的无限过程必须推动仿真时间前进。下面这种写法会在同一仿真时间内无限循环，可能让仿真卡死：

```systemverilog
forever begin
    a = $random;
end
```

应该写成：

```systemverilog
forever begin
    #10;
    a = $random;
end
```

或等待事件：

```systemverilog
forever begin
    @(posedge clk);
    a <= $urandom;
end
```

随机激励还必须有 expected model。只随机输入、不比较输出，不能证明 DUT 正确。

![参考模型与结果比较](<./screenshots/任务027_Clock_Swith_Glitch_Free_Verdi调试方法和Makefile/scoreboard_reference_model_4460s.jpg>)

截图核对：视频 74:00-76:00，画面应出现 reference model 或 scoreboard 思路；重点看 expected 与 DUT output 是否独立比较。

## 最小交付闭环：从命令到无毛刺结论

Clock switch debug 的最小闭环是一条可复现证据链，而不是一张“看起来没问题”的波形截图。必须能从命令入口追到波形窗口，再追到结构和源码。

| 环节 | 要交付的证据 | 不通过信号 |
|---|---|---|
| 输入 | RTL、TB、filelist、Makefile、切换激励、dump 配置 | 只能手敲命令，不能重跑 |
| 编译 | `make compile` log 无关键错误 | filelist 缺文件或编译选项不支持 debug |
| 仿真 | `make sim` 生成 FSDB，仿真覆盖至少一次 `sel` 切换 | FSDB 不存在，或切换没发生 |
| Verdi | `verdi -f filelist.f -ssf wave.fsdb` 能打开 source/schematic/wave | 只能看波形，无法 cross-probe 源码 |
| 波形判读 | `sel -> old_enable -> new_enable -> gated_clk -> clk_out` 完整 | 只看 `clk_out` 最终跟随哪路时钟 |
| 结论 | 切换窗口无重叠 enable、无窄脉冲、无额外边沿 | 没有放大切换窗口，或无法说明周期宽度 |

最小实操任务：截取一次 `sel` 翻转，把游标所在时间、old/new enable 状态、两路 gated clock、`clk_out` 周期宽度写成一行结论。结论不能只写“pass”，必须说明为什么没有 glitch。

## 复习与自测

1. 为什么普通 mux 不能直接切两路时钟？
2. Glitch-free clock switch 的判定标准为什么不能只看 `clk_out` 最后选对？
3. Verdi 命令中的 `-f filelist.f` 和 `-ssf wave.fsdb` 分别解决什么问题？
4. 如果 Verdi 看不到内部 enable，优先检查哪几处？
5. 为什么 `forever begin a=$random; end` 会让仿真卡住？
6. 一份可交付的 clock switch debug 证据至少包含什么？

参考答案：

1. 选择信号和两路时钟没有共同相位约束，组合 mux 可能制造窄脉冲或半截周期，这些会被后级寄存器当成真实时钟边沿。
2. 最终选对只说明稳态功能正确；glitch-free 要证明切换窗口里旧 enable 已撤销、新 enable 后进入、两个 gated clock 不重叠、`clk_out` 没有额外边沿。
3. `-f` 让 Verdi 读源码文件列表，建立 source/schematic 层次；`-ssf` 读 FSDB 波形。
4. 查 `$fsdbDumpvars` 层次、VCS debug 选项、filelist 是否正确、仿真是否生成了包含内部层次的 FSDB。
5. 循环体没有 delay 或 event control，会在同一仿真时间无限执行，时间不前进。
6. Makefile、filelist、仿真 log、FSDB、关键波形截图、schematic 截图、切换窗口判读和修复/回归结论。



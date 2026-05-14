# 任务50：AHB eFlash控制器设计4

## 本章知识全景图

这一讲把 eFlash 行为模型的 TB 代码逐段拆开，并通过改写实验得到一个关键结论：对这个 eFlash 模型，重新 program 某些 word 前需要先 erase 对应 page，否则第二次写入可能读回混合错误值。这里的重点不是学一套复杂验证框架，而是学会把时序图写成 task，用波形和读回值验证存储体规则。

| 层级 | 核心概念 | 本章要形成的判断 | 连接到前端交付 |
|---|---|---|---|
| TB 接口 | `reg` 驱动控制脚、`wire` 接 `DOUT` | TB 直接扮演 controller，驱动 eFlash IP | 模型 bring-up |
| page erase task | page number、`XADR={page,2'b00}` | task 用 delay 实现 datasheet timing | erase stimulus |
| program task | `XADR/YADR/DIN/PROG/NVSTR/YE` | 一个 task 写一个 word，时间顺序必须对 | program stimulus |
| read task | `XE/YE/SE`、delay 后采 `DOUT` | 读 task 要等过 access time 再拿数据 | read check |
| 实验调试 | 多次写读、Verdi reload | 改 TB 后看波形和读回值，而不是猜 | debug 方法 |
| 重要结论 | program 前先 erase | flash 写入受存储体特性约束 | 软件驱动、controller 状态 |

最短学习路径：

```text
先看 TB 定义了哪些 eFlash 接口
  -> 看 page_erase task 怎样复刻 erase 波形
  -> 看 program_word task 怎样复刻 program 波形
  -> 看 read_word task 怎样等 access time
  -> 改写多次 program/read 实验
  -> 从读回错误推出“写前需擦除”的设计约束
```

## 全视频地图

| 时间段 | 教学块 | 必须保留的知识动作 |
|---|---|---|
| 00:00-03:30 | TB 接口与行为模型入口 | 确认 TB 直接驱动 eFlash 控制脚，先把 controller 从问题里拿掉 |
| 03:30-11:30 | page_erase / program_word / read_word task | 把 datasheet 时序翻译成 task，理解 delay 只属于仿真 |
| 11:30-20:00 | 多次 program/read 实验 | 通过波形和读回值观察存储体真实规则 |
| 20:00-31:00 | erase 后写入与不 erase 覆盖写对比 | 推出 program 前需要 page erase 的约束 |
| 31:00-34:51 | 从 TB task 过渡到 controller RTL | 把 #delay 迁移成 FSM + counter + status |

## 1. 简单 TB 的价值是直接暴露 IP 行为

这个 TB 不是 UVM，也不是完整 SoC 验证平台。它用 `reg` 变量直接驱动 eFlash 的输入控制脚，用 `wire` 接收 `DOUT`，相当于手写一个最小 controller。

![TB 接口定义](<./screenshots/任务050_AHB_eflash控制器设计4/task50_00_tb_interfaces_01m30s.jpg>)

> 图注：01:30 左右。这里要看 TB 中定义的 `XADR/YADR/DIN/XE/YE/SE/PROG/ERASE/NVSTR` 等信号。TB 直接控制这些脚，行为模型负责给出 `DOUT`。

这种 TB 的边界很清楚：

```text
能验证：
  eFlash 行为模型是否按时序响应。
  task 生成的 erase/program/read 波形是否正确。
  写入后能否读回。

不能验证：
  AHB 协议完整性。
  controller 与 CPU/software 的所有交互。
  多 master、异常访问、低功耗等系统场景。
```

所以它是 bring-up 工具，不是最终验证全部。

## 2. `page_erase` task 是时序图的代码版本

`page_erase` 的输入是 page number。因为一页有 4 行，TB 会把 page number 放到 `XADR[9:2]`，低两位补 0。随后按 datasheet 要求拉起 `XE/ERASE`、等待 `TNVS`、拉起 `NVSTR`、保持 erase 时间、再 hold 和 recover。

![page_erase task](<./screenshots/任务050_AHB_eflash控制器设计4/task50_01_page_erase_task_03m45s.jpg>)

> 图注：03:45 左右。这里要看 delay 值和控制脚顺序：`#5000` 对应 5us，`#20000000` 对应 20ms，task 本质是在复刻 page erase 波形。

语义可压成：

```systemverilog
task page_erase(input [7:0] page);
    XADR  = {page, 2'b00};
    XE    = 1'b1;
    ERASE = 1'b1;
    #5000;          // TNVS
    NVSTR = 1'b1;
    #20000000;      // erase busy
    ERASE = 1'b0;
    #5000;          // TNVH
    XE    = 1'b0;
    NVSTR = 1'b0;
    #10000;         // recover margin
endtask
```

这些 delay 是仿真 stimulus 的写法。真正 controller RTL 不能用 `#delay` 实现硬件等待，而要用 FSM + counter。

## 3. `program_word` task 写的是一个 32-bit 位置

`program_word` 的输入包括 `XADR`、`YADR` 和 32-bit data。它先设置地址和数据，再按 `PROG -> NVSTR -> YE -> hold -> recover` 的顺序驱动。

![program_word task](<./screenshots/任务050_AHB_eflash控制器设计4/task50_02_program_word_task_07m45s.jpg>)

> 图注：07:45 左右。这里要看 `XADR/YADR/DIN` 在 `YE` 拉起前已经稳定，`YE` 有效期间保持 program 时间，之后再按 hold 顺序释放。

关键顺序：

```text
XADR/YADR/DIN stable
  -> PROG=1, XE=1
  -> wait TNVS
  -> NVSTR=1
  -> wait TPGS
  -> YE=1
  -> wait TPROG
  -> YE=0
  -> wait TPGH
  -> PROG=0
  -> wait TNVH
  -> NVSTR/XE=0
  -> recover
```

这段代码让读者看到：时序图不是 PPT 上的图，它能一行一行变成可跑的 stimulus。

## 4. `read_word` task 要等 access time 后采样

读 task 输入 `XADR/YADR`，输出 `read_data`。它拉起 `XE/YE/SE` 后等待一段时间，再把 `DOUT` 赋给 `read_data`。

![read_word task](<./screenshots/任务050_AHB_eflash控制器设计4/task50_03_read_word_task_10m20s.jpg>)

> 图注：10:20 左右。这里要看 `#50` 的意义：它大于 24ns access time，所以采样 `DOUT` 时数据已经稳定。

读 task 的核心：

```systemverilog
task read_word(input [9:0] xadr, input [4:0] yadr, output [31:0] read_data);
    XADR = xadr;
    YADR = yadr;
    XE   = 1'b1;
    YE   = 1'b1;
    SE   = 1'b1;
    #50;
    read_data = DOUT;
    XE   = 1'b0;
    YE   = 1'b0;
    SE   = 1'b0;
endtask
```

如果把 `#50` 改得小于 access time，读回值可能不稳定。接到 AHB controller 后，这段等待就对应 `HREADYOUT=0` 的等待拍。

## 5. 多次 program/read 实验用来暴露真实存储规则

课程中把 TB 改成多写几个地址，再读回来。第一次先 erase 再 program，读回值正确；第二次不 erase 直接 program，读回出现错误或混合值。

![多次写入波形](<./screenshots/任务050_AHB_eflash控制器设计4/task50_04_multi_write_wave_18m55s.jpg>)

> 图注：18:55 左右。这里要看连续调用多个 program task 时，地址和数据依次变化，但每个 task 之间都按独立 program 流程退出和 recover。

这个实验说明：只看 datasheet 的 program 波形还不够，还要用行为模型验证“能不能在未 erase 的 page 上再次 program”。模型行为会暴露实际存储体限制。

## 6. 先 erase 后写，读回正确

当 page 已经擦除，再写入多组 32-bit 数据，读回能和写入值对应。

![erase 后读回正确](<./screenshots/任务050_AHB_eflash控制器设计4/task50_05_erase_then_read_ok_25m15s.jpg>)

> 图注：25:15 左右。这里要看读回值和前面写入的 `12345678`、`11223344`、`56787654`、`55667788` 等是否一致。正确读回证明 erase + program + read 三段闭环成立。

最小成功链：

```text
page_erase(page)
  -> program_word(addr0, data0)
  -> program_word(addr1, data1)
  -> read_word(addr0) == data0
  -> read_word(addr1) == data1
```

这条链可以作为 controller 后续验证用例的原型。

## 7. 不 erase 直接第二次写，读回异常

第二次尝试往同一片区域写新数据时，如果没有先 erase，读回值不再等于新写入值，出现类似旧值和新值混杂的现象。

![未擦除直接写的错误结果](<./screenshots/任务050_AHB_eflash控制器设计4/task50_06_no_erase_bad_result_27m20s.jpg>)

> 图注：27:20 左右。这里要看第二轮 program 后的读回值：它不是期望的新数据，说明这个 eFlash 模型不支持像 SRAM 那样随意覆盖写。

这不是 TB 小错误，而是 flash 类存储的关键特性：program 通常只能把某些 bit 朝一个方向改变，恢复到可重新写的状态需要 erase。具体行为由 IP 决定，但“写前先擦除对应粒度”是必须检查的设计约束。

## 8. 重新 erase 后第二次写入恢复正确

课程随后在第二轮 program 前再次 erase 对应 page，读回恢复正确。这一步把结论钉住：问题不是 task 写错地址，而是缺少 erase。

![重新擦除后读回正确](<./screenshots/任务050_AHB_eflash控制器设计4/task50_07_reerase_fixed_result_30m15s.jpg>)

> 图注：30:15 左右。这里要看第二轮先 erase 再 program 后，读回值重新匹配新写入数据。对 controller 和驱动来说，这意味着更新 page 不能省略 erase 阶段。

软件或 controller 要更新 page 内少量 word 时，安全流程通常是：

```text
1. 读出整页旧内容到 buffer。
2. 修改 buffer 中目标 word。
3. 擦除整页。
4. 按 word 重新 program 整页或必要范围。
5. 读回校验。
```

如果只改一个 word 就直接 program，可能破坏同页其他内容或读回错误。

这条结论会影响 controller 和软件驱动之间的契约。硬件可以提供 `erase_page`、`program_word`、`read_word`、`busy`、`done`、`error` 等寄存器或状态；软件必须按顺序调用，不能把普通内存写入语义直接套到 flash 上。若硬件想自动完成“读整页、改 word、擦页、写回”，controller 就会显著复杂，需要页缓存、错误恢复和掉电保护；课程当前更适合先做显式命令式控制器。

## 9. 从 TB task 过渡到 controller RTL

TB 中的 `#delay` 只是仿真等待。controller RTL 要把它们改成时钟计数：

| TB 写法 | RTL 对应 |
|---|---|
| `#5000` | `SETUP` 状态计 5us 对应 cycle |
| `#20000000` | `ERASE_BUSY` 状态计 20ms 或 worst case |
| `#50` | `READ_WAIT` 状态计 access time |
| task 参数 | AHB 地址/数据寄存器或 command register |
| task 返回 | done/busy/status 或 `HREADYOUT` 完成 |

这就是学习简单 TB 的意义：先用最直观的 delay 写出正确波形，再把 delay 系统化成硬件状态。

## 10. 最小闭环：写两个实验判断存储规则

实验 A：验证正常写读。

```text
page_erase(P)
program A0 = 32'h1234_5678
read A0 -> 应为 32'h1234_5678
```

实验 B：验证覆盖写限制。

```text
program A0 = 32'h9876_5432   // 不先 erase
read A0 -> 若不等于新值，记录为必须先 erase
page_erase(P)
program A0 = 32'h9876_5432
read A0 -> 应恢复正确
```

这两个实验比单次写读更有价值，因为它们直接决定 controller 的 command 顺序和软件驱动策略。

后续把 TB 思路迁移到 controller 验证时，至少保留三组 testcase：

| testcase | 目的 | 通过标准 |
|---|---|---|
| erase-program-read | 验证基础写读闭环 | 读回等于写入值 |
| program-without-erase | 验证模型约束和错误场景 | 记录并解释读回异常，不把它当随机波形 |
| erase-reprogram-read | 验证重新擦除后可再次写入 | 第二轮读回等于第二轮写入值 |

这三组用例能把“flash 不是 SRAM”固定成可回归的工程事实。

## 本讲在 50-54 链条中的位置

任务50 是本批的底层事实来源：先不看 AHB，不看寄存器，只用 TB 直接驱动 eFlash 行为模型，确认存储体自己的 erase/program/read 规则。后面所有 controller 设计都不能违背这里得到的结论。

| 本讲输入 | 本讲输出 | 后续使用 |
|---|---|---|
| eFlash 行为模型、datasheet timing、简单 TB | page erase / program / read task | 任务52 的 timing 配置和 command 规格 |
| 多次写读实验 | program 前需要 erase 的验证结论 | 任务51/52 的软件操作顺序 |
| 波形与读回值 | 可回归 testcase | 任务53/54 的 controller 验证点 |

验收口径：读者必须能说明“为什么 eFlash 不能当 SRAM 覆盖写”，并能把 TB 里的 `#delay` 翻译成 RTL 里的 FSM 状态和 counter。

## 常见误区和失败信号

| 误区 | 正确判断 | 失败信号 |
|---|---|---|
| TB 里 `#delay` 可以照搬进 RTL | RTL 要用 FSM + counter | 综合失败或不可综合 |
| read task 可以立刻采 `DOUT` | 必须等过 access time | 读到 X 或旧值 |
| flash 可以像 SRAM 一样覆盖写 | 许多 flash 需要先 erase 再 program | 第二次写读回混合值 |
| 只看一轮写读就够 | 覆盖写、跨 page、连续读写都要测 | 初次正确，重复操作失败 |
| page erase 只影响目标 word | erase 粒度是 page | 同页其他 word 被清掉 |

## 深层理解：flash 不是可随手改字的 SRAM，而是“先清场再刻字”

SRAM 像白板，某一格可以直接擦掉重写；eFlash 更像刻在一片材料上的字，很多情况下不能把某个 word 当成白板反复覆盖。常见流程是先按 page 把一片区域恢复到擦除态，再把需要的 bit program 成目标值。这个差别会直接影响 controller、软件驱动和掉电保护。

这也是本讲“未擦除直接再次 program 会错”的核心价值：它让你看到 eFlash 的物理约束不是抽象说明，而是会反映到读回结果里。

| 场景 | SRAM 直觉 | eFlash 正确口径 |
|---|---|---|
| 改一个 word | 直接写目标 word | 可能要读整页、改缓存、擦页、重写整页 |
| 连续 program | 多次覆盖即可 | 受 program 规则限制，可能只能单向改变某些 bit |
| 掉电中断 | 下次继续写 | 可能处于擦完未写回或写一半状态 |
| 验证通过 | 写后读一次 | 还要测不擦直接写、擦后重写、跨 page、异常中断 |

## page buffer 和掉电场景的失败信号

如果 controller 或软件想修改 page 内一个 word，工程上经常需要 page buffer：

```text
读出整页旧数据
  -> 在 buffer 中修改目标 word
  -> page erase
  -> 按 word/program 序列写回整页
  -> readback 校验
```

失败信号：

| 失败现象 | 深层原因 |
|---|---|
| 目标 word 正确，同页其他 word 变成擦除态 | 擦页前没有保存整页旧数据 |
| 擦除后掉电，重启发现 page 空了 | 没有掉电恢复策略或双备份机制 |
| program 中断后部分 word 正确、部分错误 | 没有写入进度记录和 readback 校验 |
| readback 偶发错误 | access time 不足或 program/erase 后 recover 不足 |
| 二次 program 混合值 | 未擦除直接覆盖写 |

eFlash 控制器不能只追求“正常路径能跑”，还要定义失败恢复：忙时拒绝新命令、异常中断后如何判断 page 状态、写完后是否校验。

## 复习与自测

1. `page_erase` task 为什么输入 page number，而不是完整 word address？

   参考答案：erase 粒度是 page，不是单个 word；page number 对应 `XADR[9:2]`。

2. 为什么 TB 里可以用 `#20000000`，controller RTL 里不能这样写？

   参考答案：`#delay` 是仿真时间控制，不可综合成硬件等待；RTL 要用时钟计数器实现等待。

3. `read_word` 为什么等待 50ns？

   参考答案：eFlash read access time 约 24ns，50ns 留出裕量，确保采样 `DOUT` 时数据稳定。

4. 第二次不 erase 直接 program 后读回错误，说明什么？

   参考答案：这个 eFlash 模型不支持任意覆盖写；更新前需要按 page 粒度 erase，再 program。

5. 如果只想改 page 里的 1 个 word，为什么还可能需要保存整页旧数据？

   参考答案：erase 会清掉整页；为了不丢同页其他 word，需要先读出整页，修改目标 word 后再擦除并写回。

## 工程核对口径

本章通过标准：

1. 能解释 `page_erase`、`program_word`、`read_word` 三个 task 的输入、输出和等待条件。
2. 能说明为什么 TB 里的 `#delay` 必须在 RTL 中变成 FSM + counter。
3. 能用实验说明“不擦除直接 program”为什么不可靠。
4. 能设计 page 修改流程：读整页、改 buffer、擦页、写回、校验。
5. 能列出掉电、中断、busy 访问和 readback 失败时的系统处理策略。



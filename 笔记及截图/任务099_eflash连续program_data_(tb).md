# 任务99：eFlash 连续 program data（TB）

## 本章知识全景图

这一讲把任务 98 的 RTL 改造放进 testbench 和波形里验收。核心结论是：连续 program 不是“仿真能跑完”就算对，而是要证明配置寄存器、FSM 状态、`program_cnt`、YADDR、写入 data、NVSTR 外层时序和最终 readback 全部一致。

| 层级 | 核心概念 | 本讲验收口径 |
|---|---|---|
| TB 配置 | erase、program data、program number | 先擦除目标 page，再配置 4 组 data 和连续 program 数量。 |
| 编译门 | make/VCS error | 先解决语法、端口、未声明信号等硬错误。 |
| 波形调试 | Verdi、state、counter、address、data、NVSTR | 不只看仿真结束，要看关键状态是否按设计跳转。 |
| 连续写成功 | `program_cnt` 递增、YADDR 递增、data mux 变化 | 每个 DWord 被写到连续地址，且数据不同。 |
| readback | 读回 4 个值 | 最终以读回数据匹配写入数据作为功能闭环。 |
| 设计复盘 | efficiency、burst、边界 | 连续 program 的价值是减少外层等待，不是省掉每个 word 必需的 program 时间。 |

最短学习路径：

```text
先用 TB 擦除目标页
  -> 写入 program_data0..3 和 program_number
  -> 编译，修掉语法/端口错误
  -> 打开 Verdi 看 state/counter/address/data/NVSTR
  -> 确认连续 program 波形
  -> readback 四个值
  -> 回到 RTL 总结连续 program 的工程收益
```

## 全视频地图

| 时间段 | 视频块 | 视觉证据 | 学习目标 |
|---|---|---|---|
| 01:42-05:57 | TB 配置连续 program | `task99_00_tb_program_start_01m42s.jpg`、`task99_01_program_data_values_03m23s.jpg` | 配置 erase、4 个 program data、program number。 |
| 06:46-09:17 | 编译错误与首次 debug | `task99_02_compile_error_06m46s.jpg`、`task99_03_verdi_debug_09m17s.jpg` | 先过编译门，再进波形定位。 |
| 09:17-14:48 | Verdi 波形验证主链 | `task99_04_program_wave_success_14m00s.jpg` | 看 state、counter、address、data 是否连续变化。 |
| 14:48-19:02 | program timing 细看 | `task99_05_program_timing_wave_19m02s.jpg` | 确认 NVSTR、program pulse、hold、recover 时序没有被破坏。 |
| 19:02-22:12 | readback 验证 | `task99_06_readback_values_21m15s.jpg` | 读回 4 个值并与写入值对上。 |
| 22:12-26:44 | 设计复盘 | `task99_07_design_lesson_23m51s.jpg` | 总结 continuous program 的效率收益和练习价值。 |

## 视觉证据与截图说明

| 截图 | 教学职责 |
|---|---|
| ![TB program start](<./screenshots/任务099_eflash连续program_data_(tb)/task99_00_tb_program_start_01m42s.jpg>) | 展示 TB 从 erase 后进入 program 配置。 |
| ![program data values](<./screenshots/任务099_eflash连续program_data_(tb)/task99_01_program_data_values_03m23s.jpg>) | 对齐 4 个待写入数据和 program number。 |
| ![compile error](<./screenshots/任务099_eflash连续program_data_(tb)/task99_02_compile_error_06m46s.jpg>) | 说明 RTL/TB 改造后的第一关通常是编译错误。 |
| ![Verdi debug](<./screenshots/任务099_eflash连续program_data_(tb)/task99_03_verdi_debug_09m17s.jpg>) | 展示进入波形工具后需要组织信号组。 |
| ![program wave success](<./screenshots/任务099_eflash连续program_data_(tb)/task99_04_program_wave_success_14m00s.jpg>) | 用波形确认连续 program 主流程跑通。 |
| ![program timing wave](<./screenshots/任务099_eflash连续program_data_(tb)/task99_05_program_timing_wave_19m02s.jpg>) | 对齐 program pulse、address、counter 的时间关系。 |
| ![readback values](<./screenshots/任务099_eflash连续program_data_(tb)/task99_06_readback_values_21m15s.jpg>) | 用终端/仿真输出证明读回数据匹配。 |
| ![design lesson](<./screenshots/任务099_eflash连续program_data_(tb)/task99_07_design_lesson_23m51s.jpg>) | 总结连续 program 的设计逻辑和练习要求。 |

## 1. TB 的第一步是建立干净初始条件

连续 program 前必须先 erase 目标 page。Flash 类存储不是普通 SRAM，不能默认旧内容可直接覆盖成任意值；如果不先擦除，program 结果可能受旧值影响，TB 会把存储介质规则和 RTL bug 混在一起。

TB 最小顺序：

```text
1. reset
2. 配置 page erase，擦除目标 page
3. 等 erase done/status
4. 配置 program base address
5. 写 program_data0..3
6. 写 program_number = 4
7. 启动 program
8. 等 program done/status
9. 读回连续 4 个 DWord
10. 比较 readback 与 expected
```

这一顺序的重点不是“照着视频操作”，而是给验证一个明确前提：如果 readback 错，优先怀疑连续 program 逻辑，而不是旧 flash 内容。

## 2. 测试数据要能暴露 mux 和地址错误

四个 program data 不能都写相同值。如果四个值一样，data mux 接错、`program_cnt` 不递增、YADDR 不递增，都可能被掩盖。

更好的测试数据满足三个条件：

| 条件 | 原因 |
|---|---|
| 每个 DWord 不同 | 能看出 data mux 是否随 `program_cnt` 切换。 |
| 高低 nibble 都有变化 | 能看出 bit 顺序、字节序、截断错误。 |
| 不全是 0 或全 1 | 避免擦除态或默认态掩盖错误。 |

课程中使用类似 `0x12345566`、`0x55667788`、`0xAABBCCDD`、`0x87654321/32` 这类互不相同的值，目的就是让波形和 readback 一眼能看出顺序。

## 3. 编译错误是第一道门，不是最终 debug

RTL 改端口、寄存器和 FSM 后，最常见第一类失败是编译错误。包括：

| 症状 | 常见原因 | 修复方向 |
|---|---|---|
| undeclared identifier | 新信号只在某层声明，另一层没声明。 | 补齐声明或 include。 |
| port mismatch | module 例化没有同步新增端口。 | 按端口链逐层补连接。 |
| width mismatch | `program_number`、counter、case selector 位宽不一致。 | 明确计数范围和比较宽度。 |
| syntax error | 手工复制修改漏逗号、分号、括号。 | 回到报错行附近最小修改。 |

编译通过只说明“代码能被工具读懂”。后面仍要看波形证明“代码按预期运行”。

## 4. Verdi 波形要按验证问题组织信号

波形不是越多越好，而是要围绕连续 program 的关键判断组织。

建议波形组：

```text
配置组:
  program_data0..3
  program_number
  program_start / program_done

状态组:
  flash_state / program_state
  program_cnt
  program_last

地址数据组:
  flash_xaddr
  flash_yaddr
  flash_din
  macro_dout / read_data

控制脚组:
  XE / YE / SE
  PROG
  NVSTR
  erase/program enable

总线反馈组:
  status
  interrupt
  error
```

如果只看终端 pass，很容易漏掉“写入虽然成功，但外层时序重复了”“counter 多加了一次”“最后一次地址错位”等问题。连续 program 的正确性必须在时序链上闭合。

## 5. 连续 program 的成功波形应该长什么样

成功波形应满足这些局部事实：

| 检查点 | 期望现象 | 错误信号 |
|---|---|---|
| `program_number` | 稳定为 4 或本次配置值 | 为 0、X、旧值。 |
| `program_cnt` | 每完成一个 word 增加一次，0->1->2->3 | 一直为 0、跳过值、到 4 后才结束。 |
| `flash_yaddr` | base、base+1、base+2、base+3 | 不变、错位、溢出未处理。 |
| `flash_din` | 依次等于 data0/data1/data2/data3 | 一直等于 data0 或顺序错。 |
| `NVSTR` | 外层拉起后覆盖连续事务 | 每个 word 都重复起落，效率收益消失。 |
| program pulse | 每个 word 都有合法 pulse | 少一次、多一次、宽度不满足。 |
| recover | 所有 word 完成后再进入 | 每个 word 后都 recover，或最后不 recover。 |

注意：连续 program 不意味着每个 word 的 program pulse 可以省掉。eFlash 仍需要对每个 DWord 执行实际编程时间；优化的是外层重复开销。

## 6. readback 是功能闭环，不能只看中间波形

波形能证明控制过程，readback 证明存储结果。最终必须从 eFlash 中读回连续 4 个 DWord，并与 expected 比较。

建议 TB 不只打印，还要自动 compare：

```systemverilog
task automatic check_readback(input [31:0] addr, input [31:0] exp);
  logic [31:0] got;
  begin
    read_word(addr, got);
    if (got !== exp) begin
      $error("eFlash readback mismatch: addr=%h exp=%h got=%h", addr, exp, got);
    end
  end
endtask
```

验证连续 4 个 word：

```systemverilog
check_readback(BASE_ADDR + 0, 32'h1234_5566);
check_readback(BASE_ADDR + 1, 32'h5566_7788);
check_readback(BASE_ADDR + 2, 32'hAABB_CCDD);
check_readback(BASE_ADDR + 3, 32'h8765_4321);
```

若课程原 TB 只靠人工看终端输出，学习时可以先接受；但工程项目里应把它升级成自动断言或 scoreboard，否则回归测试不可持续。

## 7. Debug 的真实顺序：先粗后细

遇到错误不要从所有信号同时猜。按下面顺序排查更稳：

```text
1. 编译是否过？
2. TB 是否真的写了 program_data 和 program_number？
3. RTL 配置寄存器侧是否收到值？
4. control/FSM 侧是否通过端口拿到值？
5. program_cnt 是否按 word 完成事件递增？
6. data mux 是否随 program_cnt 变化？
7. YADDR 是否递增？
8. readback 是否匹配？
```

这个顺序从“值有没有进来”到“状态有没有走对”再到“结果有没有写对”，比直接盯一大片波形更快。

## 8. 本次任务的设计收益

连续 program 的收益来自减少重复等待。假设单 word program 每次都要额外等待 5 us TNVS、若干 program setup、NVH、recover，那么写 4 个 word 会重复这些外层成本 4 次。连续 program 把外层成本摊到一次事务里，吞吐更接近 eFlash macro 支持的 burst 写入能力。

但它不是无限加速：

| 仍然存在的成本 | 原因 |
|---|---|
| 每个 word 的 program pulse | 每个 DWord 都要真正写入非易失存储。 |
| 地址/data 选择时间 | 每个 DWord 都有不同位置和数据。 |
| macro 约束 | eFlash 的物理写入时序不能被 RTL 随意压缩。 |
| row/page 边界 | 跨边界需要额外控制或拆事务。 |

所以连续 program 是“去掉重复外层开销”，不是“绕过 eFlash 编程时间”。

## 深层理解：TB 是流水线的称重站

任务 98 把 RTL 流水线搭起来，任务 99 的 TB 要做称重站：每一件货是否从正确入口进入、经过正确工位、落到正确地址、最后读回正确重量。只看 `done` 像只看货车到达出口，不称重、不看箱号，就无法发现中途把四箱货装反。

测试数据必须互不相同，原因不是形式主义，而是为了让错误显影：

| 测试设计 | 能暴露的问题 | 如果省掉会怎样 |
|---|---|---|
| 先 erase | 旧 flash 内容干扰 | 把旧值误判成新写入 |
| data0..data3 不同 | data mux、counter 顺序 | 四个相同值会掩盖 mux 错误 |
| `program_number=1/2/3/4` | last 判断和循环次数 | 只测 4 看不出提前结束 |
| YADDR 边界测试 | row/page 越界 | 地址递增 bug 潜伏 |
| readback/scoreboard | 最终存储结果 | 波形对但实际没写入 |

深层经验是：验证不是给 RTL 鼓掌，而是设计让 RTL 露馅的场景。好的 TB 像秤，坏的 TB 像观众；观众只看流程热闹，秤会告诉你每一件货是否真的对。

## AI+IC 连接

这类 TB 思维可以直接迁移到 NPU 和 SoC 验证：只改 RTL 不看波形是不够的，必须设计能暴露 mux、counter、address、burst 边界的测试数据。NPU 中验证 DMA burst、weight load、feature map tile 写入时，也要用不同数据模式、连续地址、counter 波形和 readback/scoreboard 闭环证明。

## 工程练习

1. 把当前 TB 的人工 readback 打印改成自动 compare。
2. 增加 `program_number=1/2/3/4` 四组测试，分别验证结束条件。
3. 增加 `program_yaddr=30, program_number=4` 的边界测试，要求 RTL 报错或禁止配置。
4. 在波形里标出第一次和最后一次 program pulse，确认 recover 只出现在最后。
5. 给 `program_cnt` 写一个断言：事务期间它不能超过 `program_number-1`。

## 常见误区和失败信号

| 误区 | 正确判断 |
|---|---|
| 仿真跑完就算对。 | 要看配置、状态、counter、地址、data、readback 是否闭合。 |
| 四个 data 写一样也能测连续 program。 | 相同 data 会掩盖 mux 和顺序错误。 |
| 编译报错只是小问题不用记录。 | 编译错误常暴露端口链、声明和位宽设计遗漏。 |
| 波形只看 final done。 | `done` 可能拉起，但中间时序可能效率错误或地址错位。 |
| readback 人眼看一下就行。 | 工程回归应自动 compare 或 scoreboard。 |

## 复习与自测

1. 为什么连续 program TB 要先 erase？  
   答案：Flash 写入受旧内容影响，先 erase 能建立干净初始条件，避免把旧数据规则误判成 RTL bug。

2. 为什么四个 program data 应该互不相同？  
   答案：不同值能暴露 data mux、counter 和地址顺序错误；相同值可能让错误隐藏。

3. 波形中证明连续 program 的三个关键信号是什么？  
   答案：`program_cnt` 递增、`flash_yaddr` 连续递增、`flash_din` 依次切换到 data0..data3；同时应检查 NVSTR 外层不重复。

4. readback 验证证明了什么？  
   答案：证明数据不仅在控制波形上出现过，而且最终真实写入 eFlash 并能按地址读回。

5. 连续 program 为什么不能省掉每个 word 的 program pulse？  
   答案：每个 DWord 都要经过 eFlash macro 的物理编程过程；连续 program 只能省掉外层重复 setup/recover 等成本。

## 工程核对口径

连续 program TB 的完成标准应写成可自动判定的检查：

1. 编译门：新增端口、声明、位宽无错误。
2. 配置门：寄存器写入后 `program_number/data0..data3/base_yaddr` 稳定可见。
3. 波形门：`program_cnt` 从 0 到 N-1，`flash_yaddr` 连续递增，`flash_din` 按 data 序列切换。
4. 时序门：外层 setup/recover 不重复，per-word program pulse 不丢。
5. 结果门：readback 与期望数组逐项 compare，失败时报地址、期望值、实际值。

最终回归里，人眼看 Verdi 只能作为定位手段，不能替代 scoreboard。能自动比较，才说明这条流水线不只是“看起来在运行”，而是每件货都过秤。


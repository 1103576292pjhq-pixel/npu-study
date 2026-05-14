# 44_AHB_SRAM控制器设计7

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：建立 Memory BIST 的系统认识：为什么芯片需要制造测试，为什么嵌入式 SRAM 不能只靠 ATE 或 CPU 测，MBIST 如何用片上控制器、测试算法和比较逻辑完成存储器自测试。
- 核心概念：manufacturing test、ATE、DFT、BIST、MBIST、scan insertion、ATPG、fault simulation、MISR、March algorithm、test coverage、test time、stuck-at fault、transition fault、address decoder fault、coupling fault。
- 逻辑主线：芯片制造后必须筛掉坏片；存储器容量大、嵌入深、外部测试成本高，所以把测试逻辑放进芯片内部。MBIST 的本质是片上控制器自动生成地址、读写序列和期望值，对 SRAM 输出做比较，并给出 pass/fail。
- 最小学习路径：先理解制造测试的 pass/fail 目标，再区分 ATE、CPU 测试和 MBIST，随后看 SoC 中 DFT/BIST 的策略平衡，最后读 MBIST 架构和 March 算法。

### 2. 概念地图

| 层级 | 核心对象 | 要解决的问题 | 输出 |
|---|---|---|---|
| 制造测试 | ATE、test program | 封装芯片是否可销售 | pass/fail |
| 可测性设计 | DFT/BIST | 普通功能路径测不到的内部缺陷 | 测试结构 |
| 存储器测试 | MBIST | 大容量嵌入式 SRAM 如何高覆盖低成本测试 | done/fail |
| 测试架构 | BIST controller、MUX、MISR | 自动生成地址、数据、控制和比较 | 自测试闭环 |
| 测试算法 | March | 用读写序列覆盖常见存储故障 | 测试向量 |
| 质量权衡 | coverage、time、area | 覆盖率、测试时间、芯片面积之间取舍 | DFT/BIST 策略 |

### 3. 阅读顺序

```text
制造测试为什么存在
  -> ATE、CPU 测试、MBIST 的边界
  -> SoC 中 DFT/BIST 策略
  -> 含 DFT 的设计流程
  -> MBIST 架构
  -> March 算法和故障覆盖
```

## 全视频地图

| 时间段 | 视频块 | 画面证据 | 这一段要学会什么 |
|---|---|---|---|
| 05:00 左右 | 制造测试目标 | packaged IC、ATE、test program、pass/fail | 制造测试回答芯片能不能卖，不回答 RTL 写得漂不漂亮。 |
| 10:00-15:00 | CMOS 缺陷直觉 | inverter layout、PMOS/NMOS、金属/扩散区 | 功能仿真不能覆盖真实硅片开路、短路、桥接等物理缺陷。 |
| 20:00-30:00 | SoC DFT/BIST 与流程 | BIST、scan、ATPG、fault simulation | 可测性结构必须和设计流程同步，否则内部节点和嵌入式 memory 很难测。 |
| 40:00 左右 | ATE/CPU/MBIST 对比 | 三种 embedded memory 测试方法 | CPU 测试灵活但覆盖受限，MBIST 是嵌入式 SRAM 的主流量产方案。 |
| 45:00-50:00 | MBIST 架构 | BIST controller、MUX、MISR、fail/done | MBIST 用片上控制器接管 memory，自动生成地址、数据、控制和比较。 |
| 55:00-60:00 | March 算法和覆盖率 | March 步骤、SAF/TF/AF/CF/RF/PSF 表 | March 用有序全地址读写覆盖常见 fault，覆盖率、面积和测试时间必须权衡。 |
## 1. 制造测试只问一个硬问题：这颗芯片能不能卖

制造测试发生在芯片生产出来之后。ATE 根据 test program 给封装芯片施加输入、采集输出，最后把芯片分成 pass 和 fail。它的目标不是证明 RTL 写得漂亮，而是用可接受的时间和成本筛掉制造缺陷。

视觉验证：视频 05:00 左右，画面应能看到 packaged IC chips、ATE、test program、pass/fail testing 的流程图。

![Manufacturing test](<./screenshots/任务044_AHB_SRAM控制器设计7/task44_00_manufacturing_test_05m00s.jpg>)

制造测试的基本矛盾：

| 目标 | 压力 |
|---|---|
| 覆盖更多缺陷 | 测试向量更多，时间更长 |
| 测试更快 | 可能覆盖率下降 |
| 成本更低 | ATE 时间和通道资源受限 |
| 测试更深层内部节点 | 普通芯片管脚不可直接访问内部节点 |

因此芯片不能只靠外部输入输出做黑盒测试。内部寄存器、组合逻辑、存储器阵列都需要可测性结构。

## 2. CMOS 反相器例子说明“功能正常”和“制造无缺陷”不是一回事

课程用 CMOS inverter layout 解释制造缺陷直觉：版图里有扩散区、多晶硅、金属、电源和地，任何开路、短路、桥接、工艺偏差都可能让理想逻辑门失效。RTL 仿真只证明设计意图，制造测试要证明真实硅片没有致命缺陷。

视觉验证：视频 10:00-15:00，画面应能看到 CMOS inverter layout、截面图和老师对 PMOS/NMOS、电源/地、输出节点的标注。

![CMOS inverter layout](<./screenshots/任务044_AHB_SRAM控制器设计7/task44_01_cmos_inverter_layout_10m00s.jpg>)

这对 SRAM 更严重。SRAM 不是几个门，而是大量重复 cell、wordline、bitline、sense amplifier 和 decoder。即使控制器 RTL 正确，只要某个 cell stuck-at、某条 bitline 有耦合、某个地址 decoder 出错，读写结果就会错。

## 3. SoC 里的 DFT/BIST 要在覆盖率、时间和成本之间平衡

SoC 中通常同时有逻辑 DFT、memory BIST、模拟 BIST、scan chain、JTAG/测试端口等结构。最优策略不是“加越多越好”，而是保证错误覆盖率足够高，同时让测试时间足够短、面积和时序代价可接受。

视觉验证：视频 20:00-25:00，画面应能看到 SoC 中存储器 BIST、模拟 BIST、内部扫描链、共享控制器和测试端口。

![SoC DFT and BIST](<./screenshots/任务044_AHB_SRAM控制器设计7/task44_02_soc_dft_bist_20m00s.jpg>)

设计取舍：

| 策略 | 好处 | 代价 |
|---|---|---|
| 加强 BIST/DFT | 覆盖率高、定位容易 | 面积增加、时序路径变复杂 |
| 减少 DFT 结构 | 面积和时序压力小 | 测试质量下降、坏片流出风险上升 |
| 全靠 ATE | 结构少 | 测试时间长，深层 memory 难测 |
| 全靠 CPU 程序 | 灵活 | 依赖芯片已能正常启动，不能覆盖所有嵌入式 memory |

工程上要把 DFT/BIST 尽早纳入 RTL 和架构，而不是最后补丁式塞进去。

## 4. 含 DFT 的流程必须和功能设计同步

含 DFT 的设计流程通常包括电路设计、可测性分析、逻辑综合、扫描插入、测试向量生成、故障仿真和输出。DFT 不是后端工具自动补上的边角料，它会反过来影响 RTL 写法、模块边界、时钟复位和测试模式。

视觉验证：视频 30:00 左右，画面应能看到含 DFT 设计流程图：电路设计、可测性分析、逻辑综合、扫描插入、自动测试向量生成、错误仿真、高覆盖率、输出。

![DFT design flow](<./screenshots/任务044_AHB_SRAM控制器设计7/task44_03_dft_flow_30m00s.jpg>)

流程中的关键节点：

```text
RTL 设计
  -> 可测性分析：哪些节点难以控制或观察
  -> 逻辑综合：生成门级网表
  -> scan insertion：把触发器组织成扫描链
  -> ATPG：自动生成测试向量
  -> fault simulation：评估故障覆盖率
  -> 输出测试数据和约束
```

Memory BIST 是这条路线中的存储器专项解决方案。它不替代 scan，也不替代功能验证；它专门解决嵌入式 memory 难以被外部向量直接充分测试的问题。

## 5. ATE、CPU 测试和 MBIST 各自边界不同

嵌入式 memory 的测试方法可以粗分为 ATE 测试、CPU 测试和 MBIST。三者不是谁完全替代谁，而是适用条件不同。

视觉验证：视频 40:00 左右，画面应能看到“嵌入式 Memory 的测试方法”：ATE 测试、CPU 测试、MBIST 的对比。

![Memory test methods](<./screenshots/任务044_AHB_SRAM控制器设计7/task44_04_memory_test_methods_40m00s.jpg>)

| 方法 | 优点 | 缺点 | 适用判断 |
|---|---|---|---|
| ATE 测试 | 外部专业设备，标准化 pass/fail | 算法复杂、容量大时测试时间长、嵌入式 memory 不易直接访问 | 必要但不适合单独承担全部 memory 测试 |
| CPU 测试 | 软件可修改，灵活，不额外增加太多硬件 | 依赖 CPU 和系统能正常工作，CPU 与 memory 不一定直接相连，软件开发耗人力 | 适合 bring-up 和部分系统级自检 |
| MBIST | 片上自动测试，覆盖率高，成本低，能直接靠近 memory | 增加面积和可能影响时序，需要设计和验证 BIST 逻辑 | 嵌入式 SRAM 的主流方案 |

结论很直接：大容量嵌入式 SRAM 不能只靠 CPU 软件循环读写。CPU 程序要经过总线、cache、互连、权限和启动流程，无法保证每个 memory cell 都被按目标算法覆盖。

## 6. MBIST 的核心是“片上测试向量生成 + 自动比较”

MBIST 是结构性 DFT 技术，测试结构放在 memory 附近。它自动生成地址、写数据、读控制和期望值，对 memory 输出进行比较，然后给出 fail/done。

视觉验证：视频 45:00 左右，画面应能看到 MBIST 概述：结构性 DFT、测试结构内置于 memory 内、自动生成测试向量、自动比较输出。

![MBIST overview](<./screenshots/任务044_AHB_SRAM控制器设计7/task44_05_mbist_overview_45m00s.jpg>)

MBIST 的最小闭环：

```text
BIST controller
  -> 生成测试地址
  -> 生成测试数据 pattern
  -> 生成读写控制
  -> 驱动 RAM/ROM
  -> 采集读出数据
  -> 与期望值比较或压缩进 MISR
  -> 输出 fail/done
```

这和前几讲的 AHB function path 不同。function path 是 CPU/DMA 通过 AHB 访问 SRAM；MBIST path 是测试控制器接管 SRAM 端口，按测试算法直接访问所有地址。

## 7. MBIST 架构由控制器、MUX、存储器和响应分析组成

MBIST 架构图中，BIST 控制器产生测试地址、读写使能和测试数据；MUX 在 function 信号和 test 信号之间选择；RAM/ROM 被测；MISR 或比较器分析响应。这个结构解释了后续 RTL 里为什么要有 `bist_en`、test address、test data、mux 和 fail/done。

视觉验证：视频 50:00 左右，画面应能看到 BIST 控制器、RAM/ROM、MUX、MISR、`t_addr/t_rd/t_capture/fail/misr_do` 等信号。

![MBIST architecture](<./screenshots/任务044_AHB_SRAM控制器设计7/task44_06_mbist_architecture_50m00s.jpg>)

角色分工：

| 模块 | 职责 |
|---|---|
| BIST controller | 控制测试阶段、地址方向、读写动作和结束条件 |
| Address generator | 遍历 memory 地址，支持递增/递减 |
| Pattern generator | 生成 0、1、棋盘格或算法需要的数据 |
| Function/Test MUX | 在正常访问和测试访问之间切换 |
| Comparator/MISR | 检查读出值是否符合预期，压缩或报告结果 |
| Fail/Done output | 对外报告测试失败或完成 |

学习 RTL 时要按这个结构找代码，而不是从第一行顺序读到最后一行。先找 mux，确认测试路径能接管 memory；再找 address/pattern/FSM；最后找 compare 和 done。

## 8. March 算法用有序读写覆盖常见存储故障

March 算法的思想很朴素：按某个地址方向遍历全存储器，对每个单元执行一组读写动作。它的价值不是“算法复杂”，而是用很小的时间复杂度覆盖 stuck-at、transition、address decoder、coupling 等常见 memory fault。

视觉验证：视频 55:00 左右，画面应能看到 March 算法步骤：先全写 0，读第一个单元应为 0，写 1，再读应为 1，对后续单元重复，后面再读 1、写 0、读 0 等。

![March algorithm](<./screenshots/任务044_AHB_SRAM控制器设计7/task44_07_march_algorithm_55m00s.jpg>)

一个简化 March 序列可以写成：

```text
1. 按递增地址，全存储器写 0
2. 按递增地址，对每个地址读 0、写 1
3. 按递增地址或递减地址，对每个地址读 1、写 0
4. 最后再读 0，确认回到预期状态
```

真实 March 算法有多种变体，例如 MATS++、March X、March Y、March C-。区别在于读写序列、地址方向和覆盖故障类型的能力。你不需要先死背所有名字，先掌握“全地址、指定方向、读写交替、比较期望值”这个骨架。

## 9. 覆盖率、复杂度和测试时间是三角关系

March 算法的复杂度通常用对每个 memory cell 的操作次数表示。操作越多，覆盖的故障类型通常越多，但测试时间也越长。量产测试里，时间就是成本，所以算法选择必须兼顾覆盖率和测试时长。

视觉验证：视频 60:00 左右，画面应能看到 March 算法覆盖率表，列出 SAF、TF、AF、CF、RF、PSF 等故障类型和不同算法覆盖率。

![March coverage table](<./screenshots/任务044_AHB_SRAM控制器设计7/task44_08_march_coverage_60m00s.jpg>)

常见故障缩写：

| 缩写 | 含义 | 直觉 |
|---|---|---|
| SAF | stuck-at fault | 某个 cell 卡在 0 或 1 |
| TF | transition fault | 0->1 或 1->0 翻转失败 |
| AF | address decoder fault | 地址译码选错单元 |
| CF | coupling fault | 一个单元变化影响邻近单元 |
| RF | retention fault | 数据保持能力不足 |
| PSF | pattern sensitive fault | 特定数据图案下出错 |

MBIST 的工程目标是选择足够好的算法和结构，在可接受时间内达到目标覆盖率，并把结果用 `bist_done/bist_fail` 这种简单接口交给 SoC 测试流程。

## 10. 本讲和 AI+IC/NPU 的连接

NPU 内部有大量 SRAM：权重缓存、激活缓存、片上 scratchpad、DMA buffer、寄存器文件和中间结果缓存。随着 SRAM 数量增多，memory fault 对芯片良率和可靠性的影响更大。理解 MBIST，是理解 AI 芯片“为什么能量产、怎么筛坏片、怎么在测试成本内保证质量”的基础。

## 11. 深层理解：MBIST 是给 SRAM 装“自检医生”

普通功能仿真像医生问病人“你现在能不能走路”；制造测试像用仪器检查每块肌肉、神经和骨头有没有缺陷。SRAM cell 数量巨大，靠 CPU 程序逐个测试既慢又受系统启动条件限制，所以芯片里要放一个专门的自检医生：MBIST controller。

MBIST 的完整 bring-up 链路可以这样看：

```text
进入 test mode
  -> function/test mux 切到 BIST path
  -> BIST 生成地址、数据、读写控制
  -> SRAM macro 执行 March 序列
  -> compare 读出值和期望值
  -> 汇总 bist_done / bist_fail
  -> SoC 测试流程读取结果
```

每一步都有失败信号：

| 阶段 | 失败信号 | 第一检查点 |
|---|---|---|
| test mode 进入 | `bist_en` 有效但 macro 仍接 function path | mux select 极性、scan/test mode 条件 |
| 地址遍历 | 地址停住或跳变异常 | address counter、up/down 控制、终止条件 |
| March 写读 | 写阶段没有真实写入，读阶段读不到期望值 | `CEN/WEN/OEN` 低有效极性 |
| compare | 首次 mismatch | 记录地址、pattern、state、DOUT |
| done/fail 上报 | 测试不结束或 fail 被吞 | final state、done 条件、fail latch |

## 12. 覆盖率、时间、面积的三角取舍

March 算法越复杂，覆盖故障类型越多，但测试时间和 BIST 控制逻辑也越重。工程上不是“算法越长越好”，而是在目标故障覆盖率、量产测试时间和面积/时序影响之间取平衡。

| 取舍项 | 太弱的后果 | 太强的代价 |
|---|---|---|
| 故障覆盖 | 坏片漏测，现场可靠性风险 | 算法更长、控制更复杂 |
| 测试时间 | 量产 throughput 高但风险大 | ATE 时间增加，成本上升 |
| 面积开销 | BIST 过小可能控制能力不足 | BIST 逻辑占面积、影响布线 |
| 时序影响 | mux/test path 插入可能影响 function path | 需要更严格约束和隔离 |

NPU 里 SRAM 数量多，这个三角取舍会被放大。一个小 SRAM 的测试时间不长，几十上百个 SRAM 累加后就会变成量产成本。

## 最后速记

### 本章最该记住的结论

- 制造测试的核心输出是 pass/fail，不是功能仿真报告。
- DFT/BIST 是为了让内部节点和嵌入式 memory 变得可控制、可观察。
- CPU 测试灵活但覆盖和前置条件受限，不能替代 MBIST。
- MBIST 用片上控制器接管 memory，自动生成地址、数据、控制和比较。
- March 算法通过有序全地址读写覆盖常见 memory fault。
- 覆盖率、测试时间、面积和时序影响必须一起权衡。

### 复习与自测

1. 为什么制造测试不能只靠 RTL 仿真？

   答案：RTL 仿真验证设计逻辑，不能发现真实硅片制造中的开路、短路、桥接、cell stuck-at、译码错误等物理缺陷。

2. 为什么嵌入式 SRAM 不适合只靠 CPU 程序测试？

   答案：CPU 测试依赖芯片能启动和软件能运行，且访问路径经过总线和系统结构，不能保证直接、完整、高覆盖地测试每个 memory cell。

3. MBIST 中 function/test MUX 的作用是什么？

   答案：正常模式下让 CPU/AHB 等 function path 访问 memory；测试模式下让 BIST 控制器生成的地址、数据和控制信号接管 memory。

4. March 算法为什么要按地址方向反复读写 0 和 1？

   答案：不同方向和不同历史值的读写序列能暴露 stuck-at、transition、地址译码、耦合等故障，比单次写读覆盖更高。

5. `bist_done=1` 和 `bist_fail=0` 分别说明什么？

   答案：`bist_done=1` 表示测试流程走完，`bist_fail=0` 表示测试期间未检测到读出值和期望值不一致；两者一起才表示本轮 BIST 通过。

## 工程核对口径

完成本章后，要能把 MBIST 从概念落到项目检查：

1. 能说清 function path、test path 和 mux 边界。
2. 能解释 March 算法为什么要多轮全地址读写。
3. 能把 `bist_done/bist_fail` 和 compare 逻辑联系起来。
4. 能说明覆盖率、测试时间、面积、时序影响之间的取舍。
5. 能判断一张 MBIST 波形是“只是启动了”，还是“已经完整通过”。


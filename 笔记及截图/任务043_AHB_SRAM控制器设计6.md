# 43_AHB_SRAM控制器设计6

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：读 SRAM macro datasheet 和库文件，把 `sram_sp_hse_8kx8` 的规格、端口、真值表、功耗表、模型文件和 RTL wrapper 连接到 AHB SRAM controller。
- 核心概念：single-port synchronous SRAM、`8192x8`、TSMC CL018G、access time、cycle time、logic table、`CEN/WEN/OEN`、data out、standby、high-Z、PVT corner、`.lib/.db/.v/.lef/.gds/.tlf`、BIST ports。
- 逻辑主线：前端集成 SRAM macro 不能只会例化模块名。必须能从 datasheet 读出容量、端口语义、控制真值、时序/功耗边界和库文件用途，再把这些约束落实到 `sram_core` 与 `ahb_slave_if` 的控制信号。
- 最小学习路径：先读宏的身份和容量，再读 block diagram 和 truth table，随后看功耗/PVT，再回到工程目录里的模型与库文件，最后检查 RTL 端口是否保留 BIST/DFT 钩子。

### 2. 概念地图

| 层级 | 核心对象 | 读什么 | 工程意义 |
|---|---|---|---|
| 宏身份 | `sram_sp_hse_8kx8` | single-port、8192x8、工艺节点 | 确认容量和接口边界 |
| 端口结构 | block diagram | 地址、数据、CLK、CEN、OEN、WEN | 决定 wrapper 端口连接 |
| 行为语义 | logic table | standby/write/read/high-Z | 决定控制脚有效电平 |
| 时序边界 | access/cycle time | 读写能否单周期完成 | 决定 HREADY 策略 |
| PVT/功耗 | power table | read/write/standby current | 决定 bank gating 价值 |
| 库文件 | `.lib/.db/.lef/.gds/.v` | 仿真、综合、STA、后端各用什么 | 正确交付和集成 |
| 测试接口 | BIST/DFT ports | `bist_done/fail`、测试控制 | 后续 Memory BIST |

### 3. 阅读顺序

```text
datasheet 首页
  -> block diagram
  -> logic table
  -> power/PVT table
  -> model 目录中的库文件
  -> RTL wrapper 的 macro 端口和 BIST/DFT 信号
```

## 全视频地图

| 时间段 | 视频块 | 画面证据 | 这一段要学会什么 |
|---|---|---|---|
| 00:00-10:00 | Datasheet 首页和 macro 身份 | `sram_sp_hse_8kx8`、`8192X8`、工艺/速度信息 | 从名字和首页读出容量、端口类型、工艺和基本时序边界。 |
| 15:00 左右 | Block diagram | 地址、数据、`CLK/CEN/OEN/WEN` | wrapper 连接不是凭感觉，要按 macro 端口语义生成控制。 |
| 20:00 左右 | Logic table | `CEN/WEN/OEN`、Mode、Data Out | 真值表是控制脚的判定标准，低有效和输出状态不能猜。 |
| 25:00 左右 | 功耗/PVT 表 | read/write current、standby、corner | bank gating 和 deselect 关系到功耗，不只是功能正确。 |
| 30:00 左右 | 模型库文件 | `.v/.lib/.db/.lef/.gds/.tlf` | 不同文件服务仿真、综合、STA、后端和版图交付，不能混用。 |
| 35:00 左右 | BIST/DFT 端口 | `bist_done*`、`bist_fail*` | 正常功能路径和测试路径都连到 SRAM，但控制权必须分清。 |
## 1. `sram_sp_hse_8kx8` 的名字已经包含关键信息

`sram_sp_hse_8kx8` 可以拆开读：`sram` 是存储器类型，`sp` 是 single port，`hse` 表示高速增强一类宏，`8kx8` 表示深度 8192、宽度 8 bit。它不是 RTL 里随便写的数组，而是 memory compiler 生成的硬宏及其配套模型。

视觉验证：视频 00:00-10:00，画面应能看到 datasheet 首页中的 `High-Speed Single-Port Synchronous SRAM`、`sram_sp_hse_8kx8`、`8192X8`、TSMC CL018G、access/cycle time 等信息。

![SRAM datasheet overview](<./screenshots/任务043_AHB_SRAM控制器设计6/task43_00_datasheet_overview_00m00s.jpg>)

最小容量计算：

```text
8192 x 8 bit = 8192 byte = 8KB
8 个 8KB macro = 64KB
```

这和前面 AHB SRAM controller 的 64KB 地址窗口对应。若一个 bank 由 4 个 8-bit macro 拼成 32-bit 宽，则一个 bank 容量是 `8192 x 32 bit = 32KB`，两个 bank 正好 64KB。

## 2. Block diagram 告诉你 wrapper 该连哪些脚

SRAM block diagram 把 macro 内部拆成 memory core、wordline driver、precharge、write driver、sense amplifier、input/output buffer、address decode 和 clock/control。前端不需要设计这些模拟/存储阵列细节，但必须正确驱动它们暴露出来的端口。

视觉验证：视频 15:00 左右，画面应能看到 SRAM block diagram，包含地址输入、数据输入输出、`CLK/CEN/OEN/WEN` 等控制端口。

![SRAM block diagram](<./screenshots/任务043_AHB_SRAM控制器设计6/task43_01_sram_block_diagram_15m00s.jpg>)

controller 看到的是端口，不是内部晶体管：

| Macro 端口 | 语义 | controller 要做什么 |
|---|---|---|
| `A[12:0]` | 8192 深度地址 | 从 SRAM offset 中切出 macro 内部地址 |
| `D[7:0]` | 写数据 | 从 `HWDATA` 选择对应 byte lane |
| `Q[7:0]` | 读数据 | 拼接成 32-bit `sram_data_out` |
| `CLK` | 同步时钟 | 连接系统或 SRAM 时钟 |
| `CEN` | chip enable，低有效 | 只有访问目标 macro 时拉低 |
| `WEN` | write enable，低有效 | 写周期拉低，读周期拉高 |
| `OEN` | output enable，低有效 | 读周期允许输出 |

如果把这些控制脚的有效电平理解反了，波形会看起来“有变化”，但 macro 实际没有执行预期操作。

## 3. Logic table 是读写控制的法律文本

SRAM logic table 直接规定 `CEN/WEN/OEN` 不同组合下 macro 是 standby、write、read 还是 high-Z。它比口头经验更可靠，RTL 的控制脚生成必须和这张表一致。

视觉验证：视频 20:00 左右，画面应能看到 SRAM Logic Table，列出 `CEN/WEN/OEN`、Data Out、Mode、Function。

![SRAM logic table](<./screenshots/任务043_AHB_SRAM控制器设计6/task43_02_logic_table_20m00s.jpg>)

典型读法：

| `CEN` | `WEN` | `OEN` | 模式 | 输出 | 含义 |
|---|---|---|---|---|---|
| H | X | X | Standby | Last Data | 未选中，不进行新访问 |
| L | L | L 或 X | Write | Data In 或相关定义 | 将 D 写入地址 A |
| L | H | L | Read | SRAM Data | 从地址 A 读出 Q |
| X/L | X/H | H | High-Z | Z | 输出关闭 |

以 datasheet 为准，不同库的表述可能略有差异。对本项目最重要的结论是：`CEN/WEN/OEN` 是低有效控制，读写模式由三者组合决定。AHB slave interface 的 `bank*_csn`、`sram_w_en`、`read enable` 都必须和这张表对齐。

## 4. 功耗表说明 bank gating 不是装饰

SRAM datasheet 中的功耗表按 PVT corner、读写状态和 standby 状态列出电流。读写 AC current 远高于 standby current，说明“未访问 bank 不打开”不是为了代码好看，而是为了减少真实芯片功耗。

视觉验证：视频 25:00 左右，画面应能看到 power table，包括 read/write AC current、peak current、deselected current、standby current 和 fast/typical/slow corner。

![SRAM power table](<./screenshots/任务043_AHB_SRAM控制器设计6/task43_03_power_table_25m00s.jpg>)

前端设计要得到两个判断：

1. 功能正确只证明能读写，不证明功耗合理。
2. 低功耗首先体现在控制脚：未命中 bank 的 `CEN/CSN` 不应被打开。

NPU 里的 SRAM 占面积和动态功耗都很大。buffer banking、clock gating、chip select gating 这些动作，最后都会落实为“少打开不需要的 SRAM 宏”。

## 5. 模型目录里的文件服务不同阶段

课程中进入 `model/` 目录查看 SRAM macro 交付物。一个 memory macro 通常不只给一个 `.v` 文件，还会带综合库、时序库、物理抽象、版图、功耗/时序相关文件。每种文件服务不同工具链阶段。

视觉验证：视频 30:00 左右，画面应能看到 `model/` 目录中 `.lib`、`.db`、`.v`、`.lef`、`.gds`、`.tlf` 等文件。

![Model library files](<./screenshots/任务043_AHB_SRAM控制器设计6/task43_04_model_library_files_30m00s.jpg>)

常见文件用途：

| 文件类型 | 主要用途 |
|---|---|
| `.v` | RTL/门级仿真的行为模型或 blackbox 模型 |
| `.lib` | STA、综合、功耗分析使用的 Liberty 库 |
| `.db` | Synopsys 工具使用的编译后二进制库 |
| `.lef` | 后端布局布线使用的物理抽象 |
| `.gds` | 最终版图数据 |
| `.tlf/.sdf/.spef` 等 | 不同流程下的时序或寄生相关数据 |

前端同学至少要知道仿真用哪个模型、综合是否需要 blackbox、STA 用哪个 corner 的 `.lib`，否则“仿真过了”也无法进入真实交付流程。

## 6. RTL wrapper 必须保留 BIST/DFT 接口边界

本讲后段回到 RTL，看 `sram_core` 和相关 wrapper 中的 `bist_done`、`bist_fail`、`dft_en` 等端口。这些信号不是普通功能读写路径的一部分，却是芯片制造测试和量产筛选的重要入口。

视觉验证：视频 35:00 左右，画面应能看到 RTL 中 `bist_done0...bist_done7`、`bist_fail0...bist_fail7` 等 BIST 相关信号。

![BIST ports in RTL](<./screenshots/任务043_AHB_SRAM控制器设计6/task43_05_bist_ports_35m00s.jpg>)

正确分层是：

```text
function path:
  AHB -> ahb_slave_if -> bank/lane/write/read -> SRAM macro

BIST/DFT path:
  test enable -> BIST controller/wrapper -> SRAM macro test pins -> done/fail
```

两条路径都连接 SRAM macro，但控制权不同。正常功能模式下，AHB controller 主导读写；测试模式下，BIST/DFT 逻辑主导存储器访问。后续任务会专门讲 Memory BIST，这里先把接口边界认清。

## 7. 从 datasheet 回到 RTL 的检查清单

读完 datasheet 后，应该能回到 RTL 做一轮接口检查：

```text
容量:
  8K x 8 macro 数量是否能拼成 64KB

地址:
  macro address 位宽是否为 13 bit
  bank select 是否来自正确 offset 高位

控制:
  CEN/WEN/OEN 是否按低有效生成
  standby 时未访问 bank 是否保持未选中

数据:
  写数据 byte lane 是否和 HSIZE/HADDR 对齐
  读数据拼接顺序是否和 lane 定义一致

时序:
  access/cycle time 是否支持当前 HREADY 策略

测试:
  BIST/DFT 接口是否保留并正确连到 wrapper
```

这张清单比“看懂了 datasheet”更重要。真正的学习结果是能把规格转成 RTL 和验证点。

## 8. 本讲和 AI+IC/NPU 的连接

AI 芯片里的 SRAM macro 数量通常远多于通用控制器项目。你需要频繁读不同容量、宽度、PVT 和功耗特性的 memory macro 文档，然后决定如何 bank、如何拼宽、如何做低功耗片选、如何接 BIST。SRAM datasheet 阅读能力，是 NPU 存储系统设计的基本功。

## 9. 深层理解：datasheet 是硬件合同，不是资料截图

SRAM datasheet 不是“看一下参数”的文档，而是 controller 和 memory macro 之间的硬件合同。合同里写了容量、端口、低有效控制、地址位宽、读写时序、功耗状态、测试端口和交付文件。RTL 设计者的任务是把合同条款翻译成可执行代码、可检查波形和可交付约束。

| datasheet 条款 | RTL 设计决策 | 验证/实现检查 |
|---|---|---|
| `8K x 8` | 13-bit 地址、8-bit lane、多个 macro 拼 32-bit | 地址位宽、lane 拼接、容量边界 |
| logic table | `CEN/WEN/OEN` 低有效组合 | read/write/standby 波形是否合法 |
| access/cycle time | `HREADYOUT` 是否可单拍，是否需要等待 | 读数据采样点、STA 约束 |
| power table | 未访问 bank/lane 不应打开 | bank/lane 片选是否最小化 |
| model files | `.v/.lib/.db/.lef/.gds` 各给不同工具 | 仿真、综合、STA、布局布线是否拿对文件 |
| BIST/DFT pins | wrapper 保留测试路径 | function/test mux 和制造测试入口 |

datasheet 像建筑图纸和材料说明：看懂图纸不等于房子建对，必须把每个尺寸、材料和施工要求落到代码、脚本、报告和测试里。

## 10. 失败信号：哪类文件错会在哪一站暴露

| 文件/信息 | 服务阶段 | 错误表现 |
|---|---|---|
| `.v` model | RTL/门级仿真 | 仿真找不到模块、端口不匹配、行为模型不符合预期 |
| `.lib` | 综合、STA | timing arc 缺失、corner 不对、面积/功耗报告不可信 |
| `.db` | Synopsys 工具读取 | DC 读库失败或映射不到目标单元 |
| `.lef` | P&R 抽象 | 后端看不到 macro 尺寸、pin 或 blockage |
| `.gds` | 版图交付 | 最终物理实现缺失或 tapeout 数据不完整 |
| logic table | RTL 控制脚 | 低有效读反，所有 bank/lane 行为反相 |
| timing table | HREADY/counter/STA | 单拍返回过早，或等待时间不足 |

所以不要把“仿真过了”当成全链路通过。仿真只证明模型和当前激励下的行为，综合/STA/后端还要依赖不同文件和参数。

## 最后速记

### 本章最该记住的结论

- `8K x 8` 表示 8192 个 8-bit 单元，即 8KB。
- SRAM macro 不懂 AHB，只懂地址、数据、时钟和 `CEN/WEN/OEN`。
- logic table 是控制脚生成的依据，尤其要注意低有效。
- 功耗表说明未访问 bank 必须尽量不打开。
- `.v/.lib/.db/.lef/.gds` 服务不同工具阶段，不能混用。
- BIST/DFT 端口是制造测试入口，和正常 AHB function path 要分清。

### 复习与自测

1. 一个 `8192x8` SRAM macro 容量是多少？

   答案：8192 个 8-bit 单元，即 8192 byte，等于 8KB。

2. 为什么 AHB controller 不能把 `HWRITE` 直接接到 `WEN`？

   答案：`WEN` 通常低有效，而且 SRAM 写入还需要 chip enable、地址、数据、byte lane 和时序对齐；`HWRITE` 只是 AHB 侧方向信号，不能直接作为 macro 写使能。

3. `.lib` 和 `.v` 的用途有什么区别？

   答案：`.v` 主要用于仿真或 blackbox 表达，`.lib` 主要用于综合、STA 和功耗/时序分析。仿真过了不代表 `.lib` corner 和时序约束已经满足。

4. 为什么 standby current 对 controller 设计有意义？

   答案：它说明未访问 SRAM bank 的功耗远低于读写状态，因此 controller 应该只打开目标 bank/lane，避免所有 macro 同时翻转。

## 工程核对口径

本章学完后，拿到任意 SRAM macro datasheet 要能做三件事：

1. 算容量、地址位宽和 lane 拼接方式。
2. 按 logic table 写出 read/write/standby 的控制脚组合。
3. 把 access/cycle time 转成 AHB 等待策略或时序约束。
4. 说明 `.v/.lib/.db/.lef/.gds` 分别在哪个工具阶段使用。
5. 找出 function path 和 BIST/DFT path 的边界。


# 41_AHB_SRAM控制器设计4

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：用 Verdi 波形反推 AHB SRAM controller 的真实数据路径，重点看 `sram_core` 端口、bank/lane 波形、读数据返回和 `ahb_slave_if` 中的读写控制逻辑。
- 核心概念：Verdi hierarchy、`sram_core`、`sram_q0...sram_q7`、`sram_data_out`、`bank_sel`、`bank0_csn/bank1_csn`、`hsize_sel`、`haddr_sel`、`sram_write`、`sram_read`、active-low chip select。
- 逻辑主线：波形不是孤立结果，必须能回到 RTL。先从 hierarchy 下钻到 SRAM macro，观察 AHB 事务如何变成 bank/lane 控制；再回到 `ahb_slave_if`，用代码解释为什么某个 bank 被选中、为什么某几个 byte lane 被打开、为什么 `HRDATA` 返回这个值。
- 最小学习路径：先看 Verdi 层级，再看 macro 端口和波形，随后读 `ahb_slave_if` 中 `sram_data_out`、`sram_write/read`、`bank*_csn` 和 byte lane 生成逻辑。

### 2. 概念地图

| 层级 | 核心对象 | 本讲要掌握的判断 | 后续用途 |
|---|---|---|---|
| 波形层 | AHB 信号、SRAM q、bank 控制 | 一笔写读是否真的到达 macro | 功能 debug |
| Macro 层 | `sram_core` 端口 | SRAM macro 只认地址、控制和数据，不认 AHB 协议 | 接口转换 |
| 返回路径 | `sram_q*` -> `sram_data_out` -> `HRDATA` | bank 选择决定读哪个 32-bit 片段 | 读数据 mux |
| 写读使能 | `sram_write/sram_read/sram_w_en` | 有效 AHB transfer 才能触发 SRAM | 防止误访问 |
| 片选逻辑 | `bank0_csn/bank1_csn` | `CSN` 是低有效，0 才表示选中 | bank/lane 选择 |
| 宽度逻辑 | `HSIZE + HADDR[1:0]` | byte/halfword/word 决定打开几个 lane | 支持 8/16/32-bit |

### 3. 阅读顺序

```text
Verdi hierarchy
  -> sram_core 端口
  -> SRAM q 和 bank 控制波形
  -> ahb_slave_if 读数据 mux
  -> sram_write/sram_read 生成
  -> bank select 和 byte lane 片选
```

## 全视频地图

| 时间段 | 视频块 | 画面证据 | 这一段要学会什么 |
|---|---|---|---|
| 05:00 左右 | Verdi 层级和波形 | `sramc_top`、`ahb_slave_if`、`sram_core` | 顶层 AHB 波形不够，要下钻到 SRAM 层确认事务真的到达 macro。 |
| 10:00 左右 | `sram_core` 端口 | `sram_q0...sram_q7` 与控制端口 | SRAM core 不懂 AHB，只接收地址、控制、写数据并返回 macro q。 |
| 15:00 左右 | bank/lane 波形 | bank control、lane select、SRAM q | 低有效 `CSN` 中 0 才是选中，不能把 1 当 enable。 |
| 20:00 左右 | TB 时钟与波形对齐 | clock/reset 代码和波形 | 如果波形和 task 预期不对齐，先查 clock、reset、task 是否真的执行。 |
| 30:00 左右 | 工具运行结果 | VCS 编译/仿真日志 | 编译能跑只证明工具链通了，不证明读写功能正确。 |
| 35:00-40:00 | 回到 RTL 解释波形 | `sram_data_out`、`sram_read/write`、`bank*_csn` | 波形里的 bank 和 lane 必须能由 RTL 逻辑逐项解释。 |
## 1. Verdi 先证明“事务真的进入了 SRAM 层”

本讲开头在 Verdi 中下钻层级，目标不是看界面，而是确认一笔 AHB 写读事务已经穿过 `sramc_top` 和 `ahb_slave_if`，到达 `sram_core` 以及里面的多个 SRAM macro 实例。只看顶层 AHB 波形无法证明 SRAM 被正确访问，必须看到 macro 端口级别的响应。

视觉验证：视频 05:00 左右，画面应能看到 Verdi hierarchy、`sramc_top`、`ahb_slave_if`、`sram_core` 以及底部 AHB/SRAM 波形。

![Verdi hierarchy and waveform](<./screenshots/任务041_AHB_SRAM控制器设计4/task41_00_wave_hierarchy_05m00s.jpg>)

调试时建议把波形分成三组：

```text
AHB 事务组:
  hsel, htrans, hwrite, hsize, haddr, hwdata, hrdata

控制转换组:
  sram_write, sram_read, sram_addr, bank_sel, bank0_csn, bank1_csn

SRAM 返回组:
  sram_q0 ... sram_q7, sram_data_out
```

如果 AHB 组正确但控制转换组不动，问题在 `ahb_slave_if` 的有效访问判断或地址切片；如果控制转换组正确但 SRAM 返回组不对，问题可能在 macro 连接、bank/lane 片选或读数据 mux。

## 2. `sram_core` 是 AHB 协议被翻译后的世界

`sram_core` 的端口不会出现 `HTRANS/HRESP/HREADY` 这类 AHB 语义，它只接收 SRAM 需要的控制脚：clock、reset、读写使能、地址、写数据、bank 片选、BIST/DFT 相关信号，并输出每个 macro 的 q 数据。

视觉验证：视频 10:00 左右，画面应能看到 `sram_core.v` 的输入端口和 `sram_q0...sram_q7` 输出端口。

![SRAM core ports](<./screenshots/任务041_AHB_SRAM控制器设计4/task41_01_sram_core_ports_10m00s.jpg>)

这说明 controller 的职责已经发生了转换：

| AHB 侧问题 | SRAM 侧答案 |
|---|---|
| 这笔 transfer 是否有效 | 是否产生 `sram_read/sram_write` |
| 访问地址是多少 | `sram_addr` 和 `bank_sel` |
| 访问宽度是多少 | byte lane 的 `csn` 掩码 |
| 写数据是多少 | `sram_wdata` |
| 读回哪个 macro | `sram_q*` 经 mux 组成 `sram_data_out` |

如果你在 SRAM macro 端口上还想找 `HTRANS`，说明边界没分清。AHB 语义必须在 slave interface 中被消化，macro 只执行存储体读写。

## 3. 波形里的 bank/lane 是低有效控制

Verdi 波形中，`bank0_csn[3:0]` 和 `bank1_csn[3:0]` 不是“1 表示选中”，而是 `CSN` 低有效：某一位为 0，才表示对应 byte lane 被选中。`4'b0000` 是 4 个 byte lane 全选，`4'b1111` 是全不选。

视觉验证：视频 15:00 左右，画面应能看到 `sram_core` 端口、bank control 信号以及底部 bank/lane 波形。

![Macro waveform and bank lanes](<./screenshots/任务041_AHB_SRAM控制器设计4/task41_02_macro_wave_bank_lanes_15m00s.jpg>)

最小判断表：

| 访问类型 | 对齐地址 | 应打开的 lane | `csn` 直觉 |
|---|---:|---|---|
| 32-bit word | `HADDR[1:0]=00` | lane0-lane3 | `4'b0000` |
| 16-bit halfword | `HADDR[1]=0` | lane0-lane1 | `4'b1100` 或按项目位序等价 |
| 16-bit halfword | `HADDR[1]=1` | lane2-lane3 | `4'b0011` 或按项目位序等价 |
| 8-bit byte | `HADDR[1:0]` | 单个 lane | 只有一位为 0 |

位序要以项目 RTL 为准。学习时不要死背某张图的 `4'b1100` 是低半字还是高半字，要看 `haddr_sel` 到 `sram_csn` 的代码映射。

## 4. Testbench clock 和波形必须能对齐到事务

本讲在波形和 testbench 之间来回切换，是为了训练一件事：TB 里的一次 task 调用，必须能在波形上找到对应的地址阶段、数据阶段、SRAM 写入和读回。

视觉验证：视频 20:00 左右，画面应能看到 TB clock/reset 代码与底部波形同时出现。

![TB clock and waveform](<./screenshots/任务041_AHB_SRAM控制器设计4/task41_03_tb_clock_wave_20m00s.jpg>)

对齐方式：

```text
TB 中调用 ahb_write_32(addr, data)
  -> 波形中 HADDR/HTRANS/HWRITE 出现一拍地址阶段
  -> 下一拍 HWDATA 出现对应 data
  -> controller 打开 bank/lane 和 sram_w_en
  -> 后续 read task 读回同地址
  -> HRDATA 等于写入值
```

如果 TB 调用了 task 但波形中没有相应变化，先查 task 是否被注释、reset 是否未释放、clock 是否跑起来、Makefile 是否编译了最新 TB 文件。

## 5. 工具通过不等于功能通过

编译运行日志显示设计文件被解析、VCS 正常编译、仿真启动和结束，这只能说明工具链层面没有阻塞。它不自动证明 AHB SRAM controller 的功能正确。

视觉验证：视频 30:00 左右，画面应能看到 VCS 编译解析文件、进入仿真、生成结果的终端输出。

![Compile and simulation log](<./screenshots/任务041_AHB_SRAM控制器设计4/task41_04_compile_success_30m00s.jpg>)

要把成功信号分成两层：

| 层级 | 成功表现 | 不能替代什么 |
|---|---|---|
| 工具层 | 编译无 error、仿真能跑完、FSDB 能打开 | 不能证明读写功能正确 |
| 功能层 | 写入值能按地址和宽度读回，bank/lane 与预期一致 | 不能证明所有边界场景覆盖 |
| 覆盖层 | byte/halfword/word、边界地址、非法地址、reset、BIST 等用例都覆盖 | 不能靠单个 sanity test 代替 |

本讲主要做到工具层和基本功能层闭环，后续要继续扩展 testcase。

## 6. 读数据返回路径由 `bank_sel` 决定

`sram_core` 里多个 8-bit macro 输出会组成两个 bank 的 32-bit 数据，最终 `sram_data_out` 根据 `bank_sel` 从 bank0 或 bank1 中选一路返回 AHB。

视觉验证：视频 35:00 左右，画面应能看到 `ahb_slave_if.v` 中 `hrdata = sram_data_out`、`sram_data_out` 由 `bank_sel` 选择 `sram_q*` 拼接得到。

![AHB slave read and bank logic](<./screenshots/任务041_AHB_SRAM控制器设计4/task41_05_ahb_slave_read_bank_logic_35m00s.jpg>)

典型逻辑是：

```systemverilog
assign hrdata = sram_data_out;

assign sram_data_out =
    bank_sel ? {sram_q7, sram_q6, sram_q5, sram_q4}
             : {sram_q3, sram_q2, sram_q1, sram_q0};
```

这段代码回答的是“读回哪个 bank”。如果 `sram_q*` 本身正确但 `HRDATA` 错，优先查 `bank_sel` 和拼接顺序；如果 `bank_sel` 错，继续查 `sram_addr` 的高位切片。

## 7. `sram_write/read` 和 `bank*_csn` 是有效访问的硬件判据

`sram_write` 与 `sram_read` 必须来自有效 AHB transfer，而不是只看 `HWRITE`。一笔有效访问至少要满足 `HSEL` 选中、`HTRANS` 是 `NONSEQ/SEQ`、必要时 `HREADY` 表示地址阶段被接受。

视觉验证：视频 40:00 左右，画面应能看到 `sram_write`、`sram_read`、`sram_w_en`、`bank_sel`、`bank0_csn/bank1_csn`、`haddr_sel/hsize_sel` 的生成逻辑。

![Byte lane and CSN logic](<./screenshots/任务041_AHB_SRAM控制器设计4/task41_06_byte_lane_csn_logic_40m00s.jpg>)

代码逻辑可以拆成三层：

```systemverilog
// 1. 有效 AHB 访问
sram_write = valid_ahb && hwrite;
sram_read  = valid_ahb && !hwrite;

// 2. SRAM 内部地址和 bank
sram_addr = sram_write ? haddr_r[15:0] : haddr[15:0];
bank_sel  = sram_addr[15];

// 3. 低有效 bank 片选
bank0_csn = (sram_csn_en && bank_sel == 1'b0) ? sram_csn : 4'b1111;
bank1_csn = (sram_csn_en && bank_sel == 1'b1) ? sram_csn : 4'b1111;
```

其中写路径往往使用打一拍后的 `haddr_r/hsize_r`，读路径可能直接使用当前读地址或按设计打一拍。关键是不能把写数据阶段和下一笔地址阶段混在一起。

## 8. Byte lane 逻辑是 8/16/32-bit 支持的核心

本项目的 SRAM macro 是 8-bit 宽，多个 macro 组合成 32-bit bank。`HSIZE` 和地址低位决定一次访问到底选几个 byte lane。只要这里错，32-bit sanity test 可能通过，byte 和 halfword 仍然会错。

最小规则：

```text
HSIZE=word:
  只有 word 对齐访问，全 4 lane 选中

HSIZE=halfword:
  HADDR[1]=0 -> 低半字两个 lane
  HADDR[1]=1 -> 高半字两个 lane

HSIZE=byte:
  HADDR[1:0] 指定单个 lane
```

如果规格不支持未对齐 halfword/word，要明确是上游保证不会发，还是本 slave 返回 error。没有这条约定，验证和 RTL 很容易各按各的理解写。

## 9. 本讲和 AI+IC/NPU 的连接

NPU 片上 SRAM 经常按 bank 和 byte lane 组织。算子访存时，8-bit 权重、16-bit 激活、32-bit 配置寄存器或 DMA burst 可能共享同一组 SRAM 宏。你现在练的 `HSIZE + HADDR[1:0] -> byte lane`，就是后续理解 buffer banking、低功耗片选、访存冲突和带宽利用率的基础。

## 10. 深层理解：AHB 到 SRAM 是“翻译官 + 分拣机”

AHB 侧说的是协议语言：`HADDR`、`HTRANS`、`HWRITE`、`HSIZE`、`HWDATA`、`HRDATA`。SRAM macro 侧只听硬件脚语言：地址、片选、读写使能、写数据、读数据。`ahb_slave_if` 的角色就是翻译官，把协议句子翻成 SRAM 能执行的动作；bank/lane 逻辑则像分拣机，把一笔访问分到正确 bank 和正确 byte lane。

这个比喻能解释本讲最容易错的地方：翻译不能只翻一个词。`HWRITE=1` 只说明方向是写，不等于现在就能写 SRAM；还要看 transfer 是否有效、地址阶段和数据阶段是否对齐、`HREADY` 是否允许推进、`HSIZE/HADDR[1:0]` 打开哪些 lane。少看任一条件，都可能把错误的地址、错误的数据或错误的 byte lane 写进 SRAM。

## 11. 操作闭环：从错误 `HRDATA` 反推第一处故障

读回错误时，不要直接改 mux。按这条链路从外往内查：

| 层级 | 必看信号 | 通过标准 | 失败后下一步 |
|---|---|---|---|
| AHB 请求 | `HSEL/HTRANS/HWRITE/HSIZE/HADDR/HREADY` | 是有效读事务，地址和宽度合法 | 若无效，查 master 激励或 transfer 判断 |
| 地址保存 | `haddr_reg/bank_sel/haddr_sel` | 写数据阶段使用上一拍地址，读返回路径 bank 正确 | 若打一拍错，查地址/control pipeline |
| lane 片选 | `bank*_csn`、byte lane mask | 低有效，目标 lane 为 0，非目标为 1 | 若 lane 错，查 `HSIZE + HADDR[1:0]` |
| macro 输出 | `sram_q0...sram_q7` | 目标 macro 输出与预期存储值一致 | 若 q 错，查写入、地址、macro 连接 |
| 返回 mux | `sram_data_out/HRDATA` | mux 选择目标 bank/lane 并返回到 AHB | 若 q 对而 HRDATA 错，查 mux 和返回寄存 |

如果 `HREADY` 后续被改成可插 wait state，还要把“哪一拍采样地址、哪一拍写数据、哪一拍返回读数据”重新画成时序表。AHB 的两阶段像快递单和包裹分两步到柜台：第一拍登记地址，第二拍送来数据；柜台如果临时暂停收单，所有登记和分拣都必须跟着停住，不能只停一半。

## 最后速记

### 本章最该记住的结论

- 波形必须能回到 RTL，RTL 必须解释波形为什么这样变。
- `sram_core` 不懂 AHB，它只接收 SRAM 控制脚和数据。
- `CSN` 低有效，`0` 才表示对应 lane 被选中。
- `sram_data_out` 的 bank mux 决定 `HRDATA` 从哪组 `sram_q*` 来。
- `sram_write/read` 必须由有效 AHB transfer 生成，不能只看 `HWRITE`。
- Byte lane 逻辑决定 8/16/32-bit 访问是否真的正确。

### 复习与自测

1. 为什么编译无 error 不等于功能正确？

   答案：编译无 error 只说明工具能解析并运行设计，功能正确还需要证明写入、读回、bank 选择、byte lane、返回 mux 和边界场景都符合预期。

2. `bank0_csn=4'b1111` 表示什么？

   答案：如果 `CSN` 是低有效，`4'b1111` 表示 bank0 的四个 byte lane 全不选中。

3. 读回值不对时，应该先查 `HRDATA` 还是 `sram_q*`？

   答案：先沿路径查。若 `sram_q*` 已经正确，问题在 bank mux 或 `HRDATA` 返回；若 `sram_q*` 不正确，问题在写入、片选、地址或 macro 连接。

4. 为什么 32-bit 测试通过后仍要测 byte/halfword？

   答案：32-bit 访问通常打开所有 lane，无法暴露单 lane 和双 lane 片选错误；byte/halfword 才能检查 `HSIZE` 和地址低位的映射。

## 工程核对口径

本章合格标准不是“能打开 Verdi”，而是能用波形解释 RTL：

1. 能把一笔 AHB 读写从 `HADDR/HTRANS` 跟到 `bank*_csn` 和 `sram_q*`。
2. 能说明 AHB 地址阶段和数据阶段为什么会影响写地址保存。
3. 能按低有效语义读 `CSN/WEN/OEN`，不把 1 当作默认有效。
4. 能用 `HSIZE + HADDR[1:0]` 推导 byte lane。
5. 能在读回错误时定位到请求层、lane 层、macro 层还是返回 mux 层。


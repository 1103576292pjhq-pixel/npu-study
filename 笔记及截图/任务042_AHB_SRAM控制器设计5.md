# 42_AHB_SRAM控制器设计5

## 本章知识全景图

### 1. 一眼看懂这讲在讲什么

- 本章主题：继续调通 AHB SRAM controller 的 `ahb_slave_if`，把波形里的 bank/lane 行为落实到 `sram_read/sram_write`、地址选择、`HREADY` 响应、`hsize_sel/haddr_sel` 和 `bank*_csn` 生成逻辑。
- 核心概念：`sram_read`、`sram_write`、`sram_w_en`、`hready_resp`、`hready_r`、`hresp`、`sram_addr`、`sram_addr_out`、`hsize_sel`、`haddr_sel`、`bank_sel`、`bank0_csn/bank1_csn`、active-low enable。
- 逻辑主线：AHB slave interface 的难点不是写出几个 assign，而是保证“哪一拍被接受、哪一拍驱动 SRAM、哪几个 byte lane 被选中、哪一路数据返回”全部对齐。每条 RTL 都要能在 Verdi 波形上找到证据。
- 最小学习路径：先看波形确认读写闭环，再读 `sram_read/write` 的有效访问条件，然后看 `hready` 响应、地址 mux、bank select 和 byte lane 片选。

### 2. 概念地图

| 层级 | 核心对象 | 关键问题 | 错误后果 |
|---|---|---|---|
| 协议响应 | `hready_resp/hresp` | slave 是否承诺单周期响应 | master 采样时机错 |
| 访问分类 | `sram_read/sram_write` | 当前 transfer 是读还是写 | SRAM 被误读或误写 |
| 地址选择 | `sram_addr` | 写路径用打一拍地址，读路径用读地址 | 写数据写到错误地址 |
| 宽度选择 | `hsize_sel/haddr_sel` | byte/halfword/word 打开哪些 lane | 部分字节污染或未写 |
| bank 选择 | `bank_sel`、`bank*_csn` | 访问 bank0 还是 bank1 | 读错 bank 或双 bank 冲突 |
| 波形闭环 | Verdi trace | RTL 行为是否能解释波形 | 调试没有抓手 |

### 3. 阅读顺序

```text
从波形确认写读闭环
  -> 看 sram_core 和 q 输出
  -> 回到 ahb_slave_if
  -> 读 hready/hresp 的响应策略
  -> 读 sram_read/write 和地址选择
  -> 读 hsize/haddr 到 byte lane 的映射
  -> 用 bank_csn 波形验证结果
```

## 全视频地图

| 时间段 | 视频块 | 画面证据 | 这一段要学会什么 |
|---|---|---|---|
| 00:00 左右 | 波形闭环回看 | AHB、SRAM q、bank 控制波形 | 先确认写读结果存在，再回到 RTL 找每个结果的原因。 |
| 15:00 左右 | 地址与 bank 选择 | `sram_addr`、`sram_addr_out`、`bank_sel` | 写路径地址要对齐当前 `HWDATA`，读路径地址要对齐返回策略。 |
| 20:00 左右 | AHB 响应策略 | `hready_resp/hresp/hrdata` | `HREADYOUT` 固定高只有在单周期响应成立时才合理。 |
| 25:00 左右 | byte lane 生成 | `hsize_sel/haddr_sel/sram_csn` | `HSIZE + HADDR[1:0]` 决定打开哪个 byte lane，低有效要反着看。 |
| 30:00 左右 | 读写使能 | `sram_read/sram_write/sram_w_en` | 有效 transfer 才能触发 SRAM，不能响应 IDLE/BUSY。 |
| 45:00-50:00 | 波形验证和 warning | `bank*_csn` 波形、warning 弹窗 | 交付前要把 RTL 规则和 Verdi 证据逐条对上，并区分 warning 风险。 |
## 1. 波形闭环先给出“结果证据”

本讲继续在 Verdi 里观察同一批写读事务。波形里能看到 AHB 地址、写数据、读数据、SRAM q 输出、bank 片选和内部控制信号，这些信号共同证明 controller 不是只跑了 testbench，而是真的把访问送到了 SRAM 层。

视觉验证：视频 00:00 左右，画面应能看到 AHB 信号、SRAM q、`sram_csn_en`、`sram_addr`、bank 控制等波形。

![Waveform and SRAM core signals](<./screenshots/任务042_AHB_SRAM控制器设计5/task42_00_wave_sram_core_00m00s.jpg>)

读波形时不要只看最后 `HRDATA` 是否等于预期。更可靠的顺序是：

```text
1. HSEL/HTRANS/HWRITE/HADDR/HWDATA 是否形成合法事务
2. sram_write/sram_read 是否只在有效事务时触发
3. sram_addr 是否落到预期 bank 和 macro 地址
4. bank*_csn 是否只打开目标 bank/lane
5. sram_q* 是否返回写入过的数据
6. sram_data_out/HRDATA 是否选择了正确 bank
```

一旦某一级不对，下一级即使偶然正确也不能算设计正确。

## 2. `hready/hresp` 表达的是 slave 响应策略

代码中 `hready_resp` 和 `hresp` 常被写成固定值，表示这个 SRAM slave 暂时按单周期、无 error 响应处理。固定高 `HREADYOUT` 的前提是读路径能在 AHB 数据阶段前稳定返回；如果后续 SRAM 读延迟或 controller 增加等待周期，就必须同步修改 `HREADYOUT` 策略。

视觉验证：视频 20:00 左右，画面应能看到 `hready_r/hready_resp/hresp/hrdata` 等响应和返回逻辑。

![HREADY and response registers](<./screenshots/任务042_AHB_SRAM控制器设计5/task42_02_hready_delay_regs_20m00s.jpg>)

最小判断：

```systemverilog
assign hready_resp = 1'b1;
assign hresp       = 2'b00; // OKAY
assign hrdata      = sram_data_out;
```

这段写法不是永远正确，它只是建立在“当前设计可以单周期响应”的假设上。若读数据需要多拍，`HREADYOUT` 必须拉低插入 wait state，否则 AHB master 会在错误时间采样。

## 3. `sram_read/write` 必须排除 IDLE/BUSY

AHB 的 `HTRANS` 不是每一拍都代表有效访问。`IDLE/BUSY` 不应该触发 SRAM，`NONSEQ/SEQ` 才表示有效 transfer。代码中常用 `htrans == NONSEQ || htrans == SEQ` 来生成有效访问条件。

视觉验证：视频 30:00 左右，画面应能看到 `sram_write`、`sram_read` 和 `sram_w_en` 的生成逻辑。

![SRAM read and write enable](<./screenshots/任务042_AHB_SRAM控制器设计5/task42_04_sram_read_write_enable_30m00s.jpg>)

典型写法：

```systemverilog
assign sram_write = ((htrans == HTRANS_NONSEQ) || (htrans == HTRANS_SEQ)) &&
                    hwrite_r;

assign sram_read  = ((htrans == HTRANS_NONSEQ) || (htrans == HTRANS_SEQ)) &&
                    !hwrite;

assign sram_w_en  = sram_write;
```

真实工程中还应把 `HSEL`、`HREADYIN` 和 reset 条件纳入有效访问判断。本课代码为了讲主链路，可能简化部分条件；你自己写 RTL 时不能省掉协议有效性。

## 4. 写路径地址要和写数据阶段对齐

写操作最容易错在地址选择。AHB 的写地址在上一拍，写数据在当前拍。如果 `sram_addr` 在写数据阶段还直接用当前 `HADDR`，遇到 back-to-back transfer 时就可能把 A 的数据写到 B 的地址。

视觉验证：视频 15:00 左右，画面应能看到 `sram_addr`、`sram_addr_out`、`bank_sel` 和 bank 片选逻辑的代码。

![Bank select and address code](<./screenshots/任务042_AHB_SRAM控制器设计5/task42_01_bank_select_code_15m00s.jpg>)

正确口径：

```systemverilog
assign sram_addr =
    sram_write ? haddr_r[15:0] :
    sram_read  ? haddr[15:0]   :
                 16'b0;

assign sram_addr_out = sram_addr[14:2];
```

这里 `haddr_r` 是地址阶段保存下来的写地址，`haddr` 是当前读地址。具体位宽要跟 64KB 窗口、bank 数量和 `8K x 8` 宏深度匹配。

如果写路径没有用保存地址，32-bit 单笔测试可能仍然看不出错，因为下一拍地址可能还没变；一旦连续写或 burst，就会暴露错位。

## 5. `hsize_sel/haddr_sel` 把访问宽度落到 byte lane

`HSIZE` 和 `HADDR[1:0]` 决定当前访问是 1 个 byte、2 个 byte 还是 4 个 byte。实现里常先选出 `hsize_sel` 和 `haddr_sel`，再用组合逻辑生成 `sram_csn`。

视觉验证：视频 25:00 左右，画面应能看到 `hsize_sel`、`haddr_sel` 和 `sram_csn` 的组合逻辑。

![HSIZE byte lane logic](<./screenshots/任务042_AHB_SRAM控制器设计5/task42_03_hsize_byte_lane_logic_25m00s.jpg>)

最小规则：

```text
word:
  sram_csn = 4'b0000

halfword:
  address low half -> 打开两个低 byte lane
  address high half -> 打开两个高 byte lane

byte:
  HADDR[1:0] 选择唯一 byte lane
```

因为 `CSN` 低有效，所以“打开 lane”在代码里表现为对应 bit 置 0。初学者常把 1 当作 enable，导致所有 lane 判断反着写。

## 6. `bank_sel` 选择 32KB bank，`bank*_csn` 选择 bank 内 lane

若 64KB SRAM 用两个 32KB bank 组成，`sram_addr[15]` 可以作为 bank 选择位；每个 bank 内再用 `sram_csn[3:0]` 控制 4 个 byte lane。这样一次访问只打开目标 bank 的目标 lane，另一 bank 保持全不选。

视觉验证：视频 45:00 左右，画面应能看到 `bank0_csn/bank1_csn` 波形和 `sram_addr[15]`、`sram_csn` 的对应关系。

![Bank CSN waveform](<./screenshots/任务042_AHB_SRAM控制器设计5/task42_05_bank_csn_wave_45m00s.jpg>)

典型逻辑：

```systemverilog
assign bank_sel = sram_addr[15];

assign bank0_csn = (sram_csn_en && (bank_sel == 1'b0)) ? sram_csn : 4'b1111;
assign bank1_csn = (sram_csn_en && (bank_sel == 1'b1)) ? sram_csn : 4'b1111;
```

这段逻辑同时服务功能和功耗：功能上防止写错 bank，功耗上避免无关 SRAM macro 被唤醒。NPU buffer 设计中，类似 bank gating 是降低 SRAM 动态功耗的基本动作。

## 7. 工具 warning 要区分“可忽略”和“必须修”

本讲后段有保存文件、重新跑仿真、查看 warning 的过程。工具 warning 不能一概忽略，也不能一概当成 bug。判断标准是它是否影响综合语义、仿真语义或波形证据。

视觉验证：视频 50:00 左右，画面应能看到代码保存后的 warning 弹窗和 Verdi/代码界面。

![Final code warning](<./screenshots/任务042_AHB_SRAM控制器设计5/task42_06_final_code_warning_50m00s.jpg>)

处理原则：

| warning 类型 | 处理口径 |
|---|---|
| 文件被外部修改 | 确认是否另一个工具保存过，避免覆盖新内容 |
| 未连接端口 | 若端口功能相关，必须修；若保留接口，需有注释或 tie-off |
| 位宽不匹配 | 优先检查地址、数据、lane mask，不能随便截断 |
| latch 推断 | 组合逻辑缺 default 或分支不全，通常必须修 |
| unreachable/unused | 结合设计意图判断，不能长期堆积 |

交付前端 RTL 时，warning 本身也是质量信号。一个“功能刚好跑通但 warning 一堆”的设计，不适合直接交给综合或后端。

## 8. 本讲和 AI+IC/NPU 的连接

AI 加速器的片上存储访问往往不是简单 32-bit word。权重可能是 8-bit，激活可能是 8/16-bit，配置寄存器可能是 32-bit，DMA 或阵列访问还可能需要 bank 交错。`HSIZE/HADDR -> lane mask -> bank_csn` 这条链路，是以后理解 NPU SRAM banking、partial write、读改写和低功耗访问的基础。

## 9. 深层理解：AHB slave 像窗口柜台，`HREADYOUT` 决定是否收单

把 AHB slave 想成办事窗口。master 每拍递来一张单子：地址、方向、大小和数据。`HREADYOUT=1` 表示窗口说“我处理得过来，下一张可以继续”；`HREADYOUT=0` 表示“暂停，上一张还没处理完，别换下一张”。如果你的 SRAM controller 永远把 `HREADYOUT` 绑成 1，就等于承诺每笔读写都能单拍完成。

这个承诺只有在本设计的读写路径足够短、SRAM 返回足够快、控制路径不需要等待时才成立。后续如果 SRAM macro 需要多拍读，或者 eFlash 这种慢 IP 接到 AHB，就必须插 wait state。否则 master 会以为数据已经有效，实际 `HRDATA` 还没准备好。

## 10. 连续写和 burst 的最小波形判据

连续写最容易暴露“地址打一拍”问题。合格波形应该满足：

| 拍 | AHB 侧 | SRAM 侧应看到 |
|---|---|---|
| N | 地址 A、`HWRITE=1`、有效 transfer | 保存地址 A 和控制信息，不一定立刻用当前 `HWDATA` |
| N+1 | 地址 B、当前 `HWDATA` 属于地址 A | 用保存的地址 A、bank/lane A 和当前 `HWDATA` 写 SRAM |
| N+2 | 地址 C、当前 `HWDATA` 属于地址 B | 用保存的地址 B、bank/lane B 和当前 `HWDATA` 写 SRAM |

如果波形里 `HWDATA` 和当前 `HADDR` 被直接组合使用，连续写时就像快递员把上一张包裹贴到了下一张地址单上：单笔 demo 可能看不出来，连续访问必错。

失败信号：

- 连续写两个不同地址，第二个地址读回第一个数据。
- byte 写后相邻 byte 被改写。
- `HREADYOUT=0` 时内部地址寄存仍继续推进。
- `bank_sel` 和 `HWDATA` 不在同一个数据阶段对齐。

## 最后速记

### 本章最该记住的结论

- `HREADYOUT` 固定高只在单周期读写成立时才合理。
- `sram_read/write` 必须由有效 AHB transfer 生成，不能响应 IDLE/BUSY。
- 写路径地址要用上一拍保存值对齐当前 `HWDATA`。
- `HSIZE + HADDR[1:0]` 决定 byte lane，`CSN=0` 表示选中。
- `bank_sel` 选 bank，`bank*_csn` 选 bank 内 lane。
- 每条 RTL 规则都要能在 Verdi 波形里找到对应证据。

### 复习与自测

1. 为什么写路径不能直接用当前 `HADDR`？

   答案：AHB 写数据比地址/control 晚一拍，当前 `HADDR` 可能已经是下一笔访问的地址。写 SRAM 时要用上一拍保存的写地址对齐当前 `HWDATA`。

2. `HREADYOUT` 固定为 1 的前提是什么？

   答案：slave 能在 AHB 规定的数据阶段内完成响应，尤其读数据能按时稳定返回；若不能，就必须拉低 `HREADYOUT` 插入 wait state。

3. `bank0_csn=4'b1111`、`bank1_csn=4'b0000` 表示什么？

   答案：在低有效片选语义下，bank0 全不选，bank1 的 4 个 byte lane 全选中，通常对应 bank1 的 32-bit word 访问。

4. Byte 写访问需要哪些输入共同决定 lane？

   答案：`HSIZE` 指明访问宽度为 byte，`HADDR[1:0]` 指明目标 byte 在 32-bit word 中的位置。

## 工程核对口径

完成本章后，要能独立检查：

1. `HREADYOUT=1` 的设计假设是否真的成立。
2. 写路径是否用数据阶段对齐后的地址、bank 和 lane。
3. 连续写、byte 写、halfword 写是否都能在波形中解释。
4. warning 是否影响综合语义、仿真语义或接口连接。
5. 如果未来插入 wait state，哪些寄存器和片选逻辑必须受 `HREADY` 控制。


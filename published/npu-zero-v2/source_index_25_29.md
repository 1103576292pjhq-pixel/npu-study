# 25-29 来源索引

本索引来自 canonical 作者源的来源账，只包含本轮发布章节的 reader-facing 核对入口。

## 25_地址发生器与控制器
- `SRC01-CTRL` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU Andes NPU IP核设计从入门到精通》\01.html | lines 286-338 | control register, address map, busy flag, lifecycle control
- `SRC12-DMA` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\01.html | lines 270-338 | DMA async transfer, chained commands, scheduling
- `SRC17-LOOP` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\01.html | lines 385-393 | conv loop counters, stride-derived input address
- `GEMMINI` external_paper | https://arxiv.org/abs/1911.09925 | RoCC accelerator, scratchpad, DMA, systolic array | control/configuration boundary
- `TPU` external_paper | https://arxiv.org/abs/1704.04760 | matrix unit, buffer, system control | matrix unit supply and control context
- `MLIR-LINALG` external_official | https://mlir.llvm.org/docs/Dialects/Linalg/ | structured ops, indexing maps | compiler loop/indexing view of address generation

## 26_单层卷积完整执行链
- `SRC01-PIPE` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU Andes NPU IP核设计从入门到精通》\02.html | lines 331-344 | prefetch, SRAM read, compute array, writeback
- `SRC12-OVERLAP` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\01.html | lines 270-295 | DMA transfer and compute overlap
- `SRC17-CONV` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\01.html | lines 385-393 | conv loops mapped to PE execution
- `ONNX-CONV` external_official | https://onnx.ai/onnx/operators/onnx__Conv.html | Conv operator inputs/attributes | conv shape, stride, padding semantics
- `EYERISS` external_paper | https://arxiv.org/abs/1604.07316 | dataflow, on-chip storage, data reuse | CNN accelerator execution context
- `TPU` external_paper | https://arxiv.org/abs/1704.04760 | matrix unit, unified buffer | system-level execution chain

## 27_算子支持边界
- `SRC16-OPS` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU模型量化与算子融合优化从入门到精通》\01.html | lines 297-298; 388-393 | operator support differences, fusion, intermediate writeback
- `SRC18-TVM` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU神经网络编译器TVM NPU后端从入门到精通》\01.html | lines 287-309 | compiler uses hardware traits, operator fusion, backend challenges
- `SRC05-OV` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU Intel OpenVINO NPU插件从入门到精通》\01.html | lines 286-400 | OpenVINO Runtime, conversion, NPU plugin, optimization hints
- `ONNX-OPS` external_official | https://onnx.ai/onnx/operators/ | operator specifications | operator name plus attributes/inputs/outputs boundary
- `TVM-RELAX-TRANSFORM` external_official | https://tvm.apache.org/docs/reference/api/python/relax/transform.html | Relax transform API | graph/tensor transformations, pattern handling, lowering context
- `MLIR-LINALG` external_official | https://mlir.llvm.org/docs/Dialects/Linalg/ | structured ops and indexing maps | pattern matching and conversion context

## 28_量化与定点数
- `SRC16-QUANT` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU模型量化与算子融合优化从入门到精通》\01.html | lines 347-375 | quantization, 8-bit weight/activation, per-channel, calibration
- `SRC11-POWER` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU低功耗电源管理设计从入门到精通》\01.html | lines 203-208; 257-268 | MAC, storage, data movement and power
- `SRC05-QUANT` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU Intel OpenVINO NPU插件从入门到精通》\01.html | lines 292; 400 | model optimization and NPU-specific quantization
- `TFLITE-QUANT` external_official | https://www.tensorflow.org/lite/performance/quantization_spec | int8 quantization specification | scale, zero point, per-axis deployment rules
- `ONNX-QUANTIZE` external_official | https://onnx.ai/onnx/operators/onnx__QuantizeLinear.html | QuantizeLinear operator | rounding, saturation, zero point graph semantics
- `ONNX-DEQUANTIZE` external_official | https://onnx.ai/onnx/operators/onnx__DequantizeLinear.html | DequantizeLinear operator | dequantization formula

## 29_面积功耗性能取舍
- `SRC11-PPA` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU低功耗电源管理设计从入门到精通》\01.html | lines 185-208; 246-272 | power importance, dynamic/static power, storage power, DVFS
- `SRC15-BENCH` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU性能评测与基准测试从入门到精通》\01.html | lines 259-309 | CPU/GPU/NPU comparison, bandwidth, TOPS/W, benchmark
- `SRC01-METRICS` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU Andes NPU IP核设计从入门到精通》\02.html | lines 380-412 | performance, utilization, power, area, scalability
- `TPU` external_paper | https://arxiv.org/abs/1704.04760 | matrix unit, buffer, workload performance | peak versus real performance context
- `EYERISS` external_paper | https://arxiv.org/abs/1604.07316 | data reuse, hierarchy, energy efficiency | area/power/performance design tradeoff
- `GEMMINI` external_paper | https://arxiv.org/abs/1911.09925 | configurable systolic array, scratchpad, accumulator, DMA | configurable accelerator design space

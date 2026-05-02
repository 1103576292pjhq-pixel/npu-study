# 10-19 来源索引

本索引来自 canonical 作者源的来源账，只包含本轮发布章节的 reader-facing 核对入口。

## 10_卷积如何变成多重循环
- `EXT_ONNX_CONV` external_official | https://onnx.ai/onnx/operators/onnx__Conv.html | Conv operator schema | 来源; 正式定义; 工程判断
- `EXT_CS231N_CONV` external_course | https://cs231n.github.io/convolutional-networks/ | Convolutional Layer | 来源; 直觉解释; 最小例题
- `EXT_TVM_TENSORIR` external_official | https://tvm.apache.org/docs/deep_dive/tensor_ir/index.html | Loop Iterations / Transformation | 来源; NPU 连接; 工程判断
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\01.html | lines 377-393 3x3 卷积硬件循环伪代码 | 来源; NPU 连接
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\04.html | lines 216-253 hardware loop 概念 | 来源; 工程判断
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\01.html | lines 227-274 内存墙与 DMA 优化 | 来源; 工程判断

## 11_六重循环与七重循环
- `EXT_ONNX_CONV` external_official | https://onnx.ai/onnx/operators/onnx__Conv.html | Conv operator schema | 来源; 正式定义
- `EXT_MLIR_LINALG` external_official | https://mlir.llvm.org/docs/Dialects/Linalg/ | linalg conv named ops | 来源; NPU 连接
- `EXT_TVM_TENSORIR` external_official | https://tvm.apache.org/docs/deep_dive/tensor_ir/index.html | Loop Iterations / Leverage Localities | 来源; 工程判断
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\01.html | lines 377-393 3x3 卷积硬件循环伪代码 | 来源; 直觉解释
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\03.html | lines 269-336 数据复用与数据流模式 | 来源; 工程判断
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\02.html | lines 287-417 片上存储与 DMA 双缓冲 | 来源; 工程判断

## 12_NCHW_NHWC_数据布局
- `EXT_ONNX_TRANSPOSE` external_official | https://onnx.ai/onnx/operators/onnx__Transpose.html | Transpose operator schema | 来源; 常见误区; 工程判断
- `EXT_ONNX_RESHAPE` external_official | https://onnx.ai/onnx/operators/onnx__Reshape.html | Reshape operator schema | 来源; 常见误区
- `EXT_MLIR_LINALG` external_official | https://mlir.llvm.org/docs/Dialects/Linalg/ | NCHW/NHWC convolution ops | 来源; 正式定义
- `EXT_TVM_TENSORIR` external_official | https://tvm.apache.org/docs/deep_dive/tensor_ir/index.html | Loop Iterations / Transformation | 来源; NPU 连接
- `SRC18` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU神经网络编译器TVM NPU后端从入门到精通》\03.html | lines 328-417 内存层次与 Data Layout Transformation | 来源; NPU 连接
- `SRC18` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU神经网络编译器TVM NPU后端从入门到精通》\02.html | lines 346-416 调度原语 | 来源; 工程判断
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\01.html | lines 314-338 数据布局转换与内存对齐 | 来源; 工程判断

## 13_im2col_direct_conv_winograd
- `EXT_ONNX_CONV` external_official | https://onnx.ai/onnx/operators/onnx__Conv.html | Conv operator schema | 来源; 正式定义
- `EXT_TVM_TENSORIR` external_official | https://tvm.apache.org/docs/deep_dive/tensor_ir/index.html | TensorIR scheduling | 来源; NPU 连接; 工程判断
- `EXT_WINOGRAD` external_paper | https://arxiv.org/abs/1509.09308 | Fast Algorithms for Convolutional Neural Networks | 来源; 直觉解释; 工程判断
- `EXT_CS231N_CONV` external_course | https://cs231n.github.io/convolutional-networks/ | Convolutional Layer | 来源; 最小例题
- `SRC18` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU神经网络编译器TVM NPU后端从入门到精通》\02.html | lines 346-416 schedule primitives; 453-493 conv2d auto scheduling | 来源; 工程判断
- `SRC18` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU神经网络编译器TVM NPU后端从入门到精通》\03.html | lines 385-431 CONV instruction and schedule/codegen | 来源; NPU 连接
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\02.html | lines 287-417 on-chip storage and double buffering | 来源; 工程判断

## 14_tile为什么出现
- `EXT_TVM_TENSORIR` external_official | https://tvm.apache.org/docs/deep_dive/tensor_ir/index.html | Loop transformation and locality | 来源; 工程判断
- `EXT_MLIR_LINALG` external_official | https://mlir.llvm.org/docs/Dialects/Linalg/ | Structured ops | 来源; 正式定义
- `EXT_CS231N_CONV` external_course | https://cs231n.github.io/convolutional-networks/ | Convolutional Layer | 来源; 最小例题
- `EXT_ONNX_CONV` external_official | https://onnx.ai/onnx/operators/onnx__Conv.html | Conv attributes | 来源; 工程判断
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\01.html | lines 314-338 tiling and double buffering roadmap | 来源; 为什么学
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\02.html | lines 265-269 tiled load pseudo-code; 287-417 storage/DMA | 来源; 工程判断
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\04.html | lines 620-624 hardware loop engine | 来源; NPU 连接

## 15_数据复用
- `EXT_EYERISS` external_paper | https://eyeriss.mit.edu/ | Eyeriss dataflow and reuse | 来源; 正式定义; 工程判断
- `EXT_ONNX_CONV` external_official | https://onnx.ai/onnx/operators/onnx__Conv.html | Conv operator schema | 来源; 最小例题
- `EXT_CS231N_CONV` external_course | https://cs231n.github.io/convolutional-networks/ | Convolutional Layer | 来源; 直觉解释
- `EXT_TVM_TENSORIR` external_official | https://tvm.apache.org/docs/deep_dive/tensor_ir/index.html | Leverage Localities | 来源; 工程判断
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\03.html | lines 269-336 reuse/dataflow modes | 来源; 正式定义
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\05.html | lines 550-563 convolution dataflow reuse | 来源; NPU 连接
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\01.html | lines 227-274 memory wall and DMA | 来源; 为什么学

## 16_dataflow入门
- `EXT_EYERISS` external_paper | https://eyeriss.mit.edu/ | Row-stationary dataflow | 来源; 正式定义; 工程判断
- `EXT_TPU` external_paper | https://arxiv.org/abs/1704.04760 | In-Datacenter Performance Analysis of a Tensor Processing Unit | 来源; NPU 连接
- `EXT_TVM_TENSORIR` external_official | https://tvm.apache.org/docs/deep_dive/tensor_ir/index.html | Loop transformation and locality | 来源; 工程判断
- `EXT_MLIR_LINALG` external_official | https://mlir.llvm.org/docs/Dialects/Linalg/ | Structured op iteration semantics | 来源; 正式定义
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\03.html | lines 269-336 stationary modes and reuse hierarchy | 来源; 直觉解释
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\05.html | lines 232-268 dataflow architecture; 550-563 conv dataflow | 来源; NPU 连接
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\02.html | lines 287-417 on-chip storage and DMA | 来源; 工程判断

## 17_partial_sum部分和
- `EXT_EYERISS` external_paper | https://eyeriss.mit.edu/ | Dataflow and psum reuse | 来源; 正式定义; 工程判断
- `EXT_ONNX_CONV` external_official | https://onnx.ai/onnx/operators/onnx__Conv.html | Conv reduction semantics | 来源; 正式定义
- `EXT_CS231N_CONV` external_course | https://cs231n.github.io/convolutional-networks/ | Convolutional Layer | 来源; 最小例题
- `EXT_TPU` external_paper | https://arxiv.org/abs/1704.04760 | TPU systolic matrix multiply | 来源; NPU 连接
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\03.html | lines 285-288 output-stationary psum accumulation | 来源; 工程判断
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\04.html | line 446 loop dependency handled by dataflow/buffering | 来源; 工程判断
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\02.html | lines 287-417 storage and DMA double buffering | 来源; 工程判断

## 18_带宽瓶颈
- `EXT_ROOFLINE` external_paper | https://www.osti.gov/pages/biblio/1407073 | Roofline model | 来源; 正式定义; 工程判断
- `EXT_EYERISS` external_paper | https://eyeriss.mit.edu/ | Storage access and data reuse | 来源; 工程判断
- `EXT_TPU` external_paper | https://arxiv.org/abs/1704.04760 | TPU memory and matrix unit | 来源; NPU 连接
- `EXT_TVM_TENSORIR` external_official | https://tvm.apache.org/docs/deep_dive/tensor_ir/index.html | Locality optimization | 来源; 工程判断
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\01.html | lines 227-274 memory wall and DMA | 来源; 为什么学
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\03.html | lines 237-304 bandwidth definition and LPDDR5 example | 来源; 最小例题
- `SRC15` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU性能评测与基准测试从入门到精通》\01.html | lines 259-309 CPU/GPU/NPU performance comparison and TOPS/W | 来源; 为什么学; 工程判断

## 19_循环如何映射到硬件
- `EXT_TVM_TENSORIR` external_official | https://tvm.apache.org/docs/deep_dive/tensor_ir/index.html | Loop/block/schedule transformations | 来源; 工程判断
- `EXT_MLIR_LINALG` external_official | https://mlir.llvm.org/docs/Dialects/Linalg/ | Structured op iteration semantics | 来源; 正式定义
- `EXT_EYERISS` external_paper | https://eyeriss.mit.edu/ | Dataflow mapping | 来源; NPU 连接
- `EXT_TPU` external_paper | https://arxiv.org/abs/1704.04760 | Systolic array mapping | 来源; NPU 连接
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\04.html | lines 216-253 hardware loop; 620-624 configurable loop engine | 来源; 工程判断
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\03.html | lines 191-260 systolic array and PE data paths | 来源; NPU 连接
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\02.html | lines 287-417 on-chip storage, memory interface, DMA | 来源; 工程判断

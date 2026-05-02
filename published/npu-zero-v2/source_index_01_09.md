# 01-09 来源索引

本索引来自 canonical 作者源的来源账，只包含本轮发布章节的 reader-facing 核对入口。

## 01_数字_向量_矩阵_乘加
- `01-S1` https://onnx.ai/onnx/operators/onnx__Gemm.html | operator summary and inputs A/B/C, alpha, beta, transA, transB
- `01-S2` https://onnx.ai/onnx/operators/onnx__MatMul.html | summary and multidirectional broadcasting notes
- `01-S3` https://www.arm.com/products/silicon-ip-cpu/ethos/ethos-u55 | product overview and NPU positioning
- `01-S4` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU Andes NPU IP核设计从入门到精通》\01.html | line 167 and line 216
- `01-S5` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\01.html | line 290

## 02_张量_维度_形状
- `02-S1` https://onnx.ai/onnx/operators/onnx__Reshape.html | operator summary and inputs data/shape
- `02-S2` https://onnx.ai/onnx/operators/onnx__Transpose.html | operator summary and perm attribute
- `02-S3` https://mlir.llvm.org/docs/Dialects/Linalg/ | Linalg dialect overview and structured ops rationale
- `02-S4` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU神经网络编译器TVM NPU后端从入门到精通》\02.html | line 291 and line 296
- `02-S5` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU神经网络编译器TVM NPU后端从入门到精通》\03.html | line 366 and line 367

## 03_图像_特征图_通道
- `03-S1` https://cs231n.github.io/convolutional-networks/ | Convolutional Layer section
- `03-S2` https://onnx.ai/onnx/operators/onnx__Conv.html | inputs X/W/B and outputs Y
- `03-S3` https://mlir.llvm.org/docs/Dialects/Linalg/ | structured ops and indexing maps overview
- `03-S4` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU神经网络编译器TVM NPU后端从入门到精通》\03.html | line 357
- `03-S5` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU模型量化与算子融合优化从入门到精通》\01.html | line 204 and line 228

## 04_单通道卷积到底在做什么
- `04-S1` https://onnx.ai/onnx/operators/onnx__Conv.html | attributes pads/strides/dilations and inputs X/W
- `04-S2` https://cs231n.github.io/convolutional-networks/ | Convolutional Layer section
- `04-S3` https://mlir.llvm.org/docs/Dialects/Linalg/ | structured ops and iteration-space discussion
- `04-S4` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\01.html | line 377 to line 393
- `04-S5` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU Andes NPU IP核设计从入门到精通》\02.html | line 333 to line 344

## 05_stride_padding_输出尺寸
- `05-S1` https://onnx.ai/onnx/operators/onnx__Conv.html | attributes auto_pad, pads, strides
- `05-S2` https://mlir.llvm.org/docs/Dialects/Linalg/ | structured ops and indexing maps overview
- `05-S3` https://cs231n.github.io/convolutional-networks/ | Spatial arrangement section
- `05-S4` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\01.html | line 377 to line 386
- `05-S5` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU Andes NPU IP核设计从入门到精通》\02.html | line 335

## 06_多通道卷积
- `06-S1` https://onnx.ai/onnx/operators/onnx__Conv.html | inputs X/W/B and outputs Y
- `06-S2` https://cs231n.github.io/convolutional-networks/ | Convolutional Layer and depth discussion
- `06-S3` https://mlir.llvm.org/docs/Dialects/Linalg/ | structured ops and reduction-like loop discussion
- `06-S4` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU神经网络编译器TVM NPU后端从入门到精通》\03.html | line 357
- `06-S5` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU Andes NPU IP核设计从入门到精通》\02.html | line 262 to line 273 and line 336 to line 340

## 07_多卷积核_输出通道
- `07-S1` https://onnx.ai/onnx/operators/onnx__Conv.html | inputs W and output Y
- `07-S2` https://cs231n.github.io/convolutional-networks/ | Convolutional Layer depth discussion
- `07-S3` https://mlir.llvm.org/docs/Dialects/Linalg/ | structured ops and indexing maps overview
- `07-S4` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU Andes NPU IP核设计从入门到精通》\02.html | line 262 to line 273
- `07-S5` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU神经网络编译器TVM NPU后端从入门到精通》\03.html | line 357

## 08_激活_池化_残差
- `08-S1` https://onnx.ai/onnx/operators/onnx__Relu.html | operator summary and inputs/outputs
- `08-S2` https://onnx.ai/onnx/operators/onnx__MaxPool.html; https://onnx.ai/onnx/operators/onnx__AveragePool.html | operator summaries and attributes kernel_shape/strides/pads
- `08-S3` https://onnx.ai/onnx/operators/onnx__Add.html | operator summary and broadcasting note
- `08-S4` https://arxiv.org/abs/1512.03385 | abstract and residual learning formulation
- `08-S5` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU模型量化与算子融合优化从入门到精通》\01.html | line 235 to line 280 and line 388 to line 410

## 09_全连接_GEMM
- `09-S1` https://onnx.ai/onnx/operators/onnx__Gemm.html | operator summary and attributes alpha/beta/transA/transB
- `09-S2` https://onnx.ai/onnx/operators/onnx__MatMul.html | summary and multidirectional broadcasting notes
- `09-S3` https://www.netlib.org/blas/ | BLAS routine index
- `09-S4` https://mlir.llvm.org/docs/Dialects/Linalg/ | structured ops and indexing maps overview
- `09-S5` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU神经网络编译器TVM NPU后端从入门到精通》\02.html | line 392 to line 408
- `09-S6` C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU神经网络编译器TVM NPU后端从入门到精通》\03.html | line 402

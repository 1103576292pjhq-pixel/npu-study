# 20-24 来源索引

本索引来自 canonical 作者源的来源账，只包含本轮发布章节的 reader-facing 核对入口。

## 20_MAC与PE
- `SRC01` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU Andes NPU IP核设计从入门到精通》\01.html | line 216; line 247 | PE is schedulable local compute unit; scalable PE configuration
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\01.html | line 218; lines 287-305 | MAC array, systolic array, PE grid, dataflow context
- `SRC17-RTL` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\27.html | lines 355-358 | NPU_PE RTL entry supports PE ports/control/accumulator explanation
- `EYERISS` external_paper | https://arxiv.org/abs/1604.07316 | PE array; on-chip hierarchy; data reuse | PE array and psum/data reuse engineering context
- `TPU` external_paper | https://arxiv.org/abs/1704.04760 | matrix multiply unit; systolic execution; on-chip buffer | MAC array throughput and data supply boundary
- `ONNX-GEMM` external_official | https://onnx.ai/onnx/operators/onnx__Gemm.html | Gemm operator definition | separates GEMM semantics from MAC/PE implementation

## 21_PE阵列
- `SRC01` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU Andes NPU IP核设计从入门到精通》\01.html | line 216; line 247 | PE/dataflow and scalable PE count support array-scale explanation
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\01.html | lines 287-305 | PE grid, systolic array, dataflow architecture distinction
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\02.html | lines 213-221; lines 363-385 | compute unit array, on-chip SRAM/cache, DMA and double buffering
- `EYERISS` external_paper | https://arxiv.org/abs/1604.07316 | PE array; dataflow; psum | PE array/data reuse/psum handling
- `TPU` external_paper | https://arxiv.org/abs/1704.04760 | matrix multiply unit; utilization | array peak throughput vs system utilization
- `GEMMINI` external_paper | https://arxiv.org/abs/1911.09925 | configurable systolic array; scratchpad; accumulator | configurable array and storage context

## 22_脉动阵列
- `SRC17` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\01.html | lines 287-305 | systolic array definition with rhythmic data movement through PE grid
- `SRC01` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU Andes NPU IP核设计从入门到精通》\01.html | line 216; line 247 | custom dataflow and scalable PE configuration
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\01.html | lines 176-177; lines 200-221 | systolic array with memory hierarchy and dedicated DMA context
- `KUNG` external_paper | https://cir.nii.ac.jp/crid/1360855571261536896 | Why Systolic Architectures bibliographic DOI entry | historical definition, local communication, I/O motivation
- `TPU` external_paper | https://arxiv.org/abs/1704.04760 | systolic matrix multiply unit | large-scale systolic array and unified buffer example
- `GEMMINI` external_paper | https://arxiv.org/abs/1911.09925 | configurable systolic array; scratchpad; accumulator | open configurable systolic array and SoC integration

## 23_片上SRAM与buffer
- `SRC12` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\02.html | lines 136-180; lines 345-377 | compute array, on-chip SRAM/cache, memory subsystem and DMA
- `SRC17-BANK` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\24.html | line 339; lines 343-349 | SRAM bank exposure, dataflow configuration, compiler scheduling
- `SRC17-SRAM` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\27.html | lines 547-552 | SRAM next to PE array structural placement
- `EYERISS` external_paper | https://arxiv.org/abs/1604.07316 | on-chip storage hierarchy; data reuse; psum | SRAM/buffer role in reuse and psum handling
- `TPU` external_paper | https://arxiv.org/abs/1704.04760 | unified buffer; matrix unit | on-chip buffer and data supply boundary
- `GEMMINI` external_paper | https://arxiv.org/abs/1911.09925 | scratchpad; accumulator; systolic array | scratchpad and accumulator storage organization

## 24_DMA与双缓冲
- `SRC12-DMA` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\01.html | lines 270-308 | DMA, double buffering, compute-transfer overlap
- `SRC12-PINGPONG` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU内存带宽与DMA优化从入门到精通》\02.html | lines 383-418 | double-buffer DMA pseudocode and async prefetch
- `SRC17-DESC` local_html | C:\Users\11035\Desktop\ic\npu\14、NPU\《NPU硬件循环与数据流架构从入门到精通》\24.html | line 386; line 402; line 421 | DMA descriptor queue, DMA configuration, synchronization and resource management
- `GEMMINI` external_paper | https://arxiv.org/abs/1911.09925 | DMA; scratchpad; systolic array integration | DMA/scratchpad full-stack integration context
- `TPU` external_paper | https://arxiv.org/abs/1704.04760 | unified buffer and matrix unit | system boundary between matrix compute and buffer/memory
- `MLIR-LINALG` external_official | https://mlir.llvm.org/docs/Dialects/Linalg/ | structured ops and tiling | compiler representation background for tile/data movement

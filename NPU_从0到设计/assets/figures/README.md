# Figures

只放为理解机制而重绘的图，不放装饰图。

使用规则：

- 优先重绘心智模型图，不优先截整页课件图。
- 每张图要能回答一个明确问题，例如“数据为什么复用”“瓶颈为什么转移”。
- 图名与正文小节保持一致，方便交叉引用。

当前已落图：

- `04_tile_pipeline.svg`
  - 把 `tile / SRAM / local buffer / PE array / load-compute-store` 放到同一视角，回答“阵列为什么会等数据”。
- `06_multilevel_ir_pipeline.svg`
  - 把 `Graph IR -> Loop/Tensor IR -> Target/Command -> runtime.Module` 连成一条流水，回答“为什么不能一次翻到指令”。
- `08_latency_boundary.svg`
  - 区分 `FEIL / FIL / steady-state` 的时间边界，避免 benchmark 口径混淆。
- `10_end_to_end_closed_loop.svg`
  - 把综合案例的目标、硬件、编译、runtime、性能与安全闭环压到一张图里，回答“前九卷为什么能串成一条主线”。

# NPU 从 0 到设计（零基础重构版）

这是本项目的唯一作者源。本地 Markdown、Git 工作区和思源笔记只从这里发布，不在发布目标里反向改正文。

## 当前阶段

当前已完成教材工程骨架，并完成基础篇 `01-09` 的来源闸门修复与机器验证。

- 已建立 4 卷、36 章目录。
- 已建立每章 `meta.yaml`。
- 已建立本地来源台账与章节来源映射。
- 已建立章节内容标准、模板和批次 manifest。
- 旧版 00-04 入门稿已移到 `canonical/reference/draft-intro-v1`，作为参考稿，不再作为最终正文结构。
- `chapters/00-how-to-study/chapter.md` 沿用上一轮成果并修补了明显图片链接问题。
- `chapters/01-digits-vectors-matrices-mac/chapter.md` 至 `chapters/09-fully-connected-gemm/chapter.md` 已完成来源锚点补强。
- 01-09 均包含可复核外部 URL、完整本地 HTML 路径和来源落点，可进入本地 Markdown / Git 阅读目录发布验证。

## 四卷结构

1. `v1` 零基础认知地基：00-09
2. `v2` 算子到循环：10-19
3. `v3` NPU 微架构：20-29
4. `v4` 系统闭环：30-35

## 写作规则

每章必须先从直觉开始，再给定义，最后连接到 NPU 硬件；不能默认读者已经懂卷积、矩阵、张量、数据布局或硬件循环。

每章发布前至少经过三轮检查：

1. 正确性检查：公式、维度、例题、术语不能错。
2. 零基础检查：不能跳步，不能突然引入未解释术语。
3. 教材化检查：图解、例题、自测、误区、来源链要完整。

## 已发布目标

- 本地 Markdown：`C:\Users\11035\Desktop\study\md\npu-zero-v2`
- Git 工作区发布目录：`D:\github\npu-study\published\npu-zero-v2`
- 思源笔记：`IC设计 / NPU从0到设计（零基础重构版）`

当前本地 Markdown 与 Git 阅读目录将以 `01-09` 为本轮发布闸门；思源同步需等待 API 与图片资产检查。真实状态与后续检查清单见 [work/STATUS.md](../../work/STATUS.md)。

# 数字前端就业班 1906 视频笔记

这里保存课程视频笔记的可阅读 Markdown 版本。每个任务一个目录，目录内包含：

- `任务XX：标题.md`
- `screenshots/`：该任务笔记引用的关键截图

当前已整理：

| 任务 | 主题 |
| --- | --- |
| [任务01：数字IC设计流程](./任务01：数字IC设计流程/任务01：数字IC设计流程.md) | 数字 IC 设计流程、前后端分工、RTL 到 Netlist |
| [任务02：数字前端设计工程师就业班概述](./任务02：数字前端设计工程师就业班概述/任务02：数字前端设计工程师就业班概述.md) | 课程定位、工具链、项目训练、岗位能力 |
| [任务03：VNC服务器使用说明](./任务03：VNC服务器使用说明/任务03：VNC服务器使用说明.md) | VNC 登录、远程桌面、文件传输、常见问题 |
| [任务04：linux操作系统常用命令](./任务04：linux操作系统常用命令/任务04：linux操作系统常用命令.md) | Linux 路径、目录、文件、复制移动删除 |
| [任务05：linux与gvim文本编辑工具操作实践](./任务05：linux与gvim文本编辑工具操作实践/任务05：linux与gvim文本编辑工具操作实践.md) | 复制工程、保护原始文件、gvim 操作练习 |
| [任务06：gvim文本编辑工具](./任务06：gvim文本编辑工具/任务06：gvim文本编辑工具.md) | gvim 三种模式、列编辑、分屏、文件比较 |
| [任务07：数字电路基础](./任务07：数字电路基础/任务07：数字电路基础.md) | MOS、CMOS 反相器、功耗、工艺缩放、门电路 |
| [任务08：gvim正则表达式](./任务08：gvim正则表达式/任务08：gvim正则表达式.md) | 查找替换、字符类、数量词、分组、函数式替换 |
| [任务09：逻辑综合工具Design Compiler的使用](./任务09：逻辑综合工具Design Compiler的使用/任务09：逻辑综合工具Design Compiler的使用.md) | DC 综合输入、工艺库、SDC 约束、报告判断 |
| [任务10：数字电路基础-时序逻辑基础](./任务10：数字电路基础-时序逻辑基础/任务10：数字电路基础-时序逻辑基础.md) | latch、DFF、setup/hold、时序路径、CDC |
| [任务11：逻辑仿真工具VCS的使用-Makefile](./任务11：逻辑仿真工具VCS的使用-Makefile/任务11：逻辑仿真工具VCS的使用-Makefile.md) | X 态波形、VCS 编译运行、Makefile 工程复现 |
| [任务13：逻辑综合工具-DC实操](./任务13：逻辑综合工具-DC实操/任务13：逻辑综合工具-DC实操.md) | DC 实验目录、库配置、读入 RTL、报告与脚本化 |
| [任务14：逻辑综合工具-DC实操-02](./任务14：逻辑综合工具-DC实操-02/任务14：逻辑综合工具-DC实操-02.md) | create_clock、I/O delay、网表/SDC/SDF/DDC 交付 |
| [任务15：Verilog Systemverilog - 数据类型](./任务15：Verilog Systemverilog - 数据类型/任务15：Verilog Systemverilog - 数据类型.md) | 2/4 值类型、logic、enum、数组、队列与验证类型 |
| [任务16：操作符和过程控制](./任务16：操作符和过程控制/任务16：操作符和过程控制.md) | SV 操作符、X/Z 判断、循环、case/unique/priority |
| [任务17： task-function](./任务17： task-function/任务17： task-function.md) | task/function、参数传递、ref、automatic/static、作用域 |
| [任务18：并发线程](./任务18：并发线程/任务18：并发线程.md) | fork/join、join_any、join_none、begin/end 分组与时间推导 |
| [任务19：并发线程与SV实操](./任务19：并发线程与SV实操/任务19：并发线程与SV实操.md) | disable fork、VCS/Makefile 实操、display 时间验证 |
| [任务20： 经典组合和数字电路的设计](./任务20：%20经典组合和数字电路的设计/任务20：%20经典组合和数字电路的设计.md) | MUX、译码器、编码器、DFF、计数器、移位寄存器与 testbench |
| [任务21：有限状态机的写法](./任务21：有限状态机的写法/任务21：有限状态机的写法.md) | FSM、Moore/Mealy、三段式写法、状态波形 debug |
| [任务22：同步fifo-异步fifo的设计](./任务22：同步fifo-异步fifo的设计/任务22：同步fifo-异步fifo的设计.md) | FIFO、RAM、读写指针、计数器满空、同步/异步差异 |
| [任务23：同步FIFO设计方法2介绍与仿真](./任务23：同步FIFO设计方法2介绍与仿真/任务23：同步FIFO设计方法2介绍与仿真.md) | 扩展指针满空判断、同步 FIFO 方法 2、波形 debug |
| [任务25：CDC_Metastability（亚稳态）](./任务25：CDC_Metastability（亚稳态）/任务25：CDC_Metastability（亚稳态）.md) | CDC、亚稳态、两级同步器、脉冲/多 bit/复位跨域风险 |
| [任务29：Spyglass的基本使用-2](./任务29：Spyglass的基本使用-2/任务29：Spyglass的基本使用-2.md) | SpyGlass CDC setup、约束、报告和环境问题排查 |

仓库侧只保存 reader-facing 内容，不保存思源内部 `.sy` 文件、运行日志或临时状态文件。

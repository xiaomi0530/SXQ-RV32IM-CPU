# 访存握手与回归测试

> 后续 CSR/RTOS 扩展已改变错误处理和 MMIO 延迟：访存错误现在进入机器模式 trap，MMIO 为两拍响应，并增加 CLINT 兼容地址。下面保留第一轮访存修复记录；当前行为请以 [PRIVILEGED_RTOS.md](PRIVILEGED_RTOS.md) 为准。

本次完善数据访存及其与流水线的配合，保留现有前端压缩、BHT/JTB/RAS、控制指令晚转发设计。

## 请求和响应

- EX 中有效且允许前进的 load/store 发出请求：`ex_fire && (ex_dmem_re || ex_dmem_we)`。
- `bus_m_stb && bus_m_ready` 在时钟上升沿接受一次请求。总线最多保留一个未完成请求，并锁存目标、地址、写数据、操作类型。
- 从设备 `bus_sN_stb` 只脉冲一拍；从设备必须在接受时保存需要的信息，稍后返回一拍 `ack`。**不能要求 STB 一直保持到 ACK，也不支持同拍组合 ACK。**
- 读数据必须在 ACK 有效时有效；写 ACK 表示该次写入已经完成。CPU 不提供响应反压，响应到来即接收。
- 可以在上一请求响应的同一拍接受下一请求，因此原有一拍 BRAM 不需要额外插入总线空拍。
- 复位同时取消 CPU、互连和从设备中的事务。未来接入不能同步取消的外部总线时，需要额外丢弃旧响应的机制。

例：EX 发出 LW 后，下一拍指令进入 MEM。如果 ACK 尚未到达，`mem_wait=1`，前端、ID/EX 和 EX/MEM 保持；WB 中更老的指令仍可完成。ACK 到达后，LW 的返回数据进入 WB，后续 EX 指令才能推进。等待期间不会重复发出写请求，也不会把无效读数据写入寄存器。

## 为什么分别控制保持和提交

`memory_hold` 与 `execute_hold` 不同：

- 等待访存时，MEM 保存尚未完成的事务。
- EX 正在乘除法时，MEM 中更老且已完成的指令仍然提交一次，然后 MEM 变为空泡。
- `mem_retire` 只表示当前 MEM 指令可以向 WB 前进；MEM/WB 和 MEM 转发均使用此条件。
- 乘除法 `ready` 保持到下一次运算开始，避免完成脉冲恰好发生在访存等待期间而丢失。
- 分支冲刷、预测器更新和 RAS 更新受到 EX 实际推进条件约束，避免暂停时反复更新。
- IMEM 的预读槽在暂停时保留，数据读仍优先使用第二端口。

旧实现只在乘除法时保持 EX/MEM，却让 MEM/WB 每拍采样；load 后接独立乘法会重复提交 load，甚至用后续无效读数据覆盖正确结果。新回归程序包含这一用例。

## 地址和错误处理

保留 IMEM/DMEM 原地址范围。MMIO 精确解码 `0xF0000000..0xF000003F`，只支持对齐的 32 位访问，不再把其他高地址静默映射到相同寄存器。

未映射地址、非对齐半字/字访问、向 IMEM 写入、无效访存类型和非字宽 MMIO 访问返回错误，且不会向从设备发出请求。CPU 锁存 `memory_fault` 和 `memory_fault_addr`，停止后续指令推进，直至复位。更老的 WB 指令仍可完成。

这是一种可观测的错误停机机制，**不是 RISC-V 特权异常处理**；尚未实现 `mcause/mepc/mtvec`、中断或异常返回。板级 top 当前没有连接新增的错误输出，可后续连接 LED、调试器或 SoC 状态寄存器。已解码 MMIO 窗口内未实现的寄存器仍遵循现有 MMIO 行为。

总线暂未提供从设备错误输入或超时机制；如果合法目标永久不返回 ACK，CPU 会一直等待。未来连接 GPU 时，应让命令寄存器在接受命令后及时 ACK，用另一个状态寄存器报告 GPU 工作完成。

## 文件入口

- `sources_1/new/bus_interconnect.v`：单事务互连、请求锁存、响应选择、访问检查。
- `sources_1/new/cpu.v`：等待、推进、提交和错误停机。
- `sources_1/new/ex_mem.v`：区分访存保持与乘除法排空 MEM。
- `sim_1/new/memory_regression.S`：访存依赖、字节通道、分支/JALR、乘除法交叉用例。
- `sim_1/new/memory_regression_tb.v`：可变响应延迟、无效数据注入、复位和错误停机检查。
- `sim_1/new/run_memory_regression.py`：编译程序并运行全部测试。

在 CPU 仓库根目录运行：

```powershell
python sim_1/new/run_memory_regression.py --official
```

需要 Icarus Verilog 和 RISC-V GCC；可用 `--toolchain` 指定 GCC 所在目录。输出在已忽略的 `build/memory_regression/`。测试仅在该目录生成带延迟包装的 CPU 副本和 `imem.mem`，不替换上板源文件或原程序。

共 103 项：5 种响应延迟、等待中复位、5 种错误访问，以及仓库中 46 个 RV32I/M 程序各运行两种延迟。错误用例还检查停机后连续 10 拍不再发出请求或提交指令。这些定向测试不等同于完整 ISA、特权架构或形式验证。

## 本次验证结果（2026-09-23）

- 103 项仿真全部通过；原 `cpu_tb.v` 也已重新编译。
- Vivado 2025.1，`cpu` 为顶层，器件 `xc7a100tcsg324-1`：综合通过，综合优化后 3550 LUT、2813 FF、16 BRAM、4 DSP。
- 使用 10 ns 时钟约束的独立 CPU 布局布线完成，但建立时间未收敛：WNS = -0.508 ns，TNS = -20.920 ns；保持时间 WHS = +0.106 ns。
- 这是使用测试目录 ROM 镜像的 CPU 核检查，未采用原板级 top 的 MMCM、引脚和 I/O 时序约束，不能代替完整上板工程验证，也不能据此声称已稳定运行于 100 MHz。本次未生成 bitstream 或调整板级频率。
- 报告位于 `build/memory_regression/results.log`、`utilization.rpt` 和 `timing_routed.rpt`。后续上板前仍需完成板级时序收敛。

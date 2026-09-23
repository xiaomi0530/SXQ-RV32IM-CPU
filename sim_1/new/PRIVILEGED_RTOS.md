# 机器模式 CSR、异常、中断与 RTOS

这次实现的目标是单核 **RV32IM + Zicsr + Zifencei、仅 M 模式** RTOS。不是把所有 CSR 地址都变成可写寄存器，也不包含 S/U 模式、MMU、PMP、A/F/D/C 扩展或调试模块。未实现的 CSR 会触发非法指令异常。

## 如何保持现有创新设计

普通指令仍使用双槽预读与恢复旁路、带标签的 BHT、JTB、RAS，以及 load 到 branch/JALR 的晚转发。系统指令在 ID 暂停发射，让更老的 EX/MEM/WB 排空后才操作 CSR；CSR 读数据不串入普通 ALU 数据通路。

`privileged.v` 的状态为 IDLE → EXEC 或 TRAP → REDIRECT → IDLE。WFI 在 EXEC 后进入 SLEEP。只有这些慢路径需要排空，普通指令不因此统一串行化。若排空期间更老的分支重定向，当前 ID 候选自然被冲刷，不会对错误路径的 ECALL/CSR 产生架构副作用。

精确异常的顺序是：更老指令可以完成，故障指令不退休，更年轻指令不得写寄存器或外设。MEM 访存错误和控制转移不对齐检查优先阻止年轻 EX 发请求。中断选择 ID 边界，排空之后将尚未执行的 ID 指令地址保存到 mepc。

为了正确报告指令访问异常，PC 和故障地址保留完整 32 位；预测器表项依然使用原来的窄地址。跳到 IMEM 之外会得到指令访问异常，不能静默截断成 ROM 内另一个地址。JALR 的 bit 0 按 ISA 清零，bit 1 不对齐仍产生异常。真正的零指令也会报非法指令，流水线空泡由显式 valid 区分。

另修正了已启动的错误路径除法被冲刷后，新除法 preload 被旧运算忽略的问题。

## CSR 表

| 地址 | 名称 | 实现行为 |
|---|---|---|
| 300 | mstatus | MIE[3]、MPIE[7] 可写；MPP 固定 M=3；其余不支持位为 0 |
| 301 | misa | 固定 WARL 值 40001100：RV32、I、M；写入不改变能力 |
| 304 | mie | MSIE[3]、MTIE[7]、MEIE[11] 可写 |
| 305 | mtvec | BASE + Direct(0)/Vectored(1)；保留模式写入转为 Direct |
| 306、310 | mcounteren、mstatush | 固定 0；无较低特权级，固定小端 |
| 320 | mcountinhibit | CY[0]、IR[2] 控制周期/退休计数；不影响 mtime |
| 340 | mscratch | 32 位软件暂存 |
| 341 | mepc | 32 位可写，低两位为 0，IALIGN=32 |
| 342、343 | mcause、mtval | 异常/中断原因与故障值；软件可读写 |
| 344 | mip | 硬件提供 MSIP/MTIP/MEIP，CSR 写入不改变；清中断源应操作外设 |
| B00/B80 | mcycle/mcycleh | 64 位可读写周期计数器 |
| B02/B82 | minstret/minstreth | 64 位可读写退休计数器；故障指令不计数 |
| C00/C80、C02/C82 | cycle/cycleh、instret/instreth | 上述计数器只读别名 |
| C01/C81 | time/timeh | MMIO mtime 的只读影子 |
| F11…F15 | mvendorid、marchid、mimpid、mhartid、mconfigptr | 返回 0，单 hart 编号 0 |
| B03…B1F/B83…B9F、C03…C1F/C83…C9F、323…33F | HPM 计数器及事件选择 | 实现为固定 0；Cxx 只读，未提供真实事件计数 |

六条 Zicsr 指令均实现：CSRRW/CSRRS/CSRRC 及其立即数版本。RS/RC 是否写 CSR 由指令编码中的 rs1/zimm 是否为零决定，不能用寄存器内容是否为零代替。访问不存在的 CSR，或真正尝试写只读 CSR，产生 cause=2；不会写 rd。

MRET 恢复 MIE←MPIE，置 MPIE=1，保持 MPP=M，并跳到 mepc。进入 trap 时 MPIE←MIE、MIE←0；软件需要自行保存通用寄存器。支持软件管理的嵌套异常，硬件不提供第二套上下文寄存器。

## 系统指令和异常

- ECALL：机器模式 cause=11，mepc 指向 ECALL 本身。
- EBREAK：cause=3，mtval 为断点 PC；未实现外部 debug-mode 接管。
- 非法指令/非法 CSR：cause=2，mtval 为指令字。
- 控制转移不对齐：cause=0，mepc 指向跳转指令，mtval 为目标地址；不写 link 寄存器。
- 指令访问错误：cause=1，mepc/mtval 为取指地址。有效 IMEM 范围之外不执行别名内容。
- load 地址不对齐/访问错误：cause=4/5；store 为 6/7，mtval 为数据地址。
- WFI：等待本地已使能的中断源；唤醒不依赖全局 MIE。MIE=0 时只恢复下一条指令，MIE=1 时进入中断。
- FENCE：由于单 outstanding、强顺序访存，排空后即满足顺序要求。
- FENCE.I：排空并重新取指。当前 IMEM 仍是只读存储器；不等于增加了自修改代码支持。

中断优先级为机器外部 > 机器软件 > 机器定时器，对应 mcause=8000000B/80000003/80000007。只有 mie 对应位与 mstatus.MIE 同时使能才进入中断。向量模式中，中断跳 BASE+4×cause；同步异常始终跳 BASE。

`cpu.irq_external` 为电平输入，内部双触发器同步；中断处理程序必须在外设端清源。当前板级 top 将它接 0，定时器/软件中断无需外部引脚即可工作。`memory_fault` 现在是访存错误诊断脉冲，`memory_fault_addr` 保留最近地址，不再永久停机；错误交给 mtvec 处理。

## 定时器和 MMIO

mtime 每个 CPU 时钟加 1；当前板级 90 MHz 配置下，timebase 为 90,000,000 Hz。改变 CPU 频率时必须同步修改 RTOS 的时钟参数。

| 地址 | 功能 |
|---|---|
| 02000000 | msip[0]，读写 |
| 02004000/02004004 | mtimecmp 低/高 32 位，读写，复位全 1 |
| 0200BFF8/0200BFFC | mtime 低/高 32 位，读写，复位 0 |
| F0000020/F0000024 | mtimecmp 的同一寄存器别名 |
| F0000028 | msip 的别名 |
| F0000030/F0000034 | mtime 的读写别名 |
| F0000000/F0000004 | 保留旧计时接口，现在是 mtime 的只读别名 |
| F0000018/F000001C | 真实 instret 的低/高 32 位 |

LED、UART、tohost 原地址不变。以上接口是单 hart 的 CLINT 兼容寄存器布局，不是完整 PLIC/ACLINT 设备实现。定时器比较结果寄存一拍，软件更新 mtimecmp 后允许短暂仍看到旧 pending。

RV32 软件安全更新比较值的顺序为：低字写 FFFFFFFF → 高字写新值 → 低字写新值。读取 64 位时间使用高→低→高并重试。MMIO 请求先寄存、下一拍执行，原生响应为两拍；BRAM 数据访存仍为一拍。原回归程序多出的 2 或 7 拍恰好对应其中 2 或 7 次 MMIO 写。

## RTOS 验证与复现

```powershell
python sim_1/new/run_memory_regression.py --official
python sim_1/new/run_privileged_regression.py
python sim_1/new/run_privileged_regression.py --freertos
```

需要 Icarus、RISC-V GCC；脚本可自动寻找本机 xPack 安装。首次 RTOS 测试下载 FreeRTOS-Kernel V11.2.0，固定提交 `0adc196d4bd52a2d91102b525b0aafc1e14a2386`，放在被 Git 忽略的 build 目录。FreeRTOS 上游文件不修改；示例和启动代码在 `sim_1/new/freertos/`。

示例创建两个同优先级、正常循环中既不阻塞也不主动 yield 的工作任务，以及一个更高优先级的监控任务。工作任务必须通过真实 timer 抢占才能都取得进展；同时检查上下文寄存器、ECALL yield 和嵌套临界区。监控任务经历 4 次延时、至少 20 个 tick 后检查进展并写 tohost。测试采用加速用的 10 kHz tick，并非强制应用使用该 tick 频率。

产物分别在 `build/memory_regression/`、`build/privileged_regression/`、`build/freertos_regression/`。RTOS 的 program.elf/program.map/imem.mem 可以检查和用于后续上板；脚本不会覆盖原来的 sources_1/new/imem.mem。程序约 5.2 KB ROM、5.1 KB BSS，适合当前片上存储器。

已验证 103 项普通/访存回归、4 种延迟及 WFI 中复位的特权回归，以及 3 种延迟的真实 FreeRTOS 任务运行。特权回归包含 18 次指定 cause/mepc/mtval 的陷阱检查、CSR WARL/只读语义、计数器、中断优先级、向量入口、WFI 唤醒、JALR bit0、错误路径除法冲刷。这里的结果是 RTL 仿真，不是完整 ISA 形式认证或实板测量。

## 时序审查

1. MMIO 请求寄存，切断晚分支→总线→64 位定时器写使能的长组合路径。
2. BHT 改为每个表项独立写译码，避免先用大选择器读全表再形成写使能。标签、索引混合、饱和计数器算法和更新时机不变；与原实现进行了 10,000 轮随机逐拍等价检查。
3. CSR 执行和 trap 重定向经过状态寄存器，普通算术/转发不经过 CSR 大读选择器。
4. PC+4 与 PC+8 从寄存器并行计算，晚到的步长选择不再穿过 32 位加法器。取指地址与时序行为保持一致。
5. 晚转发比较改为四个并行字节比较，保留原 MEM 周期解析时机；10 万组随机/边界输入与原实现等价。合法乘除法的预启动使用精确 M 扩展编码判定，避免将完整系统译码串进 DSP 使能。
6. 提供 `check_privileged_timing.tcl`，可在含 imem.mem 的独立构建目录运行。`-tclargs board` 使用原 top、已生成的时钟 IP 和板级 XDC，运行综合、布局布线和布线后物理优化。未使用放宽内部路径约束来隐藏违例。

### 最终验证记录（2026-09-23）

板级工程已加入 privileged.v，CPU 时钟按用户授权从 100 MHz 调整为 **90 MHz**；时钟 IP 已重新生成，UART 和 FreeRTOS 时钟参数已同步。IP 的历史模块名 `clk_main_100mhz` 保留，但实际输出为 90 MHz，输入晶振仍为 100 MHz。

Vivado 2025.1、xc7a100tcsg324-1，使用原板级 top、实际 MMCM 时钟及 FreeRTOS 测试 ROM，完成布局布线和布线后物理优化：

| 项目 | 最终结果 |
|---|---|
| CPU 周期 | 11.111 ns（90 MHz） |
| WNS / TNS | +0.036 ns / 0.000 ns，0 个建立时间违例端点 |
| WHS / THS | +0.043 ns / 0.000 ns，0 个保持时间违例端点 |
| LUT / 寄存器 | 4,988 / 3,647 |
| BRAM36 等效 / DSP | 16 / 4 |

报告位于 `build/privileged_board_90mhz/timing_routed.rpt`，最差路径为 IMEM BRAM 读出到 PC 寄存器，数据路径延迟 10.789 ns，其中布线 7.002 ns。建立时间余量较小，修改 RTL、ROM 内容或实现设置后应重新运行，不能把本结果视为未来版本保证。原板级约束没有为所有显示/UART 输出建立外部器件延迟模型；这里确认的是当前约束下的内部时序收敛，没有完成上板测量或下载 bitstream。

最终 90 MHz 配置通过 103 项指令/访存回归、5 组特权测试（含 WFI 中复位）及 3 组 FreeRTOS 测试。FreeRTOS 的延迟 0/7/19 配置分别在 193,356 / 208,874 / 227,500 个周期完成，每组发生 26 次陷阱/中断进入。

复现板级时序（先运行上面的 FreeRTOS 构建）：

```powershell
New-Item -ItemType Directory -Force build/privileged_board_90mhz
Copy-Item build/freertos_regression/imem.mem build/privileged_board_90mhz/imem.mem
Push-Location build/privileged_board_90mhz
& C:/Xilinx/2025.1/Vivado/bin/vivado.bat -mode batch -source ../../sim_1/new/check_privileged_timing.tcl -nojournal -log implementation.log -tclargs board
Pop-Location
```

该独立构建使用 FreeRTOS ROM，不覆盖原工程的 `sources_1/new/imem.mem`。要上板运行示例，需先选用该 ROM 重新生成 bitstream；原工程不会仅因增加 CSR 就自动启动 RTOS。

## 规范参考

- [RISC-V Machine-Level ISA 1.13](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html)
- [Zicsr 2.0](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html)
- [FreeRTOS V11.2.0 RISC-V port](https://github.com/FreeRTOS/FreeRTOS-Kernel/tree/V11.2.0/portable/GCC/RISC-V)

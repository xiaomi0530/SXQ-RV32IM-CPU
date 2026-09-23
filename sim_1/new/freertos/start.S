.option norvc
.option norelax
.section .text.init
.globl _start
_start:
    la sp,_stack_top
    la t0,freertos_risc_v_trap_handler
    csrw mtvec,t0
    la t0,_data_lma
    la t1,_data_start
    la t2,_data_end
1:  bgeu t1,t2,2f
    lw t3,0(t0)
    sw t3,0(t1)
    addi t0,t0,4
    addi t1,t1,4
    j 1b
2:  la t1,_bss_start
    la t2,_bss_end
3:  bgeu t1,t2,4f
    sw zero,0(t1)
    addi t1,t1,4
    j 3b
4:  call main
5:  wfi
    j 5b

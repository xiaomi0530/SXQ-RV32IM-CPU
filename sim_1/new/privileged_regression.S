.option norvc
.option norelax
.section .text.init
.globl _start
.macro check reg, value
    li t6, \value
    bne \reg,t6,fail
.endm
.macro expect cause, epc, value, resume
    li s8,\cause
    la s9,\epc
    li s10,\value
    la s11,\resume
.endm
_start:
    li sp,0x18000
    li s0,1
    li s7,0
    la t0,handler
    csrw mtvec,t0
    csrr t1,misa
    check t1,0x40001100
    csrr t1,mstatus
    check t1,0x1800
    li t0,0x1234
    csrrw t1,mscratch,t0
    check t1,0
    csrrsi t1,mscratch,3
    check t1,0x1234
    csrrci t1,mscratch,1
    check t1,0x1237
    csrrwi t1,mscratch,7
    check t1,0x1236
    li t0,8
    csrrs t1,mscratch,t0
    check t1,7
    csrrc t1,mscratch,t0
    check t1,15
    csrr t1,mscratch
    check t1,7
    csrw mscratch,zero
    csrr t1,mscratch
    check t1,0
    li t0,-1
    csrw mstatus,t0
    csrr t1,mstatus
    check t1,0x1888
    csrw mstatus,zero
    csrw mie,t0
    csrr t1,mie
    check t1,0x888
    csrw mie,zero
    csrw mepc,t0
    csrr t1,mepc
    check t1,0xfffffffc
    csrw misa,zero
    csrr t1,misa
    check t1,0x40001100
    li s0,2
    csrwi mcountinhibit,5
    li t0,100
    csrw minstret,t0
    csrwi minstreth,0
    csrr t1,instret
    check t1,100
    li t0,-1
    csrw mcycle,t0
    csrwi mcycleh,3
    csrr t1,cycle
    check t1,-1
    csrr t1,cycleh
    check t1,3
    csrwi mcountinhibit,0
    csrr t1,cycleh
    check t1,4
    li s0,3
    expect 11, ecall_site, 0, after_ecall
ecall_site: ecall
    j fail
after_ecall:
    expect 3, ebreak_site, 0, after_ebreak
    la s10,ebreak_site
ebreak_site: ebreak
    j fail
after_ebreak:
    expect 2, zero_site, 0, after_zero
zero_site: .word 0
    j fail
after_zero:
    expect 2, bad_site, 0xffffffff, after_bad
bad_site: .word 0xffffffff
    j fail
after_bad:
    expect 2, csr_bad, 0, after_csr_bad
    la t0,csr_bad
    lw s10,0(t0)
csr_bad: csrr t0,0x7c0
    j fail
after_csr_bad:
    expect 2, csr_ro, 0, after_csr_ro
    la t0,csr_ro
    lw s10,0(t0)
    li t1,0
csr_ro: csrrs t0,cycle,t1
    j fail
after_csr_ro:
    li s0,4
    expect 4, bad_load, 0x10001, after_load
    li t0,0x10001
    li a0,123
bad_load: lw a0,0(t0)
    j fail
after_load:
    check a0,123
    expect 6, bad_store, 0x10001, after_store
    li t0,0x10001
bad_store: sh a0,0(t0)
    j fail
after_store:
    expect 5, unmapped, 0x20000000, after_unmapped
    li t0,0x20000000
unmapped: lw a0,0(t0)
    j fail
after_unmapped:
    expect 7, rom_write, 0, after_rom_write
rom_write: sw a0,0(zero)
    j fail
after_rom_write:
    li s0,5
    expect 0, misjump, 0, after_misjump
    la s10,after_misjump
    addi s10,s10,2
    li a0,456
misjump: jalr a0,0(s10)
    j fail
after_misjump:
    check a0,456
    expect 0, late_misjump, 0, after_late_misjump
    la s10,after_late_misjump
    addi s10,s10,2
    li t0,0x10000
    sw s10,0(t0)
    lw t1,0(t0)
late_misjump: jalr a0,0(t1)
    j fail
after_late_misjump:
    expect 0, misbranch, 0, after_misbranch
    la s10,misbranch
    addi s10,s10,2
misbranch: .word 0x00000163
    j fail
after_misbranch:
    expect 1, _start, 0x20000000, after_far
    li s9,0x20000000
    li t0,0x20000000
    jalr a0,0(t0)
far_link: j fail
after_far:
    la t0,far_link
    bne a0,t0,fail
    // JALR must ignore bit zero, and a not-taken misaligned branch must not trap.
    la t0,odd_ok
    ori t0,t0,1
    jalr zero,0(t0)
    j fail
odd_ok:
    .word 0x00001163
    fence rw,rw
    fence.i
    // A deferred taken branch squashes a divider already preloaded from ID.
    li t0,0x10000
    li t2,77
    li t3,7
    lw t1,0(t0)
    beq t1,t1,divide_after_flush
    div a0,t2,t1
    j fail
divide_after_flush:
    div a0,t2,t3
    check a0,11
    li s0,6
    expect 0x80000003, software_resume, 0, software_resume
    li t0,0x02000000
    li t1,1
    sw t1,0(t0)
    csrwi mie,8
    // WFI wakes on locally enabled interrupts even when mstatus.MIE=0.
    wfi
    csrsi mstatus,8
software_resume:
    csrci mstatus,8
    li s0,7
    // Vectored timer entry uses BASE + 4*7, with synchronous traps at BASE.
    la t0,vectors
    ori t0,t0,1
    csrw mtvec,t0
    expect 0x80000007, timer_resume, 0, timer_resume
    li t0,0x0200bff8
    lw t1,0(t0)
    li t2,10000
    add t1,t1,t2
    li t0,0x02004000
    sw t1,0(t0)
    sw zero,4(t0)
    li t0,128
    csrw mie,t0
    csrsi mstatus,8
    wfi
timer_resume:
    csrci mstatus,8
    li s0,8
    expect 0x8000000b, external_resume, 0, external_resume
    li t0,0x800
    csrw mie,t0
    csrsi mstatus,8
    li t0,0xf000000c
    li t1,0xeeee
    sw t1,0(t0)
    wfi
external_resume:
    csrci mstatus,8
    // Simultaneously pending software/timer interrupts: software wins.
    expect 0x80000003, priority_resume, 0, priority_resume
    li t0,0x02004000
    sw zero,0(t0)
    sw zero,4(t0)
    li t0,0x02000000
    li t1,1
    sw t1,0(t0)
    li t0,0x88
    csrw mie,t0
    csrsi mstatus,8
priority_resume:
    csrci mstatus,8
    check s7,18
    li t0,0xf0000000
    sw zero,12(t0)
    li t1,1
    sw t1,8(t0)
1: j 1b
.balign 64
vectors:
.rept 12
    j handler
.endr
.balign 4
handler:
    addi sp,sp,-16
    sw t0,0(sp)
    sw t1,4(sp)
    csrr t0,mcause
    bne t0,s8,fail
    csrr t0,mepc
    bne t0,s9,fail
    csrr t0,mtval
    bne t0,s10,fail
    csrr t0,mstatus
    andi t0,t0,8
    bnez t0,fail
    addi s7,s7,1
    li t0,0x02000000
    sw zero,0(t0)
    li t0,0x02004000
    li t1,-1
    sw t1,4(t0)
    csrw mepc,s11
    lw t0,0(sp)
    lw t1,4(sp)
    addi sp,sp,16
    mret
fail:
    li t0,0xf0000000
    sw s0,12(t0)
    li t1,1
    sw t1,8(t0)
2: j 2b

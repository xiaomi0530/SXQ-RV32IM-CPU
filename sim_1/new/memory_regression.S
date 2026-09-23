.option norvc
.option norelax
.section .text.init
.globl _start
.macro check reg, value
    li t6, \value
    bne \reg, t6, fail
.endm
_start:
    li s0, 0x10000
    li s1, 0xf0000000
    li s2, 7
    li s3, 9
    li t0, 0x89abcdef
    sw t0, 0(s0)
    li t1, 0x12345678
    sw t1, 4(s0)
    lw a0, 0(s0)
    lw a1, 4(s0)
    check a0, 0x89abcdef
    check a1, 0x12345678
    lb a0, 0(s0)
    check a0, -17
    lbu a0, 1(s0)
    check a0, 0xcd
    lh a0, 2(s0)
    check a0, 0xffff89ab
    lhu a0, 0(s0)
    check a0, 0xcdef
    li t0, 0x55
    sb t0, 1(s0)
    li t0, 0x1234
    sh t0, 2(s0)
    lw a0, 0(s0)
    check a0, 0x123455ef
    lw a0, 4(s0)
    sw a0, 8(s0)
    lw a1, 8(s0)
    check a1, 0x12345678

    # Independent MUL/DIV can finish while an older load is still waiting.
    lw a0, 0(s0)
    mul a1, s2, s3
    check a1, 63
    check a0, 0x123455ef
    lw a0, 4(s0)
    div a1, s3, s2
    check a1, 1
    check a0, 0x12345678
    sw s2, 12(s0)
    lw a0, 12(s0)
    mul a1, a0, s3
    check a1, 63

    # Deferred branch must retain the load result and kill younger MMIO writes.
    sw zero, 16(s0)
    lw a0, 16(s0)
    beq a0, zero, branch_ok
    sw s2, 16(s1)
    j fail
branch_ok:
    lw a0, 12(s0)
    beq a0, a0, both_dep_ok
    sw s2, 16(s1)
    j fail
both_dep_ok:
    la t0, jalr_ok
    sw t0, 20(s0)
    lw t1, 20(s0)
    jalr ra, 0(t1)
    sw s2, 16(s1)
    j fail
jalr_ok:
    # IMEM data reads borrow its second port; test consecutive reads too.
    la t0, constants
    lw a0, 0(t0)
    lw a1, 4(t0)
    check a0, 0x2468ace0
    check a1, 0x13579bdf
    li s4, 10
loop:
    sw s4, 24(s0)
    lw a0, 24(s0)
    addi a0, a0, -1
    mv s4, a0
    bnez s4, loop
    sw zero, 12(s1)
    li t0, 1
    sw t0, 8(s1)
halt:
    j halt
fail:
    li t0, 1
    sw t0, 12(s1)
    sw t0, 8(s1)
    j halt
.balign 4
constants:
    .word 0x2468ace0, 0x13579bdf

`timescale 1ns / 1ps
`include "defines.v"

module ex_mem #(
    parameter integer BR_HASH_BITS = `BR_PRED_INDEX_BITS,
    parameter integer IMEM_ADDR_BITS = `IMEM_ADDR_BITS
)(
    input  wire clk,
    input  wire rst_n,
    input  wire pipeline_hold,
    input  wire memory_hold,
    input  wire older_flush,
    input  wire ex_valid,

    input  wire        ex_regs_we,
    input  wire [4:0]  ex_regs_w_addr,
    input  wire [31:0] ex_regs_w_data,
    input  wire [31:0] ex_dmem_wr_addr,
    input  wire [31:0] ex_dmem_w_data,
    input  wire        ex_dmem_we,
    input  wire        ex_dmem_re,
    input  wire [2:0]  ex_mem_op,
    input  wire [IMEM_ADDR_BITS-1:0] ex_ctrl_pc_low,
    input  wire        ex_pred_taken,
    input  wire [IMEM_ADDR_BITS-1:0] ex_ctrl_pred_target_low,
    input  wire [IMEM_ADDR_BITS-1:0] ex_ctrl_branch_target_low,
    input  wire [31:0] ex_ctrl_other_operand,
    input  wire [11:0] ex_ctrl_jalr_imm12,
    input  wire        ex_ctrl_both_dep,
    input  wire        ex_branch_flag,
    input  wire [BR_HASH_BITS-1:0] ex_branch_hash,
    input  wire        ex_jalr_flag,
    input  wire        ex_ret_flag,
    input  wire        ex_ctrl_defer,
    input  wire        ex_ctrl_dep_rs1,

    output reg         mem_regs_we,
    output reg  [4:0]  mem_regs_w_addr,
    output reg  [31:0] mem_regs_w_data,
    output reg  [31:0] mem_dmem_wr_addr,
    output reg  [31:0] mem_dmem_w_data,
    output reg         mem_dmem_we,
    output reg         mem_dmem_re,
    output reg  [2:0]  mem_mem_op,
    output reg  [IMEM_ADDR_BITS-1:0] mem_ctrl_pc_low,
    output reg         mem_pred_taken,
    output reg  [IMEM_ADDR_BITS-1:0] mem_ctrl_pred_target_low,
    output reg  [IMEM_ADDR_BITS-1:0] mem_ctrl_branch_target_low,
    output reg  [31:0] mem_ctrl_other_operand,
    output reg  [11:0] mem_ctrl_jalr_imm12,
    output reg         mem_ctrl_both_dep,
    output reg         mem_branch_flag,
    output reg  [BR_HASH_BITS-1:0] mem_branch_hash,
    output reg         mem_valid,
    output reg         mem_jalr_flag,
    output reg         mem_ret_flag,
    output reg         mem_ctrl_defer,
    output reg         mem_ctrl_dep_rs1
);

    always @(posedge clk) begin
        if (rst_n == `RST_ENABLE) begin
            mem_valid <= 1'b0;
            mem_regs_we <= 1'b0;
            mem_dmem_we <= 1'b0;
            mem_dmem_re <= 1'b0;
            mem_branch_flag <= 1'b0;
            mem_jalr_flag <= 1'b0;
            mem_ret_flag <= 1'b0;
            mem_pred_taken <= 1'b0;
            mem_ctrl_defer <= 1'b0;
            mem_ctrl_dep_rs1 <= 1'b0;
            mem_ctrl_both_dep <= 1'b0;
        end else if (older_flush) begin
            mem_valid <= 1'b0;
            mem_regs_we <= 1'b0;
            mem_dmem_we <= 1'b0;
            mem_dmem_re <= 1'b0;
            mem_branch_flag <= 1'b0;
            mem_jalr_flag <= 1'b0;
            mem_ret_flag <= 1'b0;
            mem_pred_taken <= 1'b0;
            mem_ctrl_defer <= 1'b0;
            mem_ctrl_dep_rs1 <= 1'b0;
            mem_ctrl_both_dep <= 1'b0;
        end else if (memory_hold) begin
            // Retain the outstanding transaction and all its metadata.
        end else if (pipeline_hold) begin
            // The older MEM instruction drains once while EX runs MUL/DIV.
            mem_valid<=0; mem_regs_we<=0; mem_dmem_we<=0; mem_dmem_re<=0;
            mem_branch_flag<=0; mem_jalr_flag<=0; mem_ret_flag<=0;
            mem_pred_taken<=0; mem_ctrl_defer<=0; mem_ctrl_dep_rs1<=0; mem_ctrl_both_dep<=0;
        end else begin
            mem_valid <= ex_valid;
            mem_regs_we <= ex_regs_we;
            mem_dmem_we <= ex_dmem_we;
            mem_dmem_re <= ex_dmem_re;
            mem_branch_flag <= ex_branch_flag;
            mem_jalr_flag <= ex_jalr_flag;
            mem_ret_flag <= ex_ret_flag;
            mem_pred_taken <= ex_pred_taken;
            mem_ctrl_defer <= ex_ctrl_defer;
            mem_ctrl_dep_rs1 <= ex_ctrl_dep_rs1;
            mem_ctrl_both_dep <= ex_ctrl_both_dep;
        end
    end

    always @(posedge clk) begin
        if (!pipeline_hold && !memory_hold) begin
            mem_regs_w_addr  <= ex_regs_w_addr;
            mem_regs_w_data  <= ex_regs_w_data;
            mem_dmem_wr_addr <= ex_dmem_wr_addr;
            mem_dmem_w_data  <= ex_dmem_w_data;
            mem_mem_op       <= ex_mem_op;
            mem_ctrl_pc_low  <= ex_ctrl_pc_low;
            mem_ctrl_pred_target_low <= ex_ctrl_pred_target_low;
            mem_ctrl_branch_target_low <= ex_ctrl_branch_target_low;
            mem_ctrl_other_operand <= ex_ctrl_other_operand;
            mem_ctrl_jalr_imm12 <= ex_ctrl_jalr_imm12;
            mem_branch_hash  <= ex_branch_hash;
        end
    end

endmodule

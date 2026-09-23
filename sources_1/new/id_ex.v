`timescale 1ns / 1ps
`include "defines.v"

module id_ex #(
    parameter integer BR_HASH_BITS = `BR_PRED_INDEX_BITS,
    parameter integer IMEM_ADDR_BITS = `IMEM_ADDR_BITS
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pipeline_stall,
    input  wire        pipeline_hold,
    input  wire        pipeline_flush,
    input  wire        id_valid,

    input  wire [31:0] id_instr_addr,
    input  wire        id_branch_nohit,
    input  wire        id_pred_taken,
    input  wire [IMEM_ADDR_BITS-1:0] id_pred_target,

    input  wire [31:0] id_alu_num1,
    input  wire [31:0] id_alu_num2,
    input  wire [3:0]  id_alu_op,
    input  wire [4:0]  id_regs_w_addr,
    input  wire        id_regs_we,
    input  wire [2:0]  id_mem_op,
    input  wire        id_dmem_we,
    input  wire        id_dmem_re,
    input  wire [31:0] id_dmem_w_data,
    input  wire        id_branch_flag,
    input  wire [IMEM_ADDR_BITS-1:0] id_branch_jump_addr,
    input  wire [BR_HASH_BITS-1:0]  id_branch_hash,
    input  wire        id_jump_flag,
    input  wire        id_jalr_flag,
    input  wire        id_call_flag,
    input  wire        id_ret_flag,
    input  wire        id_ctrl_defer,
    input  wire        id_ctrl_dep_rs1,
    input  wire        id_ctrl_dep_rs2,

    output reg   [31:0] ex_instr_addr,
    output reg          ex_branch_nohit,
    output reg          ex_pred_taken,
    output reg   [IMEM_ADDR_BITS-1:0] ex_pred_target,
    output reg   [31:0] ex_alu_num1,
    output reg   [31:0] ex_alu_num2,
    output reg   [3:0]  ex_alu_op,
    output reg   [4:0]  ex_regs_w_addr,
    output reg          ex_regs_we,
    output reg   [2:0]  ex_mem_op,
    output reg          ex_dmem_we,
    output reg          ex_dmem_re,
    output reg   [31:0] ex_dmem_w_data,
    output reg          ex_branch_flag,
    output reg   [IMEM_ADDR_BITS-1:0] ex_branch_jump_addr,
    output reg   [BR_HASH_BITS-1:0]  ex_branch_hash,
    output reg          ex_valid,
    output reg          ex_jump_flag,
    output reg          ex_jalr_flag,
    output reg          ex_call_flag,
    output reg          ex_ret_flag,
    output reg          ex_ctrl_defer,
    output reg          ex_ctrl_dep_rs1,
    output reg          ex_ctrl_dep_rs2
);

    always @(posedge clk) begin
        if (rst_n == `RST_ENABLE) begin
            ex_valid       <= 1'b0;
            ex_regs_we     <= 1'b0;
            ex_dmem_we     <= 1'b0;
            ex_dmem_re     <= 1'b0;
            ex_branch_flag <= 1'b0;
            ex_jump_flag   <= 1'b0;
            ex_jalr_flag   <= 1'b0;
            ex_call_flag   <= 1'b0;
            ex_ret_flag    <= 1'b0;
            ex_branch_nohit <= 1'b0;
            ex_pred_taken  <= 1'b0;
            ex_ctrl_defer  <= 1'b0;
            ex_ctrl_dep_rs1 <= 1'b0;
            ex_ctrl_dep_rs2 <= 1'b0;
        end else if (pipeline_flush) begin
            ex_valid       <= 1'b0;
            ex_regs_we     <= 1'b0;
            ex_dmem_we     <= 1'b0;
            ex_dmem_re     <= 1'b0;
            ex_branch_flag <= 1'b0;
            ex_jump_flag   <= 1'b0;
            ex_jalr_flag   <= 1'b0;
            ex_call_flag   <= 1'b0;
            ex_ret_flag    <= 1'b0;
            ex_branch_nohit <= 1'b0;
            ex_pred_taken  <= 1'b0;
            ex_ctrl_defer  <= 1'b0;
            ex_ctrl_dep_rs1 <= 1'b0;
            ex_ctrl_dep_rs2 <= 1'b0;
        end else if (pipeline_stall && !pipeline_hold) begin
            ex_valid       <= 1'b0;
            ex_regs_we     <= 1'b0;
            ex_dmem_we     <= 1'b0;
            ex_dmem_re     <= 1'b0;
            ex_branch_flag <= 1'b0;
            ex_jump_flag   <= 1'b0;
            ex_jalr_flag   <= 1'b0;
            ex_call_flag   <= 1'b0;
            ex_ret_flag    <= 1'b0;
            ex_branch_nohit <= 1'b0;
            ex_pred_taken  <= 1'b0;
            ex_ctrl_defer  <= 1'b0;
            ex_ctrl_dep_rs1 <= 1'b0;
            ex_ctrl_dep_rs2 <= 1'b0;
        end else if (!pipeline_hold) begin
            ex_valid       <= id_valid;
            ex_regs_we     <= id_regs_we;
            ex_dmem_we     <= id_dmem_we;
            ex_dmem_re     <= id_dmem_re;
            ex_branch_flag <= id_branch_flag;
            ex_jump_flag   <= id_jump_flag;
            ex_jalr_flag   <= id_jalr_flag;
            ex_call_flag   <= id_call_flag;
            ex_ret_flag    <= id_ret_flag;
            ex_branch_nohit <= id_branch_nohit;
            ex_pred_taken  <= id_pred_taken;
            ex_ctrl_defer  <= id_ctrl_defer;
            ex_ctrl_dep_rs1 <= id_ctrl_dep_rs1;
            ex_ctrl_dep_rs2 <= id_ctrl_dep_rs2;
        end
    end

    always @(posedge clk) begin
        if (rst_n == `RST_ENABLE) begin
            ex_instr_addr       <= 32'b0;
            ex_pred_target      <= {IMEM_ADDR_BITS{1'b0}};
            ex_alu_num1         <= 32'b0;
            ex_alu_num2         <= 32'b0;
            ex_alu_op           <= 4'b0;
            ex_regs_w_addr      <= 5'b0;
            ex_mem_op           <= 3'b0;
            ex_dmem_w_data      <= 32'b0;
            ex_branch_jump_addr <= {IMEM_ADDR_BITS{1'b0}};
            ex_branch_hash      <= {BR_HASH_BITS{1'b0}};
        end else if (pipeline_flush) begin
            ex_instr_addr       <= 32'b0;
            ex_pred_target      <= {IMEM_ADDR_BITS{1'b0}};
            ex_alu_num1         <= 32'b0;
            ex_alu_num2         <= 32'b0;
            ex_alu_op           <= 4'b0;
            ex_regs_w_addr      <= 5'b0;
            ex_mem_op           <= 3'b0;
            ex_dmem_w_data      <= 32'b0;
            ex_branch_jump_addr <= {IMEM_ADDR_BITS{1'b0}};
            ex_branch_hash      <= {BR_HASH_BITS{1'b0}};
        end else if (!(pipeline_stall || pipeline_hold)) begin
            ex_instr_addr       <= id_instr_addr;
            ex_pred_target      <= id_pred_target;
            ex_alu_num1         <= id_alu_num1;
            ex_alu_num2         <= id_alu_num2;
            ex_alu_op           <= id_alu_op;
            ex_regs_w_addr      <= id_regs_w_addr;
            ex_mem_op           <= id_mem_op;
            ex_dmem_w_data      <= id_dmem_w_data;
            ex_branch_jump_addr <= id_branch_jump_addr;
            ex_branch_hash      <= id_branch_hash;
        end
    end

endmodule

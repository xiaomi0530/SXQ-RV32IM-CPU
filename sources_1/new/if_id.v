`timescale 1ns / 1ps
`include "defines.v"

module if_id(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pipeline_stall,
    input  wire        pipeline_hold,
    input  wire        pipeline_flush,
    input  wire        frontend_kill,
    input  wire        slot0_drop_buf,

    input wire if_valid_i,
    output reg id_valid_o,
    input  wire [31:0] if_instr_i,
    input  wire [31:0] if_instr_addr_i,
    input  wire        if_branch_nohit_i,
    input  wire        if_pred_taken_i,
    input  wire [`IMEM_ADDR_BITS-1:0] if_pred_target_i,
    input  wire [31:0] if_pre_instr_i,
    input  wire [31:0] if_pre_instr_addr_i,
    input  wire        if_pre_pred_taken_i,
    input  wire [`IMEM_ADDR_BITS-1:0] if_pre_pred_target_i,
    input  wire        if_pre_valid_i,

    output reg   [31:0] id_instr_o,
    output reg   [31:0] id_instr_addr_o,
    output reg          id_branch_nohit_o,
    output reg          id_pred_taken_o,
    output reg   [`IMEM_ADDR_BITS-1:0] id_pred_target_o
);

    reg kill_fetch_r;

    always @(posedge clk) begin
        if (rst_n == `RST_ENABLE) begin
            kill_fetch_r <= 1'b0;
        end else if (pipeline_flush) begin
            kill_fetch_r <= 1'b1;
        end else if (!(pipeline_stall || pipeline_hold)) begin
            kill_fetch_r <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst_n == `RST_ENABLE) begin
            id_instr_o      <= 32'b0;
            id_valid_o <= 0;
            id_branch_nohit_o <= 1'b0;
            id_pred_taken_o <= 1'b0;
        end else if (pipeline_flush) begin
            id_instr_o      <= 32'b0;
            id_valid_o <= 0;
            id_branch_nohit_o <= 1'b0;
            id_pred_taken_o <= 1'b0;
        end else if (!(pipeline_stall || pipeline_hold)) begin
            if (slot0_drop_buf || frontend_kill || kill_fetch_r) begin
                id_instr_o      <= 32'b0;
            id_valid_o <= 0;
                id_branch_nohit_o <= 1'b0;
                id_pred_taken_o <= 1'b0;
            end else if (if_pre_valid_i) begin
                id_instr_o      <= if_pre_instr_i;
                id_valid_o <= 1;
                id_branch_nohit_o <= 1'b0;
                id_pred_taken_o <= if_pre_pred_taken_i;
            end else begin
                id_instr_o      <= if_instr_i;
                id_valid_o <= if_valid_i;
                id_branch_nohit_o <= if_branch_nohit_i;
                id_pred_taken_o <= if_pred_taken_i;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n == `RST_ENABLE) begin
            id_instr_addr_o   <= 32'b0;
            id_pred_target_o  <= {`IMEM_ADDR_BITS{1'b0}};
        end else if (pipeline_flush) begin
            id_instr_addr_o   <= 32'b0;
            id_pred_target_o  <= {`IMEM_ADDR_BITS{1'b0}};
        end else if (!(pipeline_stall || pipeline_hold)) begin
            if (slot0_drop_buf || frontend_kill || kill_fetch_r) begin
                id_instr_addr_o   <= 32'b0;
                id_pred_target_o  <= {`IMEM_ADDR_BITS{1'b0}};
            end else if (if_pre_valid_i) begin
                id_instr_addr_o  <= if_pre_instr_addr_i;
                id_pred_target_o <= if_pre_pred_target_i;
            end else begin
                id_instr_addr_o  <= if_instr_addr_i;
                id_pred_target_o <= if_pred_target_i;
            end
        end
    end

endmodule

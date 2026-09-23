`timescale 1ns / 1ps
`include "defines.v"

module pc(
    input  wire        clk,
    input  wire        rst_n,
    input wire system_redirect,
    input wire [31:0] system_pc,
    input  wire        redirect_flag,
    input  wire        redirect_force,
    input  wire [`IMEM_ADDR_BITS-1:0] redirect_addr,
    input  wire        preif_ready,
    input  wire        pipeline_stall,
    output reg   [31:0] pc_o,
    output reg          preif_valid_o
);
    localparam integer IMEM_ADDR_BITS = `IMEM_ADDR_BITS;
    localparam integer IMEM_PAD_BITS  = `CPU_ADDR_BITS - IMEM_ADDR_BITS;
    wire preif_fire = preif_valid_o && preif_ready;
    // Calculate both candidates from registered PC in parallel. A late MEM
    // redirect/port conflict only selects a result; it does not enter an adder.
    (* keep = "true" *) wire [31:0] pc_plus4 = pc_o + 32'd4;
    (* keep = "true" *) wire [31:0] pc_plus8 = pc_o + 32'd8;
    wire pc_write_en = redirect_force || !pipeline_stall;
    wire redirect_commit = redirect_flag && pc_write_en;

    always @(posedge clk) begin
        if (rst_n == `RST_ENABLE) begin
            pc_o <= 32'h0;
        end else if (system_redirect) begin
            pc_o <= system_pc;
        end else if (pc_write_en) begin
            pc_o <= redirect_flag ? {{IMEM_PAD_BITS{1'b0}}, redirect_addr} : (preif_fire ? pc_plus8 : pc_plus4);
        end
    end

    always @(posedge clk) begin
        if (rst_n == `RST_ENABLE || redirect_commit || system_redirect) begin
            preif_valid_o <= 1'b1;
        end else if (!pipeline_stall) begin
            if (preif_fire)
                preif_valid_o <= 1'b0;
        end
    end
endmodule

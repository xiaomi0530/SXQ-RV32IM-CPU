`timescale 1ns / 1ps
`include "defines.v"

module imem #(
    parameter integer IMEM_WORD_ADDR_BITS = `IMEM_WORD_ADDR_BITS,
    parameter integer IMEM_ADDR_BITS = `IMEM_ADDR_BITS,
    parameter integer IMEM_DEPTH_WORDS = `IMEM_DEPTH_WORDS
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        pipeline_stall,
    input  wire        pipeline_flush,
    input  wire [31:0] preif_pc_addr_i,
    output reg if_valid_o,
    output reg [31:0] if_instr_o,
    output reg   [31:0] if_instr_addr_o,

    input  wire        preif_valid_i,
    output wire [31:0] if_pre_instr_o,
    output reg   [31:0] if_pre_instr_addr_o,

    input  wire        bus_stb,
    output reg          bus_ack,
    input  wire [31:0] r_addr,
    input  wire        bus_we,
    input  wire [2:0]  mem_op,
    output reg   [31:0] r_data
);

    localparam integer IMEM_PAD_BITS = `CPU_ADDR_BITS - IMEM_ADDR_BITS;

    wire bus_re = bus_stb && !bus_we;
    wire [31:0] if_pre_instr_addr = {preif_pc_addr_i[31:2] + 30'd1, 2'b00};
    wire if_pre_re = preif_valid_i && !pipeline_stall && !bus_re;

    wire [IMEM_WORD_ADDR_BITS-1:0] bus_word_addr = r_addr[IMEM_ADDR_BITS-1:2];
    wire [IMEM_WORD_ADDR_BITS-1:0] if_word_addr = preif_pc_addr_i[IMEM_ADDR_BITS-1:2];
    wire [IMEM_WORD_ADDR_BITS-1:0] if_pre_word_addr = preif_pc_addr_i[IMEM_ADDR_BITS-1:2] + 1'b1;
    wire [IMEM_WORD_ADDR_BITS-1:0] portb_read_addr = bus_re ? bus_word_addr : if_pre_word_addr;

    (* ram_style = "block" *) reg [31:0] imem [0:IMEM_DEPTH_WORDS-1];
    reg  [31:0] portb_read_data;

    initial begin
        $readmemh("imem.mem",imem);
    end

    always @(posedge clk) begin
        if (!pipeline_stall || bus_re)
            portb_read_data <= imem[portb_read_addr];
    end

    always @(posedge clk) begin
        if (rst_n == `RST_ENABLE) begin
            if_instr_o <= 1'b0;
            if_valid_o <= 0;
            if_instr_addr_o <= 32'b0;
        end else if (!pipeline_stall) begin
            if_instr_o <= imem[if_word_addr];
            if_valid_o <= 1;
            if_instr_addr_o <= preif_pc_addr_i;
        end
    end

    reg [2:0]   mem_op_r;
    reg [1:0]   r_addr_r;
    reg         bus_re_r;
    reg [31:0]  word_data;
    reg         if_pre_re_r;

    always@(posedge clk) begin
        if (rst_n == `RST_ENABLE) begin
            bus_ack         <= 1'b0;
            if_pre_re_r      <= 1'b0;
            if_pre_instr_addr_o<= 32'b0;
            mem_op_r        <= 3'b0;
            r_addr_r        <= 2'b0;
            bus_re_r        <= 1'b0;
            word_data       <= 32'b0;
        end else begin
            bus_ack <= 1'b0;
            bus_re_r <= bus_re;
            if (!pipeline_stall || bus_re) if_pre_re_r <= 1'b0;
            if (bus_re || if_pre_re) begin
                if (bus_re) begin
                    mem_op_r <= mem_op;
                    r_addr_r <= r_addr[1:0];
                    bus_ack <= 1'b1;
                end else if (!pipeline_flush) begin
                    if_pre_re_r <= 1'b1;
                    if_pre_instr_addr_o <= if_pre_instr_addr;
                end
            end
        end
    end

    assign if_pre_instr_o = if_pre_re_r ? portb_read_data : 32'h0;

    always @* begin
        if (bus_re_r) begin
            word_data = portb_read_data;
            case (mem_op_r)
                3'b000:
                    case (r_addr_r[1:0])
                        2'b00: r_data = {{24{word_data[7]}},  word_data[7:0]};
                        2'b01: r_data = {{24{word_data[15]}}, word_data[15:8]};
                        2'b10: r_data = {{24{word_data[23]}}, word_data[23:16]};
                        2'b11: r_data = {{24{word_data[31]}}, word_data[31:24]};
                    endcase
                3'b001:
                    case (r_addr_r[1])
                        1'b0: r_data = {{16{word_data[15]}}, word_data[15:0]};
                        1'b1: r_data = {{16{word_data[31]}}, word_data[31:16]};
                    endcase
                3'b010: r_data = word_data;
                3'b100:
                    case (r_addr_r[1:0])
                        2'b00: r_data = {24'b0, word_data[7:0]};
                        2'b01: r_data = {24'b0, word_data[15:8]};
                        2'b10: r_data = {24'b0, word_data[23:16]};
                        2'b11: r_data = {24'b0, word_data[31:24]};
                    endcase
                3'b101:
                    case (r_addr_r[1])
                        1'b0: r_data = {16'b0, word_data[15:0]};
                        1'b1: r_data = {16'b0, word_data[31:16]};
                    endcase
                default: r_data = word_data;
            endcase
        end else begin
            r_data = 32'h0;
        end
    end

endmodule

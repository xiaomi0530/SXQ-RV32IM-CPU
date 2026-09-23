`timescale 1ns / 1ps
`include "defines.v"

module dmem #(
    parameter integer DMEM_WORD_ADDR_BITS = `DMEM_WORD_ADDR_BITS,
    parameter integer DMEM_ADDR_BITS = `DMEM_ADDR_BITS,
    parameter integer DMEM_DEPTH_WORDS = `DMEM_DEPTH_WORDS
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bus_stb,
    output wire        bus_ack,
    input  wire [31:0] w_data,
    input  wire [31:0] wr_addr,
    input  wire        bus_we,
    input  wire [2:0]  mem_op,
    output reg   [31:0] r_data
);

    (* ram_style = "block" *) reg [7:0] dmem0 [0:DMEM_DEPTH_WORDS-1];
    (* ram_style = "block" *) reg [7:0] dmem1 [0:DMEM_DEPTH_WORDS-1];
    (* ram_style = "block" *) reg [7:0] dmem2 [0:DMEM_DEPTH_WORDS-1];
    (* ram_style = "block" *) reg [7:0] dmem3 [0:DMEM_DEPTH_WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < DMEM_DEPTH_WORDS; i = i + 1) begin
            dmem0[i] = 8'h0;
            dmem1[i] = 8'h0;
            dmem2[i] = 8'h0;
            dmem3[i] = 8'h0;
        end
    end

    wire [DMEM_WORD_ADDR_BITS-1:0] word_addr = wr_addr[DMEM_ADDR_BITS-1:2];
    wire we = rst_n && bus_stb && bus_we;
    wire re = rst_n && bus_stb && !bus_we;

    reg bus_ack_w;
    reg bus_ack_r;
    reg re_r;

    reg [3:0] byte_en;
    always @* begin
        byte_en = 4'b0000;
        if (we) begin
            case (mem_op)
                3'b000: // SB
                    case (wr_addr[1:0])
                        2'b00: byte_en = 4'b0001;
                        2'b01: byte_en = 4'b0010;
                        2'b10: byte_en = 4'b0100;
                        2'b11: byte_en = 4'b1000;
                    endcase
                3'b001: // SH
                    byte_en = wr_addr[1] ? 4'b1100 : 4'b0011;
                3'b010: // SW
                    byte_en = 4'b1111;
                default:
                    byte_en = 4'b0000;
            endcase
        end
    end

    wire [7:0] wdata0 = w_data[7:0];
    wire [7:0] wdata1 = (mem_op == 3'b000) ? w_data[7:0] : w_data[15:8];
    wire [7:0] wdata2 = (mem_op == 3'b010) ? w_data[23:16] : w_data[7:0];
    wire [7:0] wdata3 = (mem_op == 3'b010) ? w_data[31:24] :
                        (mem_op == 3'b001) ? w_data[15:8]  : w_data[7:0];

    always @(posedge clk) begin
        if (byte_en[0]) dmem0[word_addr] <= wdata0;
    end
    always @(posedge clk) begin
        if (byte_en[1]) dmem1[word_addr] <= wdata1;
    end
    always @(posedge clk) begin
        if (byte_en[2]) dmem2[word_addr] <= wdata2;
    end
    always @(posedge clk) begin
        if (byte_en[3]) dmem3[word_addr] <= wdata3;
    end

    always@(posedge clk) begin
        bus_ack_w <= 1'b0;
        if (we) begin
            bus_ack_w <= 1'b1;
        end
    end

    reg [31:0]  word_data;
    reg [2:0]   mem_op_r;
    reg [1:0]   wr_addr_r;

    always@(posedge clk) begin
        bus_ack_r <= 1'b0;
        if (re) begin
            word_data <= {dmem3[word_addr], dmem2[word_addr],dmem1[word_addr], dmem0[word_addr]};
            bus_ack_r <= 1'b1;
        end
        if (re) begin mem_op_r <= mem_op; wr_addr_r <= wr_addr[1:0]; end
        re_r <= re;
    end

    assign bus_ack = bus_ack_w || bus_ack_r;

    always @* begin
        if (re_r) begin
            case (mem_op_r)
                3'b000: // LB
                    case (wr_addr_r[1:0])
                        2'b00: r_data = {{24{word_data[7]}},  word_data[7:0]};
                        2'b01: r_data = {{24{word_data[15]}}, word_data[15:8]};
                        2'b10: r_data = {{24{word_data[23]}}, word_data[23:16]};
                        2'b11: r_data = {{24{word_data[31]}}, word_data[31:24]};
                    endcase
                3'b001: // LH
                    case (wr_addr_r[1])
                        1'b0: r_data = {{16{word_data[15]}}, word_data[15:0]};
                        1'b1: r_data = {{16{word_data[31]}}, word_data[31:16]};
                    endcase
                3'b010: r_data = word_data; // LW
                3'b100: // LBU
                    case (wr_addr_r[1:0])
                        2'b00: r_data = {24'b0, word_data[7:0]};
                        2'b01: r_data = {24'b0, word_data[15:8]};
                        2'b10: r_data = {24'b0, word_data[23:16]};
                        2'b11: r_data = {24'b0, word_data[31:24]};
                    endcase
                3'b101: // LHU
                    case (wr_addr_r[1])
                        1'b0: r_data = {16'b0, word_data[15:0]};
                        1'b1: r_data = {16'b0, word_data[31:16]};
                    endcase
                default: r_data = word_data; //LW
            endcase
        end else begin
            r_data = 32'h0;
        end
    end

endmodule

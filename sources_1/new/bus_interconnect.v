`timescale 1ns / 1ps
`include "defines.v"

module bus_interconnect(
    input  wire clk,
    input  wire rst_n,

    input  wire bus_m_stb,
    output wire bus_m_ack,
    output wire bus_m_ready,
    output wire bus_m_err,
    input  wire [2:0] bus_m_op,
    output wire [2:0] bus_mem_op,
    input  wire bus_m_we,
    input  wire [31:0] bus_m_addr,
    input  wire [31:0] bus_m_dat_i,
    output wire [31:0] bus_m_dat_o,

    output wire bus_s0_stb,
    input  wire bus_s0_ack,
    output wire bus_s0_we,
    output wire [31:0] bus_s0_addr,
    input  wire [31:0] bus_s0_dat_i,
    output wire [31:0] bus_s0_dat_o,

    output wire bus_s1_stb,
    input  wire bus_s1_ack,
    output wire bus_s1_we,
    output wire [31:0] bus_s1_addr,
    input  wire [31:0] bus_s1_dat_i,
    output wire [31:0] bus_s1_dat_o,

    output wire bus_s2_stb,
    input  wire bus_s2_ack,
    output wire bus_s2_we,
    output wire [31:0] bus_s2_addr,
    input  wire [31:0] bus_s2_dat_i,
    output wire [31:0] bus_s2_dat_o
    );

    localparam integer IMEM_ADDR_BITS = `IMEM_ADDR_BITS;
    localparam integer DMEM_ADDR_BITS = `DMEM_ADDR_BITS;
    localparam [31:0] IMEM_BASE_ADDR = `IMEM_BASE_ADDR;
    localparam [31:0] DMEM_BASE_ADDR = `DMEM_BASE_ADDR;

    // One outstanding transaction. STB is a one-cycle accepted request,
    // ACK is a response (at least one cycle later). Accept a new request on
    // the previous response cycle to preserve one-request-per-cycle BRAM use.
    localparam [31:0] MMIO_BASE_ADDR = `MMIO_BASE_ADDR;
    wire sel0 = bus_m_addr[31:IMEM_ADDR_BITS] == IMEM_BASE_ADDR[31:IMEM_ADDR_BITS];
    wire sel1 = bus_m_addr[31:DMEM_ADDR_BITS] == DMEM_BASE_ADDR[31:DMEM_ADDR_BITS];
    wire clint = bus_m_addr[31:2]==30'h00800000 || bus_m_addr[31:3]==29'h00400800 || bus_m_addr[31:3]==29'h004017ff;
    wire sel2 = bus_m_addr[31:6] == MMIO_BASE_ADDR[31:6] || clint;
    wire valid_op = bus_m_we ? (bus_m_op <= 3'b010)
                            : ((bus_m_op <= 3'b010) || bus_m_op==3'b100 || bus_m_op==3'b101);
    wire aligned = (bus_m_op[1:0]==2'b00) ||
                   (bus_m_op[1:0]==2'b01 && !bus_m_addr[0]) ||
                   (bus_m_op==3'b010 && bus_m_addr[1:0]==0);
    // Existing MMIO registers are 32-bit only. Invalid accesses are completed
    // with an error, never silently aliased, issued to a slave, or left hanging.
    wire bad_request = !(sel0 || sel1 || sel2) || !valid_op || !aligned ||
                       (sel0 && bus_m_we) || (sel2 && bus_m_op!=3'b010);
    reg pending;
    reg [2:0] selection;
    reg error_q;
    reg we_q;
    reg [31:0] addr_q, data_q;
    reg [2:0] op_q;
    wire response = error_q || (selection[0] && bus_s0_ack) ||
                    (selection[1] && bus_s1_ack) || (selection[2] && bus_s2_ack);
    assign bus_m_ack = rst_n && pending && response;
    assign bus_m_err = bus_m_ack && error_q;
    assign bus_m_ready = rst_n && (!pending || bus_m_ack);
    wire accept = bus_m_stb && bus_m_ready;
    assign bus_s0_stb = accept && sel0 && !bad_request;
    assign bus_s1_stb = accept && sel1 && !bad_request;
    assign bus_s2_stb = accept && sel2 && !bad_request;
    assign bus_s0_we = accept ? bus_m_we : we_q;
    assign bus_s1_we = bus_s0_we;
    assign bus_s2_we = bus_s0_we;
    assign bus_s0_addr = accept ? bus_m_addr : addr_q;
    assign bus_s1_addr = bus_s0_addr;
    assign bus_s2_addr = bus_s0_addr;
    assign bus_s0_dat_o = accept ? bus_m_dat_i : data_q;
    assign bus_s1_dat_o = bus_s0_dat_o;
    assign bus_s2_dat_o = bus_s0_dat_o;
    assign bus_mem_op = accept ? bus_m_op : op_q;
    assign bus_m_dat_o = error_q ? 32'b0 : selection[0] ? bus_s0_dat_i :
                        selection[1] ? bus_s1_dat_i : selection[2] ? bus_s2_dat_i : 32'b0;
    always @(posedge clk) begin
        if (!rst_n) begin
            pending<=0; selection<=0; error_q<=0;
            we_q<=0; addr_q<=0; data_q<=0; op_q<=0;
        end else if (accept) begin
            pending<=1;
            selection<={sel2,sel1,sel0}; error_q<=bad_request;
            we_q<=bus_m_we; addr_q<=bus_m_addr; data_q<=bus_m_dat_i; op_q<=bus_m_op;
        end else if (bus_m_ack) begin
            pending<=0; selection<=0; error_q<=0;
        end
    end
endmodule

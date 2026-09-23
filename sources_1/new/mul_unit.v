`timescale 1ns / 1ps

module mul_unit(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        preload,
    input  wire        signed_a,
    input  wire        signed_b,
    input  wire [31:0] op_a,
    input  wire [31:0] op_b,
    output wire [63:0] result,
    output reg         ready
);

    localparam integer MUL_LATENCY = 3;

    // ------------------------------------------------------------------------
    // Front-end handshake
    // ------------------------------------------------------------------------
    reg        busy;
    reg [1:0]  latency_cnt;
    wire       preload_en = preload && !busy;
    wire       dsp_ce     = busy | preload_en;

    // ------------------------------------------------------------------------
    // Operand staging
    // ------------------------------------------------------------------------
    reg signed [16:0] a_hi_q;
    reg signed [16:0] b_hi_q;
    reg signed [16:0] a_lo_q;
    reg signed [16:0] b_lo_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            busy        <= 1'b0;
            ready       <= 1'b0;
            latency_cnt <= 2'd0;
        end else begin
            if (preload_en) begin
                ready <= 1'b0;
                busy        <= 1'b1;
                latency_cnt <= MUL_LATENCY - 1;
            end else if (busy) begin
                if (latency_cnt == 0) begin
                    busy  <= 1'b0;
                    ready <= 1'b1;
                end else begin
                    latency_cnt <= latency_cnt - 1'b1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            a_hi_q <= 17'sd0;
            b_hi_q <= 17'sd0;
            a_lo_q <= 17'sd0;
            b_lo_q <= 17'sd0;
        end else if (preload_en) begin
            a_hi_q <= signed_a ? {op_a[31], op_a[31:16]} : {1'b0, op_a[31:16]};
            b_hi_q <= signed_b ? {op_b[31], op_b[31:16]} : {1'b0, op_b[31:16]};
            a_lo_q <= {1'b0, op_a[15:0]};
            b_lo_q <= {1'b0, op_b[15:0]};
        end
    end

    // ------------------------------------------------------------------------
    // Partial products
    // ------------------------------------------------------------------------
    wire signed [33:0] pp_ll;
    wire signed [33:0] pp_lh;
    wire signed [33:0] pp_hl;
    wire signed [33:0] pp_hh;

    dsp_mul_17x17 u_mul_ll (
        .clk (clk),
        .rst_n (rst_n),
        .ce  (dsp_ce),
        .a   (a_lo_q),
        .b   (b_lo_q),
        .p   (pp_ll)
    );

    dsp_mul_17x17 u_mul_lh (
        .clk (clk),
        .rst_n (rst_n),
        .ce  (dsp_ce),
        .a   (a_lo_q),
        .b   (b_hi_q),
        .p   (pp_lh)
    );

    dsp_mul_17x17 u_mul_hl (
        .clk (clk),
        .rst_n (rst_n),
        .ce  (dsp_ce),
        .a   (a_hi_q),
        .b   (b_lo_q),
        .p   (pp_hl)
    );

    dsp_mul_17x17 u_mul_hh (
        .clk (clk),
        .rst_n (rst_n),
        .ce  (dsp_ce),
        .a   (a_hi_q),
        .b   (b_hi_q),
        .p   (pp_hh)
    );

    wire signed [63:0] term_ll = {{30{pp_ll[33]}}, pp_ll};
    wire signed [63:0] term_lh = ({{30{pp_lh[33]}}, pp_lh}) <<< 16;
    wire signed [63:0] term_hl = ({{30{pp_hl[33]}}, pp_hl}) <<< 16;
    wire signed [63:0] term_hh = ({{30{pp_hh[33]}}, pp_hh}) <<< 32;

    // Balanced adder tree to reduce logic depth.
    wire signed [63:0] sum_lo      = term_ll + term_lh;
    wire signed [63:0] sum_hi      = term_hl + term_hh;
    wire signed [63:0] product_sum = sum_lo + sum_hi;

    assign result = product_sum;

endmodule

module dsp_mul_17x17(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ce,
    input  wire signed [16:0] a,
    input  wire signed [16:0] b,
    output wire signed [33:0] p
);

`ifdef SYNTHESIS
    wire        dsp_rst = ~rst_n;
    wire [29:0] dsp_a   = {{13{a[16]}}, a};
    wire [17:0] dsp_b   = {{1{b[16]}}, b};
    wire [47:0] dsp_p;

    DSP48E1 #(
        .ACASCREG(1),
        .ADREG(0),
        .ALUMODEREG(0),
        .AREG(1),
        .A_INPUT("DIRECT"),
        .BCASCREG(1),
        .BREG(1),
        .B_INPUT("DIRECT"),
        .CARRYINREG(0),
        .CARRYINSELREG(0),
        .CREG(0),
        .DREG(0),
        .INMODEREG(0),
        .MREG(1),
        .OPMODEREG(0),
        .PREG(1),
        .USE_MULT("MULTIPLY"),
        .USE_SIMD("ONE48")
    ) dsp48e1_mul (
        .ACOUT(),
        .BCOUT(),
        .CARRYCASCOUT(),
        .CARRYOUT(),
        .MULTSIGNOUT(),
        .OVERFLOW(),
        .P(dsp_p),
        .PATTERNBDETECT(),
        .PATTERNDETECT(),
        .PCOUT(),
        .UNDERFLOW(),
        .A(dsp_a),
        .ACIN(30'd0),
        .ALUMODE(4'b0000),
        .B(dsp_b),
        .BCIN(18'd0),
        .C(48'd0),
        .CARRYCASCIN(1'b0),
        .CARRYIN(1'b0),
        .CARRYINSEL(3'b000),
        .CEA1(ce),
        .CEA2(ce),
        .CEAD(1'b0),
        .CEALUMODE(1'b0),
        .CEB1(ce),
        .CEB2(ce),
        .CEC(1'b0),
        .CECARRYIN(1'b0),
        .CECTRL(1'b0),
        .CED(1'b0),
        .CEINMODE(1'b0),
        .CEM(ce),
        .CEP(ce),
        .CLK(clk),
        .D(25'd0),
        .INMODE(5'b00000),
        .MULTSIGNIN(1'b0),
        .OPMODE(7'b0000101),
        .PCIN(48'd0),
        .RSTA(dsp_rst),
        .RSTALLCARRYIN(dsp_rst),
        .RSTALUMODE(dsp_rst),
        .RSTB(dsp_rst),
        .RSTC(dsp_rst),
        .RSTCTRL(dsp_rst),
        .RSTD(dsp_rst),
        .RSTINMODE(dsp_rst),
        .RSTM(dsp_rst),
        .RSTP(dsp_rst)
    );

    assign p = dsp_p[33:0];
`else
    reg signed [33:0] p_q;

    always @(posedge clk) begin
        if (!rst_n)
            p_q <= 34'sd0;
        else if (ce)
            p_q <= a * b;
    end

    assign p = p_q;
`endif

endmodule

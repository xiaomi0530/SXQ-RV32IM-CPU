`timescale 1ns / 1ps

module div_unit(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        preload,
    input  wire [1:0]  op,
    input  wire [31:0] op_a,
    input  wire [31:0] op_b,
    output reg   [31:0] result,
    output reg          ready
);

    localparam [2:0] S_IDLE   = 3'd0;
    localparam [2:0] S_PREP   = 3'd1;
    localparam [2:0] S_RUN    = 3'd2;
    localparam [2:0] S_FIX    = 3'd3;
    localparam [2:0] S_DONE   = 3'd4;

    reg [2:0]  state;
    reg [1:0]  op_q;
    reg [31:0] dividend_raw_q;
    reg [31:0] divisor_raw_q;
    reg [31:0] dividend_shift_q;
    reg [31:0] divisor_abs_q;
    reg [31:0] quotient_q;
    reg [32:0] remainder_q;
    reg [5:0]  iter_q;
    reg        quotient_neg_q;
    reg        remainder_neg_q;

    wire rem_sel   = op_q[1];
    wire unsigned_div = op_q[0];
    wire signed_div   = ~unsigned_div;

    wire divisor_zero     = (divisor_raw_q == 32'b0);
    wire signed_overflow  = signed_div
                          && (dividend_raw_q == 32'h8000_0000)
                          && (divisor_raw_q  == 32'hffff_ffff);

    wire [31:0] dividend_abs = (signed_div && dividend_raw_q[31]) ? (~dividend_raw_q + 32'd1) : dividend_raw_q;
    wire [31:0] divisor_abs  = (signed_div && divisor_raw_q[31])  ? (~divisor_raw_q  + 32'd1) : divisor_raw_q;

    wire [32:0] divisor_ext       = {1'b0, divisor_abs_q};
    wire [32:0] remainder_shifted = {remainder_q[31:0], dividend_shift_q[31]};
    wire        can_subtract      = (remainder_shifted >= divisor_ext);
    wire [32:0] remainder_next    = can_subtract ? (remainder_shifted - divisor_ext) : remainder_shifted;
    wire [31:0] quotient_next     = {quotient_q[30:0], can_subtract};
    wire [31:0] dividend_shift_next = {dividend_shift_q[30:0], 1'b0};

    wire [31:0] quotient_fixed = quotient_neg_q ? (~quotient_q + 32'd1) : quotient_q;
    wire [31:0] remainder_fixed = remainder_neg_q ? (~remainder_q[31:0] + 32'd1) : remainder_q[31:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            ready            <= 1'b0;
            result           <= 32'b0;
            op_q             <= 2'b0;
            dividend_raw_q   <= 32'b0;
            divisor_raw_q    <= 32'b0;
            dividend_shift_q <= 32'b0;
            divisor_abs_q    <= 32'b0;
            quotient_q       <= 32'b0;
            remainder_q      <= 33'b0;
            iter_q           <= 6'd0;
            quotient_neg_q   <= 1'b0;
            remainder_neg_q  <= 1'b0;
        end else if (preload) begin
            // A newly accepted ID instruction may replace a wrong-path divide
            // squashed by a deferred branch or trap. Never drop that preload.
            ready<=0;
            op_q<=op; dividend_raw_q<=op_a; divisor_raw_q<=op_b;
            state<=S_PREP;
        end else begin
            case (state)
                S_IDLE: begin end

                S_PREP: begin
                    if (divisor_zero) begin
                        result <= rem_sel ? dividend_raw_q : 32'hffff_ffff;
                        state  <= S_DONE;
                    end else if (signed_overflow) begin
                        result <= rem_sel ? 32'b0 : 32'h8000_0000;
                        state  <= S_DONE;
                    end else begin
                        dividend_shift_q <= dividend_abs;
                        divisor_abs_q    <= divisor_abs;
                        quotient_q       <= 32'b0;
                        remainder_q      <= 33'b0;
                        iter_q           <= 6'd32;
                        quotient_neg_q   <= signed_div && (dividend_raw_q[31] ^ divisor_raw_q[31]);
                        remainder_neg_q  <= signed_div && dividend_raw_q[31];
                        state            <= S_RUN;
                    end
                end

                S_RUN: begin
                    dividend_shift_q <= dividend_shift_next;
                    quotient_q       <= quotient_next;
                    remainder_q      <= remainder_next;
                    iter_q           <= iter_q - 6'd1;
                    if (iter_q == 6'd1)
                        state <= S_FIX;
                end

                S_FIX: begin
                    result <= rem_sel ? remainder_fixed : quotient_fixed;
                    state  <= S_DONE;
                end

                S_DONE: begin
                    ready <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

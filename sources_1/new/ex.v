`timescale 1ns / 1ps
`include "defines.v"

module ex #(
    parameter integer IMEM_ADDR_BITS = `IMEM_ADDR_BITS
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mul_preload,
    input  wire        mul_preload_signed_a,
    input  wire        mul_preload_signed_b,
    input  wire [31:0] mul_preload_op_a,
    input  wire [31:0] mul_preload_op_b,
    input  wire        div_preload,
    input  wire [1:0]  div_preload_op,
    input  wire [31:0] div_preload_op_a,
    input  wire [31:0] div_preload_op_b,
    input  wire [31:0] ex_instr_addr,
    input  wire        ex_pred_taken,
    input  wire [IMEM_ADDR_BITS-1:0] ex_pred_target,
    input  wire [31:0] ex_alu_num1,
    input  wire [31:0] ex_alu_num2,

    input  wire [3:0]  ex_alu_op,
    input  wire [2:0]  ex_mem_op,
    input  wire        ex_branch_flag,
    input  wire [IMEM_ADDR_BITS-1:0] ex_branch_jump_addr,
    input  wire        ex_jump_flag,
    input  wire        ex_ctrl_defer,

    output reg  [31:0] ex_regs_w_data,
    output wire [31:0] ex_dmem_wr_addr,

    output reg         ex_actual_jump_flag,
    output wire [IMEM_ADDR_BITS-1:0] ex_actual_jump_addr,
    output wire        ex_mispredict,
    output wire [IMEM_ADDR_BITS-1:0] ex_redirect_addr,
    output wire        ex_mul_busy,
    output wire        ex_div_busy
);

    // ------------------------------------------------------------------------
    // Datapath helpers
    // ------------------------------------------------------------------------
    wire [31:0] add_res             = ex_alu_num1 + ex_alu_num2;
    wire [31:0] sub_res             = ex_alu_num1 - ex_alu_num2;
    wire [31:0] ex_instr_addr_plus4 = ex_instr_addr + 32'd4;
    wire        is_equal            = (sub_res == 32'b0);
    wire        is_less_signed      = (ex_alu_num1[31] != ex_alu_num2[31]) ? ex_alu_num1[31] : sub_res[31];
    wire        is_less_unsigned    = (ex_alu_num1 < ex_alu_num2);

    wire is_mul    = (ex_alu_op == `ALU_OP_MUL);
    wire is_mulh   = (ex_alu_op == `ALU_OP_MULH);
    wire is_mulhsu = (ex_alu_op == `ALU_OP_MULHSU);
    wire is_mulhu  = (ex_alu_op == `ALU_OP_MULHU);
    wire mul_op    = is_mul | is_mulh | is_mulhsu | is_mulhu;
    wire div_op    = (ex_alu_op == `ALU_OP_DIVREM);

    wire [63:0] mul_result;
    wire        mul_ready;
    wire [31:0] div_result;
    wire        div_ready;

    // ------------------------------------------------------------------------
    // Multiply / divide units
    // ------------------------------------------------------------------------
    mul_unit u_mul_unit (
        .clk     (clk),
        .rst_n   (rst_n),
        .preload (mul_preload),
        .signed_a(mul_preload_signed_a),
        .signed_b(mul_preload_signed_b),
        .op_a    (mul_preload_op_a),
        .op_b    (mul_preload_op_b),
        .result  (mul_result),
        .ready   (mul_ready)
    );

    div_unit u_div_unit (
        .clk     (clk),
        .rst_n   (rst_n),
        .preload (div_preload),
        .op      (div_preload_op),
        .op_a    (div_preload_op_a),
        .op_b    (div_preload_op_b),
        .result  (div_result),
        .ready   (div_ready)
    );

    assign ex_mul_busy = mul_op && !mul_ready;
    assign ex_div_busy = div_op && !div_ready;

    // ------------------------------------------------------------------------
    // ALU result
    // ------------------------------------------------------------------------
    reg [31:0] alu_out;

    always @* begin
        case (ex_alu_op)
            `ALU_OP_ADD:    alu_out = add_res;
            `ALU_OP_SUB:    alu_out = sub_res;
            `ALU_OP_AND:    alu_out = ex_alu_num1 & ex_alu_num2;
            `ALU_OP_OR:     alu_out = ex_alu_num1 | ex_alu_num2;
            `ALU_OP_XOR:    alu_out = ex_alu_num1 ^ ex_alu_num2;
            `ALU_OP_SLL:    alu_out = ex_alu_num1 << ex_alu_num2[4:0];
            `ALU_OP_SRL:    alu_out = ex_alu_num1 >> ex_alu_num2[4:0];
            `ALU_OP_SRA:    alu_out = $signed(ex_alu_num1) >>> ex_alu_num2[4:0];
            `ALU_OP_SLT:    alu_out = {31'b0, is_less_signed};
            `ALU_OP_SLTU:   alu_out = {31'b0, is_less_unsigned};
            `ALU_OP_MUL:    alu_out = mul_result[31:0];
            `ALU_OP_MULH,
            `ALU_OP_MULHSU,
            `ALU_OP_MULHU:  alu_out = mul_result[63:32];
            `ALU_OP_DIVREM: alu_out = div_result;
            default:        alu_out = 32'b0;
        endcase
    end

    // ------------------------------------------------------------------------
    // Redirect / mispredict detection
    // ------------------------------------------------------------------------
    wire branch_taken;
    wire branch_dir_mismatch;
    wire branch_target_mismatch;
    wire branch_mispredict;
    wire jump_dir_mismatch;
    wire jump_target_mismatch;
    wire jump_mispredict;

    wire [IMEM_ADDR_BITS-1:0] add_res_low = {add_res[IMEM_ADDR_BITS-1:1],1'b0};

    assign ex_actual_jump_addr   = ex_jump_flag ? add_res_low : ex_branch_jump_addr;
    assign ex_redirect_addr      = ex_actual_jump_flag ? ex_actual_jump_addr
                                                       : ex_instr_addr_plus4[IMEM_ADDR_BITS-1:0];
    assign branch_taken          = ex_jump_flag ? 1'b1 : ex_actual_jump_flag;
    assign branch_dir_mismatch   = ex_pred_taken ^ branch_taken;
    assign branch_target_mismatch = ex_pred_taken && branch_taken && (ex_pred_target != ex_branch_jump_addr);
    assign branch_mispredict      = ex_branch_flag && !ex_ctrl_defer && (branch_dir_mismatch || branch_target_mismatch);
    assign jump_dir_mismatch      = !ex_pred_taken;
    assign jump_target_mismatch   = ex_pred_taken && (ex_pred_target != add_res_low);
    assign jump_mispredict        = ex_jump_flag && !ex_ctrl_defer && (jump_dir_mismatch || jump_target_mismatch);
    assign ex_mispredict          = branch_mispredict || jump_mispredict;

    // ------------------------------------------------------------------------
    // Control outputs
    // ------------------------------------------------------------------------
    always @* begin
        if (ex_ctrl_defer) begin
            ex_actual_jump_flag = 1'b0;
        end else if (ex_jump_flag) begin
            ex_actual_jump_flag = 1'b1;
        end else if (ex_branch_flag) begin
            case (ex_mem_op)
                3'b000: ex_actual_jump_flag = is_equal;
                3'b001: ex_actual_jump_flag = !is_equal;
                3'b100: ex_actual_jump_flag = is_less_signed;
                3'b101: ex_actual_jump_flag = !is_less_signed;
                3'b110: ex_actual_jump_flag = is_less_unsigned;
                3'b111: ex_actual_jump_flag = !is_less_unsigned;
                default: ex_actual_jump_flag = 1'b0;
            endcase
        end else begin
            ex_actual_jump_flag = 1'b0;
        end
    end

    always @* begin
        if (ex_jump_flag)
            ex_regs_w_data = ex_instr_addr + 4;
        else
            ex_regs_w_data = alu_out;
    end

    assign ex_dmem_wr_addr = add_res;

endmodule

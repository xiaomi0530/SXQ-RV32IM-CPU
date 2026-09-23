`timescale 1ns / 1ps

`include "defines.v"

module mem_ctrl_resolve #(
    parameter integer IMEM_ADDR_BITS = `IMEM_ADDR_BITS
)(
    input  wire        mem_ctrl_defer,
    input  wire        mem_ctrl_dep_rs1,
    input  wire        mem_ctrl_both_dep,
    input  wire        mem_branch_flag,
    input  wire        mem_jalr_flag,
    input  wire [2:0]  mem_mem_op,
    input  wire [IMEM_ADDR_BITS-1:0] mem_ctrl_pc_low,
    input  wire        mem_pred_taken,
    input  wire [IMEM_ADDR_BITS-1:0] mem_ctrl_pred_target_low,
    input  wire [IMEM_ADDR_BITS-1:0] mem_ctrl_branch_target_low,
    input  wire [31:0] mem_ctrl_other_operand,
    input  wire [11:0] mem_ctrl_jalr_imm12,
    input  wire [31:0] wb_late_data,
    output wire        mem_ctrl_resolve_en,
    output reg         mem_ctrl_actual_jump_flag,
    output wire [IMEM_ADDR_BITS-1:0] mem_ctrl_actual_jump_addr_low,
    output wire        mem_ctrl_mispredict,
    output wire [IMEM_ADDR_BITS-1:0] mem_ctrl_redirect_addr
);

    wire [31:0] jalr_imm = {{20{mem_ctrl_jalr_imm12[11]}}, mem_ctrl_jalr_imm12};
    wire [31:0] ctrl_num1 = mem_ctrl_dep_rs1 ? wb_late_data : mem_ctrl_other_operand;
    wire [31:0] ctrl_num2 = mem_ctrl_dep_rs1 ? mem_ctrl_other_operand : wb_late_data;
    localparam [IMEM_ADDR_BITS-1:0] ADDR_INC4 = {{(IMEM_ADDR_BITS-3){1'b0}}, 3'd4};

    // Four independent byte comparisons keep late WB operands out of a
    // 32-bit subtract carry chain. Resolution still occurs in the same MEM cycle.
    (* keep = "true" *) wire [3:0] byte_equal;
    (* keep = "true" *) wire [3:0] byte_less;
    genvar chunk;
    generate for(chunk=0;chunk<4;chunk=chunk+1) begin: compare_byte
        assign byte_equal[chunk]=ctrl_num1[chunk*8 +: 8]==ctrl_num2[chunk*8 +: 8];
        assign byte_less[chunk]=ctrl_num1[chunk*8 +: 8]<ctrl_num2[chunk*8 +: 8];
    end endgenerate
    wire unsigned_less = byte_less[3] || (byte_equal[3] && byte_less[2]) ||
                         (&byte_equal[3:2] && byte_less[1]) || (&byte_equal[3:1] && byte_less[0]);
    wire [IMEM_ADDR_BITS-1:0] jalr_sum = wb_late_data[IMEM_ADDR_BITS-1:0] + jalr_imm[IMEM_ADDR_BITS-1:0];
    wire [IMEM_ADDR_BITS-1:0] jalr_target_low = {jalr_sum[IMEM_ADDR_BITS-1:1],1'b0};
    wire [IMEM_ADDR_BITS-1:0] mem_instr_addr_plus4_low = mem_ctrl_pc_low + ADDR_INC4;
    wire        is_equal = mem_ctrl_both_dep ? 1'b1 : (&byte_equal);
    wire        is_less_signed = mem_ctrl_both_dep ? 1'b0
                              : ((ctrl_num1[31] != ctrl_num2[31]) ? ctrl_num1[31] : unsigned_less);
    wire        is_less_unsigned = mem_ctrl_both_dep ? 1'b0 : unsigned_less;
    wire        branch_taken = mem_ctrl_actual_jump_flag;
    wire        branch_dir_mismatch = mem_pred_taken ^ branch_taken;
    wire        branch_target_mismatch = mem_pred_taken
                                      && branch_taken
                                      && (mem_ctrl_pred_target_low != mem_ctrl_branch_target_low);
    wire        jump_dir_mismatch = !mem_pred_taken;
    wire        jump_target_mismatch = mem_pred_taken && (mem_ctrl_pred_target_low != jalr_target_low);
    wire        branch_mispredict = mem_branch_flag
                                 && mem_ctrl_resolve_en
                                 && (branch_dir_mismatch || branch_target_mismatch);
    wire        jump_mispredict = mem_jalr_flag
                               && mem_ctrl_resolve_en
                               && (jump_dir_mismatch || jump_target_mismatch);

    assign mem_ctrl_resolve_en = mem_ctrl_defer && (mem_branch_flag || mem_jalr_flag);
    assign mem_ctrl_actual_jump_addr_low = mem_jalr_flag ? jalr_target_low
                                                         : mem_ctrl_branch_target_low;
    assign mem_ctrl_redirect_addr = mem_ctrl_actual_jump_flag
                                  ? mem_ctrl_actual_jump_addr_low
                                  : mem_instr_addr_plus4_low;
    assign mem_ctrl_mispredict = branch_mispredict || jump_mispredict;

    always @* begin
        if (mem_jalr_flag) begin
            mem_ctrl_actual_jump_flag = mem_ctrl_resolve_en;
        end else if (mem_branch_flag) begin
            case (mem_mem_op)
                3'b000: mem_ctrl_actual_jump_flag = is_equal;
                3'b001: mem_ctrl_actual_jump_flag = !is_equal;
                3'b100: mem_ctrl_actual_jump_flag = is_less_signed;
                3'b101: mem_ctrl_actual_jump_flag = !is_less_signed;
                3'b110: mem_ctrl_actual_jump_flag = is_less_unsigned;
                3'b111: mem_ctrl_actual_jump_flag = !is_less_unsigned;
                default: mem_ctrl_actual_jump_flag = 1'b0;
            endcase
        end else begin
            mem_ctrl_actual_jump_flag = 1'b0;
        end
    end

endmodule

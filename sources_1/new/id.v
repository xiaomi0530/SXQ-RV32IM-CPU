`timescale 1ns / 1ps
`include "defines.v"

module id(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] id_instr_addr,
    input  wire [31:0] id_instr,

    output wire        id_regs_re,
    output wire [4:0]  id_rs1_addr,
    output wire [4:0]  id_rs2_addr,
    output wire        id_rs1_used,
    output wire        id_rs2_used,
    input  wire [31:0] id_rs1_data,
    input  wire [31:0] id_rs2_data,

    output wire [4:0]  id_rd_addr,
    output wire        id_regs_we,

    output reg   [3:0]  id_alu_op,
    output wire [31:0] id_alu_num1,
    output wire [31:0] id_alu_num2,

    output wire [2:0]  id_mem_op,

    output wire        id_dmem_we,
    output wire        id_dmem_re,
    output wire [31:0] id_dmem_w_data,

    output wire        id_branch_flag,
    output wire [`IMEM_ADDR_BITS-1:0] id_branch_jump_addr,
    output wire        id_jump_flag,
    output wire        id_jalr_flag,
    output wire        id_call_flag,
    output wire        id_ret_flag
);

    localparam integer IMEM_ADDR_BITS = `IMEM_ADDR_BITS;

    wire [6:0] opcode = id_instr[6:0];
    wire [2:0] funct3 = id_instr[14:12];
    wire [6:0] funct7 = id_instr[31:25];

    wire [4:0] opcode_hi = opcode[6:2];
    wire dec_r       = (opcode_hi == 5'b01100); // 0x33
    wire dec_i_alu   = (opcode_hi == 5'b00100); // 0x13
    wire dec_i_load  = (opcode_hi == 5'b00000); // 0x03
    wire dec_i_jalr  = (opcode_hi == 5'b11001); // 0x67
    wire dec_s       = (opcode_hi == 5'b01000); // 0x23
    wire dec_b       = (opcode_hi == 5'b11000); // 0x63
    wire dec_u_lui   = (opcode_hi == 5'b01101); // 0x37
    wire dec_u_auipc = (opcode_hi == 5'b00101); // 0x17
    wire dec_j_jal   = (opcode_hi == 5'b11011); // 0x6f

    wire type_r       = dec_r;
    wire type_i_alu   = dec_i_alu;
    wire type_i_load  = dec_i_load;
    wire type_i_jalr  = dec_i_jalr;
    wire type_s       = dec_s;
    wire type_b       = dec_b;
    wire type_u_lui   = dec_u_lui;
    wire type_u_auipc = dec_u_auipc;
    wire type_j_jal   = dec_j_jal;

    reg [31:0] imm;
    wire [31:0] i_imm = {{21{id_instr[31]}}, id_instr[30:20]};
    wire [31:0] s_imm = {{21{id_instr[31]}}, id_instr[30:25], id_instr[11:7]};
    wire [31:0] b_imm = {{20{id_instr[31]}}, id_instr[7], id_instr[30:25], id_instr[11:8], 1'b0};
    wire [31:0] u_imm = {id_instr[31:12], 12'b0};
    wire [31:0] j_imm = {{12{id_instr[31]}}, id_instr[19:12], id_instr[20], id_instr[30:21], 1'b0};

    always @* begin
        case (opcode_hi)
            5'b00000, 5'b00100, 5'b11001: imm = i_imm; // load / I-ALU / JALR
            5'b01000:                     imm = s_imm; // store
            5'b11000:                     imm = b_imm; // branch
            5'b01101, 5'b00101:           imm = u_imm; // LUI / AUIPC
            5'b11011:                     imm = j_imm; // JAL
            default:                      imm = 32'b0;
        endcase
    end

    assign id_rs1_addr = id_instr[19:15];
    assign id_rs2_addr = id_instr[24:20];
    assign id_rd_addr  = id_instr[11:7];

    assign id_regs_we  = type_r | type_i_alu | type_i_load | type_i_jalr | type_u_lui | type_u_auipc | type_j_jal;
    wire csr_reg_source = opcode==7'h73 && (funct3==1 || funct3==2 || funct3==3);
    assign id_regs_re  = csr_reg_source | type_r | type_i_alu | type_i_load | type_i_jalr | type_s | type_b;
    assign id_rs1_used = type_r | type_i_alu | type_i_load | type_i_jalr | type_s | type_b;
    assign id_rs2_used = type_r | type_s | type_b;

    assign id_dmem_we  = type_s;
    assign id_dmem_re  = type_i_load;
    assign id_dmem_w_data = id_rs2_data;
    assign id_mem_op   = funct3;

    wire [31:0] branch_target_full = b_imm + id_instr_addr;

    assign id_branch_flag = type_b;
    assign id_branch_jump_addr = branch_target_full[IMEM_ADDR_BITS-1:0];
    assign id_jump_flag   = type_j_jal | type_i_jalr;
    assign id_jalr_flag   = type_i_jalr;
    assign id_call_flag   = (type_j_jal | type_i_jalr) && ((id_rd_addr == 5'd1) || (id_rd_addr == 5'd5));
    assign id_ret_flag    = type_i_jalr
                         && (id_rd_addr == 5'd0)
                         && ((id_rs1_addr == 5'd1) || (id_rs1_addr == 5'd5))
                         && (i_imm == 32'b0);

    assign id_alu_num1 = (type_u_auipc | type_j_jal) ? id_instr_addr : (type_u_lui ? 32'b0 : id_rs1_data);
    assign id_alu_num2 = (type_r | type_b) ? id_rs2_data : imm;

    wire rv32m_any = dec_r && (funct7 == 7'b0000001);
    wire rv32m_mul = rv32m_any && (funct3[2] == 1'b0);
    wire rv32m_div = rv32m_any && (funct3[2] == 1'b1);

    always @* begin
        if (rv32m_mul) begin
            case (funct3)
                3'b000:  id_alu_op = `ALU_OP_MUL;
                3'b001:  id_alu_op = `ALU_OP_MULH;
                3'b010:  id_alu_op = `ALU_OP_MULHSU;
                3'b011:  id_alu_op = `ALU_OP_MULHU;
                default: id_alu_op = `ALU_OP_ADD;
            endcase
        end else if (rv32m_div) begin
            id_alu_op = `ALU_OP_DIVREM;
        end else if (rv32m_any) begin
            id_alu_op = `ALU_OP_ADD;
        end else if (type_r || type_i_alu) begin
            id_alu_op = { ( (type_r && funct7[5]) || (type_i_alu && funct3==3'b101 && funct7[5]) ), funct3 };
        end else if (type_b) begin
            id_alu_op = `ALU_OP_SUB;
        end else begin
            id_alu_op = `ALU_OP_ADD;
        end
    end

endmodule

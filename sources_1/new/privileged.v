`timescale 1ns/1ps
`include "defines.v"

// RV32IM machine-only privileged slow path. Ordinary instructions never pass
// through the CSR read mux. Serialize at ID, let older EX/MEM/WB drain, then
// execute exactly once and use the existing frontend recovery mechanism.
module privileged(
    input wire clk, rst_n,
    input wire id_valid,
    input wire [31:0] id_instr, id_pc, id_rs1,
    input wire older_empty, older_redirect,
    input wire mem_exception,
    input wire [31:0] mem_cause, mem_pc, mem_tval,
    input wire mem_far_redirect,
    input wire [31:0] mem_target,
    input wire retire,
    input wire [63:0] time_value,
    input wire irq_timer, irq_software, irq_external,
    output wire id_stop, busy, flush,
    output wire interrupt_request,
    output wire redirect,
    output reg [31:0] redirect_pc,
    output wire rf_we,
    output wire [4:0] rf_rd,
    output wire [31:0] rf_data,
    output wire system_retire,
    output wire trap_enter,
    output wire [63:0] instret_value
);
    localparam IDLE=0, EXEC=1, TRAP=2, REDIRECT=3, SLEEP=4;
    reg [2:0] state;
    reg [31:0] instr_q, pc_q, src_q, cause_q, tval_q;
    reg mstatus_mie, mstatus_mpie;
    reg [31:0] mie, mtvec, mscratch, mepc, mcause, mtval;
    reg [63:0] mcycle, minstret;
    reg [2:0] mcountinhibit;
    wire [31:0] mip = {20'b0,irq_external,3'b0,irq_timer,3'b0,irq_software,3'b0};
    wire [31:0] enabled = mip & mie;
    wire wake_pending = |enabled;
    wire interrupt_pending = mstatus_mie && wake_pending;
    assign interrupt_request = interrupt_pending;
    wire [31:0] interrupt_cause = enabled[11] ? 32'h8000000b :
                                 enabled[3] ? 32'h80000003 : 32'h80000007;
    wire [6:0] opcode = id_instr[6:0];
    wire [2:0] f3 = id_instr[14:12];
    wire [6:0] f7 = id_instr[31:25];
    reg legal;
    always @* begin
        legal=0;
        case(opcode)
            7'h37,7'h17,7'h6f: legal=1;
            7'h67: legal=f3==0;
            7'h63: legal=(f3==0 || f3==1 || f3>=4);
            7'h03: legal=(f3<=2 || f3==4 || f3==5);
            7'h23: legal=f3<=2;
            7'h13: legal=(f3==1) ? f7==0 : (f3==5) ? (f7==0 || f7==7'h20) : 1'b1;
            7'h33: legal=f7==0 || f7==1 || (f7==7'h20 && (f3==0 || f3==5));
            // Reserved FENCE operands are ignored, as required for forward compatibility.
            7'h0f: legal=f3==0 || f3==1;
            7'h73: legal=(f3==1 || f3==2 || f3==3 || f3==5 || f3==6 || f3==7) ||
                        id_instr==32'h00000073 || id_instr==32'h00100073 ||
                        id_instr==32'h30200073 || id_instr==32'h10500073;
            default: legal=0;
        endcase
    end
    wire fetch_fault = |id_pc[31:`IMEM_ADDR_BITS];
    wire fetch_misaligned = |id_pc[1:0];
    wire serial = !legal || fetch_fault || fetch_misaligned || opcode==7'h73 || opcode==7'h0f;
    assign id_stop = state!=IDLE || (id_valid && (serial || interrupt_pending));
    assign busy = state!=IDLE;
    assign redirect = state==REDIRECT;
    assign flush = redirect || mem_exception || mem_far_redirect;
    assign trap_enter = state==TRAP;
    wire csr_op = instr_q[6:0]==7'h73 && instr_q[14:12]!=0;
    wire [11:0] csr_addr=instr_q[31:20];
    wire [31:0] csr_operand=instr_q[14] ? {27'b0,instr_q[19:15]} : src_q;
    // RS/RC suppress writes for an encoded x0/zimm=0, NOT a zero register value.
    wire csr_write = instr_q[13:12]==1 || instr_q[19:15]!=0;
    reg [31:0] csr_read;
    reg csr_exists;
    wire hpm_zero = (csr_addr>=12'hb03 && csr_addr<=12'hb1f) ||
                    (csr_addr>=12'hb83 && csr_addr<=12'hb9f) ||
                    (csr_addr>=12'hc03 && csr_addr<=12'hc1f) ||
                    (csr_addr>=12'hc83 && csr_addr<=12'hc9f) ||
                    (csr_addr>=12'h323 && csr_addr<=12'h33f);
    always @* begin
        csr_read=0; csr_exists=1;
        case(csr_addr)
            12'h300: csr_read=32'h1800 | {24'b0,mstatus_mpie,3'b0,mstatus_mie,3'b0};
            12'h301: csr_read=32'h40001100; // MXL=RV32; I and M only.
            12'h304: csr_read=mie;
            12'h305: csr_read=mtvec;
            12'h306,12'h310: csr_read=0; // no lower modes, little endian
            12'h320: csr_read={29'b0,mcountinhibit};
            12'h340: csr_read=mscratch;
            12'h341: csr_read=mepc;
            12'h342: csr_read=mcause;
            12'h343: csr_read=mtval;
            12'h344: csr_read=mip;
            12'hb00,12'hc00: csr_read=mcycle[31:0];
            12'hb80,12'hc80: csr_read=mcycle[63:32];
            12'hb02,12'hc02: csr_read=minstret[31:0];
            12'hb82,12'hc82: csr_read=minstret[63:32];
            12'hc01: csr_read=time_value[31:0];
            12'hc81: csr_read=time_value[63:32];
            12'hf11,12'hf12,12'hf13,12'hf14,12'hf15: csr_read=0;
            default: csr_exists=hpm_zero;
        endcase
    end
    wire csr_illegal = !csr_exists || (csr_write && csr_addr[11:10]==2'b11);
    wire [31:0] csr_new = instr_q[13:12]==1 ? csr_operand :
                         instr_q[13:12]==2 ? csr_read | csr_operand : csr_read & ~csr_operand;
    wire csr_commit = state==EXEC && csr_op && !csr_illegal;
    assign rf_we = csr_commit && instr_q[11:7]!=0;
    assign rf_rd = instr_q[11:7];
    assign rf_data = csr_read;
    assign system_retire = state==EXEC && (!csr_op || !csr_illegal);
    assign instret_value = minstret;

    always @(posedge clk) begin
        if(!rst_n) begin
            state<=IDLE; instr_q<=0; pc_q<=0; src_q<=0; cause_q<=0; tval_q<=0; redirect_pc<=0;
            mstatus_mie<=0; mstatus_mpie<=0; mie<=0; mtvec<=0; mscratch<=0;
            mepc<=0; mcause<=0; mtval<=0; mcycle<=0; minstret<=0; mcountinhibit<=0;
        end else begin
            if(!mcountinhibit[0]) mcycle<=mcycle+1'b1;
            if(!mcountinhibit[2] && (retire || system_retire)) minstret<=minstret+1'b1;
            case(state)
                IDLE: begin
                    if(mem_exception) begin
                        pc_q<=mem_pc; cause_q<=mem_cause; tval_q<=mem_tval; state<=TRAP;
                    end else if(mem_far_redirect) begin
                        redirect_pc<=mem_target; state<=REDIRECT;
                    end else if(id_valid && id_stop && older_empty && !older_redirect) begin
                        instr_q<=id_instr; pc_q<=id_pc; src_q<=id_rs1;
                        if(interrupt_pending) begin
                            cause_q<=interrupt_cause; tval_q<=0; state<=TRAP;
                        end else if(fetch_misaligned || fetch_fault || !legal ||
                                    id_instr==32'h00000073 || id_instr==32'h00100073) begin
                            cause_q<=fetch_misaligned ? 0 : fetch_fault ? 1 : !legal ? 2 : id_instr[20] ? 3 : 11;
                            tval_q<=fetch_misaligned || fetch_fault ? id_pc : !legal ? id_instr : id_instr[20] ? id_pc : 0;
                            state<=TRAP;
                        end else state<=EXEC;
                    end
                end
                EXEC: begin
                    redirect_pc<=pc_q+4;
                    state<=REDIRECT;
                    if(csr_op && csr_illegal) begin
                        cause_q<=2; tval_q<=instr_q; state<=TRAP;
                    end else if(instr_q==32'h30200073) begin
                        mstatus_mie<=mstatus_mpie; mstatus_mpie<=1;
                        redirect_pc<=mepc;
                    end else if(instr_q==32'h10500073) state<=SLEEP;
                    if(csr_commit && csr_write) begin
                        case(csr_addr)
                            12'h300: begin mstatus_mie<=csr_new[3]; mstatus_mpie<=csr_new[7]; end
                            12'h304: mie<=csr_new & 32'h888;
                            12'h305: mtvec<={csr_new[31:2],1'b0,(csr_new[1:0]==1)};
                            12'h320: mcountinhibit<=csr_new[2:0] & 3'b101;
                            12'h340: mscratch<=csr_new;
                            12'h341: mepc<={csr_new[31:2],2'b0};
                            12'h342: mcause<=csr_new;
                            12'h343: mtval<=csr_new;
                            12'hb00: mcycle<= {mcycle[63:32],csr_new};
                            12'hb80: mcycle<= {csr_new,mcycle[31:0]};
                            12'hb02: minstret<= {minstret[63:32],csr_new};
                            12'hb82: minstret<= {csr_new,minstret[31:0]};
                            default: ; // fixed WARL fields and hardware-owned mip
                        endcase
                    end
                end
                TRAP: begin
                    mepc<={pc_q[31:2],2'b0}; mcause<=cause_q; mtval<=tval_q;
                    mstatus_mpie<=mstatus_mie; mstatus_mie<=0;
                    redirect_pc<={mtvec[31:2],2'b0} + ((cause_q[31] && mtvec[0]) ? {25'b0,cause_q[4:0],2'b0} : 32'b0);
                    state<=REDIRECT;
                end
                REDIRECT: state<=IDLE;
                SLEEP: if(wake_pending) begin
                    if(interrupt_pending) begin
                        pc_q<=pc_q+4; cause_q<=interrupt_cause; tval_q<=0; state<=TRAP;
                    end else begin redirect_pc<=pc_q+4; state<=REDIRECT; end
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule

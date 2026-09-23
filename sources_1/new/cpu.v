`timescale 1ns / 1ps
`include "defines.v"

module cpu(
    input  wire        clk,
    input  wire        rst_n,
    output wire [15:0] led,
    output wire        uart_tx,
    input wire irq_external,
    output reg         memory_fault,
    output reg [31:0]  memory_fault_addr
);

    localparam integer IMEM_ADDR_BITS = `IMEM_ADDR_BITS;
    localparam integer IMEM_PAD_BITS  = `CPU_ADDR_BITS - IMEM_ADDR_BITS;

    // ------------------------------------------------------------------------
    // Global control
    // ------------------------------------------------------------------------
    wire hazard_stall;
    wire mem_exception, mem_far_redirect;
    wire sys_stop, sys_busy, sys_flush, sys_redirect, sys_rf_we, sys_retire, trap_enter;
    wire sys_irq_pending;
    wire [31:0] sys_pc, sys_rf_data;
    wire [4:0] sys_rf_rd;
    wire [63:0] time_value, instret_value;
    wire irq_timer, irq_software;
    (* ASYNC_REG = "TRUE" *) reg [1:0] ext_irq_sync;
    always @(posedge clk) if(!rst_n) ext_irq_sync<=0; else ext_irq_sync<={ext_irq_sync[0],irq_external};
    wire pipeline_stall = hazard_stall | sys_stop;
    wire        pipeline_flush;
    wire        ex_mul_busy;
    wire        ex_div_busy;
    wire        execute_hold = ex_mul_busy | ex_div_busy;
    wire        mem_wait;
    wire        mem_fault_now;
    wire        memory_hold = mem_wait | mem_exception;
    wire        pipeline_hold = execute_hold | memory_hold | sys_busy;
    wire        ex_fire;
    wire        mem_retire;
    wire        pipeline_block = pipeline_stall | pipeline_hold;

    // ------------------------------------------------------------------------
    // PREIF
    // ------------------------------------------------------------------------
    wire        preif_valid;
    wire [31:0] preif_pc_addr;

    wire        preif_jtb_hit;
    wire [IMEM_ADDR_BITS-1:0] preif_jtb_target;
    wire        preif_next_jtb_hit;
    wire [IMEM_ADDR_BITS-1:0] preif_next_jtb_target;

    wire        slot0_ctrl_redirect;
    wire        slot1_pred_redirect;
    wire        frontend_redirect_flag;
    wire [IMEM_ADDR_BITS-1:0] frontend_redirect_addr;

    // ------------------------------------------------------------------------
    // IF
    // ------------------------------------------------------------------------
    wire if_valid, id_valid_reg;
    wire [31:0] if_instr;
    wire [31:0] if_instr_addr;
    wire [31:0] if_pre_instr;
    wire [31:0] if_pre_instr_addr;
    wire        if_pre_valid;
    reg         if_pre_valid_q;
    reg         frontend_redirect_kill_q;

    reg         if_jtb_hit;
    reg  [IMEM_ADDR_BITS-1:0] if_jtb_target;
    reg         if_pre_jtb_hit;
    reg  [IMEM_ADDR_BITS-1:0] if_pre_jtb_target;

    wire        if_is_b;
    wire        if_is_call;
    wire        if_is_ret;
    wire [31:0] if_b_imm;
    wire [`BR_PRED_INDEX_BITS-1:0] if_branch_hash;
    wire        if_branch_pred_taken;
    wire        if_branch_hit;
    wire        if_branch_pred_taken_eff;
    wire        if_pred_taken_eff;
    wire [IMEM_ADDR_BITS-1:0] if_pred_target_eff;

    wire        if_pre_is_b;
    wire        if_pre_is_call;
    wire        if_pre_is_ret;
    wire [`BR_PRED_INDEX_BITS-1:0] if_pre_branch_hash;
    wire        if_pre_branch_pred_taken;
    wire        if_pre_branch_hit;
    wire        if_pre_pred_taken_eff;
    wire [IMEM_ADDR_BITS-1:0] if_pre_pred_target_eff;
    wire        id_take_live_if;
    wire        id_take_recovery_if;

    wire        imem_bus_re;
    wire        slot1_capture_en;

    // ------------------------------------------------------------------------
    // ID
    // ------------------------------------------------------------------------
    wire [31:0] id_instr_reg;
    wire [31:0] id_instr_addr_reg;
    wire        id_branch_nohit_reg;
    wire        id_pred_taken_reg;
    wire [IMEM_ADDR_BITS-1:0] id_pred_target_reg;

    wire [31:0] id_instr;
    wire [31:0] id_instr_addr;
    wire        id_branch_nohit;
    wire        id_pred_taken;
    wire [IMEM_ADDR_BITS-1:0] id_pred_target;

    wire        id_regs_re;
    wire        id_regs_we;
    wire [4:0]  id_rs1_addr;
    wire [4:0]  id_rs2_addr;
    wire        id_rs1_used;
    wire        id_rs2_used;
    wire [4:0]  id_regs_w_addr;
    wire [31:0] id_rs1_data;
    wire [31:0] id_rs2_data;
    wire [31:0] id_rs1_data_fwd;
    wire [31:0] id_rs2_data_fwd;

    wire [3:0]  id_alu_op;
    wire [31:0] id_alu_num1;
    wire [31:0] id_alu_num2;

    wire [2:0]  id_mem_op;
    wire        id_dmem_we;
    wire        id_dmem_re;
    wire [31:0] id_dmem_w_data;
    wire        id_mul_op;
    wire        id_mul_signed_a;
    wire        id_mul_signed_b;
    wire        id_mul_preload;
    wire        id_div_op;
    wire        id_div_preload;

    wire        id_branch_flag;
    wire        id_jump_flag;
    wire        id_jalr_flag;
    wire        id_call_flag;
    wire        id_ret_flag;
    wire        id_ctrl_defer;
    wire        id_ctrl_dep_rs1;
    wire        id_ctrl_dep_rs2;
    wire [10:1] id_b_imm_lo;
    wire [`BR_PRED_INDEX_BITS-1:0] id_branch_hash;
    wire [IMEM_ADDR_BITS-1:0] id_branch_jump_addr;

    // ------------------------------------------------------------------------
    // EX
    // ------------------------------------------------------------------------
    wire [31:0] ex_instr_addr;
    wire [`BR_PRED_INDEX_BITS-1:0] ex_branch_hash;
    wire        ex_branch_nohit;
    wire        ex_pred_taken;
    wire [IMEM_ADDR_BITS-1:0] ex_pred_target;

    wire [31:0] ex_alu_num1;
    wire [31:0] ex_alu_num2;
    wire [3:0]  ex_alu_op;

    wire        ex_regs_we;
    wire [4:0]  ex_regs_w_addr;
    wire [31:0] ex_regs_w_data;

    wire        ex_dmem_we;
    wire        ex_dmem_re;
    wire [31:0] ex_dmem_w_data;
    wire [31:0] ex_dmem_wr_addr;
    wire [2:0]  ex_mem_op;

    wire        ex_branch_flag;
    wire        ex_jump_flag;
    wire        ex_jalr_flag;
    wire        ex_call_flag;
    wire        ex_ret_flag;
    wire        ex_ctrl_defer;
    wire        ex_ctrl_dep_rs1;
    wire        ex_ctrl_dep_rs2;
    wire [IMEM_ADDR_BITS-1:0] ex_branch_jump_addr;
    wire [IMEM_ADDR_BITS-1:0] ex_ctrl_pc_low;
    wire [IMEM_ADDR_BITS-1:0] ex_ctrl_pred_target_low;
    wire [IMEM_ADDR_BITS-1:0] ex_ctrl_branch_target_low;
    wire [31:0] ex_ctrl_other_operand;
    wire [11:0] ex_ctrl_jalr_imm12;
    wire        ex_ctrl_both_dep;

    wire        ex_actual_jump_flag;
    wire [IMEM_ADDR_BITS-1:0] ex_actual_jump_addr;
    wire        ex_mispredict;
    wire [IMEM_ADDR_BITS-1:0] ex_redirect_addr;

    // ------------------------------------------------------------------------
    // MEM
    // ------------------------------------------------------------------------
    wire        mem_regs_we;
    wire [4:0]  mem_regs_w_addr;
    wire [31:0] mem_regs_w_data;
    wire [31:0] mem_actual_regs_w_data;
    wire        mem_valid;
    wire [IMEM_ADDR_BITS-1:0] mem_ctrl_pc_low;
    wire        mem_pred_taken;
    wire [IMEM_ADDR_BITS-1:0] mem_ctrl_pred_target_low;
    wire [IMEM_ADDR_BITS-1:0] mem_ctrl_branch_target_low;
    wire [31:0] mem_ctrl_other_operand;
    wire [11:0] mem_ctrl_jalr_imm12;
    wire        mem_ctrl_both_dep;
    wire        mem_branch_flag;
    wire [`BR_PRED_INDEX_BITS-1:0] mem_branch_hash;
    wire        mem_jalr_flag;
    wire        mem_ret_flag;
    wire        mem_ctrl_defer;
    wire        mem_ctrl_dep_rs1;
    wire        mem_ctrl_resolve_en;
    wire        mem_ctrl_actual_jump_flag;
    wire [IMEM_ADDR_BITS-1:0] mem_ctrl_actual_jump_addr_low;
    wire        mem_ctrl_mispredict;
    wire [IMEM_ADDR_BITS-1:0] mem_ctrl_redirect_addr;
    wire        ctrl_resolve_mispredict;
    wire [IMEM_ADDR_BITS-1:0] ctrl_resolve_redirect_addr;
    wire        bp_update_sel_mem;
    wire        bp_update_en;
    wire [31:0] bp_update_pc;
    wire [`BR_PRED_INDEX_BITS-1:0] bp_update_hash;
    wire        bp_update_taken;
    wire        jtb_update_sel_mem;
    wire        jtb_update_en;
    wire [31:0] jtb_update_pc;
    wire [IMEM_ADDR_BITS-1:0] jtb_update_target;
    wire        ras_ex_jump_flag;
    wire        ras_ex_call_flag;
    wire        ras_ex_ret_flag;

    wire        mem_dmem_we;
    wire        mem_dmem_re;
    wire [31:0] mem_dmem_wr_addr;
    wire [31:0] mem_dmem_w_data;
    wire [31:0] mem_dmem_r_data;
    wire [2:0]  mem_mem_op;

    wire        bus_m_stb;
    wire        bus_m_ack;
    wire        bus_m_ready;
    wire        bus_m_err;
    wire [2:0]  bus_mem_op;
    wire        bus_m_we;
    wire [31:0] bus_m_addr;
    wire [31:0] bus_m_dat_i;
    wire [31:0] bus_m_dat_o;

    wire        bus_s0_stb;
    wire        bus_s0_ack;
    wire        bus_s0_we;
    wire [31:0] bus_s0_addr;
    wire [31:0] bus_s0_dat_i;
    wire [31:0] bus_s0_dat_o;

    wire        bus_s1_stb;
    wire        bus_s1_ack;
    wire        bus_s1_we;
    wire [31:0] bus_s1_addr;
    wire [31:0] bus_s1_dat_i;
    wire [31:0] bus_s1_dat_o;

    wire        bus_s2_stb;
    wire        bus_s2_ack;
    wire        bus_s2_we;
    wire [31:0] bus_s2_addr;
    wire [31:0] bus_s2_dat_i;
    wire [31:0] bus_s2_dat_o;

    wire        uart_valid;
    wire [7:0]  uart_data;
    wire        tohost;
    wire        uart_line;
    wire        uart_busy;
    wire        uart_ready;
    wire        uart_overflow;

    // ------------------------------------------------------------------------
    // RAS
    // ------------------------------------------------------------------------
    wire                 ras_valid;
    wire                 ras_slot1_valid_shadow;
    wire [IMEM_ADDR_BITS-1:0] ras_top_target_low;
    wire [IMEM_ADDR_BITS-1:0] ras_slot1_top_target_shadow_low;
    wire                 frontend_issue_ok;
    wire                 slot0_jump_pred_base;

    // ------------------------------------------------------------------------
    // WB
    // ------------------------------------------------------------------------
    wire        wb_regs_we;
    wire        wb_dmem_re;
    wire [4:0]  wb_regs_w_addr;
    wire [31:0] wb_actual_regs_w_data;
    wire        wb_valid;
    wire        id_valid;
    wire        ex_valid;

    // ------------------------------------------------------------------------
    // Frontend control
    // ------------------------------------------------------------------------
    assign if_pre_valid          = if_pre_valid_q;
    assign id_take_recovery_if   = preif_valid && !frontend_redirect_kill_q;
    assign id_take_live_if       = if_pre_valid || id_take_recovery_if;
    assign id_b_imm_lo           = {id_instr[7], id_instr[30:25], id_instr[11:8]};
    assign imem_bus_re           = bus_s0_stb && !bus_s0_we;
    assign slot1_capture_en      = preif_valid && !imem_bus_re;
    assign mem_actual_regs_w_data = mem_dmem_re ? mem_dmem_r_data : mem_regs_w_data;
    assign id_mul_op             = (id_alu_op == `ALU_OP_MUL)
                                || (id_alu_op == `ALU_OP_MULH)
                                || (id_alu_op == `ALU_OP_MULHSU)
                                || (id_alu_op == `ALU_OP_MULHU);
    assign id_mul_signed_a       = (id_alu_op == `ALU_OP_MUL)
                                || (id_alu_op == `ALU_OP_MULH)
                                || (id_alu_op == `ALU_OP_MULHSU);
    assign id_mul_signed_b       = (id_alu_op == `ALU_OP_MUL)
                                || (id_alu_op == `ALU_OP_MULH);
    // Recognize the exact M encoding before bypassing the global legality mux.
    // Do not route the full SYSTEM/illegal-instruction decoder into DSP enables.
    wire id_muldiv_allowed = id_instr[6:0]==7'h33 && id_instr[31:25]==7'h01 &&
                             id_instr_addr[31:IMEM_ADDR_BITS]==0 && id_instr_addr[1:0]==0 &&
                             !hazard_stall && !sys_irq_pending;
    assign id_mul_preload        = id_mul_op && id_muldiv_allowed
                                && !pipeline_flush
                                && !pipeline_hold;
    assign id_div_op             = (id_alu_op == `ALU_OP_DIVREM);
    assign id_div_preload        = id_div_op && id_muldiv_allowed
                                && !pipeline_flush
                                && !pipeline_hold;
    assign ex_ctrl_pc_low          = ex_instr_addr[IMEM_ADDR_BITS-1:0];
    assign ex_ctrl_pred_target_low = ex_pred_target;
    assign ex_ctrl_branch_target_low = ex_branch_jump_addr;
    assign ex_ctrl_other_operand = ex_ctrl_dep_rs1 ? ex_alu_num2 : ex_alu_num1;
    assign ex_ctrl_jalr_imm12    = ex_alu_num2[11:0];
    assign ex_ctrl_both_dep      = ex_ctrl_dep_rs1 && ex_ctrl_dep_rs2;
    assign ctrl_resolve_mispredict = !mem_exception && !mem_far_redirect && !sys_busy &&
                                       (mem_ctrl_mispredict || (ex_fire && ex_mispredict));
    assign ctrl_resolve_redirect_addr = mem_ctrl_mispredict ? mem_ctrl_redirect_addr
                                                            : ex_redirect_addr;
    assign bp_update_sel_mem     = mem_ctrl_resolve_en && mem_branch_flag && !mem_exception;
    assign bp_update_en          = bp_update_sel_mem
                                || (!bp_update_sel_mem
                                 && !mem_ctrl_mispredict
                                 && ex_fire && ex_branch_flag
                                 && !ex_ctrl_defer);
    assign bp_update_pc          = bp_update_sel_mem ? {{IMEM_PAD_BITS{1'b0}}, mem_ctrl_pc_low} : ex_instr_addr;
    assign bp_update_hash        = bp_update_sel_mem ? mem_branch_hash : ex_branch_hash;
    assign bp_update_taken       = bp_update_sel_mem ? mem_ctrl_actual_jump_flag
                                                     : ex_actual_jump_flag;
    assign jtb_update_sel_mem    = mem_ctrl_resolve_en && mem_jalr_flag && !mem_ret_flag && !mem_exception;
    assign jtb_update_en         = jtb_update_sel_mem
                                || (!jtb_update_sel_mem
                                 && !mem_ctrl_mispredict
                                 && ex_fire && ex_jalr_flag
                                 && !ex_ret_flag
                                 && !ex_ctrl_defer);
    assign jtb_update_pc         = jtb_update_sel_mem ? {{IMEM_PAD_BITS{1'b0}}, mem_ctrl_pc_low} : ex_instr_addr;
    assign jtb_update_target     = jtb_update_sel_mem ? mem_ctrl_actual_jump_addr_low
                                                      : ex_actual_jump_addr;
    assign ras_ex_jump_flag      = ex_fire && ex_jump_flag && !ex_ctrl_defer && !mem_ctrl_mispredict;
    assign ras_ex_call_flag      = ex_fire && ex_call_flag && !ex_ctrl_defer && !mem_ctrl_mispredict;
    assign ras_ex_ret_flag       = ex_fire && ex_ret_flag && !ex_ctrl_defer && !mem_ctrl_mispredict;

    frontend_ctrl u_frontend_ctrl (
        .if_instr                     (if_instr                     ),
        .if_instr_addr                (if_instr_addr                ),
        .if_jtb_hit                   (if_jtb_hit                   ),
        .if_jtb_target                (if_jtb_target                ),
        .if_branch_hit                (if_branch_hit                ),
        .if_branch_pred_taken         (if_branch_pred_taken         ),
        .if_pre_instr                 (if_pre_instr                 ),
        .if_pre_instr_addr            (if_pre_instr_addr            ),
        .if_pre_jtb_hit               (if_pre_jtb_hit               ),
        .if_pre_jtb_target            (if_pre_jtb_target            ),
        .if_pre_branch_hit            (if_pre_branch_hit            ),
        .if_pre_branch_pred_taken     (if_pre_branch_pred_taken     ),
        .if_pre_valid                 (if_pre_valid                 ),
        .ras_valid                    (ras_valid                    ),
        .ras_top_target_low           (ras_top_target_low           ),
        .ras_slot1_valid_shadow       (ras_slot1_valid_shadow       ),
        .ras_slot1_top_target_shadow_low(ras_slot1_top_target_shadow_low),
        .pipeline_block_if            (pipeline_block               ),
        .frontend_redirect_kill_q     (frontend_redirect_kill_q     ),
        .ex_mispredict                (ctrl_resolve_mispredict      ),
        .ex_redirect_addr             (ctrl_resolve_redirect_addr   ),
        .if_is_b                      (if_is_b                      ),
        .if_is_call                   (if_is_call                   ),
        .if_is_ret                    (if_is_ret                    ),
        .if_b_imm                     (if_b_imm                     ),
        .if_branch_hash               (if_branch_hash               ),
        .if_branch_pred_taken_eff     (if_branch_pred_taken_eff     ),
        .if_pred_taken_eff            (if_pred_taken_eff            ),
        .if_pred_target_eff           (if_pred_target_eff           ),
        .if_pre_is_b                  (if_pre_is_b                  ),
        .if_pre_is_call               (if_pre_is_call               ),
        .if_pre_is_ret                (if_pre_is_ret                ),
        .if_pre_branch_hash           (if_pre_branch_hash           ),
        .if_pre_pred_taken_eff        (if_pre_pred_taken_eff        ),
        .if_pre_pred_target_eff       (if_pre_pred_target_eff       ),
        .frontend_issue_ok            (frontend_issue_ok            ),
        .slot0_jump_pred_base         (slot0_jump_pred_base         ),
        .slot0_ctrl_redirect          (slot0_ctrl_redirect          ),
        .slot1_pred_redirect          (slot1_pred_redirect          ),
        .frontend_redirect_flag       (frontend_redirect_flag       ),
        .frontend_redirect_addr       (frontend_redirect_addr       )
    );

    branch_hash_mix u_id_branch_hash (
        .pc_value      (id_instr_addr),
        .imm_lo_value  (id_b_imm_lo  ),
        .hash_value    (id_branch_hash)
    );

    branch_predictor u_branch_predictor (
        .clk         (clk               ),
        .rst_n       (rst_n             ),
        .lookup_is_branch0(if_is_b          ),
        .lookup_pc0  (if_instr_addr         ),
        .lookup_hash0(if_branch_hash        ),
        .pred_taken0 (if_branch_pred_taken  ),
        .branch_hit0 (if_branch_hit         ),
        .lookup_is_branch1(if_pre_is_b          ),
        .lookup_pc1  (if_pre_instr_addr       ),
        .lookup_hash1(if_pre_branch_hash      ),
        .pred_taken1 (if_pre_branch_pred_taken),
        .branch_hit1 (if_pre_branch_hit       ),
        .update_en   (bp_update_en          ),
        .update_pc   (bp_update_pc          ),
        .update_hash (bp_update_hash        ),
        .update_taken(bp_update_taken       )
    );

    jump_target_buffer u_jump_target_buffer (
        .clk         (clk               ),
        .rst_n       (rst_n             ),
        .lookup_pc0  (preif_pc_addr     ),
        .hit0        (preif_jtb_hit     ),
        .target0     (preif_jtb_target  ),
        .lookup_pc1  (preif_pc_addr + 32'd4),
        .hit1        (preif_next_jtb_hit   ),
        .target1     (preif_next_jtb_target),
        .update_en   (jtb_update_en     ),
        .update_pc   (jtb_update_pc     ),
        .update_target(jtb_update_target)
    );

    ras u_ras (
        .clk                         (clk                            ),
        .rst_n                       (rst_n                          ),
        .slot0_jump_pred_base        (slot0_jump_pred_base           ),
        .if_is_call                  (if_is_call                     ),
        .if_is_ret                   (if_is_ret                      ),
        .if_instr_addr               (if_instr_addr                  ),
        .ras_valid                   (ras_valid                      ),
        .ras_top_target_low          (ras_top_target_low             ),
        .slot1_valid_shadow          (ras_slot1_valid_shadow         ),
        .slot1_top_target_shadow_low (ras_slot1_top_target_shadow_low),
        .ex_jump_flag                (ras_ex_jump_flag               ),
        .ex_call_flag                (ras_ex_call_flag               ),
        .ex_ret_flag                 (ras_ex_ret_flag                ),
        .ex_instr_addr               (ex_instr_addr                  )
    );

    // ------------------------------------------------------------------------
    // PREIF
    // ------------------------------------------------------------------------
    pc u_pc(
        .clk            (clk                  ),
        .rst_n          (rst_n                ),
        .system_redirect(sys_redirect),
        .system_pc(sys_pc),
        .redirect_flag  (frontend_redirect_flag),
        .redirect_force (ctrl_resolve_mispredict),
        .redirect_addr  (frontend_redirect_addr),
        .preif_ready    (!imem_bus_re         ),
        .pipeline_stall (pipeline_block       ),
        .pc_o           (preif_pc_addr        ),
        .preif_valid_o  (preif_valid          )
    );

    imem u_imem(
        .clk                (clk               ),
        .rst_n              (rst_n             ),
        .pipeline_stall     (pipeline_block    ),
        .pipeline_flush     (pipeline_flush    ),
        .preif_pc_addr_i    (preif_pc_addr     ),
        .if_valid_o(if_valid),
        .if_instr_o         (if_instr          ),
        .if_instr_addr_o    (if_instr_addr     ),
        .preif_valid_i      (preif_valid       ),
        .if_pre_instr_o     (if_pre_instr      ),
        .if_pre_instr_addr_o(if_pre_instr_addr ),

        .bus_stb            (bus_s0_stb        ),
        .bus_ack            (bus_s0_ack        ),
        .r_addr             (bus_s0_addr       ),
        .bus_we             (bus_s0_we         ),
        .mem_op             (bus_mem_op        ),
        .r_data             (bus_s0_dat_i      )
    );

    always @(posedge clk) begin
        if (rst_n == `RST_ENABLE) begin
            frontend_redirect_kill_q <= 1'b0;
        end else if (pipeline_flush || slot0_ctrl_redirect || slot1_pred_redirect) begin
            frontend_redirect_kill_q <= 1'b1;
        end else if (!pipeline_block) begin
            frontend_redirect_kill_q <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst_n == `RST_ENABLE) begin
            if_pre_valid_q    <= 1'b0;
            if_jtb_hit        <= 1'b0;
            if_jtb_target     <= {IMEM_ADDR_BITS{1'b0}};
            if_pre_jtb_hit    <= 1'b0;
            if_pre_jtb_target <= {IMEM_ADDR_BITS{1'b0}};
        end else begin
            if (slot0_ctrl_redirect || slot1_pred_redirect || pipeline_flush) begin
                if_pre_valid_q <= 1'b0;
                if_jtb_hit     <= 1'b0;
                if_pre_jtb_hit <= 1'b0;
            end else if (!pipeline_block) begin
                if_pre_valid_q <= slot1_capture_en;
                if_jtb_hit     <= preif_jtb_hit;
                if_pre_jtb_hit <= preif_next_jtb_hit;
            end

            if (!pipeline_block) begin
                if_jtb_target     <= preif_jtb_target;
                if_pre_jtb_target <= preif_next_jtb_target;
            end
        end
    end

    if_id u_if_id(
        .clk             (clk             ),
        .rst_n           (rst_n           ),
        .pipeline_stall  (pipeline_stall  ),
        .pipeline_hold   (pipeline_hold   ),
        .pipeline_flush  (pipeline_flush  ),
        .frontend_kill   (frontend_redirect_kill_q),
        .slot0_drop_buf  (if_pre_valid && slot0_ctrl_redirect),
        .if_valid_i(if_valid),
        .id_valid_o(id_valid_reg),
        .if_instr_i      (if_instr        ),
        .if_instr_addr_i (if_instr_addr   ),
        .if_branch_nohit_i(if_is_b && !if_branch_hit),
        .if_pred_taken_i (if_pred_taken_eff),
        .if_pred_target_i(if_pred_target_eff),
        .if_pre_instr_i  (if_pre_instr    ),
        .if_pre_instr_addr_i(if_pre_instr_addr),
        .if_pre_pred_taken_i (if_pre_pred_taken_eff),
        .if_pre_pred_target_i(if_pre_pred_target_eff),
        .if_pre_valid_i  (if_pre_valid    ),
        .id_instr_o      (id_instr_reg        ),
        .id_instr_addr_o (id_instr_addr_reg   ),
        .id_branch_nohit_o(id_branch_nohit_reg),
        .id_pred_taken_o (id_pred_taken_reg   ),
        .id_pred_target_o(id_pred_target_reg  )
    );

    // ------------------------------------------------------------------------
    // ID
    // ------------------------------------------------------------------------
    assign id_instr       = id_take_live_if ? if_instr          : id_instr_reg;
    assign id_instr_addr  = id_take_live_if ? if_instr_addr     : id_instr_addr_reg;
    assign id_branch_nohit= id_take_live_if ? (if_is_b && !if_branch_hit) : id_branch_nohit_reg;
    assign id_pred_taken  = id_take_live_if ? if_pred_taken_eff : id_pred_taken_reg;
    assign id_pred_target = id_take_live_if ? if_pred_target_eff: id_pred_target_reg;
    assign id_valid       = id_take_live_if ? if_valid : id_valid_reg;

    id u_id(
        .clk                (clk                ),
        .rst_n              (rst_n              ),
        .id_instr_addr      (id_instr_addr      ),
        .id_instr           (id_instr           ),
        .id_regs_re         (id_regs_re         ),
        .id_rs1_addr        (id_rs1_addr        ),
        .id_rs2_addr        (id_rs2_addr        ),
        .id_rs1_used        (id_rs1_used        ),
        .id_rs2_used        (id_rs2_used        ),
        .id_rs1_data        (id_rs1_data_fwd    ),
        .id_rs2_data        (id_rs2_data_fwd    ),
        .id_rd_addr         (id_regs_w_addr     ),
        .id_regs_we         (id_regs_we         ),
        .id_alu_op          (id_alu_op          ),
        .id_alu_num1        (id_alu_num1        ),
        .id_alu_num2        (id_alu_num2        ),
        .id_mem_op          (id_mem_op          ),
        .id_dmem_we         (id_dmem_we         ),
        .id_dmem_re         (id_dmem_re         ),
        .id_dmem_w_data     (id_dmem_w_data     ),
        .id_branch_flag     (id_branch_flag     ),
        .id_branch_jump_addr(id_branch_jump_addr),
        .id_jump_flag       (id_jump_flag       ),
        .id_jalr_flag       (id_jalr_flag       ),
        .id_call_flag       (id_call_flag       ),
        .id_ret_flag        (id_ret_flag        )
    );

    ctrl_late_detect u_ctrl_late_detect(
        .id_branch_flag (id_branch_flag ),
        .id_jalr_flag   (id_jalr_flag   ),
        .id_rs1_addr    (id_rs1_addr    ),
        .id_rs2_addr    (id_rs2_addr    ),
        .id_rs1_used    (id_rs1_used    ),
        .id_rs2_used    (id_rs2_used    ),
        .ex_dmem_re     (ex_dmem_re     ),
        .ex_regs_w_addr (ex_regs_w_addr ),
        .id_ctrl_defer  (id_ctrl_defer  ),
        .id_ctrl_dep_rs1(id_ctrl_dep_rs1),
        .id_ctrl_dep_rs2(id_ctrl_dep_rs2),
        .pipeline_stall (hazard_stall )
    );

    // ------------------------------------------------------------------------
    // ID_EX
    // ------------------------------------------------------------------------
    id_ex u_id_ex(
        .clk                 (clk                 ),
        .rst_n               (rst_n               ),
        .pipeline_stall      (pipeline_stall      ),
        .pipeline_hold       (pipeline_hold       ),
        .pipeline_flush      (pipeline_flush      ),
        .id_valid            (id_valid            ),

        .id_instr_addr       (id_instr_addr       ),
        .id_branch_nohit     (id_branch_nohit     ),
        .id_pred_taken       (id_pred_taken       ),
        .id_pred_target      (id_pred_target      ),
        .id_alu_num1         (id_alu_num1         ),
        .id_alu_num2         (id_alu_num2         ),
        .id_alu_op           (id_alu_op           ),
        .id_regs_w_addr      (id_regs_w_addr      ),
        .id_regs_we          (id_regs_we          ),
        .id_mem_op           (id_mem_op           ),
        .id_dmem_we          (id_dmem_we          ),
        .id_dmem_re          (id_dmem_re          ),
        .id_dmem_w_data      (id_dmem_w_data      ),
        .id_branch_flag      (id_branch_flag      ),
        .id_branch_jump_addr (id_branch_jump_addr ),
        .id_branch_hash      (id_branch_hash      ),
        .id_jump_flag        (id_jump_flag        ),
        .id_jalr_flag        (id_jalr_flag        ),
        .id_call_flag        (id_call_flag        ),
        .id_ret_flag         (id_ret_flag         ),
        .id_ctrl_defer       (id_ctrl_defer       ),
        .id_ctrl_dep_rs1     (id_ctrl_dep_rs1     ),
        .id_ctrl_dep_rs2     (id_ctrl_dep_rs2     ),

        .ex_instr_addr       (ex_instr_addr       ),
        .ex_branch_nohit     (ex_branch_nohit     ),
        .ex_pred_taken       (ex_pred_taken       ),
        .ex_pred_target      (ex_pred_target      ),
        .ex_alu_num1         (ex_alu_num1         ),
        .ex_alu_num2         (ex_alu_num2         ),
        .ex_alu_op           (ex_alu_op           ),
        .ex_regs_w_addr      (ex_regs_w_addr      ),
        .ex_regs_we          (ex_regs_we          ),
        .ex_mem_op           (ex_mem_op           ),
        .ex_dmem_we          (ex_dmem_we          ),
        .ex_dmem_re          (ex_dmem_re          ),
        .ex_dmem_w_data      (ex_dmem_w_data      ),
        .ex_branch_flag      (ex_branch_flag      ),
        .ex_branch_jump_addr (ex_branch_jump_addr ),
        .ex_branch_hash      (ex_branch_hash      ),
        .ex_valid            (ex_valid            ),
        .ex_jump_flag        (ex_jump_flag        ),
        .ex_jalr_flag        (ex_jalr_flag        ),
        .ex_call_flag        (ex_call_flag        ),
        .ex_ret_flag         (ex_ret_flag         ),
        .ex_ctrl_defer       (ex_ctrl_defer       ),
        .ex_ctrl_dep_rs1     (ex_ctrl_dep_rs1     ),
        .ex_ctrl_dep_rs2     (ex_ctrl_dep_rs2     )
    );

    // ------------------------------------------------------------------------
    // EX
    // ------------------------------------------------------------------------
    assign pipeline_flush = ctrl_resolve_mispredict | sys_flush;

    ex u_ex(
        .mul_preload           (id_mul_preload         ),
        .mul_preload_signed_a  (id_mul_signed_a        ),
        .mul_preload_signed_b  (id_mul_signed_b        ),
        .mul_preload_op_a      (id_alu_num1            ),
        .mul_preload_op_b      (id_alu_num2            ),
        .div_preload           (id_div_preload         ),
        .div_preload_op        (id_mem_op[1:0]         ),
        .div_preload_op_a      (id_alu_num1            ),
        .div_preload_op_b      (id_alu_num2            ),
        .clk                   (clk                   ),
        .rst_n                 (rst_n                 ),
        .ex_instr_addr         (ex_instr_addr         ),
        .ex_pred_taken         (ex_pred_taken         ),
        .ex_pred_target        (ex_pred_target        ),
        .ex_alu_num1           (ex_alu_num1           ),
        .ex_alu_num2           (ex_alu_num2           ),
        .ex_alu_op             (ex_alu_op             ),
        .ex_mem_op             (ex_mem_op             ),
        .ex_branch_flag        (ex_branch_flag        ),
        .ex_branch_jump_addr   (ex_branch_jump_addr   ),
        .ex_jump_flag          (ex_jump_flag          ),
        .ex_ctrl_defer         (ex_ctrl_defer         ),
        .ex_regs_w_data        (ex_regs_w_data        ),
        .ex_dmem_wr_addr       (ex_dmem_wr_addr       ),
        .ex_actual_jump_flag   (ex_actual_jump_flag   ),
        .ex_actual_jump_addr   (ex_actual_jump_addr   ),
        .ex_mispredict         (ex_mispredict         ),
        .ex_redirect_addr      (ex_redirect_addr      ),
        .ex_mul_busy           (ex_mul_busy           ),
        .ex_div_busy           (ex_div_busy           )
    );

    // ------------------------------------------------------------------------
    // EX_MEM
    // ------------------------------------------------------------------------
    ex_mem u_ex_mem(
        .clk                    (clk                    ),
        .rst_n                  (rst_n                  ),
        .pipeline_hold          (execute_hold           ),
        .memory_hold            (memory_hold | sys_busy),
        .older_flush            (mem_ctrl_mispredict | sys_flush),
        .ex_valid               (ex_valid               ),
        .ex_regs_we             (ex_regs_we             ),
        .ex_regs_w_addr         (ex_regs_w_addr         ),
        .ex_regs_w_data         (ex_regs_w_data         ),
        .ex_dmem_wr_addr        (ex_dmem_wr_addr        ),
        .ex_dmem_w_data         (ex_dmem_w_data         ),
        .ex_dmem_we             (ex_dmem_we             ),
        .ex_dmem_re             (ex_dmem_re             ),
        .ex_mem_op              (ex_mem_op              ),
        .ex_ctrl_pc_low         (ex_ctrl_pc_low         ),
        .ex_pred_taken          (ex_pred_taken          ),
        .ex_ctrl_pred_target_low(ex_ctrl_pred_target_low),
        .ex_ctrl_branch_target_low(ex_ctrl_branch_target_low),
        .ex_ctrl_other_operand  (ex_ctrl_other_operand  ),
        .ex_ctrl_jalr_imm12     (ex_ctrl_jalr_imm12     ),
        .ex_ctrl_both_dep       (ex_ctrl_both_dep       ),
        .ex_branch_flag         (ex_branch_flag         ),
        .ex_branch_hash         (ex_branch_hash         ),
        .ex_jalr_flag           (ex_jalr_flag           ),
        .ex_ret_flag            (ex_ret_flag            ),
        .ex_ctrl_defer          (ex_ctrl_defer          ),
        .ex_ctrl_dep_rs1        (ex_ctrl_dep_rs1        ),

        .mem_regs_we            (mem_regs_we            ),
        .mem_regs_w_addr        (mem_regs_w_addr        ),
        .mem_regs_w_data        (mem_regs_w_data        ),
        .mem_dmem_wr_addr       (mem_dmem_wr_addr       ),
        .mem_dmem_w_data        (mem_dmem_w_data        ),
        .mem_dmem_we            (mem_dmem_we            ),
        .mem_dmem_re            (mem_dmem_re            ),
        .mem_mem_op             (mem_mem_op             ),
        .mem_ctrl_pc_low        (mem_ctrl_pc_low        ),
        .mem_pred_taken         (mem_pred_taken         ),
        .mem_ctrl_pred_target_low(mem_ctrl_pred_target_low),
        .mem_ctrl_branch_target_low(mem_ctrl_branch_target_low),
        .mem_ctrl_other_operand (mem_ctrl_other_operand ),
        .mem_ctrl_jalr_imm12    (mem_ctrl_jalr_imm12    ),
        .mem_ctrl_both_dep      (mem_ctrl_both_dep      ),
        .mem_branch_flag        (mem_branch_flag        ),
        .mem_branch_hash        (mem_branch_hash        ),
        .mem_valid              (mem_valid              ),
        .mem_jalr_flag          (mem_jalr_flag          ),
        .mem_ret_flag           (mem_ret_flag           ),
        .mem_ctrl_defer         (mem_ctrl_defer         ),
        .mem_ctrl_dep_rs1       (mem_ctrl_dep_rs1       )
    );

    // ------------------------------------------------------------------------
    // MEM
    // ------------------------------------------------------------------------

    mem_ctrl_resolve u_mem_ctrl_resolve(
        .mem_ctrl_defer        (mem_ctrl_defer        ),
        .mem_ctrl_dep_rs1      (mem_ctrl_dep_rs1      ),
        .mem_ctrl_both_dep     (mem_ctrl_both_dep     ),
        .mem_branch_flag       (mem_branch_flag       ),
        .mem_jalr_flag         (mem_jalr_flag         ),
        .mem_mem_op            (mem_mem_op            ),
        .mem_ctrl_pc_low       (mem_ctrl_pc_low       ),
        .mem_pred_taken        (mem_pred_taken        ),
        .mem_ctrl_pred_target_low(mem_ctrl_pred_target_low),
        .mem_ctrl_branch_target_low(mem_ctrl_branch_target_low),
        .mem_ctrl_other_operand(mem_ctrl_other_operand),
        .mem_ctrl_jalr_imm12   (mem_ctrl_jalr_imm12   ),
        .wb_late_data          (wb_actual_regs_w_data ),
        .mem_ctrl_resolve_en   (mem_ctrl_resolve_en   ),
        .mem_ctrl_actual_jump_flag(mem_ctrl_actual_jump_flag),
        .mem_ctrl_actual_jump_addr_low(mem_ctrl_actual_jump_addr_low),
        .mem_ctrl_mispredict   (mem_ctrl_mispredict   ),
        .mem_ctrl_redirect_addr(mem_ctrl_redirect_addr)
    );

    // Access starts in EX, but its response belongs to the following MEM slot.
    // While waiting, retain MEM and EX; never reissue EX or retire invalid data.
    wire mem_access = mem_valid && (mem_dmem_re || mem_dmem_we);
    assign mem_wait = mem_access && !bus_m_ack;
    assign mem_fault_now = mem_access && bus_m_ack && bus_m_err;
    assign mem_retire = mem_valid && !memory_hold && !sys_busy;
    assign ex_fire = ex_valid && !pipeline_hold && !mem_ctrl_mispredict && !mem_far_redirect;
    assign bus_m_stb = rst_n && ex_fire && (ex_dmem_we || ex_dmem_re);
    always @(posedge clk) begin
        if (!rst_n) begin memory_fault<=0; memory_fault_addr<=0; end
        else begin
            memory_fault<=mem_fault_now;
            if(mem_fault_now) memory_fault_addr<=mem_dmem_wr_addr;
        end
    end
    assign bus_m_we = ex_dmem_we && !mem_ctrl_mispredict;
    assign bus_m_dat_i = ex_dmem_w_data;
    assign bus_m_addr = ex_dmem_wr_addr;
    assign mem_dmem_r_data = bus_m_dat_o;

    bus_interconnect u_bus_interconnect(
        .clk          (clk          ),
        .rst_n        (rst_n        ),
        .bus_m_stb    (bus_m_stb    ),
        .bus_m_ack    (bus_m_ack    ),
        .bus_m_ready  (bus_m_ready  ),
        .bus_m_err    (bus_m_err    ),
        .bus_m_op     (ex_mem_op    ),
        .bus_mem_op   (bus_mem_op   ),
        .bus_m_we     (bus_m_we     ),
        .bus_m_addr   (bus_m_addr   ),
        .bus_m_dat_i  (bus_m_dat_i  ),
        .bus_m_dat_o  (bus_m_dat_o  ),

        .bus_s0_stb   (bus_s0_stb   ),
        .bus_s0_ack   (bus_s0_ack   ),
        .bus_s0_we    (bus_s0_we    ),
        .bus_s0_addr  (bus_s0_addr  ),
        .bus_s0_dat_i (bus_s0_dat_i ),
        .bus_s0_dat_o (bus_s0_dat_o ),

        .bus_s1_stb   (bus_s1_stb   ),
        .bus_s1_ack   (bus_s1_ack   ),
        .bus_s1_we    (bus_s1_we    ),
        .bus_s1_addr  (bus_s1_addr  ),
        .bus_s1_dat_i (bus_s1_dat_i ),
        .bus_s1_dat_o (bus_s1_dat_o ),

        .bus_s2_stb   (bus_s2_stb   ),
        .bus_s2_ack   (bus_s2_ack   ),
        .bus_s2_we    (bus_s2_we    ),
        .bus_s2_addr  (bus_s2_addr  ),
        .bus_s2_dat_i (bus_s2_dat_i ),
        .bus_s2_dat_o (bus_s2_dat_o )
    );

    dmem u_dmem(
        .clk     (clk            ),
        .rst_n   (rst_n          ),
        .bus_stb (bus_s1_stb     ),
        .bus_ack (bus_s1_ack     ),
        .w_data  (bus_s1_dat_o   ),
        .wr_addr (bus_s1_addr    ),
        .bus_we  (bus_s1_we      ),
        .mem_op  (bus_mem_op     ),
        .r_data  (bus_s1_dat_i   )
    );

    mmio u_mmio(
        .time_value(time_value),.instret_value(instret_value),.irq_timer(irq_timer),.irq_software(irq_software),
        .clk        (clk            ),
        .rst_n      (rst_n          ),
        .bus_stb    (bus_s2_stb     ),
        .bus_ack    (bus_s2_ack     ),
        .bus_we     (bus_s2_we      ),
        .bus_addr   (bus_s2_addr    ),
        .w_data     (bus_s2_dat_o   ),
        .r_data     (bus_s2_dat_i   ),
        .led        (led            ),
        .uart_valid (uart_valid     ),
        .uart_data  (uart_data      ),
        .tohost     (tohost         ),
        .uart_busy  (uart_busy      ),
        .uart_ready (uart_ready     ),
        .uart_overflow (uart_overflow)
    );

    uart_tx u_uart_tx (
        .clk       (clk          ),
        .rst_n     (rst_n        ),
        .tx_valid  (uart_valid   ),
        .tx_data   (uart_data    ),
        .tx_busy   (uart_busy    ),
        .tx_ready  (uart_ready   ),
        .tx        (uart_line    ),
        .overflow  (uart_overflow)
    );

    assign uart_tx = uart_line;

    // ------------------------------------------------------------------------
    // WB
    // ------------------------------------------------------------------------
    mem_wb u_mem_wb(
        .clk             (clk             ),
        .rst_n           (rst_n           ),
        .mem_valid       (mem_retire      ),
        .mem_dmem_re     (mem_dmem_re     ),
        .mem_regs_we     (mem_regs_we && mem_retire),
        .mem_regs_w_addr (mem_regs_w_addr ),
        .mem_regs_w_data (mem_actual_regs_w_data),
        .wb_valid        (wb_valid        ),
        .wb_dmem_re      (wb_dmem_re      ),
        .wb_regs_we      (wb_regs_we      ),
        .wb_regs_w_addr  (wb_regs_w_addr  ),
        .wb_regs_w_data  (wb_actual_regs_w_data)
    );

    // ------------------------------------------------------------------------
    // REGS
    // ------------------------------------------------------------------------
    regs u_regs(
        .clk      (clk                   ),
        .rst_n    (rst_n                 ),
        .re       (id_regs_re            ),
        .rs1_addr (id_rs1_addr           ),
        .rs2_addr (id_rs2_addr           ),
        .rs1_data (id_rs1_data           ),
        .rs2_data (id_rs2_data           ),
        .we       (wb_regs_we | sys_rf_we),
        .w_addr   (sys_rf_we ? sys_rf_rd : wb_regs_w_addr),
        .w_data   (sys_rf_we ? sys_rf_data : wb_actual_regs_w_data)
    );

    //Forwarding Unit
    forwarding u_forwarding(
        .id_rs1_addr           (id_rs1_addr           ),
        .id_rs2_addr           (id_rs2_addr           ),
        .id_rs1_data           (id_rs1_data           ),
        .id_rs2_data           (id_rs2_data           ),

        .ex_regs_we            (ex_regs_we            ),
        .ex_regs_w_addr        (ex_regs_w_addr        ),
        .ex_regs_w_data        (ex_regs_w_data        ),

        .mem_regs_we           (mem_regs_we && mem_retire),
        .mem_regs_w_addr       (mem_regs_w_addr       ),
        .mem_regs_w_data       (mem_actual_regs_w_data),

        .wb_regs_we            (wb_regs_we            ),
        .wb_regs_w_addr        (wb_regs_w_addr        ),
        .wb_actual_regs_w_data (wb_actual_regs_w_data ),

        .id_rs1_data_fwd       (id_rs1_data_fwd       ),
        .id_rs2_data_fwd       (id_rs2_data_fwd       )
    );


    // Full architectural metadata stays beside the narrow prediction datapath.
    reg [31:0] ex_branch_full, mem_pc_full, mem_target_q;
    reg mem_taken_q;
    wire [31:0] id_branch_imm = {{19{id_instr[31]}},id_instr[31],id_instr[7],id_instr[30:25],id_instr[11:8],1'b0};
    always @(posedge clk) begin
        if(!pipeline_hold && !pipeline_stall) begin
            ex_branch_full<=id_instr_addr+id_branch_imm;
        end
        if(!execute_hold && !memory_hold && !sys_busy) begin
            mem_pc_full<=ex_instr_addr;
            mem_target_q<=ex_jump_flag ? {ex_dmem_wr_addr[31:1],1'b0} : ex_branch_full;
            mem_taken_q<=ex_actual_jump_flag;
        end
    end
    wire [31:0] late_target_sum = wb_actual_regs_w_data + {{20{mem_ctrl_jalr_imm12[11]}},mem_ctrl_jalr_imm12};
    wire [31:0] mem_full_target = mem_ctrl_defer && mem_jalr_flag ? {late_target_sum[31:1],1'b0} : mem_target_q;
    wire mem_taken = mem_ctrl_defer ? mem_ctrl_actual_jump_flag : mem_taken_q;
    wire mem_control = mem_valid && (mem_branch_flag || mem_jalr_flag || mem_taken_q);
    wire mem_target_bad = mem_control && mem_taken && mem_full_target[1];
    assign mem_far_redirect = mem_control && mem_taken && !mem_target_bad && (|mem_full_target[31:IMEM_ADDR_BITS]);
    assign mem_exception = mem_fault_now || mem_target_bad;
    wire data_misaligned = mem_mem_op[1:0]==1 ? mem_dmem_wr_addr[0] :
                           mem_mem_op[1:0]==2 ? |mem_dmem_wr_addr[1:0] : 1'b0;
    wire [31:0] mem_exception_cause = mem_target_bad ? 0 :
                                    mem_dmem_we ? (data_misaligned ? 6 : 7) : (data_misaligned ? 4 : 5);
    privileged u_privileged(
        .clk(clk),.rst_n(rst_n),.id_valid(id_valid),.id_instr(id_instr),.id_pc(id_instr_addr),.id_rs1(id_rs1_data_fwd),
        .older_empty(!ex_valid && !mem_valid && !wb_valid),.older_redirect(ctrl_resolve_mispredict),
        .mem_exception(mem_exception),.mem_cause(mem_exception_cause),.mem_pc(mem_pc_full),
        .mem_tval(mem_target_bad ? mem_full_target : mem_dmem_wr_addr),
        .mem_far_redirect(mem_far_redirect),.mem_target(mem_full_target),
        .retire(wb_valid),.time_value(time_value),.irq_timer(irq_timer),.irq_software(irq_software),.irq_external(ext_irq_sync[1]),
        .id_stop(sys_stop),.busy(sys_busy),.flush(sys_flush),.interrupt_request(sys_irq_pending),.redirect(sys_redirect),.redirect_pc(sys_pc),
        .rf_we(sys_rf_we),.rf_rd(sys_rf_rd),.rf_data(sys_rf_data),.system_retire(sys_retire),.trap_enter(trap_enter),
        .instret_value(instret_value)
    );

endmodule

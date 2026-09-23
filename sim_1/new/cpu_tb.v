`timescale 1ns / 1ps
`include "../../sources_1/new/defines.v"

module cpu_tb;

    localparam time TB_TIMEOUT_NS = 60_000_000_000;
    localparam integer BENCH_TIMER_GAP_CYCLES = 16;
    localparam integer BENCH_MIN_WINDOW_CYCLES = 1000;

    reg  clk;
    reg  rst_n;
    wire [15:0] led;
    reg         bench_pending_start;
    reg         bench_active;
    reg         bench_done;
    integer     bench_gap_count;
    reg [63:0]  bench_cycles;
    reg [63:0]  bench_retired;
    reg [63:0]  bench_ipc_x1000;
    reg [63:0]  pred_b_total;
    reg [63:0]  pred_b_dir_ok;
    reg [63:0]  pred_b_tgt_check;
    reg [63:0]  pred_b_tgt_ok;
    reg [63:0]  pred_b_ok;
    reg [63:0]  pred_jal_total;
    reg [63:0]  pred_jal_dir_ok;
    reg [63:0]  pred_jal_tgt_check;
    reg [63:0]  pred_jal_tgt_ok;
    reg [63:0]  pred_jal_ok;
    reg [63:0]  pred_jalr_total;
    reg [63:0]  pred_jalr_dir_ok;
    reg [63:0]  pred_jalr_tgt_check;
    reg [63:0]  pred_jalr_tgt_ok;
    reg [63:0]  pred_jalr_ok;
    reg         mem_ctrl_seen;
    reg [`IMEM_ADDR_BITS-1:0] mem_ctrl_seen_pc;
    reg         mem_ctrl_seen_b;
    reg         mem_ctrl_seen_jalr;

    wire timer_read_fire = u_cpu.ex_fire && u_cpu.ex_dmem_re
                        && ((u_cpu.ex_dmem_wr_addr == `MMIO_TIMER_LO_ADDR)
                         || (u_cpu.ex_dmem_wr_addr == `MMIO_TIMER_HI_ADDR));
    wire retire_fire = u_cpu.wb_valid || u_cpu.sys_retire;
    wire bench_ex_ctrl_fire = bench_active
                            && !u_cpu.pipeline_hold
                            && !u_cpu.mem_ctrl_mispredict
                            && u_cpu.ex_valid
                            && !u_cpu.ex_ctrl_defer
                            && (u_cpu.ex_branch_flag || u_cpu.ex_jump_flag);
    wire bench_ex_b_fire = bench_ex_ctrl_fire
                         && u_cpu.ex_branch_flag;
    wire bench_ex_jal_fire = bench_ex_ctrl_fire
                          && u_cpu.ex_jump_flag
                          && !u_cpu.ex_jalr_flag
                          && !u_cpu.ex_branch_flag;
    wire bench_ex_jalr_fire = bench_ex_ctrl_fire
                           && u_cpu.ex_jalr_flag;
    wire mem_ctrl_same_seen = mem_ctrl_seen
                           && (mem_ctrl_seen_pc == u_cpu.mem_ctrl_pc_low)
                           && (mem_ctrl_seen_b == u_cpu.mem_branch_flag)
                           && (mem_ctrl_seen_jalr == u_cpu.mem_jalr_flag);
    wire bench_mem_ctrl_fire = bench_active
                            && u_cpu.mem_valid
                            && u_cpu.mem_ctrl_resolve_en
                            && !mem_ctrl_same_seen;
    wire bench_mem_b_fire = bench_mem_ctrl_fire
                         && u_cpu.mem_branch_flag;
    wire bench_mem_jalr_fire = bench_mem_ctrl_fire
                            && u_cpu.mem_jalr_flag;
    wire ex_b_dir_ok = bench_ex_b_fire
                    && (u_cpu.ex_pred_taken == u_cpu.ex_actual_jump_flag);
    wire ex_b_tgt_check = bench_ex_b_fire
                       && u_cpu.ex_pred_taken
                       && u_cpu.ex_actual_jump_flag;
    wire ex_b_tgt_ok = ex_b_tgt_check
                    && (u_cpu.ex_pred_target == u_cpu.ex_actual_jump_addr);
    wire ex_b_ok = bench_ex_b_fire
                && !u_cpu.ex_mispredict;
    wire ex_jal_dir_ok = bench_ex_jal_fire
                      && u_cpu.ex_pred_taken;
    wire ex_jal_tgt_check = bench_ex_jal_fire
                         && u_cpu.ex_pred_taken;
    wire ex_jal_tgt_ok = ex_jal_tgt_check
                      && (u_cpu.ex_pred_target == u_cpu.ex_actual_jump_addr);
    wire ex_jal_ok = bench_ex_jal_fire
                  && !u_cpu.ex_mispredict;
    wire ex_jalr_dir_ok = bench_ex_jalr_fire
                       && u_cpu.ex_pred_taken;
    wire ex_jalr_tgt_check = bench_ex_jalr_fire
                          && u_cpu.ex_pred_taken;
    wire ex_jalr_tgt_ok = ex_jalr_tgt_check
                       && (u_cpu.ex_pred_target == u_cpu.ex_actual_jump_addr);
    wire ex_jalr_ok = bench_ex_jalr_fire
                   && !u_cpu.ex_mispredict;
    wire mem_b_dir_ok = bench_mem_b_fire
                     && (u_cpu.mem_pred_taken == u_cpu.mem_ctrl_actual_jump_flag);
    wire mem_b_tgt_check = bench_mem_b_fire
                        && u_cpu.mem_pred_taken
                        && u_cpu.mem_ctrl_actual_jump_flag;
    wire mem_b_tgt_ok = mem_b_tgt_check
                     && (u_cpu.mem_ctrl_pred_target_low == u_cpu.mem_ctrl_actual_jump_addr_low);
    wire mem_b_ok = bench_mem_b_fire
                 && !u_cpu.mem_ctrl_mispredict;
    wire mem_jalr_dir_ok = bench_mem_jalr_fire
                        && u_cpu.mem_pred_taken;
    wire mem_jalr_tgt_check = bench_mem_jalr_fire
                           && u_cpu.mem_pred_taken;
    wire mem_jalr_tgt_ok = mem_jalr_tgt_check
                        && (u_cpu.mem_ctrl_pred_target_low == u_cpu.mem_ctrl_actual_jump_addr_low);
    wire mem_jalr_ok = bench_mem_jalr_fire
                    && !u_cpu.mem_ctrl_mispredict;
    wire [1:0] pred_b_total_inc = {1'b0, bench_ex_b_fire}
                                + {1'b0, bench_mem_b_fire};
    wire [1:0] pred_b_dir_ok_inc = {1'b0, ex_b_dir_ok}
                                 + {1'b0, mem_b_dir_ok};
    wire [1:0] pred_b_tgt_check_inc = {1'b0, ex_b_tgt_check}
                                    + {1'b0, mem_b_tgt_check};
    wire [1:0] pred_b_tgt_ok_inc = {1'b0, ex_b_tgt_ok}
                                 + {1'b0, mem_b_tgt_ok};
    wire [1:0] pred_b_ok_inc = {1'b0, ex_b_ok}
                             + {1'b0, mem_b_ok};
    wire [1:0] pred_jalr_total_inc = {1'b0, bench_ex_jalr_fire}
                                   + {1'b0, bench_mem_jalr_fire};
    wire [1:0] pred_jalr_dir_ok_inc = {1'b0, ex_jalr_dir_ok}
                                    + {1'b0, mem_jalr_dir_ok};
    wire [1:0] pred_jalr_tgt_check_inc = {1'b0, ex_jalr_tgt_check}
                                       + {1'b0, mem_jalr_tgt_check};
    wire [1:0] pred_jalr_tgt_ok_inc = {1'b0, ex_jalr_tgt_ok}
                                    + {1'b0, mem_jalr_tgt_ok};
    wire [1:0] pred_jalr_ok_inc = {1'b0, ex_jalr_ok}
                                + {1'b0, mem_jalr_ok};

    function [63:0] pct_x100;
        input [63:0] num;
        input [63:0] den;
        begin
            if (den == 64'd0)
                pct_x100 = 64'd0;
            else
                pct_x100 = ((num * 64'd10000) + (den / 2)) / den;
        end
    endfunction

    cpu u_cpu(
        .irq_external(1'b0),
        .clk   (clk  ),
        .rst_n (rst_n),
        .led   (led  )
    );

    initial clk = 1'b0;
    always #(500_000_000.0 / `CPU_CLK_FREQ_HZ) clk = ~clk;

    initial begin
        rst_n = 1'b0;
        bench_pending_start = 1'b0;
        bench_active = 1'b0;
        bench_done = 1'b0;
        bench_gap_count = 0;
        bench_cycles = 64'd0;
        bench_retired = 64'd0;
        bench_ipc_x1000 = 64'd0;
        pred_b_total = 64'd0;
        pred_b_dir_ok = 64'd0;
        pred_b_tgt_check = 64'd0;
        pred_b_tgt_ok = 64'd0;
        pred_b_ok = 64'd0;
        pred_jal_total = 64'd0;
        pred_jal_dir_ok = 64'd0;
        pred_jal_tgt_check = 64'd0;
        pred_jal_tgt_ok = 64'd0;
        pred_jal_ok = 64'd0;
        pred_jalr_total = 64'd0;
        pred_jalr_dir_ok = 64'd0;
        pred_jalr_tgt_check = 64'd0;
        pred_jalr_tgt_ok = 64'd0;
        pred_jalr_ok = 64'd0;
        mem_ctrl_seen = 1'b0;
        mem_ctrl_seen_pc = {`IMEM_ADDR_BITS{1'b0}};
        mem_ctrl_seen_b = 1'b0;
        mem_ctrl_seen_jalr = 1'b0;
        #100;
        rst_n = 1'b1;
    end

    initial begin
        #TB_TIMEOUT_NS;
        $display("=== Simulation TIMEOUT, LED=%04x ===", led);
        $finish;
    end

    always @(posedge clk) begin
        if (u_cpu.bus_m_stb && !u_cpu.bus_m_we
                && u_cpu.bus_m_addr[31:28] == `MMIO_REGION_NIBBLE
                && u_cpu.bus_m_addr[5:0] != `MMIO_UART_TX_OFFSET
                && u_cpu.bus_m_addr[5:0] != `MMIO_UART_STATUS_OFFSET) begin
            $display("[%0t ns] MMIO READ  addr=%08x", $time, u_cpu.bus_m_addr);
            @(negedge clk);
            wait(u_cpu.bus_m_ack);
            $display("data=%08x ", u_cpu.bus_m_dat_o);
        end
    end

    always @(posedge clk) begin
        if (u_cpu.bus_m_stb && u_cpu.bus_m_we
                && u_cpu.bus_m_addr[31:28] == `MMIO_REGION_NIBBLE
                && u_cpu.bus_m_addr[5:0] != `MMIO_UART_TX_OFFSET
                && u_cpu.bus_m_addr[5:0] != `MMIO_UART_STATUS_OFFSET) begin
            $display("[%0t ns] MMIO WRITE  addr=%08x", $time, u_cpu.bus_m_addr);
            @(negedge clk);
            wait(u_cpu.bus_m_ack);
            $display("data=%08x ", u_cpu.bus_m_dat_o);
        end
    end

    always @(led) begin
        $display("[%0t ns] LED = %04x", $time, led);
    end

    always @(posedge clk) begin
        if (u_cpu.bus_m_stb && u_cpu.bus_m_we
                && u_cpu.bus_m_addr == 32'hF0000008) begin
            $display("[%0t ns] TOHOST WRITE = %08x", $time, u_cpu.bus_m_dat_i);
            if (u_cpu.bus_m_dat_i != 0) begin
                if (bench_cycles != 0) begin
                    bench_ipc_x1000 = (bench_retired * 64'd1000 + (bench_cycles / 2))
                                    / bench_cycles;
                end else begin
                    bench_ipc_x1000 = 64'd0;
                end
                $display("[TBIPC] BENCH C=%0d  I=%0d  IPC=%0d.%03d  done=%0d",
                         bench_cycles,
                         bench_retired,
                         bench_ipc_x1000 / 1000,
                         bench_ipc_x1000 % 1000,
                         bench_done);
                $display("[TBPRED] B    N=%0d  dir=%0d.%02d%%  tgt=%0d.%02d%%  total=%0d.%02d%%",
                         pred_b_total,
                         pct_x100(pred_b_dir_ok, pred_b_total) / 100,
                         pct_x100(pred_b_dir_ok, pred_b_total) % 100,
                         pct_x100(pred_b_tgt_ok, pred_b_tgt_check) / 100,
                         pct_x100(pred_b_tgt_ok, pred_b_tgt_check) % 100,
                         pct_x100(pred_b_ok, pred_b_total) / 100,
                         pct_x100(pred_b_ok, pred_b_total) % 100);
                $display("[TBPRED] JAL  N=%0d  dir=%0d.%02d%%  tgt=%0d.%02d%%  total=%0d.%02d%%",
                         pred_jal_total,
                         pct_x100(pred_jal_dir_ok, pred_jal_total) / 100,
                         pct_x100(pred_jal_dir_ok, pred_jal_total) % 100,
                         pct_x100(pred_jal_tgt_ok, pred_jal_tgt_check) / 100,
                         pct_x100(pred_jal_tgt_ok, pred_jal_tgt_check) % 100,
                         pct_x100(pred_jal_ok, pred_jal_total) / 100,
                         pct_x100(pred_jal_ok, pred_jal_total) % 100);
                $display("[TBPRED] JALR N=%0d  dir=%0d.%02d%%  tgt=%0d.%02d%%  total=%0d.%02d%%",
                         pred_jalr_total,
                         pct_x100(pred_jalr_dir_ok, pred_jalr_total) / 100,
                         pct_x100(pred_jalr_dir_ok, pred_jalr_total) % 100,
                         pct_x100(pred_jalr_tgt_ok, pred_jalr_tgt_check) / 100,
                         pct_x100(pred_jalr_tgt_ok, pred_jalr_tgt_check) % 100,
                         pct_x100(pred_jalr_ok, pred_jalr_total) / 100,
                         pct_x100(pred_jalr_ok, pred_jalr_total) % 100);
                $display("[TBPRED] ALL  N=%0d  dir=%0d.%02d%%  tgt=%0d.%02d%%  total=%0d.%02d%%  miss=%0d.%02d%%",
                         pred_b_total + pred_jal_total + pred_jalr_total,
                         pct_x100(pred_b_dir_ok + pred_jal_dir_ok + pred_jalr_dir_ok,
                                  pred_b_total + pred_jal_total + pred_jalr_total) / 100,
                         pct_x100(pred_b_dir_ok + pred_jal_dir_ok + pred_jalr_dir_ok,
                                  pred_b_total + pred_jal_total + pred_jalr_total) % 100,
                         pct_x100(pred_b_tgt_ok + pred_jal_tgt_ok + pred_jalr_tgt_ok,
                                  pred_b_tgt_check + pred_jal_tgt_check + pred_jalr_tgt_check) / 100,
                         pct_x100(pred_b_tgt_ok + pred_jal_tgt_ok + pred_jalr_tgt_ok,
                                  pred_b_tgt_check + pred_jal_tgt_check + pred_jalr_tgt_check) % 100,
                         pct_x100(pred_b_ok + pred_jal_ok + pred_jalr_ok,
                                  pred_b_total + pred_jal_total + pred_jalr_total) / 100,
                         pct_x100(pred_b_ok + pred_jal_ok + pred_jalr_ok,
                                  pred_b_total + pred_jal_total + pred_jalr_total) % 100,
                         pct_x100((pred_b_total + pred_jal_total + pred_jalr_total)
                                  - (pred_b_ok + pred_jal_ok + pred_jalr_ok),
                                  pred_b_total + pred_jal_total + pred_jalr_total) / 100,
                         pct_x100((pred_b_total + pred_jal_total + pred_jalr_total)
                                  - (pred_b_ok + pred_jal_ok + pred_jalr_ok),
                                  pred_b_total + pred_jal_total + pred_jalr_total) % 100);
                $display("=== Simulation END, LED=%04x ===", led);
                #100;
                $finish;
            end
        end
    end

    always @(posedge clk) begin
        if (u_cpu.u_mmio.uart_valid && (u_cpu.u_mmio.uart_data != 8'h0d))
            $write("%c", u_cpu.u_mmio.uart_data);
    end

    always @(posedge clk) begin
        if (rst_n == `RST_ENABLE) begin
            bench_pending_start <= 1'b0;
            bench_active <= 1'b0;
            bench_done <= 1'b0;
            bench_gap_count <= 0;
            bench_cycles <= 64'd0;
            bench_retired <= 64'd0;
            pred_b_total <= 64'd0;
            pred_b_dir_ok <= 64'd0;
            pred_b_tgt_check <= 64'd0;
            pred_b_tgt_ok <= 64'd0;
            pred_b_ok <= 64'd0;
            pred_jal_total <= 64'd0;
            pred_jal_dir_ok <= 64'd0;
            pred_jal_tgt_check <= 64'd0;
            pred_jal_tgt_ok <= 64'd0;
            pred_jal_ok <= 64'd0;
            pred_jalr_total <= 64'd0;
            pred_jalr_dir_ok <= 64'd0;
            pred_jalr_tgt_check <= 64'd0;
            pred_jalr_tgt_ok <= 64'd0;
            pred_jalr_ok <= 64'd0;
            mem_ctrl_seen <= 1'b0;
            mem_ctrl_seen_pc <= {`IMEM_ADDR_BITS{1'b0}};
            mem_ctrl_seen_b <= 1'b0;
            mem_ctrl_seen_jalr <= 1'b0;
        end else if (!bench_done) begin
            if (timer_read_fire) begin
                if (bench_active) begin
                    if (bench_cycles >= BENCH_MIN_WINDOW_CYCLES) begin
                        bench_active <= 1'b0;
                        bench_done <= 1'b1;
                    end else begin
                        bench_active <= 1'b0;
                        bench_pending_start <= 1'b1;
                        bench_gap_count <= 0;
                        bench_cycles <= 64'd0;
                        bench_retired <= 64'd0;
                        pred_b_total <= 64'd0;
                        pred_b_dir_ok <= 64'd0;
                        pred_b_tgt_check <= 64'd0;
                        pred_b_tgt_ok <= 64'd0;
                        pred_b_ok <= 64'd0;
                        pred_jal_total <= 64'd0;
                        pred_jal_dir_ok <= 64'd0;
                        pred_jal_tgt_check <= 64'd0;
                        pred_jal_tgt_ok <= 64'd0;
                        pred_jal_ok <= 64'd0;
                        pred_jalr_total <= 64'd0;
                        pred_jalr_dir_ok <= 64'd0;
                        pred_jalr_tgt_check <= 64'd0;
                        pred_jalr_tgt_ok <= 64'd0;
                        pred_jalr_ok <= 64'd0;
                        mem_ctrl_seen <= 1'b0;
                        mem_ctrl_seen_pc <= {`IMEM_ADDR_BITS{1'b0}};
                        mem_ctrl_seen_b <= 1'b0;
                        mem_ctrl_seen_jalr <= 1'b0;
                    end
                end else begin
                    bench_pending_start <= 1'b1;
                    bench_gap_count <= 0;
                end
            end else begin
                if (bench_pending_start && !bench_active) begin
                    if (bench_gap_count >= (BENCH_TIMER_GAP_CYCLES - 1)) begin
                        bench_pending_start <= 1'b0;
                        bench_active <= 1'b1;
                        bench_cycles <= 64'd0;
                        bench_retired <= 64'd0;
                        pred_b_total <= 64'd0;
                        pred_b_dir_ok <= 64'd0;
                        pred_b_tgt_check <= 64'd0;
                        pred_b_tgt_ok <= 64'd0;
                        pred_b_ok <= 64'd0;
                        pred_jal_total <= 64'd0;
                        pred_jal_dir_ok <= 64'd0;
                        pred_jal_tgt_check <= 64'd0;
                        pred_jal_tgt_ok <= 64'd0;
                        pred_jal_ok <= 64'd0;
                        pred_jalr_total <= 64'd0;
                        pred_jalr_dir_ok <= 64'd0;
                        pred_jalr_tgt_check <= 64'd0;
                        pred_jalr_tgt_ok <= 64'd0;
                        pred_jalr_ok <= 64'd0;
                        mem_ctrl_seen <= 1'b0;
                        mem_ctrl_seen_pc <= {`IMEM_ADDR_BITS{1'b0}};
                        mem_ctrl_seen_b <= 1'b0;
                        mem_ctrl_seen_jalr <= 1'b0;
                    end else begin
                        bench_gap_count <= bench_gap_count + 1;
                    end
                end else if (bench_active) begin
                    bench_cycles <= bench_cycles + 64'd1;
                    if (retire_fire)
                        bench_retired <= bench_retired + 64'd1;
                    pred_b_total <= pred_b_total + pred_b_total_inc;
                    pred_b_dir_ok <= pred_b_dir_ok + pred_b_dir_ok_inc;
                    pred_b_tgt_check <= pred_b_tgt_check + pred_b_tgt_check_inc;
                    pred_b_tgt_ok <= pred_b_tgt_ok + pred_b_tgt_ok_inc;
                    pred_b_ok <= pred_b_ok + pred_b_ok_inc;
                    pred_jal_total <= pred_jal_total + {63'd0, bench_ex_jal_fire};
                    pred_jal_dir_ok <= pred_jal_dir_ok + {63'd0, ex_jal_dir_ok};
                    pred_jal_tgt_check <= pred_jal_tgt_check + {63'd0, ex_jal_tgt_check};
                    pred_jal_tgt_ok <= pred_jal_tgt_ok + {63'd0, ex_jal_tgt_ok};
                    pred_jal_ok <= pred_jal_ok + {63'd0, ex_jal_ok};
                    pred_jalr_total <= pred_jalr_total + pred_jalr_total_inc;
                    pred_jalr_dir_ok <= pred_jalr_dir_ok + pred_jalr_dir_ok_inc;
                    pred_jalr_tgt_check <= pred_jalr_tgt_check + pred_jalr_tgt_check_inc;
                    pred_jalr_tgt_ok <= pred_jalr_tgt_ok + pred_jalr_tgt_ok_inc;
                    pred_jalr_ok <= pred_jalr_ok + pred_jalr_ok_inc;
                end
            end

            if (u_cpu.mem_ctrl_resolve_en) begin
                mem_ctrl_seen <= 1'b1;
                mem_ctrl_seen_pc <= u_cpu.mem_ctrl_pc_low;
                mem_ctrl_seen_b <= u_cpu.mem_branch_flag;
                mem_ctrl_seen_jalr <= u_cpu.mem_jalr_flag;
            end else begin
                mem_ctrl_seen <= 1'b0;
            end
        end
    end

endmodule

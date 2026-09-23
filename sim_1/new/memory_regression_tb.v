`timescale 1ns/1ps
`include "defines.v"
module memory_regression_tb;
    reg clk=0, rst_n=0;
    always #(500_000_000.0 / `CPU_CLK_FREQ_HZ) clk=~clk;
    wire [15:0] led;
    wire uart_tx;
    cpu dut(.irq_external(1'b0),.clk(clk),.rst_n(rst_n),.led(led),.uart_tx(uart_tx));
    integer cycles=0, stores=0, uart_stores=0, waits=0;
    integer limit=200000, expect_fault=0, reset_wait=0;
    initial begin
        if($value$plusargs("LIMIT=%d",limit)) begin end
        if($value$plusargs("FAULT=%d",expect_fault)) begin end
        if($value$plusargs("RESET_WAIT=%d",reset_wait)) begin end
        repeat(6) @(negedge clk); rst_n=1;
        if(reset_wait) begin
            wait(dut.mem_wait);
            repeat(2) @(negedge clk); rst_n=0;
            repeat(6) @(negedge clk); rst_n=1;
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            cycles=0; stores=0; uart_stores=0; waits=0;
        end else begin
            cycles=cycles+1;
            if(dut.bus_m_stb && !dut.bus_m_ready)
                $fatal(1,"Request issued while bus unavailable");
            if(dut.mem_wait && dut.mem_retire)
                $fatal(1,"Memory instruction retired before response");
            if($test$plusargs("TRACE"))
                $display("PC=%h EX=%h MEM=%h WB=%b x%0d=%h bus=%b/%b addr=%h wait=%b",
                    dut.preif_pc_addr,dut.ex_instr_addr,dut.mem_ctrl_pc_low,
                    dut.wb_regs_we,dut.wb_regs_w_addr,dut.wb_actual_regs_w_data,
                    dut.bus_m_stb,dut.bus_m_ack,dut.bus_m_addr,dut.mem_wait);
            if(dut.bus_s2_stb && dut.bus_s2_we) begin
                stores=stores+1;
                if(dut.bus_s2_addr==32'hf0000010) uart_stores=uart_stores+1;
            end
            if(dut.mem_wait) waits=waits+1;
            if(dut.memory_fault) begin
                if(!expect_fault) $fatal(1,"Unexpected memory fault at %h",dut.memory_fault_addr);
            end
            if(expect_fault && dut.trap_enter) begin
                if(dut.u_privileged.cause_q<4 || dut.u_privileged.cause_q>7 ||
                   dut.u_privileged.tval_q!==dut.memory_fault_addr || dut.bus_m_stb || dut.mem_retire)
                    $fatal(1,"Incorrect memory exception");
                $display("PASS memory exception addr=%h cause=%0d cycles=%0d",dut.memory_fault_addr,dut.u_privileged.cause_q,cycles);
                $finish;
            end
            if(dut.u_mmio.tohost) begin
                if(expect_fault || led!==0) $fatal(1,"Program failed LED=%h",led);
                if(!$test$plusargs("OFFICIAL") && (stores!=2 || uart_stores!=0))
                    $fatal(1,"Repeated/wrong-path MMIO store: %0d UART=%0d",stores,uart_stores);
                $display("PASS memory program cycles=%0d waits=%0d MMIO stores=%0d",cycles,waits,stores);
                $finish;
            end
            if(cycles>=limit) $fatal(1,"Timeout PC=%h MEMwait=%b",dut.preif_pc_addr,dut.mem_wait);
        end
    end
endmodule

// Test-only response shim; native slaves see each request exactly once.
// Delay 0 is the original one-cycle peripheral latency. Positive delay holds
// ack low and poisons read data until the saved response becomes available.
module response_delay(input clk,input rst_n,input native_ack,input [31:0] native_data,
                      output ack,output [31:0] data);
    integer delay_max=0, countdown=0, number=0;
    reg pending=0, delayed_ack=0;
    reg [31:0] saved_data=0;
    initial if($value$plusargs("DELAY=%d",delay_max)) begin end
    assign ack=delay_max==0 ? native_ack : delayed_ack;
    assign data=delay_max==0 ? native_data : (delayed_ack ? saved_data : 32'hdeadbeef);
    always @(posedge clk) begin
        if(!rst_n) begin pending<=0;delayed_ack<=0;countdown<=0;number<=0;end
        else if(delay_max!=0) begin
            delayed_ack<=0;
            if(native_ack) begin
                if(pending) $fatal(1,"Second request before prior response");
                saved_data<=native_data;pending<=1;
                countdown<=1+(number%delay_max);number<=number+1;
            end else if(pending) begin
                if(countdown==1) begin pending<=0;delayed_ack<=1;end
                else countdown<=countdown-1;
            end
        end
    end
endmodule

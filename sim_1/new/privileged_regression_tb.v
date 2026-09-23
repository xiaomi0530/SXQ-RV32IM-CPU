`timescale 1ns/1ps
`include "defines.v"
module privileged_regression_tb;
    reg clk=0, rst_n=0, external_irq=0;
    always #(500_000_000.0 / `CPU_CLK_FREQ_HZ) clk=~clk;
    wire [15:0] led;
    wire uart_tx;
    cpu dut(.clk(clk),.rst_n(rst_n),.led(led),.uart_tx(uart_tx),.irq_external(external_irq));
    initial begin
        repeat(6) @(negedge clk); rst_n=1;
        if($test$plusargs("RESET_WFI")) begin
            wait(dut.u_privileged.state==4);
            @(negedge clk); rst_n=0;
            repeat(6) @(negedge clk); rst_n=1;
        end
    end
    integer cycles=0, traps=0, external_wait=0;
    always @(posedge clk) if(!rst_n) begin
        cycles=0; traps=0; external_wait=0; external_irq<=0;
    end else begin
        cycles=cycles+1;
        if(led==16'heeee) begin
            external_wait=external_wait+1;
            if(external_wait==100) external_irq<=1;
        end
        if(dut.trap_enter) begin
            traps=traps+1;
            if(dut.u_privileged.cause_q==32'h8000000b) external_irq<=0;
            if($test$plusargs("TRACE")) $display("trap pc=%h cause=%h val=%h",dut.u_privileged.pc_q,dut.u_privileged.cause_q,dut.u_privileged.tval_q);
        end
        if(dut.sys_rf_we && dut.wb_regs_we) $fatal(1,"Two RF writers");
        if(dut.bus_m_stb && !dut.bus_m_ready) $fatal(1,"Unaccepted request");
        if(dut.sys_busy && dut.bus_m_stb) $fatal(1,"Request during system operation");
        if(dut.u_mmio.tohost) begin
            if(led!==0) $fatal(1,"FAIL stage=%0d pc=%h mcause=%h mepc=%h mtval=%h traps=%0d",led,dut.preif_pc_addr,dut.u_privileged.mcause,dut.u_privileged.mepc,dut.u_privileged.mtval,traps);
            $display("PASS privileged cycles=%0d traps=%0d",cycles,traps); $finish;
        end
        if(cycles==1000000) $fatal(1,"Timeout pc=%h state=%0d mie=%h mip=%h",dut.preif_pc_addr,dut.u_privileged.state,dut.u_privileged.mie,dut.u_privileged.mip);
    end
endmodule

`timescale 1ns / 1ps
`include "defines.v"

// Register map (base = 0xF0000000)
//   0x00  cycle_cnt_lo   [RO] 64-bit cycle counter low word
//   0x04  cycle_cnt_hi   [RO] 64-bit cycle counter high word
//   0x08  tohost         [WO] bit0=1 indicates program completed
//   0x0C  led            [WO] drive LED[15:0]
//   0x10  uart_tx_data   [WO] enqueue one byte to UART
//   0x14  uart_status    [RO] {overflow, busy, ready}

module mmio(
    output wire [63:0] time_value,
    input wire [63:0] instret_value,
    output reg irq_timer,
    output wire irq_software,
    input  wire        clk,
    input  wire        rst_n,

    input  wire        bus_stb,
    output reg          bus_ack,
    input  wire        bus_we,
    input  wire [31:0] bus_addr,
    input  wire [31:0] w_data,
    output reg   [31:0] r_data,

    output reg   [15:0] led,
    output reg          uart_valid,
    output reg   [7:0]  uart_data,
    output reg          tohost,
    input  wire        uart_busy,
    input  wire        uart_ready,
    input  wire        uart_overflow
);

    // Two-cycle slave: capture once, then decode/execute the registered request.
    // This removes the late-branch -> interconnect -> timer write-enable path.
    reg req_valid, req_we;
    reg [31:0] req_addr, req_data;
    always @(posedge clk) begin
        if(!rst_n) begin req_valid<=0; req_we<=0; req_addr<=0; req_data<=0; end
        else begin
            req_valid<=bus_stb;
            if(bus_stb) begin req_we<=bus_we; req_addr<=bus_addr; req_data<=w_data; end
        end
    end
    reg [63:0] cycle_cnt;
    reg [63:0] mtimecmp;
    reg msip;
    assign time_value=cycle_cnt;
    assign irq_software=msip;
    // Registered comparison keeps the 64-bit timer out of interrupt arbitration.
    always @(posedge clk) if(!rst_n) irq_timer<=0; else irq_timer<=cycle_cnt>=mtimecmp;
    wire [31:0] word_addr={req_addr[31:2],2'b0};
    wire [5:0] offset = word_addr==32'h02000000 ? 6'h28 :
                       word_addr==32'h02004000 ? 6'h20 : word_addr==32'h02004004 ? 6'h24 :
                       word_addr==32'h0200bff8 ? 6'h30 : word_addr==32'h0200bffc ? 6'h34 : req_addr[5:0];
    always @(posedge clk) begin
        if(!rst_n) begin mtimecmp<=64'hffffffffffffffff; msip<=0; end
        else if(req_valid && req_we) case(offset)
            6'h20: mtimecmp[31:0]<=req_data;
            6'h24: mtimecmp[63:32]<=req_data;
            6'h28: msip<=req_data[0];
            default: ;
        endcase
    end
    always @(posedge clk) begin
        if (!rst_n) cycle_cnt <= 64'h0;
        else if(req_valid && req_we && offset==6'h30) cycle_cnt<={cycle_cnt[63:32],req_data};
        else if(req_valid && req_we && offset==6'h34) cycle_cnt<={req_data,cycle_cnt[31:0]};
        else cycle_cnt <= cycle_cnt + 1;
    end

    always @(posedge clk) begin
        if (!rst_n) bus_ack <= 1'b0;
        else        bus_ack <= req_valid;
    end

    always @(posedge clk) begin
        uart_valid <= 1'b0;
        if (!rst_n) begin
            tohost    <= 1'b0;
            led       <= 16'h0;
            uart_data <= 8'h0;
        end else if (req_valid && req_we) begin
            case (offset)
                `MMIO_TOHOST_OFFSET: tohost <= req_data[0];
                `MMIO_LED_OFFSET:    led    <= req_data[15:0];
                `MMIO_UART_TX_OFFSET: begin
                    uart_data  <= req_data[7:0];
                    uart_valid <= 1'b1;
                end
                default: ;
            endcase
        end
    end

    always @(posedge clk) begin
        case (offset)
            6'h30, `MMIO_TIMER_LO_OFFSET:   r_data <= cycle_cnt[31:0];
            6'h34, `MMIO_TIMER_HI_OFFSET:   r_data <= cycle_cnt[63:32];
            `MMIO_INSTRET_LO_OFFSET: r_data <= instret_value[31:0];
            `MMIO_INSTRET_HI_OFFSET: r_data <= instret_value[63:32];
            `MMIO_UART_STATUS_OFFSET:r_data <= {29'd0, uart_overflow, uart_busy, uart_ready};
            6'h20: r_data<=mtimecmp[31:0];
            6'h24: r_data<=mtimecmp[63:32];
            6'h28: r_data<={31'b0,msip};
            default:                 r_data <= 32'h0;
        endcase
    end

endmodule

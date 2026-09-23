`ifndef QXW_DEFINES_V
`define QXW_DEFINES_V

`ifndef RST_ENABLE
`define RST_ENABLE 1'b0
`endif

// ---------------------------------------------------------------------------
// Address / memory layout
// ---------------------------------------------------------------------------
`ifndef CPU_ADDR_BITS
`define CPU_ADDR_BITS 32
`endif

`ifndef IMEM_BASE_ADDR
`define IMEM_BASE_ADDR 32'h0000_0000
`endif

`ifndef IMEM_WORD_ADDR_BITS
`define IMEM_WORD_ADDR_BITS 13
`endif

`ifndef IMEM_DEPTH_WORDS
`define IMEM_DEPTH_WORDS (1 << `IMEM_WORD_ADDR_BITS)
`endif

`ifndef IMEM_ADDR_BITS
`define IMEM_ADDR_BITS (`IMEM_WORD_ADDR_BITS + 2)
`endif

`ifndef DMEM_BASE_ADDR
`define DMEM_BASE_ADDR 32'h0001_0000
`endif

`ifndef DMEM_WORD_ADDR_BITS
`define DMEM_WORD_ADDR_BITS 13
`endif

`ifndef DMEM_DEPTH_WORDS
`define DMEM_DEPTH_WORDS (1 << `DMEM_WORD_ADDR_BITS)
`endif

`ifndef DMEM_ADDR_BITS
`define DMEM_ADDR_BITS (`DMEM_WORD_ADDR_BITS + 2)
`endif

// ---------------------------------------------------------------------------
// Frontend predictor
// ---------------------------------------------------------------------------
`ifndef BR_PRED_PC_CANON_BITS
`define BR_PRED_PC_CANON_BITS 12
`endif

`ifndef BR_PRED_ENTRY_NUM
`define BR_PRED_ENTRY_NUM 64
`endif

`ifndef BR_PRED_INDEX_BITS
`define BR_PRED_INDEX_BITS 6
`endif

`ifndef BR_PRED_TAG_BITS
`define BR_PRED_TAG_BITS 5
`endif

`ifndef JTB_ENTRY_NUM
`define JTB_ENTRY_NUM 8
`endif

`ifndef JTB_INDEX_BITS
`define JTB_INDEX_BITS 3
`endif

`ifndef RAS_DEPTH
`define RAS_DEPTH 8
`endif

`ifndef RAS_PTR_W
`define RAS_PTR_W 3
`endif

// ---------------------------------------------------------------------------
// Core clock / UART
// ---------------------------------------------------------------------------
`ifndef CPU_CLK_FREQ_HZ
`define CPU_CLK_FREQ_HZ 90_000_000
`endif

`ifndef CPU_UART_BAUD_RATE_SYNTH
`define CPU_UART_BAUD_RATE_SYNTH 115_200
`endif

`ifndef CPU_UART_BAUD_RATE_SIM
`define CPU_UART_BAUD_RATE_SIM 3_000_000
`endif

`ifndef CPU_UART_BAUD_RATE
    `ifdef SYNTHESIS
        `define CPU_UART_BAUD_RATE `CPU_UART_BAUD_RATE_SYNTH
    `else
        `define CPU_UART_BAUD_RATE `CPU_UART_BAUD_RATE_SIM
    `endif
`endif

`ifndef CPU_UART_FIFO_DEPTH
`define CPU_UART_FIFO_DEPTH 4
`endif

// ---------------------------------------------------------------------------
// Shared datapath encodings
// ---------------------------------------------------------------------------
`ifndef ALU_OP_ADD
`define ALU_OP_ADD 4'b0000
`endif

`ifndef ALU_OP_SUB
`define ALU_OP_SUB 4'b1000
`endif

`ifndef ALU_OP_AND
`define ALU_OP_AND 4'b0111
`endif

`ifndef ALU_OP_OR
`define ALU_OP_OR 4'b0110
`endif

`ifndef ALU_OP_XOR
`define ALU_OP_XOR 4'b0100
`endif

`ifndef ALU_OP_SLL
`define ALU_OP_SLL 4'b0001
`endif

`ifndef ALU_OP_SRL
`define ALU_OP_SRL 4'b0101
`endif

`ifndef ALU_OP_SRA
`define ALU_OP_SRA 4'b1101
`endif

`ifndef ALU_OP_SLT
`define ALU_OP_SLT 4'b0010
`endif

`ifndef ALU_OP_SLTU
`define ALU_OP_SLTU 4'b0011
`endif

`ifndef ALU_OP_MUL
`define ALU_OP_MUL 4'b1001
`endif

`ifndef ALU_OP_MULH
`define ALU_OP_MULH 4'b1010
`endif

`ifndef ALU_OP_MULHSU
`define ALU_OP_MULHSU 4'b1011
`endif

`ifndef ALU_OP_DIVREM
`define ALU_OP_DIVREM 4'b1100
`endif

`ifndef ALU_OP_MULHU
`define ALU_OP_MULHU 4'b1111
`endif

// ---------------------------------------------------------------------------
// MMIO map
// ---------------------------------------------------------------------------
`ifndef MMIO_BASE_ADDR
`define MMIO_BASE_ADDR 32'hF0000000
`endif

`ifndef MMIO_REGION_NIBBLE
`define MMIO_REGION_NIBBLE 4'hF
`endif

`ifndef MMIO_TIMER_LO_OFFSET
`define MMIO_TIMER_LO_OFFSET 6'h00
`endif

`ifndef MMIO_TIMER_HI_OFFSET
`define MMIO_TIMER_HI_OFFSET 6'h04
`endif

`ifndef MMIO_TOHOST_OFFSET
`define MMIO_TOHOST_OFFSET 6'h08
`endif

`ifndef MMIO_LED_OFFSET
`define MMIO_LED_OFFSET 6'h0C
`endif

`ifndef MMIO_UART_TX_OFFSET
`define MMIO_UART_TX_OFFSET 6'h10
`endif

`ifndef MMIO_UART_STATUS_OFFSET
`define MMIO_UART_STATUS_OFFSET 6'h14
`endif

`ifndef MMIO_INSTRET_LO_OFFSET
`define MMIO_INSTRET_LO_OFFSET 6'h18
`endif

`ifndef MMIO_INSTRET_HI_OFFSET
`define MMIO_INSTRET_HI_OFFSET 6'h1C
`endif

`ifndef MMIO_TIMER_LO_ADDR
`define MMIO_TIMER_LO_ADDR (`MMIO_BASE_ADDR + 32'h0000_0000)
`endif

`ifndef MMIO_TIMER_HI_ADDR
`define MMIO_TIMER_HI_ADDR (`MMIO_BASE_ADDR + 32'h0000_0004)
`endif

`ifndef MMIO_TOHOST_ADDR
`define MMIO_TOHOST_ADDR (`MMIO_BASE_ADDR + 32'h0000_0008)
`endif

`ifndef MMIO_LED_ADDR
`define MMIO_LED_ADDR (`MMIO_BASE_ADDR + 32'h0000_000C)
`endif

`ifndef MMIO_UART_TX_ADDR
`define MMIO_UART_TX_ADDR (`MMIO_BASE_ADDR + 32'h0000_0010)
`endif

`ifndef MMIO_UART_STATUS_ADDR
`define MMIO_UART_STATUS_ADDR (`MMIO_BASE_ADDR + 32'h0000_0014)
`endif

`ifndef MMIO_INSTRET_LO_ADDR
`define MMIO_INSTRET_LO_ADDR (`MMIO_BASE_ADDR + 32'h0000_0018)
`endif

`ifndef MMIO_INSTRET_HI_ADDR
`define MMIO_INSTRET_HI_ADDR (`MMIO_BASE_ADDR + 32'h0000_001C)
`endif

// ---------------------------------------------------------------------------
// Testbench statistics
// ---------------------------------------------------------------------------
`ifndef TB_BP_STATS_ENABLE
`define TB_BP_STATS_ENABLE 1'b1
`endif

`ifndef TB_PERIODIC_STATS_ENABLE
`define TB_PERIODIC_STATS_ENABLE 1'b0
`endif

`ifndef TB_BRANCH_PC_STAT_SLOTS
`define TB_BRANCH_PC_STAT_SLOTS 1024
`endif

`ifndef TB_JALR_PC_STAT_SLOTS
`define TB_JALR_PC_STAT_SLOTS 16
`endif

`ifndef TB_SLOT1_TRACK_SLOTS
`define TB_SLOT1_TRACK_SLOTS 32
`endif

`ifndef TB_SLOT1_TYPE_B
`define TB_SLOT1_TYPE_B 3'd1
`endif

`ifndef TB_SLOT1_TYPE_JAL
`define TB_SLOT1_TYPE_JAL 3'd2
`endif

`ifndef TB_SLOT1_TYPE_JALR
`define TB_SLOT1_TYPE_JALR 3'd3
`endif

`ifndef TB_SLOT1_TYPE_RET
`define TB_SLOT1_TYPE_RET 3'd4
`endif

`ifndef TB_SLOT1_TYPE_CALL_JALR
`define TB_SLOT1_TYPE_CALL_JALR 3'd5
`endif

`ifndef TB_SLOT1_TYPE_INDIRECT_JALR
`define TB_SLOT1_TYPE_INDIRECT_JALR 3'd6
`endif

`endif

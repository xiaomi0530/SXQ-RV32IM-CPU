`timescale 1ns / 1ps
`include "defines.v"

module branch_predictor #(
    parameter integer ENTRY_NUM  = `BR_PRED_ENTRY_NUM,
    parameter integer INDEX_BITS = `BR_PRED_INDEX_BITS,
    parameter integer PC_CANON_BITS = `BR_PRED_PC_CANON_BITS,
    parameter integer TAG_BITS = `BR_PRED_TAG_BITS
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        lookup_is_branch0,
    input  wire [31:0] lookup_pc0,
    input  wire [INDEX_BITS-1:0] lookup_hash0,
    output wire        pred_taken0,
    output wire        branch_hit0,
    input  wire        lookup_is_branch1,
    input  wire [31:0] lookup_pc1,
    input  wire [INDEX_BITS-1:0] lookup_hash1,
    output wire        pred_taken1,
    output wire        branch_hit1,
    input  wire        update_en,
    input  wire [31:0] update_pc,
    input  wire [INDEX_BITS-1:0] update_hash,
    input  wire        update_taken
);

    reg [ENTRY_NUM-1:0]              branch_valid;
    reg [TAG_BITS-1:0]               branch_tag    [0:ENTRY_NUM-1];
    reg [1:0]                        bht_ctr    [0:ENTRY_NUM-1];

    function [TAG_BITS-1:0] pack_branch_tag;
        input [31:0] pc_value;
        integer bit_idx;
        integer src_idx;
        begin
            pack_branch_tag = {TAG_BITS{1'b0}};
            for (src_idx = (INDEX_BITS + 2); src_idx < PC_CANON_BITS; src_idx = src_idx + 1) begin
                bit_idx = src_idx - (INDEX_BITS + 2);
                if (bit_idx < TAG_BITS)
                    pack_branch_tag[bit_idx] = pc_value[src_idx];
                else
                    pack_branch_tag[bit_idx % TAG_BITS] = pack_branch_tag[bit_idx % TAG_BITS] ^ pc_value[src_idx];
            end
        end
    endfunction

    wire [INDEX_BITS-1:0] lookup_idx0 = lookup_pc0[INDEX_BITS+1:2] ^ lookup_hash0;
    wire [TAG_BITS-1:0]   lookup_tag0 = pack_branch_tag(lookup_pc0);
    wire [INDEX_BITS-1:0] lookup_idx1 = lookup_pc1[INDEX_BITS+1:2] ^ lookup_hash1;
    wire [TAG_BITS-1:0]   lookup_tag1 = pack_branch_tag(lookup_pc1);
    wire [INDEX_BITS-1:0] update_idx  = update_pc[INDEX_BITS+1:2] ^ update_hash;
    wire [TAG_BITS-1:0]   update_tag  = pack_branch_tag(update_pc);

    assign branch_hit0     = lookup_is_branch0 && branch_valid[lookup_idx0] && (branch_tag[lookup_idx0] == lookup_tag0);
    assign pred_taken0  = branch_hit0 && bht_ctr[lookup_idx0][1];
    assign branch_hit1     = lookup_is_branch1 && branch_valid[lookup_idx1] && (branch_tag[lookup_idx1] == lookup_tag1);
    assign pred_taken1  = branch_hit1 && bht_ctr[lookup_idx1][1];

    integer i;
    always @(posedge clk) begin
        if (rst_n == `RST_ENABLE) begin
            branch_valid <= {ENTRY_NUM{1'b0}};
            for (i = 0; i < ENTRY_NUM; i = i + 1) begin
                branch_tag[i]    <= {TAG_BITS{1'b0}};
                bht_ctr[i]    <= 2'b01;
            end
        end else begin
            // Decode the write index per entry. Do not read the entire BHT
            // through a large mux to generate its own write enable.
            for (i = 0; i < ENTRY_NUM; i = i + 1) begin
                if (update_en && update_idx == i) begin
                    if (update_taken) begin
                        branch_valid[i] <= 1'b1;
                        branch_tag[i] <= update_tag;
                    end
                    if (branch_valid[i] && branch_tag[i] == update_tag) begin
                        if (update_taken) begin
                            case (bht_ctr[i])
                                2'b00: bht_ctr[i]<=2'b01;
                                2'b01: bht_ctr[i]<=2'b10;
                                default: bht_ctr[i]<=2'b11;
                            endcase
                        end else begin
                            case (bht_ctr[i])
                                2'b11: bht_ctr[i]<=2'b10;
                                2'b10: bht_ctr[i]<=2'b01;
                                default: bht_ctr[i]<=2'b00;
                            endcase
                        end
                    end else if(update_taken) bht_ctr[i]<=2'b10;
                end
            end
        end
    end
endmodule

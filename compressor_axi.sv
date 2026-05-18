//`timescale 1ns / 1ps
//`define SIMULATION

//module compressor_axi #(
//    parameter integer DATA_WIDTH    = 64,
//    parameter integer STRB_WIDTH    = DATA_WIDTH / 8,
//    parameter integer HASH_ENTRIES  = 32,
//    parameter integer HISTORY_DEPTH = 256
//)(
//    input  logic                   clk,
//    input  logic                   rst_n,

//    input  logic [DATA_WIDTH-1:0]  in_data,
//    input  logic [STRB_WIDTH-1:0]  in_strb,
//    input  logic                   in_valid,
//    input  logic                   in_last,
//    output logic                   in_ready,

//    output logic [DATA_WIDTH-1:0]  out_data,
//    output logic [STRB_WIDTH-1:0]  out_strb,
//    output logic                   out_valid,
//    output logic                   out_last,
//    input  logic                   out_ready,

//    output logic [31:0]            stat_bytes_in,
//    output logic [31:0]            stat_bytes_out
//);

//// ================================================================
//// LOCALPARAMS
//// ================================================================
//localparam integer HASH_BITS = $clog2(HASH_ENTRIES);
//// HASH_ENTRIES=32 → HASH_BITS=5 → hash index 0 to 31

//localparam logic [1:0] TYPE_LITERAL  = 2'b00;
//localparam logic [1:0] TYPE_ZERO_RLE = 2'b01;
//localparam logic [1:0] TYPE_MATCH    = 2'b10;

//// ================================================================
//// STAGE 1 REGISTERS
//// ================================================================
//logic [DATA_WIDTH-1:0]   s1_data;
//logic [STRB_WIDTH-1:0]   s1_strb;
//logic                    s1_valid;
//logic                    s1_last;
//logic                    s1_is_zero;
//logic [HASH_BITS-1:0]    s1_hash_idx;
//logic [15:0]             s1_position;

//// ================================================================
//// STAGE 2 REGISTERS
//// ================================================================
//logic [DATA_WIDTH-1:0]   s2_data;
//logic [STRB_WIDTH-1:0]   s2_strb;
//logic                    s2_valid;
//logic                    s2_last;
//logic                    s2_is_zero;
//logic                    s2_is_match;
//logic [15:0]             s2_match_offset;
//logic [15:0]             s2_zero_count;

//// ================================================================
//// STAGE 3 OUTPUT REGISTERS
//// ================================================================
//logic [DATA_WIDTH-1:0]   s3_data;
//logic [STRB_WIDTH-1:0]   s3_strb;
//logic                    s3_valid;
//logic                    s3_last;

//// ================================================================
//// HASH TABLE
//// ================================================================
//logic [31:0]             hash_table_data  [0:HASH_ENTRIES-1];
//logic [15:0]             hash_table_pos   [0:HASH_ENTRIES-1];
//logic                    hash_table_valid [0:HASH_ENTRIES-1];

//// ================================================================
//// COUNTERS
//// ================================================================
//logic [15:0]             stream_position;
//logic [15:0]             zero_run_count;
//logic                    in_zero_run;

//// ================================================================
//// STALL LOGIC
//// Pipeline stalls when output has valid data but output wont accept
//// ================================================================
//logic pipeline_stall;
//assign pipeline_stall = s3_valid && !out_ready;
//assign in_ready       = !pipeline_stall;

//// ================================================================
//// HASH COMPUTATION - STAGE 1
//// FIX: use intermediate wire instead of expression bit-select
//// Vivado 2018.2 does not support (expression)[n:0] syntax
//// ================================================================
//logic [7:0]           hash_xor_result;
//logic [HASH_BITS-1:0] computed_hash;
//logic                 is_all_zero;

//// XOR all four bytes of lower 32 bits
//assign hash_xor_result = in_data[7:0]   ^ in_data[15:8]  ^
//                          in_data[23:16] ^ in_data[31:24];

//// Take only bottom HASH_BITS from the XOR result
//assign computed_hash   = hash_xor_result[HASH_BITS-1:0];

//// Zero check - all 64 bits must be zero
//assign is_all_zero     = (in_data == 64'h0);

//// ================================================================
//// STAGE 1 - Capture input, compute hash, detect zero
//// ================================================================
//always_ff @(posedge clk or negedge rst_n) begin
//    if (!rst_n) begin
//        s1_valid        <= 1'b0;
//        s1_data         <= '0;
//        s1_strb         <= '0;
//        s1_last         <= 1'b0;
//        s1_is_zero      <= 1'b0;
//        s1_hash_idx     <= '0;
//        s1_position     <= 16'd0;
//        stream_position <= 16'd0;
//        zero_run_count  <= 16'd0;
//        in_zero_run     <= 1'b0;
//    end else if (!pipeline_stall) begin
//        if (in_valid) begin
//            s1_data     <= in_data;
//            s1_strb     <= in_strb;
//            s1_last     <= in_last;
//            s1_is_zero  <= is_all_zero;
//            s1_hash_idx <= computed_hash;
//            s1_position <= stream_position;
//            s1_valid    <= 1'b1;
//            stream_position <= stream_position + 1;
//            if (is_all_zero) begin
//                zero_run_count <= zero_run_count + 1;
//                in_zero_run    <= 1'b1;
//            end else begin
//                zero_run_count <= 16'd0;
//                in_zero_run    <= 1'b0;
//            end
//        end else begin
//            s1_valid <= 1'b0;
//        end
//    end
//end

//// ================================================================
//// STAGE 2 - Hash table lookup and match decision
//// ================================================================
//always_ff @(posedge clk or negedge rst_n) begin : stage2_block
//    integer idx;
//    if (!rst_n) begin
//        s2_valid        <= 1'b0;
//        s2_data         <= '0;
//        s2_strb         <= '0;
//        s2_last         <= 1'b0;
//        s2_is_zero      <= 1'b0;
//        s2_is_match     <= 1'b0;
//        s2_match_offset <= 16'd0;
//        s2_zero_count   <= 16'd0;
//        for (idx = 0; idx < HASH_ENTRIES; idx = idx + 1) begin
//            hash_table_valid[idx] <= 1'b0;
//            hash_table_data[idx]  <= 32'd0;
//            hash_table_pos[idx]   <= 16'd0;
//        end
//    end else if (!pipeline_stall) begin
//        if (s1_valid) begin
//            s2_data       <= s1_data;
//            s2_strb       <= s1_strb;
//            s2_last       <= s1_last;
//            s2_is_zero    <= s1_is_zero;
//            s2_valid      <= 1'b1;
//            s2_zero_count <= zero_run_count;

//            if (!s1_is_zero &&
//                hash_table_valid[s1_hash_idx] &&
//                (hash_table_data[s1_hash_idx] == s1_data[31:0])) begin
//                // Match found in hash table
//                s2_is_match     <= 1'b1;
//                s2_match_offset <= s1_position - hash_table_pos[s1_hash_idx];
//            end else begin
//                s2_is_match     <= 1'b0;
//                s2_match_offset <= 16'd0;
//            end

//            // Update hash table with new entry
//            if (!s1_is_zero) begin
//                hash_table_data[s1_hash_idx]  <= s1_data[31:0];
//                hash_table_pos[s1_hash_idx]   <= s1_position;
//                hash_table_valid[s1_hash_idx] <= 1'b1;
//            end
//        end else begin
//            s2_valid <= 1'b0;
//        end
//    end
//end

//// ================================================================
//// STAGE 3 - Token formation
//// Priority: ZERO_RLE first, then MATCH, then LITERAL
//// ================================================================
//always_ff @(posedge clk or negedge rst_n) begin
//    if (!rst_n) begin
//        s3_valid        <= 1'b0;
//        s3_data         <= '0;
//        s3_strb         <= '1;
//        s3_last         <= 1'b0;
//        stat_bytes_in   <= 32'd0;
//        stat_bytes_out  <= 32'd0;
//    end else if (!pipeline_stall) begin
//        if (s2_valid) begin
//            // Count input bytes regardless of compression type
//            stat_bytes_in <= stat_bytes_in + (DATA_WIDTH / 8);
//            s3_strb       <= s2_strb;
//            s3_last       <= s2_last;
//            s3_valid      <= 1'b1;

//            if (s2_is_zero) begin
//                // ZERO_RLE path
//                // Only emit a token for the FIRST zero in a run
//                // Subsequent zeros are suppressed (output suppressed)
//                if (s2_zero_count == 16'd0) begin
//                    // First zero - emit token
//                    // Format: [63:62]=01(type) [61:16]=unused [15:0]=count
//                    s3_data <= {TYPE_ZERO_RLE,
//                                {(DATA_WIDTH-18){1'b0}},
//                                16'd1};
//                    s3_valid       <= 1'b1;
//                    stat_bytes_out <= stat_bytes_out + (DATA_WIDTH/8);
//                end else begin
//                    // Subsequent zeros - suppress output beat
//                    s3_valid <= 1'b0;
//                    // bytes_out not incremented = compression happening
//                end

//            end else if (s2_is_match) begin
//                // MATCH path
//                // Format: [63:62]=10(type) [61:48]=unused
//                //         [47:32]=offset [31:16]=length [15:0]=unused
//                s3_data <= {TYPE_MATCH,
//                            {(DATA_WIDTH-34){1'b0}},
//                            s2_match_offset,
//                            16'd4};
//                s3_valid       <= 1'b1;
//                stat_bytes_out <= stat_bytes_out + (DATA_WIDTH/8);

//            end else begin
//                // LITERAL path - no compression possible
//                // Format: [63:62]=00(type) [61:0]=raw data (lower bits)
//                s3_data <= {TYPE_LITERAL, s2_data[DATA_WIDTH-3:0]};
//                s3_valid       <= 1'b1;
//                stat_bytes_out <= stat_bytes_out + (DATA_WIDTH/8);
//            end

//        end else begin
//            s3_valid <= 1'b0;
//        end
//    end
//end

//// ================================================================
//// OUTPUT ASSIGNMENTS
//// ================================================================
//assign out_data  = s3_data;
//assign out_strb  = s3_strb;
//assign out_valid = s3_valid;
//assign out_last  = s3_last;

//// ================================================================
//// SIMULATION DISPLAY
//// ================================================================
//`ifdef SIMULATION
//always @(posedge clk) begin
//    if (out_valid && out_ready) begin
//        case (out_data[DATA_WIDTH-1:DATA_WIDTH-2])
//            TYPE_LITERAL:
//                $display("[COMP] t=%0t LITERAL  raw=0x%016h",
//                         $time, out_data);
//            TYPE_ZERO_RLE:
//                $display("[COMP] t=%0t ZERO_RLE count=%0d",
//                         $time, out_data[15:0]);
//            TYPE_MATCH:
//                $display("[COMP] t=%0t MATCH    offset=%0d len=%0d",
//                         $time, out_data[31:16], out_data[15:0]);
//            default:
//                $display("[COMP] t=%0t UNKNOWN  0x%016h",
//                         $time, out_data);
//        endcase
//    end
//end
//`endif

//endmodule
`timescale 1ns / 1ps
`define SIMULATION

module compressor_axi #(
    parameter integer DATA_WIDTH    = 64,
    parameter integer STRB_WIDTH    = DATA_WIDTH / 8,
    parameter integer HASH_ENTRIES  = 32,
    parameter integer HISTORY_DEPTH = 256
)(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic [DATA_WIDTH-1:0]  in_data,
    input  logic [STRB_WIDTH-1:0]  in_strb,
    input  logic                    in_valid,
    input  logic                    in_last,
    output logic                    in_ready,

    output logic [DATA_WIDTH-1:0]  out_data,
    output logic [STRB_WIDTH-1:0]  out_strb,
    output logic                    out_valid,
    output logic                    out_last,
    input  logic                    out_ready,

    output logic [31:0]            stat_bytes_in,
    output logic [31:0]            stat_bytes_out
);

// ================================================================
// LOCALPARAMS
// ================================================================
localparam integer HASH_BITS = $clog2(HASH_ENTRIES);

localparam logic [1:0] TYPE_LITERAL  = 2'b00;
localparam logic [1:0] TYPE_ZERO_RLE = 2'b01;
localparam logic [1:0] TYPE_MATCH    = 2'b10;

// ================================================================
// STAGE 1 REGISTERS
// ================================================================
logic [DATA_WIDTH-1:0]   s1_data;
logic [STRB_WIDTH-1:0]   s1_strb;
logic                    s1_valid;
logic                    s1_last;
logic                    s1_is_zero;
logic                    s1_is_first_zero; // FIX: Explicitly tracks first zero item
logic [HASH_BITS-1:0]    s1_hash_idx;
logic [15:0]             s1_position;

// ================================================================
// STAGE 2 REGISTERS
// ================================================================
logic [DATA_WIDTH-1:0]   s2_data;
logic [STRB_WIDTH-1:0]   s2_strb;
logic                    s2_valid;
logic                    s2_last;
logic                    s2_is_zero;
logic                    s2_is_first_zero; // FIX: Pipelined tracking flag
logic                    s2_is_match;
logic [15:0]             s2_match_offset;
logic [15:0]             s2_zero_count;

// ================================================================
// STAGE 3 OUTPUT REGISTERS
// ================================================================
logic [DATA_WIDTH-1:0]   s3_data;
logic [STRB_WIDTH-1:0]   s3_strb;
logic                    s3_valid;
logic                    s3_last;

// ================================================================
// HASH TABLE
// ================================================================
logic [DATA_WIDTH-1:0]   hash_table_data  [0:HASH_ENTRIES-1]; // FIX: Widened to full 64-bit width
logic [15:0]             hash_table_pos   [0:HASH_ENTRIES-1];
logic                    hash_table_valid [0:HASH_ENTRIES-1];

// ================================================================
// COUNTERS
// ================================================================
logic [15:0]             stream_position;
logic [15:0]             zero_run_count;
logic                    in_zero_run;

// ================================================================
// STALL LOGIC
// ================================================================
logic pipeline_stall;
assign pipeline_stall = s3_valid && !out_ready;
assign in_ready       = !pipeline_stall;

// ================================================================
// HASH COMPUTATION - STAGE 1
// ================================================================
logic [7:0]           hash_xor_result;
logic [HASH_BITS-1:0] computed_hash;
logic                 is_all_zero;

assign hash_xor_result = in_data[7:0]   ^ in_data[15:8]  ^
                         in_data[23:16] ^ in_data[31:24];

assign computed_hash   = hash_xor_result[HASH_BITS-1:0];
assign is_all_zero     = (in_data == '0);

// ================================================================
// STAGE 1 - Capture input, compute hash, detect zero
// ================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_valid         <= 1'b0;
        s1_data          <= '0;
        s1_strb          <= '0;
        s1_last          <= 1'b0;
        s1_is_zero       <= 1'b0;
        s1_is_first_zero <= 1'b0;
        s1_hash_idx      <= '0;
        s1_position      <= 16'd0;
        stream_position  <= 16'd0;
        zero_run_count   <= 16'd0;
        in_zero_run      <= 1'b0;
    end else if (!pipeline_stall) begin
        if (in_valid) begin
            s1_data         <= in_data;
            s1_strb         <= in_strb;
            s1_last         <= in_last;
            s1_is_zero      <= is_all_zero;
            s1_hash_idx     <= computed_hash;
            s1_position     <= stream_position;
            s1_valid        <= 1'b1;
            stream_position <= stream_position + 1;
            
            if (is_all_zero) begin
                s1_is_first_zero <= !in_zero_run;
                zero_run_count   <= in_last ? 16'd0 : (zero_run_count + 1);
                in_zero_run      <= !in_last; // Terminate zero run tracking if packet ends
            end else begin
                s1_is_first_zero <= 1'b0;
                zero_run_count   <= 16'd0;
                in_zero_run      <= 1'b0;
            end
        end else begin
            s1_valid <= 1'b0;
        end
    end
end

// ================================================================
// STAGE 2 - Hash table lookup and match decision
// ================================================================
always_ff @(posedge clk or negedge rst_n) begin : stage2_block
    integer idx;
    if (!rst_n) begin
        s2_valid         <= 1'b0;
        s2_data          <= '0;
        s2_strb          <= '0;
        s2_last          <= 1'b0;
        s2_is_zero       <= 1'b0;
        s2_is_first_zero <= 1'b0;
        s2_is_match      <= 1'b0;
        s2_match_offset  <= 16'd0;
        s2_zero_count    <= 16'd0;
        for (idx = 0; idx < HASH_ENTRIES; idx = idx + 1) begin
            hash_table_valid[idx] <= 1'b0;
            hash_table_data[idx]  <= '0;
            hash_table_pos[idx]   <= 16'd0;
        end
    end else if (!pipeline_stall) begin
        if (s1_valid) begin
            s2_data          <= s1_data;
            s2_strb          <= s1_strb;
            s2_last          <= s1_last;
            s2_is_zero       <= s1_is_zero;
            s2_is_first_zero <= s1_is_first_zero;
            s2_valid         <= 1'b1;
            s2_zero_count    <= zero_run_count;

            if (!s1_is_zero &&
                hash_table_valid[s1_hash_idx] &&
                (hash_table_data[s1_hash_idx] == s1_data)) begin // FIX: Full width match evaluation
                s2_is_match     <= 1'b1;
                s2_match_offset <= s1_position - hash_table_pos[s1_hash_idx];
            end else begin
                s2_is_match     <= 1'b0;
                s2_match_offset <= 16'd0;
            end

            // Update hash table with new entry
            if (!s1_is_zero) begin
                hash_table_data[s1_hash_idx]  <= s1_data; // FIX: Full width stored safely
                hash_table_pos[s1_hash_idx]   <= s1_position;
                hash_table_valid[s1_hash_idx] <= 1'b1;
            end
        end else begin
            s2_valid <= 1'b0;
        end
    end
end

// ================================================================
// STAGE 3 - Token formation
// ================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s3_valid        <= 1'b0;
        s3_data         <= '0;
        s3_strb         <= '1;
        s3_last         <= 1'b0;
        stat_bytes_in   <= 32'd0;
        stat_bytes_out  <= 32'd0;
    end else if (!pipeline_stall) begin
        if (s2_valid) begin
            stat_bytes_in <= stat_bytes_in + (DATA_WIDTH / 8);
            s3_strb       <= s2_strb;
            s3_last       <= s2_last;
            s3_valid      <= 1'b1;

            if (s2_is_zero) begin
                // FIX: Force token out if it's the first zero OR if it contains the TLAST flag
                if (s2_is_first_zero || s2_last) begin
                    s3_data <= {TYPE_ZERO_RLE,
                                {(DATA_WIDTH-18){1'b0}},
                                16'd1};
                    s3_valid       <= 1'b1;
                    stat_bytes_out <= stat_bytes_out + (DATA_WIDTH/8);
                end else begin
                    s3_valid       <= 1'b0; // Suppress duplicate intermediate zeros safely
                end

            end else if (s2_is_match) begin
                s3_data <= {TYPE_MATCH,
                            {(DATA_WIDTH-34){1'b0}},
                            s2_match_offset,
                            16'd4};
                s3_valid       <= 1'b1;
                stat_bytes_out <= stat_bytes_out + (DATA_WIDTH/8);

            end else begin
                s3_data <= {TYPE_LITERAL, s2_data[DATA_WIDTH-3:0]};
                s3_valid       <= 1'b1;
                stat_bytes_out <= stat_bytes_out + (DATA_WIDTH/8);
            end

        end else begin
            s3_valid <= 1'b0;
        end
    end
end

// ================================================================
// OUTPUT ASSIGNMENTS
// ================================================================
assign out_data  = s3_data;
assign out_strb  = s3_strb;
assign out_valid = s3_valid;
assign out_last  = s3_last;

// ================================================================
// SIMULATION DISPLAY
// ================================================================
`ifdef SIMULATION
always @(posedge clk) begin
    if (out_valid && out_ready) begin
        case (out_data[DATA_WIDTH-1:DATA_WIDTH-2])
            TYPE_LITERAL:
                $display("[COMP] t=%0t LITERAL  raw=0x%016h",
                         $time, out_data);
            TYPE_ZERO_RLE:
                $display("[COMP] t=%0t ZERO_RLE count=%0d last=%b",
                         $time, out_data[15:0], out_last);
            TYPE_MATCH:
                $display("[COMP] t=%0t MATCH    offset=%0d len=%0d",
                         $time, out_data[31:16], out_data[15:0]);
            default:
                $display("[COMP] t=%0t UNKNOWN  0x%016h",
                         $time, out_data);
        endcase
    end
end
`endif

endmodule



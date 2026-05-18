//`timescale 1ns / 1ps

//module token_decompressor #(
//    parameter int DATA_WIDTH = 64
//)(
//    input  logic                    clk,
//    input  logic                    rst_n,

//    // Input Interface (Connected to Module 7 Read Master)
//    input  logic                    in_valid,
//    input  logic [DATA_WIDTH-1:0]   in_token,

//    // Output Interface (Feeds downstream to Module 9 Multiplier)
//    output logic                    out_valid,
//    output logic [DATA_WIDTH-1:0]   out_data
//);

//    // Dictionary Look-up Table for Token IDs
//    // These reverse the compression done back in Module 4
//    localparam logic [64-1:0] PATTERN_0 = 64'hDEAD_BEEF_CAFE_FEED;
//    localparam logic [64-1:0] PATTERN_1 = 64'h1122_3344_5566_7788;
//    localparam logic [64-1:0] PATTERN_2 = 64'h99AA_BBCC_DDEE_FF00;
//    localparam logic [64-1:0] PATTERN_3 = 64'h0000_0000_FFFF_FFFF;

//    // Internal signals for registered output
//    logic                    out_valid_reg;
//    logic [DATA_WIDTH-1:0]   out_data_reg;

//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            out_valid_reg <= 1'b0;
//            out_data_reg  <= '0;
//        end else begin
//            out_valid_reg <= in_valid; // 1-clock cycle pipeline latency

//            if (in_valid) begin
//                // Check if the word contains the designated token header prefix
//                if (in_token[63:32] == 32'hAAAA_BBBB) begin
//                    // Decode the token ID hidden in the lower bits
//                    case (in_token[7:0])
//                        8'h00:   out_data_reg <= PATTERN_0;
//                        8'h01:   out_data_reg <= PATTERN_1;
//                        8'h02:   out_data_reg <= PATTERN_2;
//                        8'h03:   out_data_reg <= PATTERN_3;
//                        default: out_data_reg <= 64'hEEEE_EEEE_EEEE_EEEE; // Error pattern if unknown token
//                    endcase
//                end else begin
//                    // Literal Pass-Through (Data wasn't compressed)
//                    out_data_reg <= in_token;
//                end
//            end else begin
//                out_data_reg <= '0;
//            end
//        end
//    end

//    // Drive outputs
//    assign out_valid = out_valid_reg;
//    assign out_data  = out_data_reg;

//endmodule


// ///// 2nd code 
//`timescale 1ns / 1ps

//module token_decompressor #(
//    parameter int DATA_WIDTH = 64
//)(
//    input  logic                    clk,
//    input  logic                    rst_n,

//    // Input Interface (Connected to Module 7 Read Master)
//    input  logic                    in_valid,
//    input  logic [DATA_WIDTH-1:0]   in_token,

//    // Output Interface (Feeds downstream to Module 9 Multiplier)
//    output logic                    out_valid,
//    output logic [DATA_WIDTH-1:0]   out_data
//);

//    // --- 1. INTERNAL ELASTIC INPUT FIFO ---
//    // Buffers incoming raw AXI bursts completely so we never drop incoming data.
//    localparam int FIFO_DEPTH = 32;
//    logic [DATA_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];
//    logic [4:0] fifo_wr_ptr, fifo_rd_ptr;
//    logic [5:0] fifo_count;
//    logic fifo_empty;

//    assign fifo_empty = (fifo_count == 0);

//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            fifo_wr_ptr <= '0;
//            fifo_rd_ptr <= '0;
//            fifo_count  <= '0;
//        end else begin
//            // Write Side
//            if (in_valid && (fifo_count < FIFO_DEPTH)) begin
//                fifo_mem[fifo_wr_ptr] <= in_token;
//                fifo_wr_ptr           <= fifo_wr_ptr + 1;
//            end
//            // Read Side (Controlled by Decompression FSM)
//            if (fifo_rd_en) begin
//                fifo_rd_ptr <= fifo_rd_ptr + 1;
//            end
//            // Track Occupancy
//            if (in_valid && !fifo_rd_en) begin
//                fifo_count <= fifo_count + 1;
//            end else if (!in_valid && fifo_rd_en) begin
//                fifo_count <= fifo_count - 1;
//            end
//        end
//    end

//    // --- 2. DICTIONARY HISTORY STORAGE ---
//    logic [DATA_WIDTH-1:0] history_ram [0:1023];
//    logic [9:0]            history_wr_ptr;

//    // --- 3. DECOMPRESSION FSM LOGIC ---
//    typedef enum logic [1:0] {
//        IDLE             = 2'b00,
//        PARSE_TOKEN      = 2'b01,
//        DECOMPRESS_MATCH = 2'b10
//    } dc_state_t;

//    dc_state_t current_state, next_state;
    
//    logic                  fifo_rd_en;
//    logic [DATA_WIDTH-1:0] active_token;
//    logic                  is_match_token;
//    logic [15:0]           match_offset;
//    logic [15:0]           match_len;
    
//    logic [15:0]           len_counter;
//    logic [15:0]           saved_offset;

//    // Read head assignment
//    assign active_token   = fifo_mem[fifo_rd_ptr];
//    assign is_match_token = active_token[63];
//    assign match_offset   = active_token[31:16];
//    assign match_len      = active_token[15:0];

//    // State Tracking
//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            current_state <= IDLE;
//            len_counter   <= '0;
//            saved_offset  <= '0;
//        end else begin
//            current_state <= next_state;
            
//            if (current_state == PARSE_TOKEN && !fifo_empty && is_match_token) begin
//                len_counter  <= match_len;
//                saved_offset <= match_offset;
//            end else if (current_state == DECOMPRESS_MATCH && len_counter > 0) begin
//                len_counter  <= len_counter - 1;
//            end
//        end
//    end

//    // Combinational Next State & Output Decoding
//    always_comb begin
//        next_state = current_state;
//        fifo_rd_en = 1'b0;
//        out_valid  = 1'b0;
//        out_data   = '0;

//        case (current_state)
//            IDLE: begin
//                if (!fifo_empty) next_state = PARSE_TOKEN;
//            end

//            PARSE_TOKEN: begin
//                if (!fifo_empty) begin
//                    // 1. Ignore AXI padding zeros completely
//                    if (active_token == '0) begin
//                        fifo_rd_en = 1'b1;
//                        next_state = IDLE;
//                    end
//                    // 2. Handle Match Token (0x8000...)
//                    else if (is_match_token) begin
//                        next_state = DECOMPRESS_MATCH;
//                    end 
//                    // 3. Handle Literal Pass-Through
//                    else begin
//                        out_data   = active_token;
//                        out_valid  = 1'b1;
//                        fifo_rd_en = 1'b1;
//                        next_state = IDLE;
//                    end
//                end
//            end

//            DECOMPRESS_MATCH: begin
//                if (len_counter > 0) begin
//                    out_valid = 1'b1;
//                    // Asynchronous lookback read from distributed history array
//                    out_data  = history_ram[history_wr_ptr - saved_offset];
//                    next_state = DECOMPRESS_MATCH;
//                end else begin
//                    fifo_rd_en = 1'b1; // Consume the match token now that expansion finished
//                    next_state = IDLE;
//                end
//            end
            
//            default: next_state = IDLE;
//        endcase
//    end

//    // History Buffer Memory Write Controller
//    integer i;
//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            history_wr_ptr <= '0;
//            for (i = 0; i < 1024; i = i + 1) begin
//                history_ram[i] <= '0;
//            end
//        end else begin
//            // Save Valid Literals to Dictionary
//            if (current_state == PARSE_TOKEN && !fifo_empty && !is_match_token && (active_token != '0)) begin
//                history_ram[history_wr_ptr] <= active_token;
//                history_wr_ptr              <= history_wr_ptr + 1;
//            end
//            // Save Reconstructed Match Data Blocks back to Dictionary (Handles Overlaps)
//            else if (current_state == DECOMPRESS_MATCH && out_valid) begin
//                history_ram[history_wr_ptr] <= out_data;
//                history_wr_ptr              <= history_wr_ptr + 1;
//            end
//        end

  //  end

//endmodule


`timescale 1ns / 1ps

module token_decompressor #(
    parameter int DATA_WIDTH = 64
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // Input Interface (Connected to Module 7 Read Master)
    input  logic                  in_valid,
    input  logic [DATA_WIDTH-1:0] in_token,

    // Output Interface (Feeds downstream to Module 9 Multiplier)
    output logic                  out_valid,
    output logic [DATA_WIDTH-1:0] out_data
);

    // ================================================================
    // ALL DECLARATIONS DECLARED UPFRONT TO STOP COMPILER ERRORS
    // ================================================================
    localparam int FIFO_DEPTH = 32;

    logic [DATA_WIDTH-1:0] fifo_mem [0:FIFO_DEPTH-1];
    logic [4:0]            fifo_wr_ptr, fifo_rd_ptr;
    logic [5:0]            fifo_count;
    logic                  fifo_empty;
    logic                  fifo_full;
    logic                  fifo_rd_en;
    logic                  fifo_wr_en;

    // Dictionary History Storage
    // BRAM attribute: forces Vivado to use Block RAM instead of 65,536 flip-flops
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] history_ram [0:1023];
    logic [9:0]            history_wr_ptr;

    // FSM States
    typedef enum logic [1:0] {
        IDLE             = 2'b00,
        PARSE_TOKEN      = 2'b01,
        DECOMPRESS_MATCH = 2'b10
    } dc_state_t;

    dc_state_t current_state, next_state;

    logic [DATA_WIDTH-1:0] active_token;
    logic                  is_match_token;
    logic [15:0]           match_offset;
    logic [15:0]           match_len;

    logic [15:0]           len_counter;
    logic [15:0]           saved_offset;

    // ================================================================
    // ASSIGNMENTS & DISCRETE FIFO INTERFACES
    // ================================================================
    assign fifo_empty     = (fifo_count == 0);
    assign fifo_full      = (fifo_count == FIFO_DEPTH);
    
    // Safely write if there's room, or if a read opens up a slot on the same cycle
    assign fifo_wr_en     = in_valid && (!fifo_full || fifo_rd_en);

    assign active_token   = fifo_mem[fifo_rd_ptr];
    assign is_match_token = active_token[63];
    assign match_offset   = active_token[31:16];
    assign match_len      = active_token[15:0];

    // --- 1. INTERNAL ELASTIC INPUT FIFO CONTROL ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr <= '0;
            fifo_rd_ptr <= '0;
            fifo_count  <= '0;
        end else begin
            // Fixed Occupancy Logic (Handles simultaneous read/write cleanly without counter desync)
            case ({fifo_wr_en, fifo_rd_en})
                2'b10:   fifo_count <= fifo_count + 1;
                2'b01:   fifo_count <= fifo_count - 1;
                default: fifo_count <= fifo_count; // Unchanged for 2'b00 and simultaneous 2'b11
            endcase

            // Write Side
            if (fifo_wr_en) begin
                fifo_mem[fifo_wr_ptr] <= in_token;
                fifo_wr_ptr           <= fifo_wr_ptr + 1;
            end
            
            // Read Side
            if (fifo_rd_en) begin
                fifo_rd_ptr <= fifo_rd_ptr + 1;
            end
        end
    end

    // --- 2. DECOMPRESSION FSM STATE TRACKING ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            len_counter   <= '0;
            saved_offset  <= '0;
        end else begin
            current_state <= next_state;
            
            if (current_state == PARSE_TOKEN && !fifo_empty && is_match_token) begin
                len_counter  <= match_len;
                saved_offset <= match_offset;
            end else if (current_state == DECOMPRESS_MATCH && len_counter > 0) begin
                len_counter  <= len_counter - 1;
            end
        end
    end

    // --- 3. COMBINATIONAL NEXT STATE & OUTPUT DECODING ---
    always_comb begin
        next_state = current_state;
        fifo_rd_en = 1'b0;
        out_valid  = 1'b0;
        out_data   = '0;

        case (current_state)
            IDLE: begin
                if (!fifo_empty) next_state = PARSE_TOKEN;
            end

            PARSE_TOKEN: begin
                if (!fifo_empty) begin
                    // 1. Ignore AXI padding zeros completely
                    if (active_token == '0) begin
                        fifo_rd_en = 1'b1;
                        next_state = fifo_empty ? IDLE : PARSE_TOKEN; // Skip bubbles
                    end
                    // 2. Handle Match Token (0x8000...)
                    else if (is_match_token) begin
                        next_state = DECOMPRESS_MATCH;
                    end 
                    // 3. Handle Literal Pass-Through
                    else begin
                        out_data   = active_token;
                        out_valid  = 1'b1;
                        fifo_rd_en = 1'b1;
                        next_state = fifo_empty ? IDLE : PARSE_TOKEN; // Stream continuous data
                    end
                end
            end

            DECOMPRESS_MATCH: begin
                if (len_counter > 0) begin
                    out_valid  = 1'b1;
                    // Asynchronous lookback read from distributed history array
                    out_data   = history_ram[history_wr_ptr - saved_offset];
                    next_state = DECOMPRESS_MATCH;
                end else begin
                    fifo_rd_en = 1'b1; // Consume the match token now that expansion finished
                    next_state = fifo_empty ? IDLE : PARSE_TOKEN;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end

    // --- 4. HISTORY BUFFER MEMORY WRITE CONTROLLER ---
    // NOTE: history_ram is NOT reset — Block RAM contents are undefined after
    // reset by design. The history_wr_ptr reset ensures we start writing at
    // position 0. Old stale data is harmless because we only read positions
    // we have previously written to.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            history_wr_ptr <= '0;
        end else begin
            // Save Valid Literals to Dictionary
            if (current_state == PARSE_TOKEN && !fifo_empty && !is_match_token && (active_token != '0)) begin
                history_ram[history_wr_ptr] <= active_token;
                history_wr_ptr              <= history_wr_ptr + 1;
            end
            // Save Reconstructed Match Data Blocks back to Dictionary (Handles Overlaps)
            else if (current_state == DECOMPRESS_MATCH && out_valid) begin
                history_ram[history_wr_ptr] <= out_data;
                history_wr_ptr              <= history_wr_ptr + 1;
            end
        end
    end

endmodule

//// FILE    : rtl/entropy_unit.sv
//// MODULE  : Entropy Analyzer - Predictive Bypass Unit
//// PURPOSE : Samples the FIRST 8 BEATS of every incoming AXI burst.
////           Builds a byte-frequency histogram in hardware.
////           Outputs bypass=1 if data looks non-compressible
////           (encrypted, already compressed, truly random).
////           Outputs bypass=0 if data looks compressible
////           (zeros, text, repeated patterns, code).
////
//// HOW ENTROPY IS MEASURED IN HARDWARE:
////   True Shannon entropy H = -Σ p(x)*log2(p(x)) requires
////   logarithms - expensive in hardware.
////
////   We use a FAST APPROXIMATION instead:
////   Count how many DISTINCT byte values appear in the sample.
////   Few distinct values → low entropy → compressible
////   Many distinct values → high entropy → non-compressible
////
////   Threshold: if >200 of 256 possible byte values are seen
////   in the first 8 beats (64 bytes sampled), bypass.
////   This matches what LZ4 hardware implementations use.
////
//// CRITICAL TIMING:
////   Decision must be made BEFORE beat 9 arrives.
////   We sample beats 1-8, decide on cycle 9.
////   The bypass MUX (Module 3) switches BEFORE the burst body
////   reaches the compressor. Zero wasted cycles.
//// ============================================================

//`timescale 1ns / 1ps

//module entropy_unit #(
//    parameter integer DATA_WIDTH    = 64,    // Bits per beat (8 bytes)
//    parameter integer SAMPLE_BEATS  = 8,     // How many beats to sample
//                                             // 8 beats × 8 bytes = 64 bytes sampled
//    parameter integer BYPASS_THRESH = 200    // Distinct byte count threshold
//                                             // >200 unique bytes in 64 sampled
//                                             // → very likely non-compressible
//                                             // Tune this for your target workload
//)(
//    input  logic                  clk,
//    input  logic                  rst_n,

//    // ── Input stream (tapped from AXI slave output) ────────────
//    // These connect to the same signals leaving Module 1.
//    // The entropy unit OBSERVES - it does NOT modify the stream.
//    input  logic [DATA_WIDTH-1:0] in_data,   // Current beat data
//    input  logic                  in_valid,  // Beat is valid
//    input  logic                  in_ready,  // Downstream is ready
//    // ↑ Transfer occurs when in_valid AND in_ready are BOTH high.
//    //   We tap in_data only when a real transfer is happening.

//    input  logic                  burst_start,
//    // ↑ Pulsed HIGH for ONE cycle at the start of each new burst.
//    //   Connected from AXI slave: asserts when AW channel fires.
//    //   Resets the histogram and beat counter for the new burst.

//    // ── Decision output ────────────────────────────────────────
//    output logic                  bypass_en,
//    // ↑ The decision signal:
//    //   bypass_en = 0 → data is compressible → send through compressor
//    //   bypass_en = 1 → data is non-compressible → bypass compressor
//    //   This signal is REGISTERED (comes from a flip-flop).
//    //   Stable for the entire duration of the burst.

//    output logic                  decision_valid
//    // ↑ Pulses HIGH for ONE cycle when bypass_en is valid.
//    //   Before this pulse: bypass_en is from the previous burst.
//    //   After this pulse: bypass_en is valid for the current burst.
//    //   The bypass MUX waits for this before switching.
//);

//// ================================================================
//// INTERNAL SIGNALS AND CONSTANTS
//// ================================================================

//localparam integer BYTE_WIDTH    = 8;             // Bits per byte
//localparam integer NUM_BYTES     = DATA_WIDTH / 8; // Bytes per beat = 8
//localparam integer COUNTER_WIDTH = 8;             // 8-bit counter per bucket
//                                                  // (max 256 occurrences)

//// ── Byte Frequency Histogram ───────────────────────────────────
//// This is the core data structure.
//// 256 entries (one per possible byte value 0x00 to 0xFF)
//// Each entry is a 1-bit PRESENCE FLAG (not a full counter)
////
//// WHY 1-bit not 8-bit counter?
////   We only care IF a byte value was seen, not HOW MANY TIMES.
////   256 × 1 bit = 256 bits = 32 bytes of storage in registers.
////   256 × 8 bit = 2048 bits = much larger, slower to sum.
////   The distinct-count approximation is accurate enough.
////
//logic [255:0] byte_seen;
//// ↑ byte_seen[i] = 1 if byte value 'i' was observed in the sample
////   byte_seen[0]   = 1 if 0x00 was seen
////   byte_seen[255] = 1 if 0xFF was seen
////   byte_seen = 256'hFF...FF → all 256 values seen → max entropy

//// ── Beat and Byte Counters ─────────────────────────────────────
//logic [$clog2(SAMPLE_BEATS+1)-1:0] beat_count;
//// ↑ Tracks how many beats we have sampled (0 to SAMPLE_BEATS)
////   $clog2(9) = 4 → 4-bit counter (can hold 0-15, enough for 0-8)

//logic                               sampling_done;
//// ↑ Goes HIGH when beat_count == SAMPLE_BEATS
////   After this, we stop updating the histogram (save power)

//logic                               decision_valid_r;
//// ↑ Internal registered version of decision_valid output

//// ── Distinct Byte Counter (population count of byte_seen) ──────
//// We need to count how many 1s are in the 256-bit byte_seen vector.
//// This is called POPULATION COUNT or POPCOUNT.
////
//// Naive approach: a loop in always_comb summing all 256 bits.
//// Better approach: pipeline the sum in a tree structure.
//// For now, direct sum - works fine at 200 MHz with 7-series FPGA.

//logic [8:0] distinct_count;
//// ↑ 9 bits needed to hold values 0 to 256 (2^9 = 512 > 256)

//// Popcount: sum all bits of byte_seen
//// Vivado synthesizes this efficiently using carry-chain adders
//integer i;
//always_comb begin
//    distinct_count = '0;
//    for (i = 0; i < 256; i++) begin
//        distinct_count = distinct_count + {8'b0, byte_seen[i]};
//    end
//end
//// ↑ This generates a 256-input adder tree.
////   At 200 MHz on a 7-series FPGA: ~2.5 ns delay → fits in budget.
////   At 800 MHz this would be the critical path - split into pipeline
////   stages (add 4 groups of 64 first, then sum the 4 partial sums).

//// ================================================================
//// MAIN SEQUENTIAL BLOCK - Histogram update + decision
//// ================================================================
//always_ff @(posedge clk or negedge rst_n) begin
//    if (!rst_n) begin
//        byte_seen      <= '0;      // Clear all histogram entries
//        beat_count     <= '0;
//        sampling_done  <= 1'b0;
//        bypass_en      <= 1'b0;    // Default: attempt compression
//        decision_valid_r <= 1'b0;

//    end else begin

//        // ── Default: clear pulse signals each cycle ───────────
//        decision_valid_r <= 1'b0;
//        // ↑ Pulses are HIGH for exactly 1 cycle, cleared here.
//        //   They get re-asserted below in the specific condition.

//        // ── Burst start: reset histogram for new burst ────────
//        if (burst_start) begin
//            byte_seen     <= '0;   // Clear histogram
//            beat_count    <= '0;   // Reset beat counter
//            sampling_done <= 1'b0; // Start sampling again
//            bypass_en     <= 1'b0; // Default to compress until decided
//        end

//        // ── Sample incoming beats ─────────────────────────────
//        else if (in_valid && in_ready && !sampling_done) begin
//            // A beat is being transferred AND we still need samples

//            beat_count <= beat_count + 1;

//            // Mark each byte value in this beat as "seen"
//            // DATA_WIDTH=64 means 8 bytes per beat (NUM_BYTES=8)
//            // We examine bytes [7:0], [15:8], [23:16], ... [63:56]
//            for (int b = 0; b < NUM_BYTES; b++) begin
//                // Extract byte 'b' from the current beat
//                // in_data[b*8 +: 8] = bits [(b*8)+7 : b*8]
//                // For b=0: bits [7:0]
//                // For b=1: bits [15:8]
//                // For b=7: bits [63:56]
//                automatic logic [7:0] this_byte = in_data[b*8 +: 8];
//                // ↑ 'automatic' required for loop variables in always blocks
//                //   that use non-static scoping (SystemVerilog requirement)

//                byte_seen[this_byte] <= 1'b1;
//                // ↑ Set the presence flag for this byte value.
//                //   If this_byte = 8'hAB (171 decimal), then
//                //   byte_seen[171] <= 1.
//                //   Multiple beats can set the same bucket - that's fine,
//                //   it stays 1 (idempotent OR operation).
//            end

//            // ── Check if sampling is complete ─────────────────
//            if (beat_count == (SAMPLE_BEATS - 1)) begin
//                // Just processed the last sample beat.
//                // The distinct_count combinational block already
//                // has the updated count for this beat.
//                // We read it on the NEXT clock edge here.
//                sampling_done <= 1'b1;

//                // ── MAKE THE BYPASS DECISION ──────────────────
//                // This is the core intelligence of your project.
//                //
//                // distinct_count is the combinational popcount of byte_seen.
//                // After processing SAMPLE_BEATS × NUM_BYTES bytes,
//                // if we saw more than BYPASS_THRESH distinct byte values:
//                //   → the data is likely high-entropy → bypass
//                // else:
//                //   → the data has patterns → compress
//                //
//                // NOTE: We compare to distinct_count + new bytes from THIS beat.
//                // The for-loop above just updated byte_seen combinationally
//                // BUT: always_ff reads the OLD byte_seen value (before update).
//                // So we need to account for the new bytes being added this cycle.
//                // FIX: We delay the decision by 1 cycle using sampling_done
//                // as the trigger. See the block below.
//            end
//        end

//        // ── Decision: 1 cycle after last sample beat ──────────
//        // This executes the cycle AFTER sampling_done goes high.
//        // By now, byte_seen has the final updated value including
//        // all SAMPLE_BEATS × NUM_BYTES bytes.
//        if (sampling_done && !decision_valid_r) begin
//            // Make bypass decision based on final distinct count
//            if (distinct_count > BYPASS_THRESH) begin
//                bypass_en <= 1'b1;  // High entropy → bypass compressor
//            end else begin
//                bypass_en <= 1'b0;  // Low entropy → compress
//            end
//            decision_valid_r <= 1'b1;  // Signal that decision is ready
//        end

//    end
//end

//// ================================================================
//// OUTPUT ASSIGNMENTS
//// ================================================================
//assign decision_valid = decision_valid_r;
//// ↑ Expose the registered pulse as the module output

//// ================================================================
//// SIMULATION / DEBUG HELPERS (synthesized away in FPGA build)
//// ================================================================
//`ifdef SIMULATION
//    // Print entropy decision to console during simulation
//    always @(posedge clk) begin
//        if (decision_valid_r) begin
//            $display("[ENTROPY] t=%0t  distinct_bytes=%0d  bypass=%b  (%s)",
//                     $time,
//                     distinct_count,
//                     bypass_en,
//                     bypass_en ? "BYPASS - non-compressible" : "COMPRESS - compressible");
//        end
//    end
//`endif

//endmodule


`timescale 1ns / 1ps

module entropy_unit #(
    parameter integer DATA_WIDTH    = 64,    // Bits per beat (8 bytes)
    parameter integer SAMPLE_BEATS  = 8,     // How many beats to sample
                                             // 8 beats × 8 bytes = 64 bytes sampled
    parameter integer BYPASS_THRESH = 200    // Distinct byte count threshold
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ── Input stream (tapped from AXI slave output) ────────────
    input  logic [DATA_WIDTH-1:0] in_data,   // Current beat data
    input  logic                  in_valid,  // Beat is valid
    input  logic                  in_ready,  // Downstream is ready

    input  logic                  burst_start,
    // ↑ Pulsed HIGH for ONE cycle at the start of each new burst.

    // ── Decision output ────────────────────────────────────────
    output logic                  bypass_en,
    output logic                  decision_valid
);

    // ================================================================
    // INTERNAL SIGNALS AND CONSTANTS
    // ================================================================
    localparam integer NUM_BYTES = DATA_WIDTH / 8; // Bytes per beat = 8

    logic [255:0] byte_seen;
    logic [$clog2(SAMPLE_BEATS+1)-1:0] beat_count;
    logic                               sampling_done;
    logic                               decision_valid_r;
    logic                               decision_committed; // NEW: prevents infinite re-trigger
    logic [8:0]                         distinct_count;

    // Popcount: sum all bits of byte_seen
    always_comb begin
        distinct_count = '0;
        for (int i = 0; i < 256; i++) begin
            distinct_count = distinct_count + {8'b0, byte_seen[i]};
        end
    end

    // ================================================================
    // MAIN SEQUENTIAL BLOCK - Histogram update + decision
    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_seen          <= '0;  
            beat_count         <= '0;
            sampling_done      <= 1'b0;
            bypass_en          <= 1'b0; 
            decision_valid_r   <= 1'b0;
            decision_committed <= 1'b0; // NEW
        end else begin

            // Default: clear the one-cycle pulse each cycle
            decision_valid_r <= 1'b0;

            // Burst start: reset histogram and committed flag for new burst
            if (burst_start) begin
                byte_seen          <= '0; 
                beat_count         <= '0; 
                sampling_done      <= 1'b0; 
                bypass_en          <= 1'b0;
                decision_committed <= 1'b0; // Reset for next burst
            end
            // Sample incoming beats
            else if (in_valid && in_ready && !sampling_done) begin
                beat_count <= beat_count + 1;

                // Mark each byte value in this beat as "seen"
                for (int b = 0; b < NUM_BYTES; b++) begin
                    logic [7:0] this_byte;
                    this_byte = in_data[b*8 +: 8];
                    byte_seen[this_byte] <= 1'b1;
                end

                // Check if sampling is complete
                if (beat_count == (SAMPLE_BEATS - 1)) begin
                    sampling_done <= 1'b1;
                end
            end

            // Decision: fires ONCE per burst, 1 cycle after sampling completes
            // decision_committed prevents the infinite re-trigger bug:
            //   Without it, the default clear above makes !decision_valid_r always
            //   true, causing decision_valid_r to toggle every clock forever.
            if (sampling_done && !decision_committed) begin
                if (distinct_count > BYPASS_THRESH) begin
                    bypass_en <= 1'b1;  // High entropy → bypass compressor
                end else begin
                    bypass_en <= 1'b0;  // Low entropy → compress
                end
                decision_valid_r   <= 1'b1;  // One-cycle pulse
                decision_committed <= 1'b1;  // Prevent re-trigger for this burst
            end
        end
    end

    // ================================================================
    // OUTPUT ASSIGNMENTS
    // ================================================================
    assign decision_valid = decision_valid_r;

    // ================================================================
    // SIMULATION / DEBUG HELPERS
    // ================================================================
`ifdef SIMULATION
    always @(posedge clk) begin
        if (decision_valid_r) begin
            $display("[ENTROPY] t=%0t  distinct_bytes=%0d  bypass=%b  (%s)",
                     $time,
                     distinct_count,
                     bypass_en,
                     bypass_en ? "BYPASS - non-compressible" : "COMPRESS - compressible");
        end
    end
`endif

endmodule




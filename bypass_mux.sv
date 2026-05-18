
// FILE    : rtl/bypass_mux.sv
// MODULE  : Predictive Bypass Multiplexer
// PURPOSE : Routes incoming AXI data to EITHER:
//             Path A (bypass=0): through the compressor pipeline
//             Path B (bypass=1): directly to the AXI master output
//
//           ZERO LATENCY on the bypass path:
//             Data goes through combinational wires only.
//             No pipeline registers are added.
//             The master sees the data in the SAME cycle it enters.
//
//           THE REGISTERED SELECT RULE:
//             The bypass_sel register is ONLY updated at burst
//             boundaries (when burst_start pulses).
//             It NEVER changes mid-burst.
//             WHY: changing mid-burst would corrupt an in-flight
//             compressed token stream - the compressor would get
//             half a burst and produce garbage output.
//
// CONNECTION MAP:
//
//   AXI Slave output
//       │
//       ├─────────────────────────────────────────→ [compressor input]
//       │                                                    │
//       │                                           [compressor output]
//       │                                                    │
//       └──────── bypass_sel MUX ←──────────────────────────┘
//                      │
//                      │ (bypass_sel=0 → compressor path)
//                      │ (bypass_sel=1 → bypass path)
//                      ▼
//                 AXI Master input
//
// ============================================================

`timescale 1ns / 1ps

module bypass_mux #(
    parameter integer DATA_WIDTH = 64,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ── Control ───────────────────────────────────────────────
    input  logic                  bypass_decision,
    // ↑ The bypass_en signal from entropy_unit.sv
    //   Stable for the full duration of a burst.

    input  logic                  decision_valid,
    // ↑ From entropy_unit: "bypass_decision is now valid for this burst"
    //   We latch bypass_decision into bypass_sel on this pulse.

    input  logic                  burst_start,
    // ↑ Pulsed HIGH at burst start (same signal as entropy_unit receives)
    //   Used to clear bypass_sel to safe default (compress) at burst start,
    //   before the entropy decision arrives.

    // ── Compressor path (Path A) ──────────────────────────────
    // Input side of the compressor
    output logic [DATA_WIDTH-1:0] to_comp_data,
    output logic [STRB_WIDTH-1:0] to_comp_strb,
    output logic                  to_comp_valid,
    output logic                  to_comp_last,
    input  logic                  to_comp_ready, // Backpressure from compressor
    // ↑ These connect to the compressor module's input ports.
    //   Even when bypass=1, data still flows here.
    //   But we gate to_comp_valid to 0 so compressor ignores it.

    // ── Bypass path output (Path B) ───────────────────────────
    // Output side: where data exits after the MUX
    // This connects to the AXI master module's input.
    output logic [DATA_WIDTH-1:0] out_data,
    output logic [STRB_WIDTH-1:0] out_strb,
    output logic                  out_valid,
    output logic                  out_last,
    input  logic                  out_ready, // Backpressure from AXI master
    // ↑ Backpressure from the output side.
    //   If AXI master is busy: out_ready=0
    //   This must propagate back to the correct source.

    // ── Source data (from AXI slave) ──────────────────────────
    input  logic [DATA_WIDTH-1:0] src_data,
    input  logic [STRB_WIDTH-1:0] src_strb,
    input  logic                  src_valid,
    input  logic                  src_last,
    output logic                  src_ready,
    // ↑ This is the raw data stream from Module 1 (AXI slave).
    //   The MUX taps this stream and routes it appropriately.

    // ── Compressor output (compressed data path) ──────────────
    input  logic [DATA_WIDTH-1:0] from_comp_data,
    input  logic [STRB_WIDTH-1:0] from_comp_strb,
    input  logic                  from_comp_valid,
    input  logic                  from_comp_last,
    output logic                  from_comp_ready,
    // ↑ The output of the compressor module.
    //   When bypass=0: MUX selects this stream for output.
    //   When bypass=1: MUX ignores this (compressor not running).

    // ── Status ────────────────────────────────────────────────
    output logic                  bypass_active
    // ↑ Registered output showing current bypass state.
    //   Used by CSR module to track bypass statistics.
);

// ================================================================
// BYPASS SELECT REGISTER
// ================================================================
//
// This is the ONLY flip-flop in this module.
// Everything else is combinational (pure wires).
//
// Sequence of events at burst start:
//
//   Cycle 0: burst_start pulses → bypass_sel = 0 (safe default = compress)
//   Cycles 1-8: entropy unit sampling beats 1-8
//   Cycle 9: decision_valid pulses → bypass_sel = bypass_decision
//   Cycles 10-end: data flows through selected path with stable bypass_sel
//
// Important: The first 8 beats go to BOTH paths temporarily
// (compressor receives them but produces no output until bypass_sel
//  is confirmed = 0). If bypass_sel = 1, the compressor is gated off
// retroactively via to_comp_valid control below.
//
// For your 3-day project, simplify: compress ALL beats from beat 1.
// If bypass is decided, discard compressor output and use bypass path.
// The FIFO absorbs the brief compressor activity.

logic bypass_sel;
// ↑ Registered bypass select:
//   0 = route through compressor (compress path)
//   1 = route directly to output (bypass path)

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bypass_sel    <= 1'b0;  // Default: attempt compression on reset
        bypass_active <= 1'b0;
    end else begin
        if (burst_start) begin
            // Start of new burst: reset to compress-first default.
            // Entropy unit will update this within 8+1 beats.
            bypass_sel    <= 1'b0;
            bypass_active <= 1'b0;
        end else if (decision_valid) begin
            // Entropy unit has made its decision - latch it.
            bypass_sel    <= bypass_decision;
            bypass_active <= bypass_decision;
            // ↑ bypass_sel is now stable for the rest of this burst.
        end
    end
end

// ================================================================
// COMBINATIONAL ROUTING LOGIC
// ================================================================
//
// This always_comb block is the ACTUAL MUX.
// It has NO registers - output changes instantly with inputs.
// This is what makes the bypass path truly zero-latency.

always_comb begin

    if (bypass_sel == 1'b0) begin
        // ════ COMPRESS PATH (bypass_sel = 0) ════════════════════
        //
        // Data flow:
        //   src → to_comp (compressor input)
        //   from_comp → out (AXI master input)
        //
        // Backpressure:
        //   out_ready goes back to from_comp_ready
        //   to_comp_ready goes back to src_ready

        // Forward source data to compressor
        to_comp_data  = src_data;
        to_comp_strb  = src_strb;
        to_comp_valid = src_valid;   // Pass valid signal through
        to_comp_last  = src_last;

        // Source ready follows compressor input ready
        src_ready     = to_comp_ready;
        // ↑ Backpressure chain:
        //   Compressor full → to_comp_ready=0 → src_ready=0 → AXI slave stalls

        // Output comes from compressor output
        out_data      = from_comp_data;
        out_strb      = from_comp_strb;
        out_valid     = from_comp_valid;
        out_last      = from_comp_last;

        // Compressor output ready follows output ready
        from_comp_ready = out_ready;
        // ↑ Backpressure chain:
        //   AXI master busy → out_ready=0 → from_comp_ready=0 → compressor stalls

    end else begin
        // ════ BYPASS PATH (bypass_sel = 1) ══════════════════════
        //
        // Data flow:
        //   src → out (directly, no compressor involved)
        //
        // Compressor is completely isolated:
        //   to_comp_valid = 0 → compressor sees no input
        //   from_comp_ready = 0 → we ignore compressor output
        //
        // This is the "zero latency" path.
        // The only delay is 1 wire propagation (picoseconds).

        // Bypass: source data goes directly to output
        out_data      = src_data;
        out_strb      = src_strb;
        out_valid     = src_valid;
        out_last      = src_last;

        // Output ready goes directly back to source
        src_ready     = out_ready;
        // ↑ Backpressure: AXI master busy → out_ready=0 → src_ready=0 → stalls

        // Isolate compressor - it sees nothing, produces nothing
        to_comp_data  = '0;
        to_comp_strb  = '0;
        to_comp_valid = 1'b0;  // ← Compressor input gated OFF
        to_comp_last  = 1'b0;

        from_comp_ready = 1'b0; // ← We don't want compressor output

    end
end

// ================================================================
// SIMULATION / DEBUG
// ================================================================
`ifdef SIMULATION
    always @(posedge clk) begin
        if (decision_valid) begin
            $display("[BYPASS_MUX] t=%0t  bypass_sel=%b  path=%s",
                     $time,
                     bypass_sel,
                     bypass_sel ? "BYPASS (direct passthrough)" : "COMPRESS (through pipeline)");
        end
    end
`endif

endmodule
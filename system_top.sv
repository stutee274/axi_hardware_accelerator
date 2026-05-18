// ============================================================
// FILE    : rtl/system_top.sv
// PURPOSE : Complete 9-module system top.
//           All port names match exactly what each module declares.
//
// Module names as declared in your files:
//   M1: axi4_slave         (clock: aclk / aresetn)
//   M2: entropy_unit       (clock: clk  / rst_n)
//   M3: bypass_mux         (clock: clk  / rst_n)
//   M4: compressor_axi     (clock: clk  / rst_n)
//   M5: fifo               (clock: clk  / rst_n)
//   M6: axi4_master_if     (clock: clk  / rst_n)
//   M7: axi4_read_master   (clock: clk  / rst_n)
//   M8: token_decompressor (clock: clk  / rst_n)
//   M9: hybrid_approx_multiplier (clock: clk / rst_n)
// ============================================================

`timescale 1ns / 1ps

module system_top #(
    parameter integer DATA_WIDTH = 64,
    parameter integer ADDR_WIDTH = 32,
    parameter integer ID_WIDTH   = 4,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8
)(
    // Single clock - M1 uses aclk internally but we drive
    // one clock from outside and connect to both names
    input  logic                   clk,
    input  logic                   rst_n,

    // ── AXI Slave port - CPU/DMA writes here (Module 1) ─────
    input  logic [ID_WIDTH-1:0]    s_awid,
    input  logic [ADDR_WIDTH-1:0]  s_awaddr,
    input  logic [7:0]             s_awlen,
    input  logic [2:0]             s_awsize,
    input  logic [1:0]             s_awburst,
    input  logic                   s_awvalid,
    output logic                   s_awready,
    input  logic [DATA_WIDTH-1:0]  s_wdata,
    input  logic [STRB_WIDTH-1:0]  s_wstrb,
    input  logic                   s_wlast,
    input  logic                   s_wvalid,
    output logic                   s_wready,
    output logic [ID_WIDTH-1:0]    s_bid,
    output logic [1:0]             s_bresp,
    output logic                   s_bvalid,
    input  logic                   s_bready,
    input  logic [ID_WIDTH-1:0]    s_arid,
    input  logic [ADDR_WIDTH-1:0]  s_araddr,
    input  logic [7:0]             s_arlen,
    input  logic [2:0]             s_arsize,
    input  logic [1:0]             s_arburst,
    input  logic                   s_arvalid,
    output logic                   s_arready,
    output logic [ID_WIDTH-1:0]    s_rid,
    output logic [DATA_WIDTH-1:0]  s_rdata,
    output logic [1:0]             s_rresp,
    output logic                   s_rlast,
    output logic                   s_rvalid,
    input  logic                   s_rready,

    // ── AXI Master Write port - Module 6 → DDR ───────────────
    output logic [ID_WIDTH-1:0]    mw_awid,
    output logic [ADDR_WIDTH-1:0]  mw_awaddr,
    output logic [7:0]             mw_awlen,
    output logic [2:0]             mw_awsize,
    output logic [1:0]             mw_awburst,
    output logic                   mw_awvalid,
    input  logic                   mw_awready,
    output logic [DATA_WIDTH-1:0]  mw_wdata,
    output logic [STRB_WIDTH-1:0]  mw_wstrb,
    output logic                   mw_wlast,
    output logic                   mw_wvalid,
    input  logic                   mw_wready,
    input  logic [ID_WIDTH-1:0]    mw_bid,
    input  logic [1:0]             mw_bresp,
    input  logic                   mw_bvalid,
    output logic                   mw_bready,

    // ── AXI Master Read port - Module 7 → DDR ────────────────
    output logic [ID_WIDTH-1:0]    mr_arid,
    output logic [ADDR_WIDTH-1:0]  mr_araddr,
    output logic [7:0]             mr_arlen,
    output logic [2:0]             mr_arsize,
    output logic [1:0]             mr_arburst,
    output logic                   mr_arvalid,
    input  logic                   mr_arready,
    input  logic [ID_WIDTH-1:0]    mr_rid,
    input  logic [DATA_WIDTH-1:0]  mr_rdata,
    input  logic [1:0]             mr_rresp,
    input  logic                   mr_rlast,
    input  logic                   mr_rvalid,
    output logic                   mr_rready,

    // ── Module 7 control ──────────────────────────────────────
    // rd_start triggers a read burst from DDR
    // rd_start_addr is where to read from
    // rd_burst_len is ARLEN (beats minus 1)
    input  logic                   rd_start,
    input  logic [ADDR_WIDTH-1:0]  rd_start_addr,
    input  logic [7:0]             rd_burst_len,
    output logic                   rd_done,

    // ── Module 9 output - final accelerator result ────────────
    output logic [DATA_WIDTH-1:0]  final_result,
    output logic                   final_result_valid,

    // ── Status ────────────────────────────────────────────────
    output logic                   bypass_active,
    output logic [31:0]            stat_bytes_in,
    output logic [31:0]            stat_bytes_out,
    output logic [ADDR_WIDTH-1:0]  wr_ptr_out
);

// ================================================================
// WRITE PATH - M1 → M2/M3 → M4 → M5 → M6
// ================================================================

// M1 output wires (raw data stream)
logic [DATA_WIDTH-1:0]  w_raw_data;
logic [STRB_WIDTH-1:0]  w_raw_strb;
logic                   w_raw_valid;
logic                   w_raw_last;
logic                   w_raw_ready;  // backpressure back to M1
logic [ADDR_WIDTH-1:0]  w_raw_addr;
logic [ID_WIDTH-1:0]    w_raw_id;
logic [7:0]             w_raw_len;

// M2 output wires
logic                   w_bypass_en;
logic                   w_decision_valid;

// burst_start pulse - generated here, fed to M2 and M3
logic                   w_burst_start;
logic                   w_awready_int; // M1 awready captured internally

// M3 → M4 (compress path)
logic [DATA_WIDTH-1:0]  w_to_comp_data;
logic [STRB_WIDTH-1:0]  w_to_comp_strb;
logic                   w_to_comp_valid;
logic                   w_to_comp_last;
logic                   w_to_comp_ready;

// M4 → M3 (compressed tokens back to mux)
logic [DATA_WIDTH-1:0]  w_from_comp_data;
logic [STRB_WIDTH-1:0]  w_from_comp_strb;
logic                   w_from_comp_valid;
logic                   w_from_comp_last;
logic                   w_from_comp_ready;

// M3 output → M5 FIFO write port
logic [DATA_WIDTH-1:0]  w_mux_out_data;
logic [STRB_WIDTH-1:0]  w_mux_out_strb;
logic                   w_mux_out_valid;
logic                   w_mux_out_last;
logic                   w_mux_out_ready;

// M5 FIFO read port → M6
logic [DATA_WIDTH-1:0]  w_fifo_rd_data;
logic [STRB_WIDTH-1:0]  w_fifo_rd_strb;
logic                   w_fifo_rd_valid;
logic                   w_fifo_rd_last;
logic                   w_fifo_rd_ready;
logic                   w_fifo_full;
logic                   w_fifo_empty;

// ================================================================
// READ PATH - M7 → M8 → M9
// ================================================================
logic [DATA_WIDTH-1:0]  w_m7_data_out;
logic                   w_m7_data_valid;

logic [DATA_WIDTH-1:0]  w_m8_out_data;
logic                   w_m8_out_valid;

// ================================================================
// BURST START PULSE GENERATION
// Pulses ONE cycle when AW handshake fires (awvalid AND awready).
// Both M2 (entropy reset) and M3 (bypass_sel reset) need this.
// ================================================================
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        w_burst_start <= 1'b0;
    else
        w_burst_start <= s_awvalid && w_awready_int;
end

// Drive top-level port from internal wire
assign s_awready = w_awready_int;

// ================================================================
// MODULE 1 - axi4_slave
// Note: this module uses aclk/aresetn naming convention.
// We connect our single clk/rst_n to both names.
// ================================================================
axi4_slave #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .ID_WIDTH  (ID_WIDTH)
) u_m1_slave (
    // M1 uses aclk/aresetn - connect our clk/rst_n here
    .aclk         (clk),
    .aresetn       (rst_n),

    // AXI slave write address channel
    .s_awid       (s_awid),
    .s_awaddr     (s_awaddr),
    .s_awlen      (s_awlen),
    .s_awsize     (s_awsize),
    .s_awburst    (s_awburst),
    .s_awvalid    (s_awvalid),
    .s_awready    (w_awready_int),   // internal copy for burst_start gen

    // AXI slave write data channel
    .s_wdata      (s_wdata),
    .s_wstrb      (s_wstrb),
    .s_wlast      (s_wlast),
    .s_wvalid     (s_wvalid),
    .s_wready     (s_wready),

    // AXI slave write response channel
    .s_bid        (s_bid),
    .s_bresp      (s_bresp),
    .s_bvalid     (s_bvalid),
    .s_bready     (s_bready),

    // AXI slave read address channel
    .s_arid       (s_arid),
    .s_araddr     (s_araddr),
    .s_arlen      (s_arlen),
    .s_arsize     (s_arsize),
    .s_arburst    (s_arburst),
    .s_arvalid    (s_arvalid),
    .s_arready    (s_arready),

    // AXI slave read data channel
    .s_rid        (s_rid),
    .s_rdata      (s_rdata),
    .s_rresp      (s_rresp),
    .s_rlast      (s_rlast),
    .s_rvalid     (s_rvalid),
    .s_rready     (s_rready),

    // Internal compression pipeline interface
    .comp_wdata   (w_raw_data),
    .comp_wstrb   (w_raw_strb),
    .comp_wvalid  (w_raw_valid),
    .comp_wlast   (w_raw_last),
    .comp_wready  (w_raw_ready),   // backpressure from M3
    .comp_waddr   (w_raw_addr),
    .comp_wid     (w_raw_id),
    .comp_wlen    (w_raw_len),
    
    // Status Registers
    .stat_bytes_in  (stat_bytes_in),
    .stat_bytes_out (stat_bytes_out)
);

// ================================================================
// MODULE 2 - entropy_unit
// Silently observes the raw data stream. Does NOT modify it.
// Outputs bypass_en decision before beat 9 arrives.
// ================================================================
entropy_unit #(
    .DATA_WIDTH   (DATA_WIDTH),
    .SAMPLE_BEATS (8),
    .BYPASS_THRESH(200)
) u_m2_entropy (
    .clk           (clk),
    .rst_n         (rst_n),
    .in_data       (w_raw_data),      // tap from M1 output
    .in_valid      (w_raw_valid),
    .in_ready      (w_raw_ready),
    .burst_start   (w_burst_start),
    .bypass_en     (w_bypass_en),
    .decision_valid(w_decision_valid)
);

// ================================================================
// MODULE 3 - bypass_mux
// Routes data to compressor or directly to output FIFO.
// Switch is latched once per burst, never mid-burst.
// ================================================================
bypass_mux #(
    .DATA_WIDTH(DATA_WIDTH),
    .STRB_WIDTH(STRB_WIDTH)
) u_m3_mux (
    .clk             (clk),
    .rst_n           (rst_n),

    // Control from M2
    .bypass_decision (w_bypass_en),
    .decision_valid  (w_decision_valid),
    .burst_start     (w_burst_start),

    // Source stream from M1
    .src_data        (w_raw_data),
    .src_strb        (w_raw_strb),
    .src_valid       (w_raw_valid),
    .src_last        (w_raw_last),
    .src_ready       (w_raw_ready),   // drives backpressure back to M1

    // To compressor M4 (compress path)
    .to_comp_data    (w_to_comp_data),
    .to_comp_strb    (w_to_comp_strb),
    .to_comp_valid   (w_to_comp_valid),
    .to_comp_last    (w_to_comp_last),
    .to_comp_ready   (w_to_comp_ready),

    // From compressor M4 (compressed output back)
    .from_comp_data  (w_from_comp_data),
    .from_comp_strb  (w_from_comp_strb),
    .from_comp_valid (w_from_comp_valid),
    .from_comp_last  (w_from_comp_last),
    .from_comp_ready (w_from_comp_ready),

    // Output to M5 FIFO
    .out_data        (w_mux_out_data),
    .out_strb        (w_mux_out_strb),
    .out_valid       (w_mux_out_valid),
    .out_last        (w_mux_out_last),
    .out_ready       (w_mux_out_ready),

    // Status
    .bypass_active   (bypass_active)
);

// ================================================================
// MODULE 4 - compressor_axi
// LZ4-style 3-stage pipeline.
// Receives data from M3 compress path.
// Outputs tokens back to M3 from_comp ports.
// ================================================================
compressor_axi #(
    .DATA_WIDTH   (DATA_WIDTH),
    .STRB_WIDTH   (STRB_WIDTH),
    .HASH_ENTRIES (32),
    .HISTORY_DEPTH(256)
) u_m4_compressor (
    .clk           (clk),
    .rst_n         (rst_n),
    .in_data       (w_to_comp_data),
    .in_strb       (w_to_comp_strb),
    .in_valid      (w_to_comp_valid),
    .in_last       (w_to_comp_last),
    .in_ready      (w_to_comp_ready),
    .out_data      (w_from_comp_data),
    .out_strb      (w_from_comp_strb),
    .out_valid     (w_from_comp_valid),
    .out_last      (w_from_comp_last),
    .out_ready     (w_from_comp_ready),
    .stat_bytes_in (stat_bytes_in),
    .stat_bytes_out(stat_bytes_out)
);

// ================================================================
// MODULE 5 - fifo
// Decouples M3 variable-rate output from M6 AXI master.
// wr_ready=0 when full - backpressure propagates to M3, M1, CPU.
// ================================================================
fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .STRB_WIDTH(STRB_WIDTH),
    .DEPTH     (16)
) u_m5_fifo (
    .clk          (clk),
    .rst_n        (rst_n),
    .wr_data      (w_mux_out_data),
    .wr_strb      (w_mux_out_strb),
    .wr_valid     (w_mux_out_valid),
    .wr_last      (w_mux_out_last),
    .wr_ready     (w_mux_out_ready),
    .rd_data      (w_fifo_rd_data),
    .rd_strb      (w_fifo_rd_strb),
    .rd_valid     (w_fifo_rd_valid),
    .rd_last      (w_fifo_rd_last),
    .rd_ready     (w_fifo_rd_ready),
    .fill_level   (),
    .full         (w_fifo_full),
    .empty        (w_fifo_empty),
    .overflow_err ()
);

// ================================================================
// MODULE 6 - axi4_master_if
// Reads compressed tokens from M5 FIFO.
// Packages them into AXI write bursts to DDR.
// ================================================================
axi4_master_if #(
    .DATA_WIDTH   (DATA_WIDTH),
    .STRB_WIDTH   (STRB_WIDTH),
    .ADDR_WIDTH   (ADDR_WIDTH),
    .ID_WIDTH     (ID_WIDTH),
    .MAX_BURST_LEN(15)
) u_m6_master_wr (
    .clk                  (clk),
    .rst_n                (rst_n),

    // From M5 FIFO read port
    .fifo_data            (w_fifo_rd_data),
    .fifo_strb            (w_fifo_rd_strb),
    .fifo_valid           (w_fifo_rd_valid),
    .fifo_last            (w_fifo_rd_last),
    .fifo_ready           (w_fifo_rd_ready),

    // AXI write address channel to DDR
    .m_awid               (mw_awid),
    .m_awaddr             (mw_awaddr),
    .m_awlen              (mw_awlen),
    .m_awsize             (mw_awsize),
    .m_awburst            (mw_awburst),
    .m_awvalid            (mw_awvalid),
    .m_awready            (mw_awready),

    // AXI write data channel to DDR
    .m_wdata              (mw_wdata),
    .m_wstrb              (mw_wstrb),
    .m_wlast              (mw_wlast),
    .m_wvalid             (mw_wvalid),
    .m_wready             (mw_wready),

    // AXI write response channel from DDR
    .m_bid                (mw_bid),
    .m_bresp              (mw_bresp),
    .m_bvalid             (mw_bvalid),
    .m_bready             (mw_bready),

    // Configuration
    .compressed_base_addr (32'hC000_0000),

    // Status
    .wr_ptr_out           (wr_ptr_out),
    .total_bursts         (),
    .error_resp           ()
);

// ================================================================
// MODULE 7 - axi4_read_master
// Sends AR read request to DDR at rd_start_addr.
// Receives R channel data and forwards to M8.
// Port names from your file:
//   control: rd_start, rd_start_addr, rd_burst_len, rd_done
//   output:  data_valid, data_out
//   AXI AR: m_axi_arid, m_axi_araddr, m_axi_arlen, m_axi_arsize,
//           m_axi_arburst, m_axi_arvalid, m_axi_arready
//   AXI R:  m_axi_rid, m_axi_rdata, m_axi_rresp, m_axi_rlast,
//           m_axi_rvalid, m_axi_rready
// ================================================================
axi4_read_master #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .ID_WIDTH  (ID_WIDTH)
) u_m7_master_rd (
    .clk           (clk),
    .rst_n         (rst_n),

    // Control interface
    .rd_start      (rd_start),
    .rd_start_addr (rd_start_addr),
    .rd_burst_len  (rd_burst_len),
    .rd_done       (rd_done),

    // Output to M8 decompressor
    .data_valid    (w_m7_data_valid),
    .data_out      (w_m7_data_out),

    // AXI read address channel to DDR
    .m_axi_arid    (mr_arid),
    .m_axi_araddr  (mr_araddr),
    .m_axi_arlen   (mr_arlen),
    .m_axi_arsize  (mr_arsize),
    .m_axi_arburst (mr_arburst),
    .m_axi_arvalid (mr_arvalid),
    .m_axi_arready (mr_arready),

    // AXI read data channel from DDR
    .m_axi_rid     (mr_rid),
    .m_axi_rdata   (mr_rdata),
    .m_axi_rresp   (mr_rresp),
    .m_axi_rlast   (mr_rlast),
    .m_axi_rvalid  (mr_rvalid),
    .m_axi_rready  (mr_rready)
);

// ================================================================
// MODULE 8 - token_decompressor
// Receives compressed tokens from M7.
// Decodes ZERO_RLE, MATCH, LITERAL back to original data.
// Port names from your file:
//   input:  in_valid, in_token  (NOT in_data, NOT in_last/in_ready)
//   output: out_valid, out_data
// ================================================================
token_decompressor #(
    .DATA_WIDTH(DATA_WIDTH)
) u_m8_decomp (
    .clk       (clk),
    .rst_n     (rst_n),
    .in_valid  (w_m7_data_valid),
    .in_token  (w_m7_data_out),    // NOTE: port is in_token not in_data
    .out_valid (w_m8_out_valid),
    .out_data  (w_m8_out_data)
);

// ================================================================
// MODULE 9 - hybrid_approx_multiplier
// Receives decompressed data from M8.
// Performs OR-LSB approximate multiplication on {A[31:0], B[31:0]}.
// No parameters - fixed 64-bit as declared in your file.
// Port names: in_valid, in_data, out_valid, out_product
// ================================================================
hybrid_approx_multiplier u_m9_mult (
    .clk        (clk),
    .rst_n      (rst_n),
    .in_valid   (w_m8_out_valid),
    .in_data    (w_m8_out_data),
    .out_valid  (final_result_valid),
    .out_product(final_result)
);
endmodule
//`timescale 1ns / 1ps
//`define SIMULATION

//module axi4_master_if #(
//    parameter integer DATA_WIDTH    = 64,
//    parameter integer STRB_WIDTH    = DATA_WIDTH / 8,
//    parameter integer ADDR_WIDTH    = 32,
//    parameter integer ID_WIDTH      = 4,
//    parameter integer MAX_BURST_LEN = 15
//)(
//    input  logic                    clk,
//    input  logic                    rst_n,

//    // From FIFO interface
//    input  logic [DATA_WIDTH-1:0]   fifo_data,
//    input  logic [STRB_WIDTH-1:0]   fifo_strb,
//    input  logic                    fifo_valid,
//    input  logic                    fifo_last,
//    output logic                    fifo_ready,

//    // AXI4 Write Address Channel
//    output logic [ID_WIDTH-1:0]     m_awid,
//    output logic [ADDR_WIDTH-1:0]   m_awaddr,
//    output logic [7:0]              m_awlen,
//    output logic [2:0]              m_awsize,
//    output logic [1:0]              m_awburst,
//    output logic                    m_awvalid,
//    input  logic                    m_awready,

//    // AXI4 Write Data Channel
//    output logic [DATA_WIDTH-1:0]   m_wdata,
//    output logic [STRB_WIDTH-1:0]   m_wstrb,
//    output logic                    m_wlast,
//    output logic                    m_wvalid,
//    input  logic                    m_wready,

//    // AXI4 Write Response Channel
//    input  logic [ID_WIDTH-1:0]     m_bid,
//    input  logic [1:0]              m_bresp,
//    input  logic                    m_bvalid,
//    output logic                    m_bready,

//    // Configuration & Status
//    input  logic [ADDR_WIDTH-1:0]   compressed_base_addr,
//    output logic [ADDR_WIDTH-1:0]   wr_ptr_out,
//    output logic [31:0]             total_bursts,
//    output logic                    error_resp
//);

//    // State Encoding
//    typedef enum logic [1:0] {
//        MW_IDLE = 2'b00,
//        MW_ADDR = 2'b01,
//        MW_DATA = 2'b10,
//        MW_RESP = 2'b11
//    } mw_state_e;

//    mw_state_e             mw_state;
//    logic [ADDR_WIDTH-1:0] wr_ptr;
//    logic [7:0]            beat_count;
//    logic [ID_WIDTH-1:0]   txn_id;

//    // ──────────────────────────────────────────────────────────────
//    // Combinational Flow Control (Fixes the Backpressure Stall)
//    // ──────────────────────────────────────────────────────────────
//    always_comb begin
//        // Defaults
//        m_wvalid   = 1'b0;
//        m_wlast    = 1'b0;
//        fifo_ready = 1'b0;
//        m_wdata    = fifo_data;
//        m_wstrb    = fifo_strb;

//        if (mw_state == MW_DATA) begin
//            m_wvalid   = fifo_valid;
//            fifo_ready = m_wready;
//            m_wlast    = (beat_count == m_awlen);
//        end
//    end

//    // Always-on Write Response Acceptance
//    assign m_bready   = 1'b1;
//    assign wr_ptr_out = wr_ptr;

//    // ──────────────────────────────────────────────────────────────
//    // Sequential State Machine Sequence
//    // ──────────────────────────────────────────────────────────────
//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            mw_state     <= MW_IDLE;
//            wr_ptr       <= '0;
//            beat_count   <= '0;
//            txn_id       <= '0;
//            total_bursts <= '0;
//            error_resp   <= 1'b0;
//            m_awvalid    <= 1'b0;
//            m_awid       <= '0;
//            m_awaddr     <= '0;
//            m_awlen      <= '0;
//            m_awsize     <= 3'd3;  // 8 Bytes
//            m_awburst    <= 2'b01; // INCR
//        end else begin
//            error_resp <= 1'b0;

//            case (mw_state)
//                MW_IDLE: begin
//                    if (fifo_valid) begin
//                        m_awid    <= txn_id;
//                        m_awaddr  <= compressed_base_addr + wr_ptr;
//                        m_awlen   <= MAX_BURST_LEN[7:0];
//                        m_awsize  <= 3'd3;
//                        m_awburst <= 2'b01;
//                        m_awvalid <= 1'b1;
//                        beat_count<= 8'd0;
//                        mw_state  <= MW_ADDR;
//                    end
//                end

//                MW_ADDR: begin
//                    if (m_awready && m_awvalid) begin
//                        m_awvalid <= 1'b0;
//                        mw_state  <= MW_DATA;
//                    end
//                end

//                MW_DATA: begin
//                    if (m_wvalid && m_wready) begin
//                        if (beat_count == m_awlen) begin
//                            // Advance Tracking Configurations
//                            wr_ptr   <= wr_ptr + ((m_awlen + 1) * (DATA_WIDTH/8));
//                            txn_id   <= txn_id + 1;
//                            mw_state <= MW_RESP;
//                        end else begin
//                            beat_count <= beat_count + 1;
//                        end
//                    end
//                end

//                MW_RESP: begin
//                    if (m_bvalid && m_bready) begin
//                        total_bursts <= total_bursts + 1;
//                        if (m_bresp != 2'b00) begin
//                            error_resp <= 1'b1;
//                        end
//                        mw_state <= MW_IDLE;
//                    end
//                end
//            endcase
//        end
//    end

//    // Simulation Monitors
//`ifdef SIMULATION
//    always @(posedge clk) begin
//        if (m_awvalid && m_awready)
//            $display("[MASTER] t=%0t AW fired addr=0x%08h len=%0d", $time, m_awaddr, m_awlen);
//        if (m_wvalid && m_wready)
//            $display("[MASTER] t=%0t W  data=0x%016h last=%b", $time, m_wdata, m_wlast);
//        if (m_bvalid && m_bready)
//            $display("[MASTER] t=%0t B  resp=%02b wr_ptr=0x%08h", $time, m_bresp, wr_ptr);
//    end
//`endif

//endmodule

/// 2nd code 


//`timescale 1ns / 1ps
//`define SIMULATION

//module axi4_master_if #(
//    parameter integer DATA_WIDTH    = 64,
//    parameter integer STRB_WIDTH    = DATA_WIDTH / 8,
//    parameter integer ADDR_WIDTH    = 32,
//    parameter integer ID_WIDTH      = 4,
//    parameter integer MAX_BURST_LEN = 15
//)(
//    input  logic                    clk,
//    input  logic                    rst_n,

//    // From FIFO interface
//    input  logic [DATA_WIDTH-1:0]   fifo_data,
//    input  logic [STRB_WIDTH-1:0]   fifo_strb,
//    input  logic                    fifo_valid,
//    input  logic                    fifo_last,
//    output logic                    fifo_ready,

//    // AXI4 Write Address Channel
//    output logic [ID_WIDTH-1:0]     m_awid,
//    output logic [ADDR_WIDTH-1:0]   m_awaddr,
//    output logic [7:0]              m_awlen,
//    output logic [2:0]              m_awsize,
//    output logic [1:0]              m_awburst,
//    output logic                    m_awvalid,
//    input  logic                    m_awready,

//    // AXI4 Write Data Channel
//    output logic [DATA_WIDTH-1:0]   m_wdata,
//    output logic [STRB_WIDTH-1:0]   m_wstrb,
//    output logic                    m_wlast,
//    output logic                    m_wvalid,
//    input  logic                    m_wready,

//    // AXI4 Write Response Channel
//    input  logic [ID_WIDTH-1:0]     m_bid,
//    input  logic [1:0]              m_bresp,
//    input  logic                    m_bvalid,
//    output logic                    m_bready,

//    // Configuration & Status
//    input  logic [ADDR_WIDTH-1:0]   compressed_base_addr,
//    output logic [ADDR_WIDTH-1:0]   wr_ptr_out,
//    output logic [31:0]             total_bursts,
//    output logic                    error_resp
//);

//    // State Encoding
//    typedef enum logic [1:0] {
//        MW_IDLE = 2'b00,
//        MW_ADDR = 2'b01,
//        MW_DATA = 2'b10,
//        MW_RESP = 2'b11
//    } mw_state_e;

//    mw_state_e             mw_state;
//    logic [ADDR_WIDTH-1:0] wr_ptr;
//    logic [7:0]            beat_count;
//    logic [ID_WIDTH-1:0]   txn_id;

//    // ──────────────────────────────────────────────────────────────
//    // Combinational Flow Control (FIXED: Zero-Padding Logic Added)
//    // ──────────────────────────────────────────────────────────────
//    always_comb begin
//        // Safe Defaults
//        m_wvalid   = 1'b0;
//        m_wlast    = 1'b0;
//        fifo_ready = 1'b0;
//        m_wdata    = 64'h0;
//        m_wstrb    = 8'h00; 

//        if (mw_state == MW_DATA) begin
//            // KEEP m_wvalid HIGH to prevent the burst from hanging
//            m_wvalid = 1'b1; 
//            m_wlast  = (beat_count == m_awlen);

//            if (fifo_valid) begin
//                // Normal Operation: Real data from the FIFO
//                m_wdata    = fifo_data;
//                m_wstrb    = fifo_strb;
//                fifo_ready = m_wready; // Only pop FIFO if AXI target accepts it
//            end else begin
//                // FIFO Empty mid-burst: Send padding data
//                m_wdata    = 64'h0;
//                m_wstrb    = 8'h00; // 00 means memory ignores this write beat
//                fifo_ready = 1'b0;  // Do not pop from empty FIFO
//            end
//        end
//    end

//    // Always-on Write Response Acceptance
//    assign m_bready   = 1'b1;
//    assign wr_ptr_out = wr_ptr;

//    // ──────────────────────────────────────────────────────────────
//    // Sequential State Machine Sequence
//    // ──────────────────────────────────────────────────────────────
//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            mw_state     <= MW_IDLE;
//            wr_ptr       <= '0;
//            beat_count   <= '0;
//            txn_id       <= '0;
//            total_bursts <= '0;
//            error_resp   <= 1'b0;
//            m_awvalid    <= 1'b0;
//            m_awid       <= '0;
//            m_awaddr     <= '0;
//            m_awlen      <= '0;
//            m_awsize     <= 3'd3;  // 8 Bytes
//            m_awburst    <= 2'b01; // INCR
//        end else begin
//            error_resp <= 1'b0;

//            case (mw_state)
//                MW_IDLE: begin
//                    // Trigger when first valid token arrives from compression
//                    if (fifo_valid) begin
//                        m_awid    <= txn_id;
//                        m_awaddr  <= compressed_base_addr + wr_ptr;
//                        m_awlen   <= MAX_BURST_LEN[7:0];
//                        m_awsize  <= 3'd3;
//                        m_awburst <= 2'b01;
//                        m_awvalid <= 1'b1;
//                        beat_count<= 8'd0;
//                        mw_state  <= MW_ADDR;
//                    end
//                end

//                MW_ADDR: begin
//                    if (m_awready && m_awvalid) begin
//                        m_awvalid <= 1'b0;
//                        mw_state  <= MW_DATA;
//                    end
//                end

//                MW_DATA: begin
//                    if (m_wvalid && m_wready) begin
//                        if (beat_count == m_awlen) begin
//                            // Advance Tracking Configurations
//                            wr_ptr   <= wr_ptr + ((m_awlen + 1) * (DATA_WIDTH/8));
//                            txn_id   <= txn_id + 1;
//                            mw_state <= MW_RESP;
//                        end else begin
//                            beat_count <= beat_count + 1;
//                        end
//                    end
//                end

//                MW_RESP: begin
//                    if (m_bvalid && m_bready) begin
//                        total_bursts <= total_bursts + 1;
//                        if (m_bresp != 2'b00) begin
//                            error_resp <= 1'b1;
//                        end
//                        mw_state <= MW_IDLE;
//                    end
//                end
//            endcase
//        end
//    end

//    // Simulation Monitors
//`ifdef SIMULATION
//    always @(posedge clk) begin
//        if (m_awvalid && m_awready)
//            $display("[MASTER] t=%0t AW fired addr=0x%08h len=%0d", $time, m_awaddr, m_awlen);
//        if (m_wvalid && m_wready) begin
//            if (fifo_valid)
//                $display("[MASTER] t=%0t W  data=0x%016h last=%b (VALID)", $time, m_wdata, m_wlast);
//            else
//                $display("[MASTER] t=%0t W  data=0x%016h last=%b (PAD)", $time, m_wdata, m_wlast);
//        end
//        if (m_bvalid && m_bready)
//            $display("[MASTER] t=%0t B  resp=%02b wr_ptr=0x%08h", $time, m_bresp, wr_ptr);
//    end
//`endif

//endmodule


`timescale 1ns / 1ps
// NOTE: Do NOT define SIMULATION here — pass it via simulator settings only
// `define SIMULATION

module axi4_master_if #(
    parameter integer DATA_WIDTH    = 64,
    parameter integer STRB_WIDTH    = DATA_WIDTH / 8,
    parameter integer ADDR_WIDTH    = 32,
    parameter integer ID_WIDTH      = 4,
    parameter integer MAX_BURST_LEN = 15
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // From FIFO interface
    input  logic [DATA_WIDTH-1:0]   fifo_data,
    input  logic [STRB_WIDTH-1:0]   fifo_strb,
    input  logic                    fifo_valid,
    input  logic                    fifo_last,
    output logic                    fifo_ready,

    // AXI4 Write Address Channel
    output logic [ID_WIDTH-1:0]     m_awid,
    output logic [ADDR_WIDTH-1:0]   m_awaddr,
    output logic [7:0]              m_awlen,
    output logic [2:0]              m_awsize,
    output logic [1:0]              m_awburst,
    output logic                    m_awvalid,
    input  logic                    m_awready,

    // AXI4 Write Data Channel
    output logic [DATA_WIDTH-1:0]   m_wdata,
    output logic [STRB_WIDTH-1:0]   m_wstrb,
    output logic                    m_wlast,
    output logic                    m_wvalid,
    input  logic                    m_wready,

    // AXI4 Write Response Channel
    input  logic [ID_WIDTH-1:0]     m_bid,
    input  logic [1:0]              m_bresp,
    input  logic                    m_bvalid,
    output logic                    m_bready,

    // Configuration & Status
    input  logic [ADDR_WIDTH-1:0]   compressed_base_addr,
    output logic [ADDR_WIDTH-1:0]   wr_ptr_out,
    output logic [31:0]             total_bursts,
    output logic                    error_resp
);

    // State Encoding
    typedef enum logic [1:0] {
        MW_IDLE = 2'b00,
        MW_ADDR = 2'b01,
        MW_DATA = 2'b10,
        MW_RESP = 2'b11
    } mw_state_e;

    mw_state_e              mw_state;
    logic [ADDR_WIDTH-1:0]  wr_ptr;
    logic [7:0]             beat_count;
    logic [ID_WIDTH-1:0]    txn_id;

    // ──────────────────────────────────────────────────────────────
    // Registered Skid Buffer (Fixes Combinatorial Path & Inefficiency Gap)
    // ──────────────────────────────────────────────────────────────
    logic                  skid_valid;
    logic [DATA_WIDTH-1:0] skid_data;
    logic [STRB_WIDTH-1:0] skid_strb;
    logic                  pad_mode;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            skid_valid <= 1'b0;
            fifo_ready <= 1'b0;
            pad_mode   <= 1'b0;
        end else begin
            // Default to not popping
            fifo_ready <= 1'b0;

            // If skid buffer is empty, or if we are consuming the data this cycle
            if (!skid_valid || (m_wvalid && m_wready)) begin
                if (fifo_valid && mw_state != MW_IDLE) begin
                    // Pop real data
                    skid_data  <= fifo_data;
                    skid_strb  <= fifo_strb;
                    skid_valid <= 1'b1;
                    pad_mode   <= 1'b0;
                    fifo_ready <= 1'b1; // Registered pop!
                end else if (mw_state == MW_DATA && !fifo_valid) begin
                    // FIFO empty mid-burst: send padding
                    skid_data  <= 64'h0;
                    skid_strb  <= 8'h00;
                    skid_valid <= 1'b1;
                    pad_mode   <= 1'b1;
                    fifo_ready <= 1'b0;
                end else begin
                    skid_valid <= 1'b0;
                end
            end
        end
    end

    always_comb begin
        if (mw_state == MW_DATA) begin
            m_wvalid = skid_valid;
            m_wdata  = skid_data;
            m_wstrb  = skid_strb;
            m_wlast  = (beat_count == m_awlen);
        end else begin
            m_wvalid = 1'b0;
            m_wdata  = 64'h0;
            m_wstrb  = 8'h00;
            m_wlast  = 1'b0;
        end
    end

    // Always-on Write Response Acceptance
    assign m_bready   = 1'b1;
    assign wr_ptr_out = wr_ptr;

    // ──────────────────────────────────────────────────────────────
    // Sequential State Machine Sequence
    // ──────────────────────────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mw_state     <= MW_IDLE;
            wr_ptr       <= '0;
            beat_count   <= '0;
            txn_id       <= '0;
            total_bursts <= '0;
            error_resp   <= 1'b0;
            m_awvalid    <= 1'b0;
            m_awid       <= '0;
            m_awaddr     <= '0;
            m_awlen      <= '0;
            m_awsize     <= 3'd3;  // 8 Bytes
            m_awburst    <= 2'b01; // INCR
        end else begin
            error_resp <= 1'b0;

            case (mw_state)
                MW_IDLE: begin
                    // Trigger when first valid token arrives from compression
                    if (fifo_valid) begin
                        m_awid    <= txn_id;
                        m_awaddr  <= compressed_base_addr + wr_ptr;
                        m_awlen   <= MAX_BURST_LEN[7:0];
                        m_awsize  <= 3'd3;
                        m_awburst <= 2'b01;
                        m_awvalid <= 1'b1;
                        beat_count<= 8'd0;
                        mw_state  <= MW_ADDR;
                    end
                end

                MW_ADDR: begin
                    // AXI Bug Fix: Hold awvalid until awready is asserted
                    if (m_awready && m_awvalid) begin
                        m_awvalid <= 1'b0;
                        mw_state  <= MW_DATA;
                    end
                end

                MW_DATA: begin
                    if (m_wvalid && m_wready) begin
                        if (beat_count == m_awlen) begin
                            // Advance Tracking Configurations
                            wr_ptr   <= wr_ptr + ((m_awlen + 1) * (DATA_WIDTH/8));
                            txn_id   <= txn_id + 1;
                            mw_state <= MW_RESP;
                        end else begin
                            beat_count <= beat_count + 1;
                        end
                    end
                end

                MW_RESP: begin
                    if (m_bvalid && m_bready) begin
                        total_bursts <= total_bursts + 1;
                        if (m_bresp != 2'b00) begin
                            error_resp <= 1'b1;
                        end
                        mw_state <= MW_IDLE;
                    end
                end
            endcase
        end
    end

    // ──────────────────────────────────────────────────────────────
    // Simulation Monitors (Gated properly)
    // ──────────────────────────────────────────────────────────────
`ifdef SIMULATION
    always @(posedge clk) begin
        if (m_awvalid && m_awready)
            $display("[MASTER] t=%0t AW fired addr=0x%08h len=%0d", $time, m_awaddr, m_awlen);
        if (m_wvalid && m_wready) begin
            if (!pad_mode)
                $display("[MASTER] t=%0t W  data=0x%016h last=%b (VALID)", $time, m_wdata, m_wlast);
            else
                $display("[MASTER] t=%0t W  data=0x%016h last=%b (PAD)", $time, m_wdata, m_wlast);
        end
        if (m_bvalid && m_bready)
            $display("[MASTER] t=%0t B  resp=%02b wr_ptr=0x%08h", $time, m_bresp, wr_ptr);
    end
`endif 

endmodule







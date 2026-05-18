// ============================================================================
// FILE    : fifo.sv
// MODULE  : fifo  (Module 5 – Elastic Token Buffer)
// PURPOSE : Synchronous FIFO decoupling the compression pipeline (M3/M4)
//           from the AXI4 Write Master (M6).
//           wr_ready provides back-pressure to the upstream mux.
//           rd_valid signals downstream that data is available.
// ============================================================================
`timescale 1ns / 1ps

module fifo #(
    parameter integer DATA_WIDTH = 64,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8,
    parameter integer DEPTH      = 16   // must be power-of-2
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // Write port (from Bypass Mux / Compressor output)
    input  logic [DATA_WIDTH-1:0]   wr_data,
    input  logic [STRB_WIDTH-1:0]   wr_strb,
    input  logic                    wr_valid,
    input  logic                    wr_last,
    output logic                    wr_ready,   // back-pressure to upstream

    // Read port (to AXI4 Write Master M6)
    output logic [DATA_WIDTH-1:0]   rd_data,
    output logic [STRB_WIDTH-1:0]   rd_strb,
    output logic                    rd_valid,
    output logic                    rd_last,
    input  logic                    rd_ready,   // consumed by M6

    // Status
    output logic [$clog2(DEPTH):0]  fill_level,
    output logic                    full,
    output logic                    empty,
    output logic                    overflow_err
);

    // ----------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------
    localparam int PTR_W = $clog2(DEPTH);

    logic [DATA_WIDTH-1:0] mem_data [0:DEPTH-1];
    logic [STRB_WIDTH-1:0] mem_strb [0:DEPTH-1];
    logic                  mem_last [0:DEPTH-1];

    logic [PTR_W-1:0] wr_ptr;
    logic [PTR_W-1:0] rd_ptr;
    logic [PTR_W:0]   count;   // one extra bit to distinguish full vs empty

    // ----------------------------------------------------------------
    // Status
    // ----------------------------------------------------------------
    assign full       = (count == DEPTH[PTR_W:0]);
    assign empty      = (count == '0);
    assign fill_level = count;
    assign wr_ready   = ~full;
    assign rd_valid   = ~empty;

    // ----------------------------------------------------------------
    // Write / Read logic
    // ----------------------------------------------------------------
    logic do_wr, do_rd;
    assign do_wr = wr_valid && wr_ready;
    assign do_rd = rd_valid && rd_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr       <= '0;
            rd_ptr       <= '0;
            count        <= '0;
            overflow_err <= 1'b0;
        end else begin
            overflow_err <= 1'b0;

            // Write
            if (do_wr) begin
                mem_data[wr_ptr] <= wr_data;
                mem_strb[wr_ptr] <= wr_strb;
                mem_last[wr_ptr] <= wr_last;
                wr_ptr           <= wr_ptr + 1'b1;
            end

            // Read
            if (do_rd) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            // Count
            case ({do_wr, do_rd})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase

            // Overflow detection
            if (wr_valid && full && !do_rd)
                overflow_err <= 1'b1;
        end
    end

    // Output combinational read data for true First-Word Fall-Through (FWFT)
    // This fixes the X-propagation bug where the register would latch the
    // empty memory slot on the same cycle the first write occurred.
    assign rd_data = empty ? '0 : mem_data[rd_ptr];
    assign rd_strb = empty ? '0 : mem_strb[rd_ptr];
    assign rd_last = empty ? 1'b0 : mem_last[rd_ptr];

    // ----------------------------------------------------------------
    // Simulation monitor
    // ----------------------------------------------------------------
`ifdef SIMULATION
    always @(posedge clk) begin
        if (do_wr)
            $display("[FIFO] t=%0t WRITE data=0x%016h fill=%0d last=%b",
                     $time, wr_data, count+1, wr_last);
        if (overflow_err)
            $display("[FIFO] t=%0t ** OVERFLOW ** fill=%0d", $time, count);
    end
`endif

endmodule

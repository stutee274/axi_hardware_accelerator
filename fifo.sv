//`timescale 1ns / 1ps
//`define SIMULATION

//module fifo #(
//    parameter integer DATA_WIDTH = 64,
//    parameter integer STRB_WIDTH = DATA_WIDTH / 8,
//    parameter integer DEPTH      = 16
//)(
//    input  logic                   clk,
//    input  logic                   rst_n,

//    input  logic [DATA_WIDTH-1:0]  wr_data,
//    input  logic [STRB_WIDTH-1:0]  wr_strb,
//    input  logic                   wr_valid,
//    input  logic                   wr_last,
//    output logic                   wr_ready,

//    output logic [DATA_WIDTH-1:0]  rd_data,
//    output logic [STRB_WIDTH-1:0]  rd_strb,
//    output logic                   rd_valid,
//    output logic                   rd_last,
//    input  logic                   rd_ready,

//    output logic [$clog2(DEPTH):0] fill_level,
//    output logic                   full,
//    output logic                   empty,
//    output logic                   overflow_err
//);

//localparam integer PTR_WIDTH = $clog2(DEPTH);

//logic [DATA_WIDTH-1:0]  mem_data [0:DEPTH-1];
//logic [STRB_WIDTH-1:0]  mem_strb [0:DEPTH-1];
//logic                   mem_last [0:DEPTH-1];
//logic [PTR_WIDTH-1:0]   wr_ptr;
//logic [PTR_WIDTH-1:0]   rd_ptr;
//logic [PTR_WIDTH:0]     count;

//// Status flags - purely combinational
//assign full       = (count == DEPTH[PTR_WIDTH:0]);
//assign empty      = (count == '0);
//assign fill_level = count;
//assign wr_ready   = !full;
//assign rd_valid   = !empty;

//// Combinational read output
//// Data is always visible at rd_ptr - rd_valid tells master if meaningful
//assign rd_data = mem_data[rd_ptr];
//assign rd_strb = mem_strb[rd_ptr];
//assign rd_last = mem_last[rd_ptr];

//// Pointer control and memory write
//always_ff @(posedge clk or negedge rst_n) begin : ptr_block
//    integer idx;
//    if (!rst_n) begin
//        wr_ptr       <= '0;
//        rd_ptr       <= '0;
//        overflow_err <= 1'b0;
//        for (idx = 0; idx < DEPTH; idx = idx + 1) begin
//            mem_data[idx] <= '0;
//            mem_strb[idx] <= '0;
//            mem_last[idx] <= 1'b0;
//        end
//    end else begin
//        overflow_err <= 1'b0;

//        if (wr_valid && wr_ready) begin
//            mem_data[wr_ptr] <= wr_data;
//            mem_strb[wr_ptr] <= wr_strb;
//            mem_last[wr_ptr] <= wr_last;
//            wr_ptr           <= wr_ptr + 1;
//        end

//        if (wr_valid && !wr_ready)
//            overflow_err <= 1'b1;

//        if (rd_valid && rd_ready)
//            rd_ptr <= rd_ptr + 1;
//    end
//end

//// Count - only driven here to avoid multiple-driver error
//always_ff @(posedge clk or negedge rst_n) begin : count_block
//    if (!rst_n) begin
//        count <= '0;
//    end else begin
//        case ({(wr_valid && wr_ready), (rd_valid && rd_ready)})
//            2'b10:   count <= count + 1;
//            2'b01:   count <= count - 1;
//            2'b11:   count <= count;
//            default: count <= count;
//        endcase
//    end
//end

//`ifdef SIMULATION
//always @(posedge clk) begin
//    if (wr_valid && wr_ready)
//        $display("[FIFO] t=%0t WRITE data=0x%016h fill=%0d last=%b",
//                 $time, wr_data, count, wr_last);
//    if (rd_valid && rd_ready)
//        $display("[FIFO] t=%0t READ  data=0x%016h fill=%0d last=%b",
//                 $time, rd_data, count, rd_last);
//    if (overflow_err)
//        $display("[FIFO] t=%0t *** OVERFLOW ***", $time);
//end
//`endif

//endmodule

`timescale 1ns / 1ps

module fifo #(
    parameter integer DATA_WIDTH = 64,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8,
    parameter integer DEPTH      = 16
)(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic [DATA_WIDTH-1:0]  wr_data,
    input  logic [STRB_WIDTH-1:0]  wr_strb,
    input  logic                    wr_valid,
    input  logic                    wr_last,
    output logic                    wr_ready,

    output logic [DATA_WIDTH-1:0]  rd_data,
    output logic [STRB_WIDTH-1:0]  rd_strb,
    output logic                    rd_valid,
    output logic                    rd_last,
    input  logic                    rd_ready,

    output logic [$clog2(DEPTH):0] fill_level,
    output logic                    full,
    output logic                    empty,
    output logic                    overflow_err
);

localparam integer PTR_WIDTH = $clog2(DEPTH);

logic [DATA_WIDTH-1:0]  mem_data [0:DEPTH-1];
logic [STRB_WIDTH-1:0]  mem_strb [0:DEPTH-1];
logic                    mem_last [0:DEPTH-1];
logic [PTR_WIDTH-1:0]   wr_ptr;
logic [PTR_WIDTH-1:0]   rd_ptr;
logic [PTR_WIDTH:0]     count;

// Status flags - purely combinational
assign full       = (count == DEPTH[PTR_WIDTH:0]);
assign empty      = (count == '0);
assign fill_level = count;
assign wr_ready   = !full;
assign rd_valid   = !empty;

// Combinational read output
assign rd_data = mem_data[rd_ptr];
assign rd_strb = mem_strb[rd_ptr];
assign rd_last = mem_last[rd_ptr];

// Pointer control and memory write
always_ff @(posedge clk or negedge rst_n) begin : ptr_block
    integer idx;
    if (!rst_n) begin
        wr_ptr       <= '0;
        rd_ptr       <= '0;
        overflow_err <= 1'b0;
        for (idx = 0; idx < DEPTH; idx = idx + 1) begin
            mem_data[idx] <= '0;
            mem_strb[idx] <= '0;
            mem_last[idx] <= 1'b0;
        end
    end else begin
        overflow_err <= 1'b0;

        if (wr_valid && wr_ready) begin
            mem_data[wr_ptr] <= wr_data;
            mem_strb[wr_ptr] <= wr_strb;
            mem_last[wr_ptr] <= wr_last;
            
            // FIX: Dynamic wrapping logic to protect non-power-of-2 depth allocations
            if (wr_ptr == DEPTH-1) wr_ptr <= '0;
            else                   wr_ptr <= wr_ptr + 1;
        end

        if (wr_valid && !wr_ready)
            overflow_err <= 1'b1;

        if (rd_valid && rd_ready) begin
            // FIX: Dynamic wrapping logic for safe tracking
            if (rd_ptr == DEPTH-1) rd_ptr <= '0;
            else                   rd_ptr <= rd_ptr + 1;
        end
    end
end

// Count - only driven here to avoid multiple-driver error
always_ff @(posedge clk or negedge rst_n) begin : count_block
    if (!rst_n) begin
        count <= '0;
    end else begin
        case ({(wr_valid && wr_ready), (rd_valid && rd_ready)})
            2'b10:   count <= count + 1;
            2'b01:   count <= count - 1;
            2'b11:   count <= count;
            default: count <= count;
        endcase
    end
end

`ifdef SIMULATION
always @(posedge clk) begin
    if (wr_valid && wr_ready)
        $display("[FIFO] t=%0t WRITE data=0x%016h fill=%0d last=%b",
                 $time, wr_data, count, wr_last);
    if (rd_valid && rd_ready)
        $display("[FIFO] t=%0t READ  data=0x%016h fill=%0d last=%b",
                 $time, rd_data, count, rd_last);
    if (overflow_err)
        $display("[FIFO] t=%0t *** OVERFLOW ***", $time);
end
`endif

endmodule









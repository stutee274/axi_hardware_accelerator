
`timescale 1ns / 1ps

module axi4_slave #(
    parameter integer DATA_WIDTH = 64,   
    parameter integer ADDR_WIDTH = 32,   
    parameter integer ID_WIDTH   = 4,    
    parameter integer STRB_WIDTH = DATA_WIDTH / 8
)(
    // Global Signals
    input  logic                    aclk,
    input  logic                    aresetn,
    
    // Write Address Channel (AW)
    input  logic [ID_WIDTH-1:0]     s_awid,
    input  logic [ADDR_WIDTH-1:0]   s_awaddr,
    input  logic [7:0]              s_awlen,
    input  logic [2:0]              s_awsize,
    input  logic [1:0]              s_awburst,
    input  logic                    s_awvalid,
    output logic                    s_awready,

    // Write Data Channel (W)
    input  logic [DATA_WIDTH-1:0]   s_wdata,
    input  logic [STRB_WIDTH-1:0]   s_wstrb,
    input  logic                    s_wlast,
    input  logic                    s_wvalid,
    output logic                    s_wready,
    
    // Write Response Channel (B)
    output logic [ID_WIDTH-1:0]     s_bid,
    output logic [1:0]              s_bresp,
    output logic                    s_bvalid,
    input  logic                    s_bready,

    // Read Address Channel (AR)
    input  logic [ID_WIDTH-1:0]     s_arid,
    input  logic [ADDR_WIDTH-1:0]   s_araddr,
    input  logic [7:0]              s_arlen,
    input  logic [2:0]              s_arsize,
    input  logic [1:0]              s_arburst,
    input  logic                    s_arvalid,
    output logic                    s_arready,

    // Read Data Channel (R)
    output logic [ID_WIDTH-1:0]     s_rid,
    output logic [DATA_WIDTH-1:0]   s_rdata,
    output logic [1:0]              s_rresp,
    output logic                    s_rlast,
    output logic                    s_rvalid,
    input  logic                    s_rready,

    // Interface to Compression Engine
    output logic [DATA_WIDTH-1:0]   comp_wdata,
    output logic [STRB_WIDTH-1:0]   comp_wstrb,
    output logic                    comp_wvalid,
    output logic                    comp_wlast,
    input  logic                    comp_wready, // Backpressure input
    output logic [ADDR_WIDTH-1:0]   comp_waddr,
    output logic [ID_WIDTH-1:0]     comp_wid,
    output logic [7:0]              comp_wlen,

    // Status Registers from Compressor
    input  logic [31:0]             stat_bytes_in,
    input  logic [31:0]             stat_bytes_out
);

    // Write FSM States
    typedef enum logic [1:0] {
        WR_IDLE = 2'b00,
        WR_DATA = 2'b01,
        WR_RESP = 2'b10
    } wr_state_e;

    wr_state_e wr_state;

    // Latched Write Registers
    logic [ADDR_WIDTH-1:0]  wr_addr_q;  
    logic [ID_WIDTH-1:0]    wr_id_q;     
    logic [7:0]             wr_len_q;    
    logic [7:0]             wr_beat_cnt; 

    // Read FSM States
    typedef enum logic {
        RD_IDLE = 1'b0,
        RD_DATA = 1'b1
    } rd_state_e;

    rd_state_e rd_state;

    // Latched Read Registers
    logic [ID_WIDTH-1:0]    rd_id_q;
    logic [ADDR_WIDTH-1:0]  rd_addr_q;
    logic [7:0]             rd_len_q;
    logic [7:0]             rd_beat_cnt;

    // ──────────────────────────────────────────────────────────────
    // WRITE CHANNEL FSM
    // ──────────────────────────────────────────────────────────────
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_state    <= WR_IDLE;
            wr_addr_q   <= '0;
            wr_id_q     <= '0;
            wr_len_q    <= '0;
            wr_beat_cnt <= '0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (s_awvalid && s_awready) begin
                        wr_addr_q   <= s_awaddr;
                        wr_id_q     <= s_awid;
                        wr_len_q    <= s_awlen;
                        wr_beat_cnt <= '0;
                        wr_state    <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (s_wvalid && s_wready) begin
                        wr_beat_cnt <= wr_beat_cnt + 1;
                        if (s_wlast) begin
                            wr_state <= WR_RESP;
                        end
                    end
                end

                WR_RESP: begin
                    if (s_bvalid && s_bready) begin
                        wr_state <= WR_IDLE;
                    end
                end
                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // Combinational Write Channel Assignments
    always_comb begin
        s_awready   = (wr_state == WR_IDLE);
        s_wready    = (wr_state == WR_DATA) ? comp_wready : 1'b0;
        s_bvalid    = (wr_state == WR_RESP);
        s_bid       = wr_id_q;
        s_bresp     = 2'b00; // OKAY Response

        // Forward to compressor pipeline
        comp_wdata  = s_wdata;
        comp_wstrb  = s_wstrb;
        comp_wvalid = (wr_state == WR_DATA) ? s_wvalid : 1'b0;
        comp_wlast  = s_wlast;
        comp_waddr  = wr_addr_q;
        comp_wid    = wr_id_q;
        comp_wlen   = wr_len_q;
    end

    // ──────────────────────────────────────────────────────────────
    // READ CHANNEL FSM
    // ──────────────────────────────────────────────────────────────
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rd_state    <= RD_IDLE;
            rd_id_q     <= '0;
            rd_len_q    <= '0;
            rd_beat_cnt <= '0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (s_arvalid && s_arready) begin
                        rd_id_q     <= s_arid;
                        rd_addr_q   <= s_araddr;
                        rd_len_q    <= s_arlen;
                        rd_beat_cnt <= '0;
                        rd_state    <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (s_rvalid && s_rready) begin
                        rd_beat_cnt <= rd_beat_cnt + 1;
                        if (s_rlast) begin
                            rd_state <= RD_IDLE;
                        end
                    end
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

    // Combinational Read Channel Assignments
    always_comb begin
        s_arready = (rd_state == RD_IDLE);
        s_rvalid  = (rd_state == RD_DATA);
        s_rid     = rd_id_q;
        
        // Address Decode for Status Registers
        if (rd_addr_q == 32'h0000_2000) begin
            s_rdata = {32'h0000_0000, stat_bytes_out};
        end else if (rd_addr_q == 32'h0000_2004) begin
            s_rdata = {32'h0000_0000, stat_bytes_in};
        end else begin
            s_rdata = '0; 
        end
        
        s_rresp   = 2'b00;
        s_rlast   = (rd_state == RD_DATA) && (rd_beat_cnt == rd_len_q);
    end

    // ──────────────────────────────────────────────────────────────
    // Gated Simulation Monitors
    // ──────────────────────────────────────────────────────────────
`ifdef SIMULATION
    always @(posedge aclk) begin
        if (s_awvalid && s_awready) begin
            $display("[SLAVE] t=%0t AW transaction received. Addr=0x%08h ID=0x%0x", $time, s_awaddr, s_awid);
        end
        if (s_wvalid && s_wready) begin
            $display("[SLAVE] t=%0t W beat received. Data=0x%016h Strobe=0x%02h Last=%b", $time, s_wdata, s_wstrb, s_wlast);
        end
        if (s_arvalid && s_arready) begin
            $display("[SLAVE] t=%0t AR transaction received. Addr=0x%08h", $time, s_araddr);
        end
        if (s_rvalid && s_rready) begin
            $display("[SLAVE] t=%0t R beat response sent. Data=0x%016h Last=%b", $time, s_rdata, s_rlast);
        end
    end
`endif

endmodule


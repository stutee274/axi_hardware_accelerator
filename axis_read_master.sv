//`timescale 1ns / 1ps

//module axi4_read_master #(
//    parameter int DATA_WIDTH = 64,
//    parameter int ADDR_WIDTH = 32,
//    parameter int ID_WIDTH   = 4
//)(
//    // Global Clock and Reset
//    input  logic                    clk,
//    input  logic                    rst_n,

//    // Internal Control Interface
//    input  logic                    rd_start,
//    input  logic [ADDR_WIDTH-1:0]   rd_start_addr,
//    input  logic [7:0]              rd_burst_len,  // AxLEN: number of beats - 1
//    output logic                    rd_done,
    
//    // Output Interface to Decompressor Pipeline
//    output logic                    data_valid,
//    output logic [DATA_WIDTH-1:0]   data_out,

//    // AXI4 Read Address Channel (AR)
//    output logic [ID_WIDTH-1:0]     m_axi_arid,
//    output logic [ADDR_WIDTH-1:0]   m_axi_araddr,
//    output logic [7:0]              m_axi_arlen,
//    output logic [2:0]              m_axi_arsize,
//    output logic [1:0]              m_axi_arburst,
//    output logic                    m_axi_arvalid,
//    input  logic                    m_axi_arready,

//    // AXI4 Read Data Channel (R)
//    input  logic [ID_WIDTH-1:0]     m_axi_rid,
//    input  logic [DATA_WIDTH-1:0]   m_axi_rdata,
//    input  logic [1:0]              m_axi_rresp,
//    input  logic                    m_axi_rlast,
//    input  logic                    m_axi_rvalid,
//    output logic                    m_axi_rready
//);

//    // FSM States
//    typedef enum logic [1:0] {
//        IDLE    = 2'b00,
//        RD_ADDR = 2'b01,
//        RD_DATA = 2'b10
//    } state_t;

//    state_t current_state, next_state;

//    // Fixed AXI parameters for a 64-bit transmission
//    assign m_axi_arid    = 4'b0001;          // Arbitrary Read ID
//    assign m_axi_arsize  = 3'b011;           // 3'b011 = 8 bytes (64-bit)
//    assign m_axi_arburst = 2'b01;            // INCR burst type

//    // FSM State Registers
//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            current_state <= IDLE;
//        end else begin
//            current_state <= next_state;
//        end
//    end

//    // FSM Combinational Logic
//    always_comb begin
//        next_state = current_state;
//        case (current_state)
//            IDLE: begin
//                if (rd_start) next_state = RD_ADDR;
//            end
//            RD_ADDR: begin
//                if (m_axi_arready && m_axi_arvalid) next_state = RD_DATA;
//            end
//            RD_DATA: begin
//                if (m_axi_rvalid && m_axi_rready && m_axi_rlast) next_state = IDLE;
//            end
//            default: next_state = IDLE;
//        endcase
//    end

//    // Registering Address Channel outputs
//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            m_axi_araddr  <= '0;
//            m_axi_arlen   <= '0;
//            m_axi_arvalid <= 1'b0;
//        end else begin
//            if (current_state == IDLE && rd_start) begin
//                m_axi_araddr  <= rd_start_addr;
//                m_axi_arlen   <= rd_burst_len;
//                m_axi_arvalid <= 1'b1;
//            end else if (current_state == RD_ADDR && m_axi_arready) begin
//                m_axi_arvalid <= 1'b0; // Handshake complete
//            end
//        end
//    end

//    // Read Data Path Control
//    // Master is ready to receive data whenever it is in the RD_DATA state
//    assign m_axi_rready = (current_state == RD_DATA);

//    // Driving data outputs towards Decompressor
//    assign data_valid   = (current_state == RD_DATA) && m_axi_rvalid;
//    assign data_out     = m_axi_rdata;
//   assign rd_done      = (current_state == RD_DATA) && m_axi_rvalid && m_axi_rlast;

//endmodule


///////  2nd code 
//`timescale 1ns / 1ps

//module axi4_read_master #(
//    parameter int DATA_WIDTH = 64,
//    parameter int ADDR_WIDTH = 32,
//    parameter int ID_WIDTH   = 4
//)(
//    // Global Clock and Reset
//    input  logic                    clk,
//    input  logic                    rst_n,

//    // Internal Control Interface
//    input  logic                    rd_start,
//    input  logic [ADDR_WIDTH-1:0]   rd_start_addr,
//    input  logic [7:0]              rd_burst_len,  // AxLEN: number of beats - 1
//    output logic                    rd_done,
    
//    // Output Interface to Decompressor Pipeline
//    output logic                    data_valid,
//    output logic [DATA_WIDTH-1:0]   data_out,

//    // AXI4 Read Address Channel (AR)
//    output logic [ID_WIDTH-1:0]     m_axi_arid,
//    output logic [ADDR_WIDTH-1:0]   m_axi_araddr,
//    output logic [7:0]              m_axi_arlen,
//    output logic [2:0]              m_axi_arsize,
//    output logic [1:0]              m_axi_arburst,
//    output logic                    m_axi_arvalid,
//    input  logic                    m_axi_arready,

//    // AXI4 Read Data Channel (R)
//    input  logic [ID_WIDTH-1:0]     m_axi_rid,
//    input  logic [DATA_WIDTH-1:0]   m_axi_rdata,
//    input  logic [1:0]              m_axi_rresp,
//    input  logic                    m_axi_rlast,
//    input  logic                    m_axi_rvalid,
//    output logic                    m_axi_rready
//);

//    // FSM States
//    typedef enum logic [1:0] {
//        IDLE    = 2'b00,
//        RD_ADDR = 2'b01,
//        RD_DATA = 2'b10
//    } state_t;

//    state_t current_state, next_state;

//    // Fixed AXI parameters for a 64-bit transmission
//    assign m_axi_arid    = 4'b0001;          
//    assign m_axi_arsize  = 3'b011;           // 8 bytes (64-bit)
//    assign m_axi_arburst = 2'b01;            // INCR burst type

//    // FSM State Registers
//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            current_state <= IDLE;
//        end else begin
//            current_state <= next_state;
//        end
//    end

//    // FSM Combinational Logic
//    always_comb begin
//        next_state = current_state;
//        case (current_state)
//            IDLE: begin
//                if (rd_start) next_state = RD_ADDR;
//            end
//            RD_ADDR: begin
//                if (m_axi_arready && m_axi_arvalid) next_state = RD_DATA;
//            end
//            RD_DATA: begin
//                if (m_axi_rvalid && m_axi_rready && m_axi_rlast) next_state = IDLE;
//            end
//            default: next_state = IDLE;
//        endcase
//    end

//    // Registering Address Channel outputs
//    always_ff @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            m_axi_araddr  <= '0;
//            m_axi_arlen   <= '0;
//            m_axi_arvalid <= 1'b0;
//        end else begin
//            if (current_state == IDLE && rd_start) begin
//                m_axi_araddr  <= rd_start_addr;
//                m_axi_arlen   <= rd_burst_len;
//                m_axi_arvalid <= 1'b1;
//            end else if (current_state == RD_ADDR && m_axi_arready) begin
//                m_axi_arvalid <= 1'b0; // Handshake complete
//            end
//        end
//    end

//    // Read Data Path Control
//    assign m_axi_rready = (current_state == RD_DATA);

//    // Driving data outputs towards Decompressor
//    assign data_valid   = (current_state == RD_DATA) && m_axi_rvalid;
//    assign data_out      = m_axi_rdata;
//    assign rd_done      = (current_state == RD_DATA) && m_axi_rvalid && m_axi_rready && m_axi_rlast;

//endmodule


`timescale 1ns / 1ps
`define SIMULATION

module axi4_read_master #(
    parameter integer DATA_WIDTH = 64,
    parameter integer ADDR_WIDTH = 32,
    parameter integer ID_WIDTH   = 4
)(
    // Global Clock and Reset
    input  logic                    clk,
    input  logic                    rst_n,

    // Internal Control Interface
    input  logic                    rd_start,
    input  logic [ADDR_WIDTH-1:0]   rd_start_addr,
    input  logic [7:0]              rd_burst_len,  // AxLEN: number of beats - 1
    output logic                    rd_done,
    
    // Output Interface to Decompressor Pipeline
    output logic                    data_valid,
    output logic [DATA_WIDTH-1:0]   data_out,

    // AXI4 Read Address Channel (AR)
    output logic [ID_WIDTH-1:0]     m_axi_arid,
    output logic [ADDR_WIDTH-1:0]   m_axi_araddr,
    output logic [7:0]              m_axi_arlen,
    output logic [2:0]              m_axi_arsize,
    output logic [1:0]              m_axi_arburst,
    output logic                    m_axi_arvalid,
    input  logic                    m_axi_arready,

    // AXI4 Read Data Channel (R)
    input  logic [ID_WIDTH-1:0]     m_axi_rid,
    input  logic [DATA_WIDTH-1:0]   m_axi_rdata,
    input  logic [1:0]              m_axi_rresp,
    input  logic                    m_axi_rlast,
    input  logic                    m_axi_rvalid,
    output logic                    m_axi_rready
);

    // FSM States
    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        RD_ADDR = 2'b01,
        RD_DATA = 2'b10
    } state_t;

    state_t current_state, next_state;

    // Static AXI Parameters
    assign m_axi_arid    = {{(ID_WIDTH-1){1'b0}}, 1'b1}; // Dynamically sized safely            
    assign m_axi_arsize  = 3'b011;                        // 8 bytes (64-bit)
    assign m_axi_arburst = 2'b01;                         // INCR burst type

    // FSM State Registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // FSM Combinational Logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (rd_start) next_state = RD_ADDR;
            end
            RD_ADDR: begin
                // Transition only when the address phase completely handshakes
                if (m_axi_arready && m_axi_arvalid) next_state = RD_DATA;
            end
            RD_DATA: begin
                // Transition back to IDLE only on the validated final beat
                if (m_axi_rvalid && m_axi_rready && m_axi_rlast) next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // Registering Address Channel outputs (Guarantees AXI Handshake Stability)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_araddr  <= '0;
            m_axi_arlen   <= '0;
            m_axi_arvalid <= 1'b0;
        end else begin
            if (current_state == IDLE && rd_start) begin
                m_axi_araddr  <= rd_start_addr;
                m_axi_arlen   <= rd_burst_len;
                m_axi_arvalid <= 1'b1;
            end else if (current_state == RD_ADDR && m_axi_arready) begin
                m_axi_arvalid <= 1'b0; // Clear immediately when accepted
            end
        end
    end

    // Read Data Path Control
    assign m_axi_rready = (current_state == RD_DATA);

    // Driving data outputs towards Decompressor
    assign data_valid   = (current_state == RD_DATA) && m_axi_rvalid;
    assign data_out     = m_axi_rdata;
    assign rd_done      = (current_state == RD_DATA) && m_axi_rvalid && m_axi_rready && m_axi_rlast;

    // ──────────────────────────────────────────────────────────────
    // Gated Simulation Monitors
    // ──────────────────────────────────────────────────────────────
`ifdef SIMULATION
    always @(posedge clk) begin
        if (m_axi_arvalid && m_axi_arready) begin
            $display("[READ MASTER] t=%0t AR fired addr=0x%08h len=%0d", $time, m_axi_araddr, m_axi_arlen);
        end
        if (m_axi_rvalid && m_axi_rready) begin
            $display("[READ MASTER] t=%0t R beat recv data=0x%016h last=%b resp=%b", $time, m_axi_rdata, m_axi_rlast, m_axi_rresp);
        end
    end
`endif

endmodule

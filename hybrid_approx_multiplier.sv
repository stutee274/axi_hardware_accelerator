`timescale 1ns / 1ps

module hybrid_approx_multiplier (
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Input Interface from Module 8 Decompressor
    input  logic                    in_valid,
    input  logic [63:0]             in_data,     // Contains {Operand_A[31:0], Operand_B[31:0]}
    
    // Output Interface to Master Controller / Next Stage
    output logic                    out_valid,
    output logic [63:0]             out_product
);

    // Internal Operand Segments
    logic [31:0] op_a, op_b;
    logic [15:0] a_msb, a_lsb;
    logic [15:0] b_msb, b_lsb;

    // Intermediate Math Layers
    logic [31:0] exact_msb_prod;
    logic [31:0] approx_cross_a;
    logic [31:0] approx_cross_b;
    logic [31:0] approx_lsb_part;
    logic [63:0] final_approx_sum;

    // Pipeline Registers
    logic        out_valid_reg;
    logic [63:0] out_product_reg;

    // Unpack the incoming data stream into two distinct 32-bit numbers
    assign op_a = in_data[63:32];
    assign op_b = in_data[31:0];

    // Subdivide operands into Upper (Exact) and Lower (Approximate) 16-bit windows
    assign a_msb = op_a[31:16];
    assign a_lsb = op_a[15:0];
    assign b_msb = op_b[31:16];
    assign b_lsb = op_b[15:0];

    always_comb begin
        // 1. EXACT MANIPULATION: High-precision calculation for the critical MSBs
        exact_msb_prod = a_msb * b_msb;

        // 2. APPROXIMATE LOGIC: OR-LSB compression layers for the cross terms and lower bits
        approx_cross_a  = a_msb * b_lsb;
        approx_cross_b  = a_lsb * b_msb;
        approx_lsb_part = (a_lsb | b_lsb); // Pure OR-gate approximation for the absolute LSBs

        // 3. HYBRID ASSEMBLY: Merge exact shifted MSB with the bitwise OR'd low-order parts
        // Note: Explicit 64-bit casting ensures no truncation or warning happens 
        // when ORing 48-bit shifted results with 64-bit bounds.
        final_approx_sum = {exact_msb_prod, 32'b0} | 
                           {16'b0, approx_cross_a, 16'b0} | 
                           {16'b0, approx_cross_b, 16'b0} | 
                           {32'b0, approx_lsb_part};
    end

    // Sequential Pipeline Stage
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid_reg   <= 1'b0;
            out_product_reg <= '0;
        end else begin
            out_valid_reg   <= in_valid;
            if (in_valid) begin
                out_product_reg <= final_approx_sum;
            end else begin
                out_product_reg <= '0;
            end
        end
    end

    // Assign Outputs
    assign out_valid   = out_valid_reg;
    assign out_product = out_product_reg;

endmodule
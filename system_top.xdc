## ============================================================
## FILE    : system_top.xdc
## PURPOSE : Timing and I/O constraints for system_top
##
## IMPORTANT: Adjust the clock period to match your FPGA board.
##   - 100 MHz → period = 10.000 ns (Nexys A7, Arty A7, ZedBoard)
##   - 125 MHz → period =  8.000 ns (some Kintex boards)
##   - 200 MHz → period =  5.000 ns (high-performance targets)
##
## IMPORTANT: If synthesizing as Out-of-Context (OOC), you do
##   NOT need pin assignments — only clock and I/O delay constraints.
## ============================================================

## ────────────────────────────────────────────────────────────────
## PRIMARY CLOCK DEFINITION
## ────────────────────────────────────────────────────────────────
## Adjust period for your target frequency.
## 10 ns = 100 MHz (safe starting point for Artix-7)
create_clock -period 10.000 -name sys_clk [get_ports clk]

## ────────────────────────────────────────────────────────────────
## INPUT DELAY CONSTRAINTS
## ────────────────────────────────────────────────────────────────
## These tell Vivado when input signals are stable relative to clk.
## Values below assume ~2 ns setup margin — adjust if needed.
##
## AXI Slave interface inputs
set_input_delay -clock sys_clk -max 3.000 [get_ports {s_awid[*] s_awaddr[*] s_awlen[*] s_awsize[*] s_awburst[*] s_awvalid}]
set_input_delay -clock sys_clk -min 1.000 [get_ports {s_awid[*] s_awaddr[*] s_awlen[*] s_awsize[*] s_awburst[*] s_awvalid}]

set_input_delay -clock sys_clk -max 3.000 [get_ports {s_wdata[*] s_wstrb[*] s_wlast s_wvalid}]
set_input_delay -clock sys_clk -min 1.000 [get_ports {s_wdata[*] s_wstrb[*] s_wlast s_wvalid}]

set_input_delay -clock sys_clk -max 3.000 [get_ports {s_bready}]
set_input_delay -clock sys_clk -min 1.000 [get_ports {s_bready}]

set_input_delay -clock sys_clk -max 3.000 [get_ports {s_arid[*] s_araddr[*] s_arlen[*] s_arsize[*] s_arburst[*] s_arvalid s_rready}]
set_input_delay -clock sys_clk -min 1.000 [get_ports {s_arid[*] s_araddr[*] s_arlen[*] s_arsize[*] s_arburst[*] s_arvalid s_rready}]

## AXI Master Write interface inputs (from DDR/memory)
set_input_delay -clock sys_clk -max 3.000 [get_ports {mw_awready mw_wready mw_bid[*] mw_bresp[*] mw_bvalid}]
set_input_delay -clock sys_clk -min 1.000 [get_ports {mw_awready mw_wready mw_bid[*] mw_bresp[*] mw_bvalid}]

## AXI Master Read interface inputs (from DDR/memory)
set_input_delay -clock sys_clk -max 3.000 [get_ports {mr_arready mr_rid[*] mr_rdata[*] mr_rresp[*] mr_rlast mr_rvalid}]
set_input_delay -clock sys_clk -min 1.000 [get_ports {mr_arready mr_rid[*] mr_rdata[*] mr_rresp[*] mr_rlast mr_rvalid}]

## Control inputs
set_input_delay -clock sys_clk -max 3.000 [get_ports {rst_n rd_start rd_start_addr[*] rd_burst_len[*]}]
set_input_delay -clock sys_clk -min 1.000 [get_ports {rst_n rd_start rd_start_addr[*] rd_burst_len[*]}]

## ────────────────────────────────────────────────────────────────
## OUTPUT DELAY CONSTRAINTS
## ────────────────────────────────────────────────────────────────
## AXI Slave interface outputs
set_output_delay -clock sys_clk -max 3.000 [get_ports {s_awready s_wready s_bid[*] s_bresp[*] s_bvalid}]
set_output_delay -clock sys_clk -min 0.500 [get_ports {s_awready s_wready s_bid[*] s_bresp[*] s_bvalid}]

set_output_delay -clock sys_clk -max 3.000 [get_ports {s_arready s_rid[*] s_rdata[*] s_rresp[*] s_rlast s_rvalid}]
set_output_delay -clock sys_clk -min 0.500 [get_ports {s_arready s_rid[*] s_rdata[*] s_rresp[*] s_rlast s_rvalid}]

## AXI Master Write interface outputs
set_output_delay -clock sys_clk -max 3.000 [get_ports {mw_awid[*] mw_awaddr[*] mw_awlen[*] mw_awsize[*] mw_awburst[*] mw_awvalid}]
set_output_delay -clock sys_clk -min 0.500 [get_ports {mw_awid[*] mw_awaddr[*] mw_awlen[*] mw_awsize[*] mw_awburst[*] mw_awvalid}]

set_output_delay -clock sys_clk -max 3.000 [get_ports {mw_wdata[*] mw_wstrb[*] mw_wlast mw_wvalid mw_bready}]
set_output_delay -clock sys_clk -min 0.500 [get_ports {mw_wdata[*] mw_wstrb[*] mw_wlast mw_wvalid mw_bready}]

## AXI Master Read interface outputs
set_output_delay -clock sys_clk -max 3.000 [get_ports {mr_arid[*] mr_araddr[*] mr_arlen[*] mr_arsize[*] mr_arburst[*] mr_arvalid mr_rready}]
set_output_delay -clock sys_clk -min 0.500 [get_ports {mr_arid[*] mr_araddr[*] mr_arlen[*] mr_arsize[*] mr_arburst[*] mr_arvalid mr_rready}]

## Status and result outputs
set_output_delay -clock sys_clk -max 3.000 [get_ports {rd_done final_result[*] final_result_valid bypass_active stat_bytes_in[*] stat_bytes_out[*] wr_ptr_out[*]}]
set_output_delay -clock sys_clk -min 0.500 [get_ports {rd_done final_result[*] final_result_valid bypass_active stat_bytes_in[*] stat_bytes_out[*] wr_ptr_out[*]}]

## ────────────────────────────────────────────────────────────────
## ASYNC RESET - Mark as false path for timing
## ────────────────────────────────────────────────────────────────
## The asynchronous reset is not a synchronous data path.
## Without this, Vivado may report false timing violations on reset.
set_false_path -from [get_ports rst_n]

## ────────────────────────────────────────────────────────────────
## OPTIONAL: I/O STANDARD (Uncomment and adjust for your board)
## ────────────────────────────────────────────────────────────────
## set_property IOSTANDARD LVCMOS33 [get_ports *]
## set_property PACKAGE_PIN W5 [get_ports clk]

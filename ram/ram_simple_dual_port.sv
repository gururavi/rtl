/*------------------------------------------------------------
@filename:    ram_simple_dual_port.sv
@author:      Guru Ravi
@version:     1.0
@description: Simple Dual Port RAM (1 read and 1 write port) 
--------------------------------------------------------------
@history:
    GR    Apr 3, 2018    v1.00a (initial release)
--------------------------------------------------------------*/
module ram_simple_dual_port #(
   parameter WIDTH     = 32,
   parameter DEPTH     = 32,
   parameter DEPTH_LOG = $clog2(DEPTH) 
)(
   input                        WR_CLK, 
   input                        WR_EN,  
   input      [(DEPTH_LOG-1):0] WR_ADDR,
   input      [(WIDTH-1):0]     WR_DATA,
   input                        RD_CLK, 
   input                        RD_EN,  
   input      [(DEPTH_LOG-1):0] RD_ADDR,
   output reg [(WIDTH-1):0]     RD_DATA 
);

   // Set ram style per requirement: "block" or "distributed"
   // This synthesis attribute is Xilinx specific.
   (*ram_style="block"*) logic [(WIDTH-1):0] ram_mem [(DEPTH-1):0] = '{default:'0};
 
   /* FIFO RAM inference: in bram mode this should infer- 
      Simple Dual Port (SDP). */
   always_ff@(posedge WR_CLK) begin : RAM_WR_PORT
      if (WR_EN) begin
         ram_mem[WR_ADDR] <= WR_DATA;
      end
   end : RAM_WR_PORT

   always_ff@(posedge RD_CLK) begin : RAM_RD_PORT
      if (RD_EN) begin
         RD_DATA <= ram_mem[RD_ADDR];  
      end
   end : RAM_RD_PORT
endmodule : ram_simple_dual_port

/*-------------------------------------------------------------------------
@filename:    async_one_deep_fifo.sv
@author:      Guru Ravi
@version:     1.0
@description: 1-deep/2-register FIFO synchronizer
---------------------------------------------------------------------------
@history:
    GR    Apr 09, 2018    v1.00a (initial release)
---------------------------------------------------------------------------*/

module async_one_deep_fifo #(
   parameter WIDTH = 32
)(
   input                RST, // asynchronous active high reset 
   // Write signals
   input                WR_CLK, 
   output               WR_RDY,
   input                WR_EN,
   input  [(WIDTH-1):0] WR_DATA,
   // Read signals
   input                RD_CLK, 
   output               RD_VALID,
   input                RD_EN,
   output [(WIDTH-1):0] RD_DATA
);

   logic wr_en_i, rd_en_i,
         wr_addr, rd_addr,
         wr_addr_s0, wr_addr_s1,
         rd_addr_s0, rd_addr_s1;

   always_ff@(posedge WR_CLK or posedge RST) begin : WR_ADDR_INC 
      if (RST) begin
         wr_addr <= 1'b0;
      end else begin
         wr_addr <= (wr_addr ^ wr_en_i);
      end
   end : WR_ADDR_INC 

   always_ff@(posedge RD_CLK or posedge RST) begin : RD_ADDR_INC 
      if (RST) begin
         rd_addr <= 1'b0;
      end else begin
         rd_addr <= (rd_addr ^ rd_en_i);
      end
   end : RD_ADDR_INC 

   always_ff@(posedge WR_CLK or posedge RST) begin : RD_ADDR_SYNC 
      if (RST) begin
         rd_addr_s0 <= 1'b0;
         rd_addr_s1 <= 1'b0;
      end else begin
         rd_addr_s0 <= rd_addr;
         rd_addr_s1 <= rd_addr_s0;
      end
   end : RD_ADDR_SYNC 
   
   always_ff@(posedge RD_CLK or posedge RST) begin : WR_ADDR_SYNC 
      if (RST) begin
         wr_addr_s0 <= 1'b0;
         wr_addr_s1 <= 1'b0;
      end else begin
         wr_addr_s0 <= wr_addr;
         wr_addr_s1 <= wr_addr_s0;
      end
   end : WR_ADDR_SYNC 

   assign wr_en_i  = (WR_EN & WR_RDY);
   assign rd_en_i  = (RD_EN & RD_VALID);

   assign WR_RDY   = ~(wr_addr ^ rd_addr_s1); // not full
   assign RD_VALID =  (rd_addr ^ wr_addr_s1); // not empty

// Module Instantiations
   // RAM 
   ram_simple_dual_port #(
      .WIDTH   (WIDTH), 
      .DEPTH   (2)
   ) ram_inst (
      .WR_CLK  (WR_CLK ),
      .WR_EN   (wr_en_i),  
      .WR_ADDR (wr_addr),
      .WR_DATA (WR_DATA),
      .RD_CLK  (RD_CLK ),
      .RD_EN   (1'b1   ), 
      .RD_ADDR (rd_addr),
      .RD_DATA (RD_DATA)
   );
endmodule : async_one_deep_fifo

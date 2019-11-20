/*-------------------------------------------------------------------------
@filename:    async_fifo.sv
@author:      Guru Ravi
@version:     1.0
@description: Asynchronous FIFO with async reset:
              ~ based on 'FIFO Design with Asynchronous Pointer Comparisons'
                method by Cliff Cummings (Sunburst Design). Refer to the paper:
                http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO2.pdf  
              ~ Synthesizable FIFO (verified with Xilinx FPGA).
              ~ Supports both Standard and FWFT read modes.
              ~ Writes:
                * 'WR_ACK' is asserted next cycle after 'WR_EN'.
                * 'FULL' is asserted along with last 'WR_ACK'.
              ~ Reads:
                * FWFT: 
                  - 'RD_VALID' goes high when fifo is not empty, and 
                    'RD_EN' changes next data on the output bus.
                  - 'EMPTY' is asserted next cycle after last 'RD_EN'.
                * Non-FWFT: 
                  - 'RD_VALID' is asserted next cycle after 'RD_EN'.
                  - 'EMPTY' is asserted along with last 'RD_VALID'.
---------------------------------------------------------------------------
@history:
    GR    Apr 08, 2018    v1.00a (initial release)
---------------------------------------------------------------------------*/

module async_fifo #(
   parameter WIDTH     = 32,
   parameter DEPTH     = 32,  // = n^2, with n>=3
   parameter DEPTH_LOG = $clog2(DEPTH), 
   parameter FWFT      = 1'b0 // First-Word-Fall-Through
)(
   input                    RST, // asynchronous active high reset 
   input                    WR_CLK, 
   input                    WR_EN,
   input      [(WIDTH-1):0] WR_DATA,
   output reg               WR_ACK,
   input                    RD_CLK,  
   input                    RD_EN,
   output     [(WIDTH-1):0] RD_DATA,
   output                   RD_VALID,
   output reg               EMPTY, FULL
);

   logic direction,
         dirset, dirclr,
         full_i, full_d, 
         empty_i, empty_d, 
         wr_en_i, rd_en_i,
         valid_d;

   logic [(WIDTH-1):0] rd_data_i; 
   
   logic [(DEPTH_LOG-1):0] rd_ptr, rd_ptr_bin, 
                           wr_ptr, wr_ptr_bin, 
                           rd_ptr_bin_curr,
                           rd_ptr_bin_next;

// FIFO read & write address generation  
   always_ff@(posedge WR_CLK or posedge RST) begin : FIFO_WR_ADDR_INC
      if (RST) begin 
         wr_ptr_bin <= '0;
      end else if (wr_en_i) begin
         wr_ptr_bin <= wr_ptr_bin + 1'b1;
      end
   end : FIFO_WR_ADDR_INC
   
   always_ff@(posedge RD_CLK or posedge RST) begin : FIFO_RD_ADDR_INC
      if (RST) begin
         rd_ptr_bin_curr <= '0;
         rd_ptr_bin_next <= '0;
      end else begin
         if (FWFT) begin 
            rd_ptr_bin_curr <= rd_ptr_bin;
            rd_ptr_bin_next <= rd_ptr_bin + 1'b1;
         end else begin   
            if (RD_EN & ~empty_d) begin    
               rd_ptr_bin_next <= rd_ptr_bin_next + 1'b1;
            end
         end
      end
   end : FIFO_RD_ADDR_INC

   always_comb begin : FIFO_RD_ADDR_SEL
      if (FWFT) begin 
         if (RD_EN & ~empty_d) begin
            rd_ptr_bin = rd_ptr_bin_next;
         end else begin
            rd_ptr_bin = rd_ptr_bin_curr;
         end
      end else begin 
         rd_ptr_bin = rd_ptr_bin_next;
      end
   end : FIFO_RD_ADDR_SEL

   // binary to gray conversion 
   assign wr_ptr[DEPTH_LOG-1] = wr_ptr_bin[DEPTH_LOG-1];
   assign rd_ptr[DEPTH_LOG-1] = rd_ptr_bin[DEPTH_LOG-1];
   generate genvar i;
      for (i=(DEPTH_LOG-2);i>=0;i--) begin
          assign wr_ptr[i] = wr_ptr_bin[i+1] ^ wr_ptr_bin[i];
          assign rd_ptr[i] = rd_ptr_bin[i+1] ^ rd_ptr_bin[i];
      end
   endgenerate

// FIFO flags generation
   // Checking the quadrant
   assign dirset =   ((wr_ptr[DEPTH_LOG-1] ^ rd_ptr[DEPTH_LOG-2]) & 
                     ~(wr_ptr[DEPTH_LOG-2] ^ rd_ptr[DEPTH_LOG-1])); // RD catching WR
   assign dirclr = ((~(wr_ptr[DEPTH_LOG-1] ^ rd_ptr[DEPTH_LOG-2]) & 
                      (wr_ptr[DEPTH_LOG-2] ^ rd_ptr[DEPTH_LOG-1])) | RST); // WR catching RD
   
   always_ff@(posedge dirset or posedge dirclr) begin : DIRECTION_FLAG
      if (dirclr) begin 
         direction <= 1'b0;
      end else begin
         direction <= 1'b1;
      end
   end : DIRECTION_FLAG

   assign empty_i = (wr_ptr==rd_ptr) & (~direction);
   assign full_i  = (wr_ptr==rd_ptr) & (direction);

   // synchronize the empty flag
   always_ff@(posedge RD_CLK or posedge empty_i) begin : EMPTY_SYNC 
      if (empty_i) begin
         empty_d <= 1'b1;
         EMPTY   <= 1'b1;
      end else begin
         empty_d <= empty_i;
         EMPTY   <= empty_d;
      end
   end : EMPTY_SYNC 
   
   // synchronize the full flag
   always_ff@(posedge WR_CLK or posedge full_i) begin : FULL_SYNC 
      if (full_i) begin
         full_d <= 1'b1;
         FULL   <= 1'b1;
      end else begin
         full_d <= full_i;
         FULL   <= full_d;
      end
   end : FULL_SYNC

   assign wr_en_i = (WR_EN & ~(full_d));
   assign rd_en_i = (FWFT)? 1'b1 : (RD_EN & ~(empty_d));

   always_ff@(posedge WR_CLK) begin : WR_ACK_REG
      WR_ACK <= (WR_EN & ~full_d);
   end : WR_ACK_REG

   always_ff@(posedge RD_CLK) begin : RD_VALID_REG
      valid_d  <= (RD_EN & ~empty_d);
   end : RD_VALID_REG
     
   assign RD_VALID = (FWFT)? ~empty_d : valid_d; 
   assign RD_DATA  = rd_data_i; 

// Module Instantiations
   // RAM 
   ram_simple_dual_port #(
      .WIDTH   (WIDTH), 
      .DEPTH   (DEPTH)
   ) ram_inst (
      .WR_CLK  (WR_CLK   ),
      .WR_EN   (wr_en_i  ),  
      .WR_ADDR (wr_ptr   ),
      .WR_DATA (WR_DATA  ),
      .RD_CLK  (RD_CLK   ),
      .RD_EN   (rd_en_i  ),   
      .RD_ADDR (rd_ptr   ),
      .RD_DATA (rd_data_i)
   );
endmodule : async_fifo

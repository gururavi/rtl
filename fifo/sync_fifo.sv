/*-------------------------------------------------------------------------
@filename:    sync_fifo.sv
@author:      Guru Ravi
@version:     1.0
@description: Synchronous FIFO with sync reset
              ~ Synthesizable FIFO (verified with Xilinx FPGA)
              ~ Supports both Standard and FWFT read modes
              ~ Writes:
                * 'WR_ACK' is asserted next cycle after 'WR_EN'.
                * 'FULL' is asserted along with last 'WR_ACK'.
                * 'OVERFLOW' is asserted for write attempts after 'FULL' 
                   is asserted.
              ~ Reads:
                * FWFT: 'VALID' goes high when fifo is not empty, and 
                        'RD_EN' changes next data on the output bus.
                        'EMPTY' is asserted next cycle after last 'RD_EN'.
                * Non-FWFT: 'VALID' is asserted next cycle after 'RD_EN'.
                        'EMPTY' is asserted along with last 'VALID'.
                * 'UNDERFLOW' is asserted for read attempts after 'EMPTY' 
                   is asserted.
              ~ use 'FREE_WORDS' to generate programmable/almost 
                full/empty externally. 
              ~ OVERFLOW/UNDERFLOW: use rising edge detect on these signals 
                since it can go low when fifo becomes empty/full.
---------------------------------------------------------------------------
@history:
    GR    Apr 04, 2018    v1.00a (initial release)
---------------------------------------------------------------------------*/
module sync_fifo #(
   parameter WIDTH     = 32,
   parameter DEPTH     = 32,
   parameter DEPTH_LOG = $clog2(DEPTH), 
   parameter FWFT      = 1'b0 // First-Word-Fall-Through
)(
   input                    CLK, RST,
   input                    WR_EN,  
   input      [(WIDTH-1):0] WR_DATA,
   output reg               WR_ACK, // Optional WR ACK  
   input                    RD_EN,  
   output                   VALID,  // Optional RD valid 
   output     [(WIDTH-1):0] RD_DATA,
   output                   EMPTY, FULL,
   output [(DEPTH_LOG-1):0] FREE_WORDS, // num free entries in RAM
   output                   OVERFLOW, UNDERFLOW
);  

   logic [(WIDTH-1):0]     rd_data_i, 
                           rd_data_d = '0; 
   
   logic [(DEPTH_LOG-1):0] rd_addr_curr = '0,
                           rd_addr_next = '0,
                           rd_addr,
                           wr_addr = '0,
                           count   = '0;
   
   logic valid_i, valid_d,
         rd_en_i, wr_en_i, wr_ack_i, 
         full_flag, full_flag_d,  
         empty_flag, empty_flag_d, empty_i;
   
// FIFO flags generation
   always_ff@(posedge CLK) begin : FULL_EMPTY_COUNT
      if (RST) begin
         count <= '0;
      end else begin // fifo depth tracker
         if (wr_en_i & ~rd_en_i) begin
            count <= count+1; 
         end else if (~wr_en_i & rd_en_i) begin 
            count <= count-1; 
         end
      end
   end : FULL_EMPTY_COUNT
   
   assign empty_flag = (count == '0)       ? 1'b1 : 1'b0; 
   assign full_flag  = (count == (DEPTH-1))? 1'b1 : 1'b0;
   
   always_ff@(posedge CLK) begin : FLAGS_REG
      empty_flag_d <= empty_flag;
      full_flag_d  <= full_flag;
   end : FLAGS_REG

   assign rd_en_i  = (RD_EN & ~empty_flag);
   assign wr_en_i  = (WR_EN & ~full_flag);
   assign wr_ack_i = (WR_EN & ~full_flag_d);
   
// FIFO write logic 
   always_ff@(posedge CLK) begin : FIFO_WR_ADDR_INC
      if (RST) begin
         wr_addr <= '0;
      end else begin
         if (wr_ack_i) begin 
            wr_addr <= wr_addr + 1'b1;
         end
      end
   end : FIFO_WR_ADDR_INC
   
// FIFO read logic 
   always_ff@(posedge CLK) begin : FIFO_RD_ADDR_INC
      if (RST) begin
         rd_addr_curr <= '0;
         rd_addr_next <= '0;
      end else begin
         rd_addr_curr <= rd_addr;
         rd_addr_next <= rd_addr + 1'b1; 
      end
   end : FIFO_RD_ADDR_INC
   
   /* This MUX holds current address during gapped reads. 
      Note that most RAMs have 1 clock cycle read latency and 
      there is also setup requirement for the read address. */ 
   always_comb begin : FIFO_RD_ADDR_SEL
      if (rd_en_i) begin
         rd_addr = rd_addr_next;
      end else begin
         rd_addr = rd_addr_curr;
      end
   end : FIFO_RD_ADDR_SEL
   
   /* FWFT mode requires 2 cycle latency to deassert 'EMPTY', 
      when the first data is written into a empty FIFO. */
   assign empty_i = (empty_flag | empty_flag_d); 
   assign valid_i = ~empty_i;

   always_ff@(posedge CLK) begin : FIFO_RD_DATA_VALID_REG
      valid_d  <= (RD_EN & valid_i);
      if (rd_en_i) begin
         rd_data_d <= rd_data_i;
      end
   end : FIFO_RD_DATA_VALID_REG

// Output Assignments
   always_ff@(posedge CLK) begin : WR_ACK_REG 
      WR_ACK <= wr_ack_i;
   end : WR_ACK_REG 
                        
   assign FULL       = full_flag_d;
   assign OVERFLOW   = (WR_EN & full_flag_d);  
   assign EMPTY      = empty_i; 
   assign UNDERFLOW  = (RD_EN & empty_i);
   assign FREE_WORDS = ((DEPTH-1)-count);

   generate 
      if (FWFT) begin
         assign RD_DATA = rd_data_i; 
         assign VALID   = valid_i; 
      end else begin
         assign RD_DATA = rd_data_d;
         assign VALID   = valid_d;
      end
   endgenerate

// Module Instantiations
   // RAM 
   ram_simple_dual_port #(
      .WIDTH   (WIDTH), 
      .DEPTH   (DEPTH)
   ) ram_inst (
      .WR_CLK  (CLK      ),
      .WR_EN   (wr_ack_i ),  
      .WR_ADDR (wr_addr  ),
      .WR_DATA (WR_DATA  ),
      .RD_CLK  (CLK      ),
      .RD_EN   (1'b1     ),  
      .RD_ADDR (rd_addr  ),
      .RD_DATA (rd_data_i)
   );
endmodule : sync_fifo

/*-----------------------------------------------------------------------------
@filename:    axis_sync_fifo_old.sv
@author:      Guru Ravi
@version:     1.0
@description: AXI-Stream synchronous FIFO with sync reset
-------------------------------------------------------------------------------
@history:
    GR    Jan 25, 2018    v1.00a (initial release)
-----------------------------------------------------------------------------*/

module axis_sync_fifo #(
   parameter DATA_WIDTH = 32, // AXI TDATA width
   parameter USER_WIDTH = 8,  // AXI TUSER width
   parameter ID_WIDTH   = 4,  // AXI TID   width
   parameter FIFO_DEPTH = 32,
   parameter FIFO_DEPTH_LOG = $clog2(FIFO_DEPTH) 
)( 
   input                       CLK, RST,

   output                      S_AXIS_TREADY, // "not full" signal
   input                       S_AXIS_TVALID,
   input  [(DATA_WIDTH-1):0]   S_AXIS_TDATA,
   input  [(USER_WIDTH-1):0]   S_AXIS_TUSER,
   input  [(ID_WIDTH-1):0]     S_AXIS_TID,
   input  [(DATA_WIDTH/8)-1:0] S_AXIS_TKEEP,
   input                       S_AXIS_TLAST,

   input                       M_AXIS_TREADY,
   output                      M_AXIS_TVALID, // "not empty" signal
   output [(DATA_WIDTH-1):0]   M_AXIS_TDATA,
   output [(USER_WIDTH-1):0]   M_AXIS_TUSER,
   output [(ID_WIDTH-1):0]     M_AXIS_TID,
   output [(DATA_WIDTH/8)-1:0] M_AXIS_TKEEP,
   output                      M_AXIS_TLAST
);

   // TDATA+TUSER+TID+TKEEP+TLAST
   localparam RAM_WIDTH = (DATA_WIDTH+USER_WIDTH+ID_WIDTH+(DATA_WIDTH/8)+1); 
   
   logic [(RAM_WIDTH-1):0]      wr_data, 
                                rd_data;
   
   logic [(FIFO_DEPTH_LOG-1):0] rd_addr_curr,
                                rd_addr_next,
                                rd_addr,
                                wr_addr;
   
   logic wr_en, full_n, empty_n;

// FIFO flags generation
   // S_AXIS_TREADY -> ~(FULL), M_AXIS_TVALID -> ~(EMPTY) 
   always_ff@(posedge CLK) begin : FIFO_FLAGS_GEN
      if (RST) begin
         full_n  <= 1'b1; // default not full
         empty_n <= 1'b0; // default empty
      end else begin
         if (wr_addr == (rd_addr-1)) begin // WR catching up with RD
            full_n <= 1'b0;
         end else begin
            full_n <= 1'b1;
         end
         if (wr_addr == rd_addr) begin
            empty_n <= 1'b0;
         end else begin
            empty_n <= 1'b1;
         end
      end
   end : FIFO_FLAGS_GEN

// FIFO write logic 
   assign wr_en = S_AXIS_TVALID & full_n; 
   // Converge the AXIS bus info into RAM write data
   assign wr_data[(DATA_WIDTH-1):0] = S_AXIS_TDATA;
   assign wr_data[(((DATA_WIDTH/8)-1)+DATA_WIDTH):DATA_WIDTH] = S_AXIS_TKEEP;
   assign wr_data[((USER_WIDTH-1)+((DATA_WIDTH/8)+DATA_WIDTH)):((DATA_WIDTH/8)+DATA_WIDTH)] = S_AXIS_TUSER;
   assign wr_data[((ID_WIDTH-1)+USER_WIDTH+((DATA_WIDTH/8)+DATA_WIDTH)):(USER_WIDTH+(DATA_WIDTH/8)+DATA_WIDTH)] = S_AXIS_TID;
   assign wr_data[RAM_WIDTH-1] = S_AXIS_TLAST;
 
   always_ff@(posedge CLK) begin : FIFO_WR_ADDR_INC
      if (RST) begin
         wr_addr <= '0;
      end else begin
         if (full_n & S_AXIS_TVALID) begin 
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
      if (empty_n & M_AXIS_TREADY) begin
         rd_addr = rd_addr_next;
      end else begin
         rd_addr = rd_addr_curr;
      end
   end : FIFO_RD_ADDR_SEL

// Output Assignments
   assign S_AXIS_TREADY = full_n;  
   // Diverge the RAM read data into AXIS bus  
   assign M_AXIS_TVALID = empty_n;      
   assign M_AXIS_TDATA  = rd_data[(DATA_WIDTH-1):0]; 
   assign M_AXIS_TKEEP  = rd_data[(((DATA_WIDTH/8)-1)+DATA_WIDTH):DATA_WIDTH];
   assign M_AXIS_TUSER  = rd_data[((USER_WIDTH-1)+((DATA_WIDTH/8)+DATA_WIDTH)):((DATA_WIDTH/8)+DATA_WIDTH)];
   assign M_AXIS_TID    = rd_data[((ID_WIDTH-1)+USER_WIDTH+((DATA_WIDTH/8)+DATA_WIDTH)):(USER_WIDTH+(DATA_WIDTH/8)+DATA_WIDTH)];
   assign M_AXIS_TLAST  = rd_data[RAM_WIDTH-1];

// Module Instantiations
   // RAM 
   ram_simple_dual_port #(
      .WIDTH   (RAM_WIDTH), 
      .DEPTH   (FIFO_DEPTH)
   ) ram_inst (
      .WR_CLK  (CLK     ),
      .WR_EN   (wr_en   ),  
      .WR_ADDR (wr_addr ),
      .WR_DATA (wr_data ),
      .RD_CLK  (CLK     ),
      .RD_EN   (1'b1    ),  
      .RD_ADDR (rd_addr ),
      .RD_DATA (rd_data )
   );
endmodule : axis_sync_fifo

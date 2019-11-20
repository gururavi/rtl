/*-----------------------------------------------------------------------------
@filename:    axis_async_fifo.sv
@author:      Guru Ravi
@version:     1.0
@description: AXI-Stream asynchronous FIFO with async reset
-------------------------------------------------------------------------------
@history:
    GR    Mar 25, 2018    v1.00a (initial release)
-----------------------------------------------------------------------------*/

module axis_async_fifo #(
   parameter DATA_WIDTH     = 32,  // AXI TDATA width
   parameter USER_WIDTH     = 8,   // AXI TUSER width
   parameter ID_WIDTH       = 4,   // AXI TID   width
   parameter FIFO_1DEEP     = 1'b1,// selects 2 deep fifo 
   // when FIFO_1DEEP is selected, the following params is don't care.
   parameter FIFO_DEPTH     = 32,  // = n^2, with n>=3
   parameter FIFO_DEPTH_LOG = $clog2(FIFO_DEPTH)
)( 
   input                       RST, // asynchronous active high reset 

   input                       S_AXIS_CLK, 
   output                      S_AXIS_TREADY, 
   input                       S_AXIS_TVALID,
   input  [(DATA_WIDTH-1):0]   S_AXIS_TDATA,
   input  [(USER_WIDTH-1):0]   S_AXIS_TUSER,
   input  [(ID_WIDTH-1):0]     S_AXIS_TID,
   input  [(DATA_WIDTH/8)-1:0] S_AXIS_TKEEP,
   input                       S_AXIS_TLAST,

   input                       M_AXIS_CLK, 
   input                       M_AXIS_TREADY,
   output                      M_AXIS_TVALID, 
   output [(DATA_WIDTH-1):0]   M_AXIS_TDATA,
   output [(USER_WIDTH-1):0]   M_AXIS_TUSER,
   output [(ID_WIDTH-1):0]     M_AXIS_TID,
   output [(DATA_WIDTH/8)-1:0] M_AXIS_TKEEP,
   output                      M_AXIS_TLAST
);

   // TDATA+TUSER+TID+TKEEP+TLAST
   localparam RAM_WIDTH = (DATA_WIDTH+USER_WIDTH+ID_WIDTH+(DATA_WIDTH/8)+1); 

   logic [(RAM_WIDTH-1):0] wr_data, rd_data;

   // Converge the AXIS bus info into RAM write data
   assign wr_data[(DATA_WIDTH-1):0] = S_AXIS_TDATA;
   assign wr_data[(((DATA_WIDTH/8)-1)+DATA_WIDTH):DATA_WIDTH] = S_AXIS_TKEEP;
   assign wr_data[((USER_WIDTH-1)+((DATA_WIDTH/8)+DATA_WIDTH)):((DATA_WIDTH/8)+DATA_WIDTH)] = S_AXIS_TUSER;
   assign wr_data[((ID_WIDTH-1)+USER_WIDTH+((DATA_WIDTH/8)+DATA_WIDTH)):(USER_WIDTH+(DATA_WIDTH/8)+DATA_WIDTH)] = S_AXIS_TID;
   assign wr_data[RAM_WIDTH-1] = S_AXIS_TLAST;

   // Diverge the RAM read data into AXIS bus  
   assign M_AXIS_TDATA  = rd_data[(DATA_WIDTH-1):0]; 
   assign M_AXIS_TKEEP  = rd_data[(((DATA_WIDTH/8)-1)+DATA_WIDTH):DATA_WIDTH];
   assign M_AXIS_TUSER  = rd_data[((USER_WIDTH-1)+((DATA_WIDTH/8)+DATA_WIDTH)):((DATA_WIDTH/8)+DATA_WIDTH)];
   assign M_AXIS_TID    = rd_data[((ID_WIDTH-1)+USER_WIDTH+((DATA_WIDTH/8)+DATA_WIDTH)):(USER_WIDTH+(DATA_WIDTH/8)+DATA_WIDTH)];
   assign M_AXIS_TLAST  = rd_data[RAM_WIDTH-1];

   generate 
      if (FIFO_1DEEP) begin
         async_one_deep_fifo #( 
            .WIDTH     (RAM_WIDTH )
         ) fifo_inst (
            .RST       (RST), 
            .WR_CLK    (S_AXIS_CLK),  
            .WR_RDY    (S_AXIS_TREADY),  // "not full" 
            .WR_EN     (S_AXIS_TVALID), 
            .WR_DATA   (wr_data), 
            .RD_CLK    (M_AXIS_CLK), 
            .RD_VALID  (M_AXIS_TVALID ), // "not empty" 
            .RD_EN     (M_AXIS_TREADY), 
            .RD_DATA   (rd_data) 
         );
      end else begin 
         logic full, empty;
         assign S_AXIS_TREADY = ~full;   // "not full" 
         assign M_AXIS_TVALID = ~empty;  // "not empty" 
         async_fifo #(
            .WIDTH     (RAM_WIDTH ),
            .DEPTH     (FIFO_DEPTH),
            .DEPTH_LOG (FIFO_DEPTH_LOG),
            .FWFT      (1'b1)
         ) fifo_inst (
            .RST       (RST), 
            .WR_CLK    (S_AXIS_CLK),  
            .WR_EN     (S_AXIS_TVALID), 
            .WR_DATA   (wr_data), 
            .WR_ACK    (), 
            .RD_CLK    (M_AXIS_CLK), 
            .RD_EN     (M_AXIS_TREADY), 
            .RD_DATA   (rd_data), 
            .RD_VALID  (), 
            .EMPTY     (empty), 
            .FULL      (full) 
         );
      end
   endgenerate   
endmodule : axis_async_fifo

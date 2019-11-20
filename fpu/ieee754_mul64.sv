/*-------------------------------------------------------------------------
@filename:    ieee754_mul64.sv
@author:      Guru Ravi
@version:     1.0
@description: - Fixed latency double precision floating point multiplier.
              - Complies with IEEE-754 (64-bit).
              - Accepts back to back inputs (fully pipelined).
---------------------------------------------------------------------------
@history:
    GR    Sep 05, 2019    v1.00a (initial release)
---------------------------------------------------------------------------*/

// Input & Output format:
// 63    -> Sign bit
// 62:52 -> Exponent (11 bits)
// 51:0  -> Mantissa (52 bits)

module ieee754_mul64 #(
   parameter WIDTH = 64
)(
   input             CLK,
   input             RST,
   input             VALID_I,
   input      [63:0] MUL_A,  
   input      [63:0] MUL_B,
   output reg        VALID_O,
   output reg [63:0] MUL_O
);

function automatic logic [5:0] find_leading_one;
   input logic [15:0] in;
   case (in) inside
      16'b1???_????_????_???? : find_leading_one = 6'd00;
      16'b01??_????_????_???? : find_leading_one = 6'd01;
      16'b001?_????_????_???? : find_leading_one = 6'd02;
      16'b0001_????_????_???? : find_leading_one = 6'd03;
      16'b0000_1???_????_???? : find_leading_one = 6'd04;
      16'b0000_01??_????_???? : find_leading_one = 6'd05;
      16'b0000_001?_????_???? : find_leading_one = 6'd06;
      16'b0000_0001_????_???? : find_leading_one = 6'd07;
      16'b0000_0000_1???_???? : find_leading_one = 6'd08;
      16'b0000_0000_01??_???? : find_leading_one = 6'd09;
      16'b0000_0000_001?_???? : find_leading_one = 6'd10;
      16'b0000_0000_0001_???? : find_leading_one = 6'd11;
      16'b0000_0000_0000_1??? : find_leading_one = 6'd12;
      16'b0000_0000_0000_01?? : find_leading_one = 6'd13;
      16'b0000_0000_0000_001? : find_leading_one = 6'd14;
      16'b0000_0000_0000_0001 : find_leading_one = 6'd15;
      default                 : find_leading_one = 6'd16; // didn't find a leading one
   endcase
endfunction : find_leading_one;

localparam C_BIAS = 1023;

logic [5:0] valid_d;

// signals to unpack the input
logic [11:0] exponent_a, exponent_b; 
logic [52:0] mantissa_a, mantissa_b;
logic sign_a, sign_b;

// signals to perform the math
logic [105:0] multiply;
logic [11:0]  add;
logic sign_xor;

// delay pipeline while normalizing & rounding
logic [11:0] exponent_z [3:0];
logic [52:0] mantissa_z [3:0];
logic sign_z [3:0];

// normalization signals
logic [5:0] quad[3:0]; 
logic [3:0] valid_quad;
logic [5:0] lead_one_pos, right_shift_pos;

// rounding signals
logic [2:0] guard, round, sticky;
logic add_one, lsb_one;

always_ff@(posedge CLK) begin
   valid_d <= {valid_d[4:0], VALID_I};
   VALID_O <= valid_d[5];

   // STAGE-1 : Compare/Select : check for NaN, Infinites, Zeros
   sign_a <= MUL_A[63];
   sign_b <= MUL_B[63];
   if ((MUL_A[62:0] == '0) || (MUL_B[62:0] == '0)) begin // Zero
      // force the result to Zero
      exponent_a <= '0;  
      exponent_b <= '0; 
      mantissa_a <= '0; 
      mantissa_b <= '0; 
   end else if ((MUL_A[62:52] == '1) || (MUL_B[62:52] == '1)) begin // NaN/Infinity
      // set one exponent to 1024 to return NaN/Infinity
      exponent_a <= 11'b01000000000; 
      exponent_b <= '0;             
      mantissa_a <= '0; 
      mantissa_b <= '0; 
   end else begin // Normal & Sub-Normal 
      exponent_a <= (MUL_A[62:52] - C_BIAS);
      exponent_b <= (MUL_B[62:52] - C_BIAS);
      mantissa_a <= {(MUL_A[62:52] != '0), MUL_A[51:0]}; // set the hidden bit based on exponent value
      mantissa_b <= {(MUL_A[62:52] != '0), MUL_B[51:0]};
   end

   // STAGE-2: Multiply & Add
   multiply <= mantissa_a * mantissa_b;
   add      <= exponent_a + exponent_b + 1; // add 1 to move decimal point one left
   sign_xor <= sign_a ^ sign_b;

   // STAGE-4 : Normalization : find leading one in multiply result
   exponent_z[0] <= add;
   mantissa_z[0] <= multiply[105:53];
   sign_z <= {sign_z[2:0], sign_xor}; 
   guard  <= {guard[1:0], multiply[53]}; 
   round  <= {round[1:0], multiply[52]}; 
   sticky <= {sticky[1:0], (multiply[51:0] != 0)}; 
   // use quad values to find 'lead_one_pos'
   quad[0] <= find_leading_one(multiply[105:90]); 
   quad[1] <= find_leading_one(multiply[89:74]); 
   quad[2] <= find_leading_one(multiply[73:58]);  
   quad[3] <= find_leading_one({multiply[57:53], 11'h000});   

   // STAGE-5 : Normalization : left shift by 'lead_one_pos'
   mantissa_z[1] <= mantissa_z[0] << lead_one_pos; // move right amount to get leading one to hidden position.
   exponent_z[1] <= exponent_z[0] - lead_one_pos; 
   
   // STAGE-6 : Normalization : right shift if exponent is less than Emin
   if ($signed(exponent_z[1]) < -1022) begin // Emin = (1 - Emax)
      mantissa_z[2] <= mantissa_z[1] >> right_shift_pos;  
      exponent_z[2] <= C_BIAS; // TODO: check for underflow/overflow ?
   end else begin
      mantissa_z[2] <= mantissa_z[1];   
      exponent_z[2] <= exponent_z[1] + C_BIAS; 
   end

   // STAGE-7 : Rounding & Re-Normalization
   mantissa_z[3] <= mantissa_z[2];   
   exponent_z[3] <= exponent_z[2];
   if (add_one) begin
      mantissa_z[3] <= mantissa_z[2] + 1;
      if (mantissa_z[2] == 53'h1fffffffffffff) begin
         exponent_z[3] <= exponent_z[2] + 1;
      end
   end else if (lsb_one) begin
      mantissa_z[3][0] <= 1'b1;
   end

   // STAGE-8 : Pack output
   MUL_O <= {sign_z[3], exponent_z[3][10:0], mantissa_z[3][51:0]};
end

// Combinatorial reduction
assign right_shift_pos = (-1022 - $signed(exponent_z[1]));

assign valid_quad = {quad[0][5], quad[1][5], quad[2][5], quad[3][5]};

always_comb begin
   case (valid_quad) inside
      4'b0??? : lead_one_pos = quad[0];
      4'b10?? : lead_one_pos = 16 + quad[1];
      4'b110? : lead_one_pos = 32 + quad[2];
      4'b1110 : lead_one_pos = 48 + quad[3];
      default : lead_one_pos = 0; 
   endcase

   case ({mantissa_z[2][0], round[2], guard[2], sticky[2]}) inside
      4'b1101, 4'b11xx : begin
          add_one = 1'b1; 
          lsb_one = 1'b0; 
      end
      4'b0101, 4'b01xx : begin
          add_one = 1'b0;
          lsb_one = 1'b1;
      end   
      default : begin
          add_one = 1'b0;
          lsb_one = 1'b0;
      end 
   endcase
end

endmodule : ieee754_mul64

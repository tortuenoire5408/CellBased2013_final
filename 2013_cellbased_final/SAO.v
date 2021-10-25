`timescale 1ns/10ps
`define LCU_SIZE0 // run test with testfixture1.v
// `define LCU_SIZE1 // run test with testfixture2.v
// `define LCU_SIZE2 // run test with testfixture3.v
module SAO (clk, reset, in_en, din, sao_type, sao_band_pos, sao_eo_class, sao_offset, lcu_x, lcu_y, lcu_size, busy, finish);
input   clk;
input   reset;
input   in_en;
input   [7:0]  din;
input   [1:0]  sao_type;
input   [4:0]  sao_band_pos;
input          sao_eo_class;
input   [15:0] sao_offset;
input   [2:0]  lcu_x;
input   [2:0]  lcu_y;
input   [1:0]  lcu_size;
output  busy;
output  finish;

//============================================================================

`ifdef LCU_SIZE0
   reg [7:0] mem [255:0];
`endif

`ifdef LCU_SIZE1
   reg [7:0] mem [1023:0];
`endif

`ifdef LCU_SIZE2
   reg [7:0] mem [4095:0];
`endif

//============================================================================

reg     busy;
reg     finish;
wire    [7:0] q;

reg wen, cen;
reg [1:0] cs, ns; // current state ; next state
reg [2:0] EO_CAT;
reg [3:0] size_b;
reg [6:0] size_width, lcu_count, pix_x, pix_y;
reg [7:0] sao_out, a, b, c;
reg [11:0] lcu_e_count;
reg [13:0] addr;

parameter IDLE = 2'd0, GET_LCU = 2'd1, CAL = 2'd2, DONE = 2'd3;
//============================================================================

sram_16384x8 golden_sram(.Q(q), .CLK(clk), .CEN(cen), .WEN(wen), .A(addr), .D(sao_out));

//============================================================================

//current state
always @(posedge clk or posedge reset) begin
  if(reset) cs <= IDLE;
  else cs <= ns;
end

//next state
always @(*) begin
  case (cs)
    IDLE: ns = GET_LCU;
    GET_LCU: if(lcu_e_count == ((size_width << size_b) - 1'd1)) ns = CAL;
             else ns = GET_LCU;
    CAL: if(lcu_e_count == ((size_width << size_b) - 1'd1)) begin
            if((lcu_x + 1'd1) * (lcu_y + 1'd1) == lcu_count) ns = DONE;
            else ns = GET_LCU;
         end else ns = CAL;
    DONE: ns = IDLE;
    default: ns = IDLE;
  endcase
end

//busy
always @(*) begin
  if(cs == IDLE) busy = 1;
  else if(cs == GET_LCU)
          if(lcu_e_count == ((size_width << size_b) - 1'd1)) busy = 1;
          else busy = 0;
  else if(cs == CAL)
          if(lcu_e_count == ((size_width << size_b) - 1'd1)) busy = 0;
          else busy = 1;
  else busy = 1;
end

//size_width => LCU width pixels
//size_b => 2 ^ size_b = size_width
//lcu_count => number of LCUs
always @(*) begin
  case (lcu_size)
    2'd0: begin size_width = 7'd16; size_b = 4'd4; lcu_count = 7'd64; end
    2'd1: begin size_width = 7'd32; size_b = 4'd5; lcu_count = 7'd16; end
    2'd2: begin size_width = 7'd64; size_b = 4'd6; lcu_count = 7'd4; end
    default: begin size_width = 7'd0; size_b = 4'd0; lcu_count = 7'd0; end
  endcase
end

//get din and store in mem
integer i;
always @(*) begin
  if(reset) begin
    for(i = 0 ; i < (size_width << size_b); i = i + 1'd1) begin
      mem[i] = 7'd0;
    end
  end else if(cs == GET_LCU && in_en) begin
    mem[lcu_e_count] = din;
  end else begin
    mem[lcu_e_count] = mem[lcu_e_count];
  end
end

//EO category
always @(*) begin
  if(cs == CAL && sao_eo_class == 1'b0) begin
    a = mem[lcu_e_count - 'd1];
    b = mem[lcu_e_count + 'd1];
    c = mem[lcu_e_count];

    if(c < a && c < b) EO_CAT = 3'd1;
    else if((c < a && c == b) || (c < b && c == a)) EO_CAT = 3'd2;
    else if((c > a && c == b) || (c > b && c == a)) EO_CAT = 3'd3;
    else if(c > a && c > b) EO_CAT = 3'd4;
    else EO_CAT = 3'd0;
  end else if(cs == CAL && sao_eo_class == 1'b1) begin
    a = mem[lcu_e_count - size_width];
    b = mem[lcu_e_count + size_width];
    c = mem[lcu_e_count];

    if(c < a && c < b) EO_CAT = 3'd1;
    else if((c < a && c == b) || (c < b && c == a)) EO_CAT = 3'd2;
    else if((c > a && c == b) || (c > b && c == a)) EO_CAT = 3'd3;
    else if(c > a && c > b) EO_CAT = 3'd4;
    else EO_CAT = 3'd0;
  end else EO_CAT = 3'd0;
end

//cen
always @(*) begin
  if(cs == IDLE) cen = 1;
  else if(cs == CAL) cen = 0;
  else cen = 1;
end

//wen
always @(*) begin
  if(cs == IDLE) wen = 1;
  else if(cs == CAL) wen = 0;
  else wen = 1;
end

//addr
always @(*) begin
  if(cs == CAL) begin
    pix_y = lcu_e_count >> size_b;
    pix_x = lcu_e_count - (pix_y << size_b);

    addr = ((lcu_y << 'd7) << size_b) + (lcu_x << size_b)
            + (pix_y << 'd7) + pix_x;
  end else addr = 0;
end

//sao_out
always @(*) begin
  if(cs == CAL) begin
    case (sao_type)
      2'd0: begin
        sao_out = mem[lcu_e_count];
      end
      2'd1: begin
        if((mem[lcu_e_count] >= sao_band_pos * 'd8) && (mem[lcu_e_count] < (sao_band_pos + 4) * 'd8)) begin
          if(mem[lcu_e_count] >= (sao_band_pos + 3) * 'd8) begin
            sao_out = mem[lcu_e_count] + {{4{sao_offset[3]}}, sao_offset[3:0]};
          end else if(mem[lcu_e_count] >= (sao_band_pos + 2) * 'd8) begin
            sao_out = mem[lcu_e_count] + {{4{sao_offset[7]}}, sao_offset[7:4]};
          end else if(mem[lcu_e_count] >= (sao_band_pos + 1) * 'd8) begin
            sao_out = mem[lcu_e_count] + {{4{sao_offset[11]}}, sao_offset[11:8]};
          end else begin
            sao_out = mem[lcu_e_count] + {{4{sao_offset[15]}}, sao_offset[15:12]}; // * 'd8 換 << 3
          end
        end else sao_out = mem[lcu_e_count];
      end
      2'd2: begin
        case (sao_eo_class)
          1'b0: begin
            if(lcu_e_count % size_width == (size_width - 1))
              sao_out = mem[lcu_e_count];
            else if(lcu_e_count % size_width == 0)
              sao_out = mem[lcu_e_count];
            else begin
              case (EO_CAT)
                3'd0: sao_out = mem[lcu_e_count];
                3'd1: sao_out = mem[lcu_e_count] + {{4{sao_offset[15]}}, sao_offset[15:12]};
                3'd2: sao_out = mem[lcu_e_count] + {{4{sao_offset[11]}}, sao_offset[11:8]};
                3'd3: sao_out = mem[lcu_e_count] + {{4{sao_offset[7]}}, sao_offset[7:4]};
                3'd4: sao_out = mem[lcu_e_count] + {{4{sao_offset[3]}}, sao_offset[3:0]};
                default: sao_out = mem[lcu_e_count];
              endcase
            end
          end
          1'b1: begin
            if(lcu_e_count < size_width)
              sao_out = mem[lcu_e_count];
            else if(lcu_e_count < (size_width << size_b - size_width))
              sao_out = mem[lcu_e_count];
            else begin
              case (EO_CAT)
                3'd0: sao_out = mem[lcu_e_count];
                3'd1: sao_out = mem[lcu_e_count] + {{4{sao_offset[15]}}, sao_offset[15:12]};
                3'd2: sao_out = mem[lcu_e_count] + {{4{sao_offset[11]}}, sao_offset[11:8]};
                3'd3: sao_out = mem[lcu_e_count] + {{4{sao_offset[7]}}, sao_offset[7:4]};
                3'd4: sao_out = mem[lcu_e_count] + {{4{sao_offset[3]}}, sao_offset[3:0]};
                default: sao_out = mem[lcu_e_count];
              endcase
            end
          end
          default: sao_out = mem[lcu_e_count];
        endcase
      end
      default: sao_out = mem[lcu_e_count];
    endcase
  end else sao_out = 8'd0;
end

//lcu_e_count
always @(posedge clk or posedge reset) begin
  if(reset) lcu_e_count <= 0;
  else begin
    if(lcu_e_count == ((size_width << size_b) - 1'd1)) lcu_e_count <= 0;
    else if(cs == CAL || in_en) lcu_e_count <= lcu_e_count + 1'd1;
  end
end

//finish
always @(*) begin
  if(cs == IDLE) finish = 0;
  else if(cs == DONE) finish = 1;
  else finish = 0;
end

//============================================================================

endmodule


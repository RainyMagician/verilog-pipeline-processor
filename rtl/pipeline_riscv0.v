`timescale 1ns/1ps
`define PIPELINE_STAGES 5
module pipeline_riscv (
  input          clk,
  input          nrst,
  input  [31:0]  inst,                          // instruction
  input  [31:0]  data_in,                       // mem data to reg_file
  output [31:0]  inst_addr,                     // PC
  output [31:0]  data_addr,                     // alu_out / mem address
  output [31:0]  data_out,                      // data to mem
  output         data_wr,                       // wr to mem?
  output [31:0]  pc_IF,
  output [31:0]  pc_ID,
  output [31:0]  pc_EXE,
  output [31:0]  pc_MEM,
  output [31:0]  pc_WB
  );
  
/*-----------------------------------------------------------------------------
DECLARATIONS
-----------------------------------------------------------------------------*/
  // IF
  wire [2:0] sel_pc;
  wire [31:0] inst_IF, pc_p4_IF;
  reg [31:0] next_pc, jr_pc;
  wire [2:0] fwd_jr;
  
  // ID
  wire wr_rf, jal, jr, sw, use_imm;
  wire [31:0] inst_ID;
  wire [31:0] pc_p4_ID, bra_off_ID, opA_ID, mem_data_ID;
  wire [31:0] wr_data, rfA, rfB;
  wire [31:0] opB_ID;
  wire [4:0] reg_addr_ID, wr_addr;
  
  wire [5:0] op;
  wire [4:0] rd, rs1, rs2;
  wire [6:0] funct;
  wire [31:0] imm_alu, imm_bra, imm_j;
  
  // EXE
  wire zero;
  wire [6:0] alu_code;
  wire [31:0] inst_EXE;
  wire [31:0] pc_p4_EXE, bra_off_EXE, opA_EXE, opB_EXE, mem_data_EXE0;
  wire [4:0] reg_addr_EXE;
  wire [31:0] bra_pc;
  wire [31:0] alu_out_EXE;
  wire [2:0] fwd_opA, fwd_opB, fwd_sw;
  reg [31:0] opA, opB;
  reg [31:0] mem_data_EXE;
  wire [31:0] fwd0;
  
  // MEM
  wire wr_mem, load, jal_pc;
  wire [31:0] inst_MEM;
  wire [31:0] pc_p4_MEM, mem_data_MEM, alu_out_MEM;
  wire [31:0] fwd1;
  wire [4:0] reg_addr_MEM;
  wire [31:0] reg_data_MEM;
  
  // WB
  wire [31:0] inst_WB;
  wire [31:0] pc_p4_WB, reg_data_WB;
  wire [31:0] fwd2, fwd3;
  wire [4:0] reg_addr_WB;
  
  // CONTROLLER
  wire stall;
  wire [1:0] flush;
  
/*-----------------------------------------------------------------------------
IF
-----------------------------------------------------------------------------*/
  
  assign pc_p4_IF = inst_addr + 4;
  assign pc_IF = inst_addr;
  
  always@(*) begin
    casez (sel_pc)
      3'b1zz:   next_pc = bra_pc;                 // BRA
      3'b01z:   next_pc = imm_j;                  // J, JAL       
      3'b001:   next_pc = jr_pc;                  // JR
      default:  next_pc = pc_p4_IF;               // PC + 4
    endcase
  end
  
  always@(*) begin
    casez (fwd_jr)
      3'b1zz:   jr_pc = fwd2;
      3'b01z:   jr_pc = fwd1;
      3'b001:   jr_pc = fwd0;
      default:  jr_pc = rfB;
    endcase
  end
  
  reg32 PC (
    .clk(clk),
    .nrst(nrst),
    .en(!stall),
    .data_in(next_pc),
    .data_out(inst_addr)
  );
    
/*-----------------------------------------------------------------------------
ID
-----------------------------------------------------------------------------*/
  
  assign op       = inst_ID[5:0];
  assign rd       = inst_ID[10:6];
  assign rs1      = jal ? 0 : inst_ID[19:15];
  assign rs2      = (jr | sw) ? rd : inst_ID[24:20];
  assign funct    = inst_ID[31:25];
  assign imm_alu  = { {16{inst_ID[31]}}, inst_ID[31:20], inst_ID[14:11] };
  assign imm_bra  = { {16{inst_ID[31]}}, inst_ID[31:25], inst_ID[14:6] };
  assign imm_j    = { {6{inst_ID[31]}}, inst_ID[31:6] };
  
  assign bra_off_ID = imm_bra;
  assign opA_ID = rfA;
  assign opB_ID = jal ? pc_p4_ID : (use_imm ? imm_alu : rfB);
  assign mem_data_ID = rfB;
  assign reg_addr_ID = jal ? 1 : rd;
  
  if_id_reg IF_ID (
    .clk(clk),
    .nrst(nrst),
    .en(!stall),
    .flush(flush[1]),
    .cur_pc0(pc_IF),
    .cur_pc(pc_ID),
    .next_pc0(pc_p4_IF),
    .next_pc(pc_p4_ID)
  );
  
  rf RF (
    .clk(clk),
    .nrst(nrst),
    .rd_addrA(rs1),
    .rd_addrB(rs2),
    .wr_en(wr_rf),
    .wr_addr(reg_addr_WB),
    .wr_data(reg_data_WB),
    .rd_dataA(rfA),
    .rd_dataB(rfB)
  );
  
/*-----------------------------------------------------------------------------
EXE
-----------------------------------------------------------------------------*/
  
  assign bra_pc = pc_p4_EXE + bra_off_EXE;
  assign fwd0 = alu_out_EXE;
  
  always@(*) begin
    casez (fwd_opA)
      3'b1zz:   opA = fwd1;                     // fr alu_out_MEM
      3'b01z:   opA = fwd2;                     // fr reg_data_WB
      3'b001:   opA = fwd3;                     // fr reg_data_WB + 1cc  
      default:  opA = opA_EXE;
    endcase
  end
  
  always@(*) begin
    casez (fwd_opB)
      3'b1zz:   opB = fwd1;
      3'b01z:   opB = fwd2;
      3'b001:   opB = fwd3;
      default:  opB = opB_EXE;
    endcase
  end
    
  always@(*) begin
    casez (fwd_sw)
      3'b1zz:   mem_data_EXE = fwd1;                     // fr alu_out_MEM
      3'b01z:   mem_data_EXE = fwd2;                     // fr reg_data_WB
      3'b001:   mem_data_EXE = fwd3;                     // fr reg_data_WB + 1cc  
      default:  mem_data_EXE = mem_data_EXE0;
    endcase
  end
  
  id_exe_reg ID_EXE (
    .clk(clk),
    .nrst(nrst),
    .en(!stall),
    .flush(flush[0]),
    .cur_pc0(pc_ID),
    .cur_pc(pc_EXE),
    .next_pc0(pc_p4_ID),
    .next_pc(pc_p4_EXE),
    .bra_off0(bra_off_ID),
    .bra_off(bra_off_EXE),
    .opA0(opA_ID),
    .opA(opA_EXE),
    .opB0(opB_ID),
    .opB(opB_EXE),
    .mem_data0(mem_data_ID),
    .mem_data(mem_data_EXE0),
    .reg_addr0(reg_addr_ID),
    .reg_addr(reg_addr_EXE)
  );
  
  alu ALU (
    .opA(opA),
    .opB(opB),
    .res(alu_out_EXE),
    .alu_code(alu_code),
    .z(zero)
  );
  
/*-----------------------------------------------------------------------------
MEM
-----------------------------------------------------------------------------*/
  
  assign reg_data_MEM = load ? data_in : (jal_pc ? pc_p4_MEM : alu_out_MEM);
  assign data_addr = alu_out_MEM;
  assign data_out = mem_data_MEM;
  assign data_wr = wr_mem;
  
  assign fwd1 = alu_out_MEM;

  exe_mem_reg EXE_MEM (
    .clk(clk),
    .nrst(nrst),
    .cur_pc0(pc_EXE),
    .cur_pc(pc_MEM),
    .next_pc0(pc_p4_EXE),
    .next_pc(pc_p4_MEM),
    .alu_out0(alu_out_EXE),
    .alu_out(alu_out_MEM),
    .mem_data0(mem_data_EXE),
    .mem_data(mem_data_MEM),
    .reg_addr0(reg_addr_EXE),
    .reg_addr(reg_addr_MEM)
  );
  
/*-----------------------------------------------------------------------------
WB
-----------------------------------------------------------------------------*/
  
  assign fwd2 = reg_data_WB;
  
  mem_wb_reg MEM_WB (
    .clk(clk),
    .nrst(nrst),
    .cur_pc0(pc_MEM),
    .cur_pc(pc_WB),
    .next_pc0(pc_p4_MEM),
    .next_pc(pc_p4_WB),
    .reg_data0(reg_data_MEM),
    .reg_data(reg_data_WB),
    .reg_addr0(reg_addr_MEM),
    .reg_addr(reg_addr_WB)
  );
  
  reg32 FWD_WB (
    .clk(clk),
    .nrst(nrst),
    .en(1'b1),
    .data_in(reg_data_WB),
    .data_out(fwd3)
  );
  
/*-----------------------------------------------------------------------------
CONTROLLER
-----------------------------------------------------------------------------*/
  
  assign data_wr = wr_mem;
  
  control CTRL (
    .clk(clk),
    .nrst(nrst),
    .zero(zero),
    .inst(inst),
    .debug_inst({ inst_WB, inst_MEM, inst_EXE, inst_ID, inst_IF }),
    .alu_code(alu_code),
    .sel_pc(sel_pc),
    .stall(stall),
    .flush(flush),
    .wr_rf(wr_rf),
    .wr_mem(wr_mem),
    .use_imm(use_imm),
    .load(load),
    .jal(jal),
    .jal_pc(jal_pc),
    .jr(jr),
    .fwd_opA(fwd_opA),
    .fwd_opB(fwd_opB),
    .fwd_sw(fwd_sw),
    .fwd_jr(fwd_jr),
    .sw(sw)
  );

endmodule

module control (
  input clk,
  input nrst,
  input zero,
  input [31:0] inst,
  output jr,                                    //
  output jal,                                   //
  output jal_pc,                                //
  output load,                                  //
  output wr_mem,                                //
  output use_imm,                               //
  output sw,                                    //
  output [`PIPELINE_STAGES*32-1:0] debug_inst,  //
  output reg [6:0] alu_code,                    //
  output reg [2:0] sel_pc,                      //
  output reg [1:0] flush,
  output reg wr_rf,                             //
  output stall,
  output [2:0] fwd_opA,                         //        
  output [2:0] fwd_opB,                         //
  output [2:0] fwd_sw,                          //
  output [2:0] fwd_jr                           //    
  );

  genvar i;
  
  wire [5:0] op           [0:4];
  wire [4:0] rd           [0:4];
  wire [4:0] rs1          [0:4];
  wire [4:0] rs2          [0:4];
  wire [6:0] funct        [0:4];
  wire [31:0] inst_cache  [0:4];
  
  assign inst_cache[0] = inst;
  generate
    for (i=0; i<=4; i=i+1) begin
      assign op[i]      = inst_cache[i][5:0];
      assign rd[i]      = inst_cache[i][10:6];
      assign rs1[i]     = inst_cache[i][19:15];
      assign rs2[i]     = inst_cache[i][24:20];
      assign funct[i]   = inst_cache[i][31:25];
    end
  endgenerate
  assign debug_inst = {
    inst_cache[4],                              // WB
    inst_cache[3],                              // MEM
    inst_cache[2],                              // EXE
    inst_cache[1],                              // ID
    inst_cache[0]                               // IF
  };
  
/*-----------------------------------------------------------------------------
inst classification (R, I, L, B, J)
-----------------------------------------------------------------------------*/
  
  reg [4:0] R_type;
  reg [4:0] I_type;
  reg [4:0] L_type;
  reg [4:0] S_type;
  reg [4:0] B_type;
  reg [4:0] J_type;
  generate
    for (i=0; i<=4; i=i+1) begin
      always@(op[i], funct[i]) begin
        R_type[i] = 0;
        I_type[i] = 0;
        L_type[i] = 0;
        S_type[i] = 0;
        B_type[i] = 0;
        J_type[i] = 0;
        case (op[i])
          6'h00:
            if (funct[i]==7'h08)
              J_type[i] = 1;
            else
              R_type[i] = 1;
          6'h08, 6'h0A:
            I_type[i] = 1;
          6'h23:
            L_type[i] = 1;
          6'h2B:
            S_type[i] = 1;
          6'h04, 6'h05:
            B_type[i] = 1;
          6'h02, 6'h03:
            J_type[i] = 1;
          default: begin
            R_type[i] = 0;
            I_type[i] = 0;
            L_type[i] = 0;
            S_type[i] = 0;
            B_type[i] = 0;
            J_type[i] = 0;
          end
        endcase
      end
    end
  endgenerate

/*-----------------------------------------------------------------------------
alu_code
-----------------------------------------------------------------------------*/
  always@(op[2], funct[2]) begin
    case (op[2])
      6'h08, 6'h23, 6'h2B:  alu_code = 7'h20;   // +
      6'h04, 6'h05:         alu_code = 7'h22;   // -
      6'h0A:                alu_code = 7'h2A;   // <
      6'h00:
        if (funct[2]==7'h08)
          alu_code = 7'h20;
        else
          alu_code = funct[2];
      default:              alu_code = 0;
    endcase
  end
  
/*-----------------------------------------------------------------------------
sel_pc
-----------------------------------------------------------------------------*/
  always@(op[1], funct[1], op[2], zero) begin
    case (op[2])
      6'h04: sel_pc[2] = zero;
      6'h05: sel_pc[2] = !zero;
      default: sel_pc[2] = 0;
    endcase
    
    case (op[1])
      6'h02, 6'h03:
        sel_pc[1:0] = 2'b10;
      6'h00:
        if (funct[1]==7'h08)
          sel_pc[1:0] = 2'b01;
        else
          sel_pc[1:0] = 2'b00;
      default:
        sel_pc[1:0] = 0;
    endcase
  end
  
/*-----------------------------------------------------------------------------
jr, jal, jal_pc
-----------------------------------------------------------------------------*/
  assign jr = ((op[1]==0) & (funct[1]==7'h08));
  assign jal = (op[1]==6'h03);
  assign jal_pc = (op[3]==6'h03);
  
/*-----------------------------------------------------------------------------
sw
-----------------------------------------------------------------------------*/
  assign sw = (op[1]==6'h2B);
  
/*-----------------------------------------------------------------------------
use_imm
-----------------------------------------------------------------------------*/
  assign use_imm = I_type[1] || L_type[1] || S_type[1];  

/*-----------------------------------------------------------------------------
load, wr_mem
-----------------------------------------------------------------------------*/
  assign load = L_type[3];
  assign wr_mem = (op[3]==6'h2B);
  
/*-----------------------------------------------------------------------------
wr_rf
-----------------------------------------------------------------------------*/
  always@(op[4]) begin
    case (op[4])
      6'h00, 6'h08, 6'h0A, 6'h23, 6'h03:
        wr_rf = 1;
      default:
        wr_rf = 0;
    endcase
  end

/*-----------------------------------------------------------------------------
dependencies checked @ ID
-----------------------------------------------------------------------------*/
  wire [2:0] Lchk;
  wire [2:0] Ichk;
  wire [2:0] Rchk;
  
  assign Lchk = { L_type[2], L_type[3], L_type[4] };
  assign Ichk = { I_type[2], I_type[3], I_type[4] };
  assign Rchk = { R_type[2], R_type[3], R_type[4] };
  
  wire [2:0] rd_written;
  assign rd_written = Ichk | Rchk | Lchk;
  
  /* 
   * TODO:
   * disable rd check if S, J, or B
   */
  
  reg [2:0] rs1dep;
  reg [5*3-1:0] rs1_chk;
  // rs1 always checked against rd if !J_type
  always@(J_type[1], rd_written, rs1[1], rd[2], rd[3], rd[4]) begin
    if (rs1[1]!=0 && !J_type[1]) begin
      rs1_chk = ~( {3{rs1[1]}} ^ {rd[2], rd[3], rd[4]} );
      rs1dep = {
        (&rs1_chk[14:10]),
        (&rs1_chk[9:5]),
        (&rs1_chk[4:0])
      } & rd_written;
    end else begin
      rs1_chk = 0;
      rs1dep = 0;
    end
  end
  
  reg [2:0] rs2dep;
  reg [5*3-1:0] rs2_chk;
  // rs2 checked against rd if R_type || B_type
  always@(R_type[1], B_type[1], rd_written, rs2[1], rd[2], rd[3], rd[4]) begin
    if (rs2[1]!=0 && (R_type[1] || B_type[1])) begin
      rs2_chk = ~( {3{rs2[1]}} ^ {rd[2], rd[3], rd[4]} );
      rs2dep = {
        (&rs2_chk[14:10]),
        (&rs2_chk[9:5]),
        (&rs2_chk[4:0])        
      } & rd_written;
    end else begin
      rs2_chk = 0;
      rs2dep = 0;
    end
  end
  
  reg [2:0] rddep;
  reg [5*3-1:0] rd_chk;
  // rd checked against rd if JR or SW
  always@(J_type[1], S_type[1], funct[1], rd_written, rd[1], rd[2], rd[3], rd[4]) begin
    if (rd[1]!=0 && ((J_type[1] && funct[1]==7'h08) || S_type[1]==6'h2B)) begin
      rd_chk = ~( {3{rd[1]}} ^ {rd[2], rd[3], rd[4]} );
      rddep = {
        (&rd_chk[14:10]),
        (&rd_chk[9:5]),
        (&rd_chk[4:0])
      } & rd_written;
    end else begin
      rd_chk = 0;
      rddep = 0;
    end
  end
  
/*-----------------------------------------------------------------------------
stall
-----------------------------------------------------------------------------*/
  assign stall = |( (rs1dep | rs2dep | rddep) & Lchk );
  
/*-----------------------------------------------------------------------------
flush
-----------------------------------------------------------------------------*/
  always@(J_type[1], op[2], zero) begin
    if ( (op[2]==6'h04 && zero) || (op[2]==6'h05 && !zero) )
      flush = 2'b11;
    else
      if (J_type[1])
        flush = 2'b10;
      else
        flush = 2'b00;
  end
  
  
  reg_fwd FWD_VECTOR (
    .clk(clk),
    .nrst(nrst),
    .fwd_opA0(rs1dep),
    .fwd_opB0(rs2dep),
    .fwd_jr0(rddep),
    .fwd_opA(fwd_opA),
    .fwd_opB(fwd_opB),
    .fwd_sw(fwd_sw),
    .fwd_jr(fwd_jr)
  );
  
  reg32 if_id (
    .clk(clk),
    .nrst(nrst & !flush[1]),
    .en(!stall),
    .data_in(inst_cache[0]),
    .data_out(inst_cache[1])
  );
  
  reg32 id_exe (
    .clk(clk),
    .nrst(nrst & !flush[0] & !stall),
    .en(1'b1),
    .data_in(inst_cache[1]),
    .data_out(inst_cache[2])
  );
  
  reg32 exe_mem (
    .clk(clk),
    .nrst(nrst),
    .en(1'b1),
    .data_in(inst_cache[2]),
    .data_out(inst_cache[3])
  );
  
  reg32 mem_wb (
    .clk(clk),
    .nrst(nrst),
    .en(1'b1),
    .data_in(inst_cache[3]),
    .data_out(inst_cache[4])
  );
    
endmodule

module if_id_reg (
  input               clk,
  input               nrst,
  input               en,
  input               flush,
  input       [31:0]  cur_pc0,
  input       [31:0]  next_pc0,
  output reg  [31:0]  cur_pc,
  output reg  [31:0]  next_pc
  );
  
  always@(posedge clk) begin
    if (!nrst | flush) begin
      cur_pc <= 0;
      next_pc <= 0;
    end else begin
      if (en) begin
        cur_pc <= cur_pc0;
        next_pc <= next_pc0;
      end
    end
  end
  
endmodule

module id_exe_reg (
  input               clk,
  input               nrst,
  input               en,
  input               flush,
  input       [31:0]  cur_pc0,
  input       [31:0]  next_pc0,
  input       [31:0]  bra_off0,
  input       [31:0]  opA0,
  input       [31:0]  opB0,
  input       [31:0]  mem_data0,
  input       [4:0]   reg_addr0,
  output reg  [31:0]  cur_pc,
  output reg  [31:0]  next_pc,
  output reg  [31:0]  bra_off,
  output reg  [31:0]  opA,
  output reg  [31:0]  opB,
  output reg  [31:0]  mem_data,
  output reg  [4:0]   reg_addr
  );
  
  always@(posedge clk) begin
    if (!nrst | flush | !en) begin
      cur_pc   <= 0;
      next_pc  <= 0;
      bra_off  <= 0;
      opA      <= 0;
      opB      <= 0;
      mem_data <= 0;
      reg_addr <= 0;
    end else begin
      cur_pc   <= cur_pc0;
      next_pc  <= next_pc0;
      bra_off  <= bra_off0;
      opA      <= opA0;
      opB      <= opB0;
      mem_data <= mem_data0;
      reg_addr <= reg_addr0;
    end
  end
  
endmodule

module exe_mem_reg (
  input               clk,
  input               nrst,
  input       [31:0]  cur_pc0,
  input       [31:0]  next_pc0,
  input       [31:0]  alu_out0,
  input       [31:0]  mem_data0,
  input       [4:0]   reg_addr0,
  output reg  [31:0]  cur_pc,
  output reg  [31:0]  next_pc,
  output reg  [31:0]  alu_out,
  output reg  [31:0]  mem_data,
  output reg  [4:0]   reg_addr
  );
  
  always@(posedge clk) begin
    if (!nrst) begin
      cur_pc   <= 0;
      next_pc  <= 0;
      alu_out  <= 0;
      mem_data <= 0;
      reg_addr <= 0;
    end else begin
      cur_pc   <= cur_pc0;
      next_pc  <= next_pc0;
      alu_out  <= alu_out0;
      mem_data <= mem_data0;
      reg_addr <= reg_addr0;
    end
  end
  
endmodule

module mem_wb_reg (
  input               clk,
  input               nrst,
  input       [31:0]  cur_pc0,
  input       [31:0]  next_pc0,
  input       [31:0]  reg_data0,
  input       [4:0]   reg_addr0,
  output reg  [31:0]  cur_pc,
  output reg  [31:0]  next_pc,
  output reg  [31:0]  reg_data,
  output reg  [4:0]   reg_addr
  );
  
  always@(posedge clk) begin
    if (!nrst) begin
      cur_pc  <= 0;
      next_pc  <= 0;
      reg_data <= 0;
      reg_addr <= 0;
    end else begin
      cur_pc   <= cur_pc0;
      next_pc  <= next_pc0;
      reg_data <= reg_data0;
      reg_addr <= reg_addr0;
    end
  end
  
endmodule

module alu (
  input signed      [31:0]  opA,
  input signed      [31:0]  opB,
  output reg signed [31:0]  res,
  input             [6:0]   alu_code,
  output                    z
  );
  
  /*
   * alu_code:
   * 0x20       : +
   * 0x22       : -
   * 0x24       : &
   * 0x25       : |
   * 0x26       : ^
   * 0x2A       : <
   */
  
  reg valid;
  assign z = (~|res)&valid;
  
  always@(*) begin
    valid = 1;
    case (alu_code)
      7'h20: begin
        res = opA + opB;
      end
      7'h22: begin
        res = opA - opB;
      end
      /*
      7'h24:
        res = opA & opB;
      7'h25:
        res = opA | opB;
      7'h26:
        res = opA ^ opB;
      */
      7'h0A, 6'h2A:
        if (opA < opB)
          res = 1;
        else
          res = 0;
      default: begin
        res = 0;
        valid = 0;
      end
    endcase
  end
endmodule

module rf (
  input           clk,
  input           nrst,
  input           wr_en,
  input   [4:0]   rd_addrA,
  input   [4:0]   rd_addrB,
  input   [4:0]   wr_addr,
  input   [31:0]  wr_data,
  output  [31:0]  rd_dataA,
  output  [31:0]  rd_dataB
  );

  reg [31:0] mem [31:0];
  integer i;
  assign rd_dataA = mem[rd_addrA];
  assign rd_dataB = mem[rd_addrB];

	always@(posedge clk) begin
		if (!nrst)
			for (i=0;i<=31;i=i+1)
				mem[i] <= 0;
		else
			if (wr_en)
				if (wr_addr!=0)
					mem[wr_addr] <= wr_data;
	end

endmodule

module reg_fwd(
  input             clk,
  input             nrst,
  input       [2:0] fwd_opA0,
  input       [2:0] fwd_opB0,
  input       [2:0] fwd_jr0,
  output reg  [2:0] fwd_opA,
  output reg  [2:0] fwd_opB,
  output reg  [2:0] fwd_sw,
  output      [2:0] fwd_jr
  );
  
  assign fwd_jr = fwd_jr0;
  
  always@(posedge clk) begin
    if (!nrst) begin
      fwd_opA <= 0;
      fwd_opB <= 0;
      fwd_sw  <= 0;
    end else begin
      fwd_opA <= fwd_opA0;
      fwd_opB <= fwd_opB0;
      fwd_sw  <= fwd_jr0;
    end
  end
endmodule

module reg32(
  input clk,
  input nrst,
  input en,
  input [31:0] data_in,
  output reg [31:0] data_out
  );
  
  always@(posedge clk) begin
    if (!nrst)
      data_out <= 0;
    else
      if (en)
        data_out <= data_in;
  end
endmodule
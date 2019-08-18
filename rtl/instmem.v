`timescale 1ns/1ps
`define MEM_DEPTH  1024*4
`define MEM_WIDTH  8
`define WORD_WIDTH 32
module instmem(
  input clk,
  input       [`WORD_WIDTH-1:0] inst_addr,
  output reg  [`WORD_WIDTH-1:0] inst
  );

  reg [`MEM_WIDTH-1:0] memory [0:`MEM_DEPTH-1];
  
  initial begin
    $readmemh("instmem.txt", memory);
  end

  //Read port
  always@(inst_addr) begin
    inst <= {memory[inst_addr],
             memory[inst_addr+1],
             memory[inst_addr+2],
             memory[inst_addr+3]};
  end
endmodule

`timescale 1ns/1ps
module tb;
  parameter half_cc = 10;
  parameter cc = 2*half_cc;
  integer i, fd;
  reg done;

  reg clk, nrst;
  wire [31:0] inst, mem_data, PC, alu_out, data_out;
  wire wr_en;
  wire [31:0] pc_IF, pc_ID, pc_EXE, pc_MEM, pc_WB;
  
  reg [4:0] test;
  
  pipeline_riscv UUT (
    .clk(clk),
    .nrst(nrst),
    .inst(inst),
    .data_in(mem_data),
    .inst_addr(PC),
    .data_addr(alu_out),
    .data_out(data_out),
    .data_wr(wr_en),
    .pc_IF(pc_IF),
    .pc_ID(pc_ID),
    .pc_EXE(pc_EXE),
    .pc_MEM(pc_MEM),
    .pc_WB(pc_WB)
  );
  
  instmem INST (
    .inst_addr(PC),
    .inst(inst)
  );
  
  datamem DATA (
    .clk(clk),
    .data_wr(wr_en),
    .data_addr(alu_out),
    .data_in(data_out),
    .data_out(mem_data)
  );

  always
    #half_cc clk = ~clk;
    
  always@(posedge clk) begin
    casez (inst)
      32'hxxxxxxxx, 32'h00000000:
        test <= {test[3:0], 1'b1};
      default:
        test <= test << 1;
    endcase
  end
  
  always@(*)
    if (&test) done = 1;
    else done = 0;
      
  initial begin
    $vcdplusfile("test.vpd");
    $vcdpluson;
    // $dumpfile("test_rtl.vpd");
    // $dumpvars(0, tb);
    fd = $fopen("new_datamem.txt", "w");
    
    clk = 0;
    nrst = 0;
    #cc;
    nrst = 1;
    #cc;
    while (!done) begin
      #cc;
    end
    
    for (i=0; i<1024*4; i=i+4) begin
        $fwrite(fd, "%h", DATA.memory[i]);
        $fwrite(fd, "%h", DATA.memory[i+1]);
        $fwrite(fd, "%h", DATA.memory[i+2]);
        $fwrite(fd, "%h\n", DATA.memory[i+3]);
    end
    $fclose(fd);
    $finish;
    
  end

  `ifdef SDF_ANNOTATE
  initial begin
    $sdf_annotate("../mapped/pipeline_riscv.sdf",UUT);
  end
  `endif

endmodule

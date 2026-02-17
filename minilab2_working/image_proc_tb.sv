// tb_image_proc_sobel_simple.sv
`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// behavioral line buffer so simulation doesn't need altera_mf
// -----------------------------------------------------------------------------

module image_proc_tb_final;

  localparam integer W = 640;

  // clock
  reg iCLK;
  initial iCLK = 1'b0;
  always #5 iCLK = ~iCLK;

  // dut i/o
  reg         iRST;      // active-low
  reg  [11:0] iPIX12;
  reg         iDVAL;
  reg         iMODE;
  reg         iCONV_EN;

  wire [11:0] oPIX12;
  wire        oDVAL;

  image_proc dut (
    .iCLK     (iCLK),
    .iRST     (iRST),
    .iPIX12   (iPIX12),
    .iDVAL    (iDVAL),
    .iMODE    (iMODE),
    .iCONV_EN (iCONV_EN),
    .oPIX12   (oPIX12),
    .oDVAL    (oDVAL)
  );

  // ------------------------------------------------------------
  // helpers
  // ------------------------------------------------------------

  // push 1 pixel. dval=0 is bubble.
  task send_pixel(input [11:0] pix, input bit dval);
    begin
      @(posedge iCLK);
      iPIX12 <= pix;
      iDVAL  <= dval;
    end
  endtask

  // send full row with constant pixel value
  task send_row_constant(input [11:0] pix);
    integer x;
    begin
      for (x=0; x<W; x=x+1) send_pixel(pix, 1'b1);
    end
  endtask

  // send a 3-wide patch at x=0..2, rest of row zeros
  task send_row_patch3(input [11:0] p0, input [11:0] p1, input [11:0] p2);
    integer x;
    begin
      send_pixel(p0, 1'b1);
      send_pixel(p1, 1'b1);
      send_pixel(p2, 1'b1);
      for (x=3; x<W; x=x+1) send_pixel(12'd0, 1'b1);
    end
  endtask

  // ------------------------------------------------------------
  // self check helpers
  // ------------------------------------------------------------

  // compare first n valid outputs against expected vector.
  // if anything mismatches, kill sim.
  task automatic check_first_valid(
    input integer n,
    input string  tag,
    input int unsigned exp_vec[]   // dynamic array, each element is 0..4095
  );
    integer seen;
    integer err;
    begin
      seen = 0;
      err  = 0;

      if (exp_vec.size() < n) begin
        $display("[%0t] %s  fail: exp_vec.size()=%0d < n=%0d", $time, tag, exp_vec.size(), n);
        $fatal(1);
      end

      while (seen < n) begin
        @(posedge iCLK);
        if (oDVAL) begin
          if (oPIX12 !== exp_vec[seen][11:0]) begin
            $display("[%0t] %s  fail @idx=%0d  got=%0d (0x%03h)  exp=%0d (0x%03h)",
                     $time, tag, seen, oPIX12, oPIX12, exp_vec[seen][11:0], exp_vec[seen][11:0]);
            err = err + 1;
          end
          seen = seen + 1;
        end
      end

      if (err == 0) begin
        $display("[%0t] %s  pass (%0d samples)", $time, tag, n);
      end else begin
        $display("[%0t] %s  fail (%0d mismatches out of %0d)", $time, tag, err, n);
        $fatal(1);
      end
    end
  endtask

  // helper: build expected arrays from the log you pasted
  task automatic build_exp_vedge(output int unsigned exp[20]);
    int i;
    begin
      for (i=0; i<20; i=i+1) exp[i] = 0;
      exp[5] = 4095;
      exp[6] = 4095;
      exp[7] = 4095;
      exp[8] = 4095;
    end
  endtask

  task automatic build_exp_hedge_mode0(output int unsigned exp[20]);
    int i;
    begin
      for (i=0; i<20; i=i+1) exp[i] = 0;
      exp[4] = 4095;
      exp[5] = 4095;
      exp[6] = 4095;
      exp[7] = 4095;
      exp[8] = 4095;
    end
  endtask

  task automatic build_exp_hedge_mode1(output int unsigned exp[20]);
    int i;
    begin
      for (i=0; i<20; i=i+1) exp[i] = 0;
      exp[4] = 4095;
      exp[5] = 4095;
      exp[6] = 0;
      exp[7] = 4095;
      exp[8] = 4095;
      exp[9] = 0;
    end
  endtask

  // ------------------------------------------------------------
  // stimulus: two patterns
  // ------------------------------------------------------------

  task automatic run_vertical_edge(input bit mode_sel);
    int unsigned exp_fixed[20];
    int unsigned exp_dyn[];
    int i;
    begin
      $display("=== vertical edge test, imode=%0b ===", mode_sel);
      iMODE    = mode_sel;
      iCONV_EN = 1'b1;

      // flush (2 full rows of 0)
      send_row_constant(12'd0);
      send_row_constant(12'd0);

      // three rows with patch at x=0..2
      send_row_patch3(12'd0, 12'hFFF, 12'hFFF);
      send_row_patch3(12'd0, 12'hFFF, 12'hFFF);
      send_row_patch3(12'd0, 12'hFFF, 12'hFFF);

      // expected based on your output log (same for mode0/mode1 in your run)
      build_exp_vedge(exp_fixed);
      exp_dyn = new[20];
      for (i=0; i<20; i=i+1) exp_dyn[i] = exp_fixed[i];

      check_first_valid(20, (mode_sel ? "mode1 vedge" : "mode0 vedge"), exp_dyn);

      exp_dyn.delete();
    end
  endtask

  task automatic run_horizontal_edge(input bit mode_sel);
    int unsigned exp_fixed[20];
    int unsigned exp_dyn[];
    int i;
    begin
      $display("=== horizontal edge test, imode=%0b ===", mode_sel);
      iMODE    = mode_sel;
      iCONV_EN = 1'b1;

      // flush (2 full rows of 0)
      send_row_constant(12'd0);
      send_row_constant(12'd0);

      // top row zeros, next two rows high
      send_row_patch3(12'd0, 12'd0, 12'd0);
      send_row_patch3(12'hFFF, 12'hFFF, 12'hFFF);
      send_row_patch3(12'hFFF, 12'hFFF, 12'hFFF);

      // expected based on your output log
      if (!mode_sel)
        build_exp_hedge_mode0(exp_fixed);
      else
        build_exp_hedge_mode1(exp_fixed);

      exp_dyn = new[20];
      for (i=0; i<20; i=i+1) exp_dyn[i] = exp_fixed[i];

      check_first_valid(20, (mode_sel ? "mode1 hedge" : "mode0 hedge"), exp_dyn);

      exp_dyn.delete();
    end
  endtask

  // ------------------------------------------------------------
  // main
  // ------------------------------------------------------------
  initial begin
    // init
    iPIX12   = 12'd0;
    iDVAL    = 1'b0;
    iMODE    = 1'b0;
    iCONV_EN = 1'b1;

    // reset
    iRST = 1'b0;
    repeat (5) @(posedge iCLK);
    iRST = 1'b1;

    // a couple bubbles
    repeat (5) send_pixel(12'd0, 1'b0);

    // checks (will print pass/fail and fatal on mismatch)
    run_vertical_edge(1'b0);
    run_vertical_edge(1'b1);

    run_horizontal_edge(1'b0);
    run_horizontal_edge(1'b1);

    $display("done.");
    $stop();
  end

endmodule

///////////////////////////////////////////
// fdivsqrtpreproc.sv
//
// Written: David_Harris@hmc.edu, me@KatherineParry.com, cturek@hmc.edu
// Modified:13 January 2022
//
// Purpose: Combined Divide and Square Root Floating Point and Integer Unit
// 
// A component of the Wally configurable RISC-V project.
// 
// Copyright (C) 2021 Harvey Mudd College & Oklahoma State University
//
// MIT LICENSE
// Permission is hereby granted, free of charge, to any person obtaining a copy of this 
// software and associated documentation files (the "Software"), to deal in the Software 
// without restriction, including without limitation the rights to use, copy, modify, merge, 
// publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons 
// to whom the Software is furnished to do so, subject to the following conditions:
//
//   The above copyright notice and this permission notice shall be included in all copies or 
//   substantial portions of the Software.
//
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
//   INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR 
//   PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS 
//   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, 
//   TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE 
//   OR OTHER DEALINGS IN THE SOFTWARE.
////////////////////////////////////////////////////////////////////////////////////////////////

`include "wally-config.vh"

module fdivsqrtpreproc (
  input  logic clk,
  input  logic IFDivStartE, 
  input  logic [`NF:0] Xm, Ym,
  input  logic [`NE-1:0] Xe, Ye,
  input  logic [`FMTBITS-1:0] Fmt,
  input  logic Sqrt,
  input  logic XZeroE,
  input  logic [`XLEN-1:0] ForwardedSrcAE, ForwardedSrcBE, // *** these are the src outputs before the mux choosing between them and PCE to put in srcA/B
	input  logic [2:0] 	Funct3E,
	input  logic MDUE, W64E,
  output logic [`DIVBLEN:0] nE, nM, mM,
  output logic NegQuotM, ALTBM, MDUM, W64M,
  output logic AsM, AZeroM, BZeroM, AZeroE, BZeroE,
  output logic [`NE+1:0] QeM,
  output logic [`DIVb+3:0] X,
  output logic [`DIVb-1:0] DPreproc,
  output logic [`XLEN-1:0] AM
);

  logic  [`DIVb-1:0] XPreproc;
  logic  [`DIVb:0] SqrtX;
  logic  [`DIVb+3:0] DivX;
  logic  [`NE+1:0] QeE;
  // Intdiv signals
  logic  [`DIVb-1:0] IFNormLenX, IFNormLenD;
  logic  [`DIVBLEN:0] mE;
  logic  [`DIVBLEN:0] ZeroDiff, IntBits, RightShiftX;
  logic  [`DIVBLEN:0] pPlusr, pPrCeil, p, ell;
  logic  [`LOGRK:0] pPrTrunc;
  logic  [`DIVb+3:0]  PreShiftX;
  logic  NumZeroE;

  // ***can probably merge X LZC with conversion
  // cout the number of leading zeros

  if (`IDIV_ON_FPU) begin
    logic signedDiv;
    logic  AsE, BsE, ALTBE, NegQuotE;
    logic  [`XLEN-1:0]  AE, BE;
    logic  [`XLEN-1:0] PosA, PosB;

    // Extract inputs, signs, zero, depending on W64 mode if applicable
    assign signedDiv = ~Funct3E[0];
    if (`XLEN==64) begin // 64-bit, supports W64
      assign AsE = signedDiv & (W64E ? ForwardedSrcAE[31] : ForwardedSrcAE[`XLEN-1]);
      assign BsE = signedDiv & (W64E ? ForwardedSrcBE[31] : ForwardedSrcBE[`XLEN-1]);
      assign AE = W64E ? {{(`XLEN-32){AsE}}, ForwardedSrcAE[31:0]} : ForwardedSrcAE;  
      assign BE = W64E ? {{(`XLEN-32){BsE}}, ForwardedSrcBE[31:0]} : ForwardedSrcBE;
      assign AZeroE = W64E ? ~(|ForwardedSrcAE[31:0]) : ~(|ForwardedSrcAE);
      assign BZeroE = W64E ? ~(|ForwardedSrcBE[31:0]) : ~(|ForwardedSrcBE);
    end else begin // 32 bits only
      assign AsE = signedDiv & ForwardedSrcAE[`XLEN-1];
      assign BsE = signedDiv & ForwardedSrcBE[`XLEN-1];
      assign AE = ForwardedSrcAE;
      assign BE = ForwardedSrcBE;
      assign AZeroE = ~(|ForwardedSrcAE);
      assign BZeroE = ~(|ForwardedSrcBE);
    end

    // Quotient is negative
    assign NegQuotE = (AsE ^ BsE) & MDUE;
    
    // Force inputs to be postiive
    assign PosA = AsE ? -AE : AE;
    assign PosB = BsE ? -BE : BE;

    // Select integer or floating point inputs 
    assign IFNormLenX = MDUE ? {PosA, {(`DIVb-`XLEN){1'b0}}} : {Xm, {(`DIVb-`NF-1){1'b0}}};
    assign IFNormLenD = MDUE ? {PosB, {(`DIVb-`XLEN){1'b0}}} : {Ym, {(`DIVb-`NF-1){1'b0}}};

    // Difference in number of leading zeros
    assign ZeroDiff = mE - ell;
    assign ALTBE = ZeroDiff[`DIVBLEN]; // A less than B
    assign p = ALTBE ? '0 : ZeroDiff;

  /* verilator lint_off WIDTH */
    // right shift amount to complete in discrete number of steps
    assign pPlusr = (`DIVBLEN)'(`LOGR) + p;
    assign pPrTrunc = pPlusr % `RK;
    assign pPrCeil = (pPlusr >> `LOGRK) + {{`DIVBLEN{1'b0}}, |(pPrTrunc)};
    assign nE = (pPrCeil * (`DIVBLEN+1)'(`DIVCOPIES)) - {{(`DIVBLEN){1'b0}}, 1'b1};
    assign IntBits = (`DIVBLEN)'(`LOGR) + p - {{(`DIVBLEN){1'b0}}, 1'b1};
    assign RightShiftX = ((`DIVBLEN)'(`RK) - 1) - (IntBits % `RK);
  /* verilator lint_on WIDTH */

    // Selet integer or floating-point operands
    assign NumZeroE = MDUE ? AZeroE : XZeroE;
    assign X = MDUE ? DivX >> RightShiftX : PreShiftX;

    // pipeline registers
    flopen #(1)        mdureg(clk, IFDivStartE, MDUE, MDUM);
    flopen #(1)        w64reg(clk, IFDivStartE, W64E, W64M);
    flopen #(`DIVBLEN+1) nreg(clk, IFDivStartE, nE, nM);
    flopen #(`DIVBLEN+1) mreg(clk, IFDivStartE, mE, mM);
    flopen #(1)       altbreg(clk, IFDivStartE, ALTBE, ALTBM);
    flopen #(1)    negquotreg(clk, IFDivStartE, NegQuotE, NegQuotM);
    flopen #(1)      azeroreg(clk, IFDivStartE, AZeroE, AZeroM);
    flopen #(1)      bzeroreg(clk, IFDivStartE, BZeroE, BZeroM);
    flopen #(1)      asignreg(clk, IFDivStartE, AsE, AsM);
    flopen #(`XLEN)   srcareg(clk, IFDivStartE, AE, AM);

  end else begin
    assign IFNormLenX = {Xm, {(`DIVb-`NF-1){1'b0}}};
    assign IFNormLenD = {Ym, {(`DIVb-`NF-1){1'b0}}};
    assign NumZeroE = XZeroE;
    assign X = PreShiftX;
  end

  // count leading zeros for denorm FP and to normalize integer inputs
  lzc #(`DIVb) lzcX (IFNormLenX, ell);
  lzc #(`DIVb) lzcY (IFNormLenD, mE);

  // Normalization shift
  assign XPreproc = IFNormLenX << (ell + {{`DIVBLEN{1'b0}}, 1'b1}); 
  assign DPreproc = IFNormLenD << (mE + {{`DIVBLEN{1'b0}}, 1'b1}); 

  //  append leading 1 (for nonzero inputs) and zero-extend
  assign SqrtX = (Xe[0]^ell[0]) ? {1'b0, ~NumZeroE, XPreproc[`DIVb-1:1]} : {~NumZeroE, XPreproc}; // Bottom bit of XPreproc is always zero because DIVb is larger than XLEN and NF
  assign DivX = {3'b000, ~NumZeroE, XPreproc};

  // *** explain why X is shifted between radices (initial assignment of WS=RX)
  if (`RADIX == 2)  assign PreShiftX = Sqrt ? {3'b111, SqrtX} : DivX;
  else              assign PreShiftX = Sqrt ? {2'b11, SqrtX, 1'b0} : DivX;

  // Floating-point exponent
  fdivsqrtexpcalc expcalc(.Fmt, .Xe, .Ye, .Sqrt, .XZero(XZeroE), .ell, .m(mE), .Qe(QeE));

  flopen #(`NE+2)    expreg(clk, IFDivStartE, QeE, QeM);
endmodule


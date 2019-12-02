/********************************************
	FPGA Atari-Tetris

					Copyright (c) 2019 MiSTer-X
*********************************************/
module FPGA_ATETRIS
(
	input 			MCLK,		// 14.318MHz
	input				RESET,
	
	input  [10:0]	INP,		// Negative Logic

	input   [8:0]	HPOS,
	input   [8:0]	VPOS,
	output			PCLK,
	output  [7:0]	POUT,
	
	output [15:0]	AOUT,

	input				ROMCL,	// Download ROM image
	input  [16:0]	ROMAD,
	input   [7:0]	ROMDT,
	input				ROMEN
);

// INP = {`SELFT,`COIN2,`COIN1,`P2LF,`P2RG,`P2DW,`P2RO,`P1LF,`P1RG,`P1DW,`P1RO};


// Reset Line
wire 			WDRST;
wire			RST = WDRST|RESET;


// CPU-Bus
wire [15:0] CPUAD;
wire  [7:0] CPUDO,CPUDI;
wire			CPUWR,CPUIRQ;


// Clock Generator
wire PCLKx2,CPUCL,DEVCL;
ATETRIS_CLKGEN cgen(MCLK,PCLKx2,PCLK,CPUCL,DEVCL);


// ROMs
wire [15:0] PRAD;
wire  [7:0] PRDT;

wire			CRCL;
wire [15:0] CRAD;
wire  [7:0] CRDT;

DLROM #(16,8) prom(DEVCL,PRAD,PRDT, ROMCL,ROMAD,ROMDT,ROMEN & ~ROMAD[16]);
DLROM #(16,8) crom( CRCL,CRAD,CRDT, ROMCL,ROMAD,ROMDT,ROMEN &  ROMAD[16]);


// ROM Bank Control
wire			PRDV;
ATETRIS_ROMAXS romaxs(RST,DEVCL,CPUAD,PRAD,PRDV);


// RAMs
wire [7:0]  RMDT;
wire		   RMDV;
ATETRIS_RAMS rams(DEVCL,CPUAD,CPUWR,CPUDO,RMDT,RMDV);


// Video
wire [7:0]	VDDT;
wire			VDDV;
wire			VBLK;
ATETRIS_VIDEO video(
	PCLKx2,PCLK,HPOS,VPOS,
	POUT,VBLK,
	CRCL,CRAD,CRDT,
	DEVCL,CPUAD,CPUDO,CPUWR,VDDT,VDDV
);


// Sound & Input port
wire [7:0]	P0 = {INP[10],VBLK,4'b1111,INP[8],INP[9]};
wire [7:0]	P1 =  INP[7:0];

wire [7:0]	SNDT;
wire			SNDV;

ATETRIS_SOUND sound(
	RST,P0,P1,
	AOUT,
	DEVCL,CPUAD,CPUDO,CPUWR,SNDT,SNDV
);


// IRQ Generator & Watch-Dog Timer
ATETRIS_IRQWDT irqwdt(RST,VPOS, DEVCL,CPUAD,CPUWR, CPUIRQ,WDRST);


// CPU data selector
wire dum;
DSEL4x8 dsel(dum,CPUDI,
	SNDV,SNDT,
	VDDV,VDDT,
	RMDV,RMDT,
	PRDV,PRDT
);

// CPU
CPU6502W cpu(RST,CPUCL,CPUAD,CPUWR,CPUDO,CPUDI,CPUIRQ);

endmodule


module ATETRIS_CLKGEN
(
	input				MCLK,		//  14.318MHz

	output			PCLKx2,	//  14.318MHz
	output			PCLK,		//  7.1590MHz

	output			CPUCL,	//  1.1789MHz
	output			DEVCL		// ~1.1789MHz
);

reg [2:0] clkdiv;
always @(posedge MCLK) clkdiv <= clkdiv+1;

assign PCLKx2 = MCLK;
assign PCLK   = clkdiv[0];

assign CPUCL  = clkdiv[2];
assign DEVCL  = ~CPUCL;

endmodule


module ATETRIS_ROMAXS
(
	input				RESET,
	input				DEVCL,
	input  [15:0]	CPUAD,
	
	output [15:0]	PRAD,
	output 			PRDV
);

wire [1:0] BS;
ATARI_SLAPSTIK1 bnkctr(RESET,DEVCL,(CPUAD[15:13]==3'b011),CPUAD[12:0],BS);

assign PRAD = {CPUAD[15],(CPUAD[15] ? CPUAD[14] : BS[0]),CPUAD[13:0]};
assign PRDV = (CPUAD[15]|(CPUAD[15:14]==2'b01));

endmodule


module ATETRIS_RAMS
(
	input				DEVCL,
	input  [15:0]	CPUAD,
	input				CPUWR,
	input   [7:0]	CPUDO,
	output  [7:0]	RMDT,
	output			RMDV
);

// WorkRAM
wire			WRDV = (CPUAD[15:12]==4'b0000);				// $0000-$0FFF
wire  [7:0] WRDT;
RAM_B #(12)	wram(DEVCL,CPUAD,WRDV,CPUWR,CPUDO,WRDT);

// NVRAM
wire			NVDV = (CPUAD[15:10]==6'b0010_01);			// $24xx-$27xx
wire  [7:0] NVDT;
RAM_B #(9,255)	nvram(DEVCL,CPUAD,NVDV,CPUWR,CPUDO,NVDT);

DSEL4x8 dsel(RMDV,RMDT,
	WRDV,WRDT,
	NVDV,NVDT
);

endmodule


module ATETRIS_IRQWDT
(
	input				RESET,
	input	  [8:0]	VP,

	input				DEVCL,
	input  [15:0]	CPUAD,
	input				CPUWR,

	output reg		IRQ = 0,
	output			WDRST
);

wire tWDTR = (CPUAD[15:10]==6'b0011_00) & CPUWR;	// $3000-$33FF
wire tIRQA = (CPUAD[15:10]==6'b0011_10) & CPUWR;	// $3800-$3BFF

// IRQ Generator
reg [8:0] pVP;
always @(posedge DEVCL) begin
	if (RESET) begin
		IRQ <= 0;
		pVP <= 0;
	end
	else begin
		if (tIRQA) IRQ <= 0;
		else if (pVP!=VP) begin
			case (VP)
				48,112,176,240: IRQ <= 1;
				80,144,208, 16: IRQ <= 0;
				default:;
			endcase
			pVP <= VP;
		end
	end
end

// Watch-Dog Timer
reg [3:0] WDT = 0;
assign WDRST = WDT[3];

reg [8:0] pVPT;
always @(posedge DEVCL) begin
	if (tWDTR) WDT <= 0;
	else if (pVPT!=VP) begin
		if (VP==0) WDT <= (WDT==8) ? 14 : (WDT+1);
		pVPT <= VP;
	end
end

endmodule


module ATETRIS_VIDEO
(
	input				PCLKx2,
	input				PCLK,
	input	  [8:0]	HPOS,
	input	  [8:0]	VPOS,

	output  [7:0]	POUT,
	output			VBLK,

	output			CRCL,
	output [15:0]	CRAD,
	input   [7:0]	CRDT,

	input				CPUCL,
	input  [15:0]	CPUAD,
	input   [7:0]	CPUDO,
	input				CPUWR,
	output  [7:0]	VDDT,
	output			VDDV
);

wire [8:0] HP = HPOS+1;
wire [8:0] VP = VPOS;

// PlayField scanline generator
wire [10:0] VRAD = {VP[7:3],HP[8:3]};
wire [15:0] VRDT;

(* preserve *) reg [5:0] CH;
always @(posedge PCLK) CH <= {VP[2:0],HP[2:0]};

assign CRCL = ~PCLKx2;
assign CRAD = {VRDT[10:0],CH[5:1]};
wire  [3:0] OPIX = CH[0] ? CRDT[3:0] : CRDT[7:4];
reg   [7:0] PALT;
always @(negedge PCLK) PALT <= {VRDT[15:12],OPIX};

assign VBLK = (VPOS>=240);


// CPU interface
wire csP = (CPUAD[15:10]==6'b0010_00);	// $2000-$23FF
wire csV = (CPUAD[15:12]==4'b0001);		// $1000-$1FFF
wire csH = csV &  CPUAD[0];
wire csL = csV & ~CPUAD[0];

wire wrH = csH & CPUWR;
wire wrL = csL & CPUWR;
wire wrP = csP & CPUWR;

wire [7:0] vdtH,vdtL,palD;

DSEL4x8 dsel(VDDV,VDDT,
	csP,palD,
   csH,vdtH,
	csL,vdtL
);

// VideoRAMs
DPRAMrw #(11,8) vrmH(PCLK,VRAD,VRDT[15:8], CPUCL,CPUAD[11:1],CPUDO,wrH,vdtH);
DPRAMrw #(11,8) vrmL(PCLK,VRAD,VRDT[ 7:0], CPUCL,CPUAD[11:1],CPUDO,wrL,vdtL);
DPRAMrw #(8,8)  palt(~PCLKx2,PALT,POUT,    CPUCL,CPUAD[ 7:0],CPUDO,wrP,palD);

endmodule


module ATETRIS_SOUND
(
	input				RESET,
	input   [7:0]	INP0,
	input   [7:0]	INP1,

	output [15:0]	AOUT,

	input				DEVCL,
	input  [15:0]	CPUAD,
	input   [7:0]	CPUDO,
	input				CPUWR,
	output  [7:0]	SNDT,
	output			SNDV
);

wire csPx = (CPUAD[15:10]==6'b0010_10);
wire csP0 = (CPUAD[5:4]==2'b00) & csPx;	// $280x
wire csP1 = (CPUAD[5:4]==2'b01) & csPx;	// $281x

wire [7:0] rdt0,rdt1;
wire [7:0] snd0,snd1;
PokeyW p0(DEVCL,RESET, CPUAD,csP0,CPUWR,CPUDO,rdt0, INP0,snd0);
PokeyW p1(DEVCL,RESET, CPUAD,csP1,CPUWR,CPUDO,rdt1, INP1,snd1);

DSEL4x8 dsel(SNDV,SNDT,
	csP0,rdt0,
	csP1,rdt1
);

wire [8:0] snd = snd0+snd1;
assign AOUT = {snd,7'h0};

endmodule


// CPU-IP wrapper
module CPU6502W
(
	input				RST,
	input				CLK,

	output [15:0]	AD,
	output 			WR,
	output  [7:0]	DO,
	input	  [7:0]	DI,

	input				IRQ
);

wire   rw;
assign WR = ~rw;

T65 cpu
(
	.mode(2'b01),
	.BCD_en(1'b1),
	.res_n(~RST),
	.enable(1'b1),
	.clk(CLK),
	.rdy(1'b1),
	.abort_n(1'b1),
	.irq_n(~IRQ),
	.nmi_n(1'b1),
	.so_n(1'b1),
	.r_w_n(rw),
	.a(AD),
	.di(DI),
	.do(DO)
);

endmodule


// Pokey-IP wrapper
module PokeyW
(
	input				CLK,

	input				RST,
	input  [3:0]	AD,
	input				CS,
	input				WE,
	input  [7:0]	WD,
	output [7:0]	RD,

	input  [7:0]	P,
	output [7:0]	SND
);

wire [3:0] ch0,ch1,ch2,ch3;

pokey core (
	.RESET_N(~RST),
	.CLK(CLK),
	.ADDR(AD),
	.DATA_IN(WD),
	.DATA_OUT(RD),
	.WR_EN(WE & CS),
	.ENABLE_179(1'b1),
	.POT_IN(P),
	
	.CHANNEL_0_OUT(ch0),
	.CHANNEL_1_OUT(ch1),
	.CHANNEL_2_OUT(ch2),
	.CHANNEL_3_OUT(ch3)
);

assign SND = ch0+ch1+ch2+ch3;

endmodule


// Data selector
module DSEL4x8
(
	output		 odv,
	output [7:0] odt,

	input en0, input [7:0] dt0,
	input en1, input [7:0] dt1,
	input en2, input [7:0] dt2,
	input en3, input [7:0] dt3
);

assign odv = en0|en1|en2|en3;

assign odt = en0 ? dt0 :
				 en1 ? dt1 :
				 en2 ? dt2 :
				 en3 ? dt3 :
				 8'h00;

endmodule


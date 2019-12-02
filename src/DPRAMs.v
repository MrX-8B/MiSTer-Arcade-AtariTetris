// Copyright (c) 2019 MiSTer-X

module DPRAMrw #(AW=8,DW=8)
(
	input 					CL0,
	input [AW-1:0]			AD0,
	output reg [DW-1:0]	RD0,

	input 					CL1,
	input [AW-1:0]			AD1,
	input [DW-1:0]			WD1,
	input						WE1,
	output reg [DW-1:0] 	RD1
);

reg [7:0] core[0:((2**AW)-1)];

always @(posedge CL0) RD0 <= core[AD0];
always @(posedge CL1) if (WE1) core[AD1] <= WD1; else RD1 <= core[AD1];

endmodule


module RAM_B #(AW=8,IV=0)
(
	input					cl,
	input	 [(AW-1):0]	ad,
	input					en,
	input					wr,
	input   [7:0]		id,
	output reg [7:0]	od
);

reg [7:0] core [0:((2**AW)-1)];

always @( posedge cl ) begin
	if (en) begin
		if (wr) core[ad] <= id;
		else od <= core[ad];
	end
end

integer i;
initial begin
	for(i=0;i<(2**AW);i=i+1)
		core[i]=IV;
end

endmodule


module DLROM #(parameter AW,parameter DW)
(
	input							CL0,
	input [(AW-1):0]			AD0,
	output reg [(DW-1):0]	DO0,

	input							CL1,
	input [(AW-1):0]			AD1,
	input	[(DW-1):0]			DI1,
	input							WE1
);

reg [(DW-1):0] core[0:((2**AW)-1)];

always @(posedge CL0) DO0 <= core[AD0];
always @(posedge CL1) if (WE1) core[AD1] <= DI1;

endmodule



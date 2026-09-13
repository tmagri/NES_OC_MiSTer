
module spram #(
	parameter addr_width    = 10,
	parameter data_width    = 8,
	parameter mem_name      = "",
	parameter mem_init_file = "",
	parameter clock2        = 0
) (
	input                    clock,
	input  [addr_width-1:0]  address,
	input  [data_width-1:0]  data,
	input                    wren,
	output reg [data_width-1:0] q
);
	// SIM: synthetic content (the real spram loads a .mif). A ramp keeps any
	// palette index nonzero so video-alive checks work.
	reg [data_width-1:0] m [0:(1<<addr_width)-1];
	integer si;
	initial begin
		for (si = 0; si < (1<<addr_width); si = si + 1)
			m[si] = {data_width{1'b0}} | (si * (2**data_width / (1<<addr_width) + 1));
		q = m[0];
	end
	always @(posedge clock) begin
		if (wren) m[address] <= data;
		q <= m[address];
	end
	wire unused = &{1'b0, clock2, mem_name, mem_init_file};
endmodule

// Lint-only stubs for the VHDL entities (never synthesized - local tooling file).
// Keeps verilator able to elaborate the pure-SystemVerilog/Verilog core.

module T65 (
	input  [1:0]  mode,
	input         BCD_en,
	input         res_n,
	input         pwr_n,
	input         clk,
	input         enable,
	input         rdy,
	input         abort_n,
	input         IRQ_n,
	input         NMI_n,
	input         so_n,
	output        R_W_n,
	output        sync,
	output        ef,
	output        mf,
	output        xf,
	output        ml,
	output        vp,
	output        vpa,
	output [7:0]  DO,
	output        Instrnew,
	input  [23:0] DI,
	output [23:0] A,
	input [63:0]  SaveStateBus_Din,
	input [9:0]   SaveStateBus_Adr,
	input         SaveStateBus_wren,
	input         SaveStateBus_rst,
	input         SaveStateBus_load,
	output [63:0] SaveStateBus_Dout
);
// Behavioral mini-6502 for simulation ONLY (Quartus never sees this file).
// Supports: A9/A2 (LD imm), 8D (STA abs), E8 (INX), D0 (BNE), 4C (JMP),
// EA (NOP), plus the reset vector fetch. One bus cycle per Enable pulse;
// A/R_W_n/DO are presented for the whole cycle like the real T65, and DI is
// latched at the Enable edge. Invariant: while fetching address X, PC = X+1.
	reg [7:0]  op, acc, xreg, dout_r;
	reg [15:0] pc, ea;
	reg [2:0]  st;         // 0=fetch done->decode, 1=operand(lo/rel/imm), 2=hi, 3=write cycle
	reg [1:0]  rst_seq;
	reg        rw;
	reg [23:0] addr_r;

	assign R_W_n = rw;
	assign A  = addr_r;
	assign DO = dout_r;
	assign sync = (st == 0);
	assign ef = 0; assign mf = 0; assign xf = 0; assign ml = 0; assign vp = 0; assign vpa = 0;
	assign Instrnew = (st == 0);
	assign SaveStateBus_Dout = 64'b0;

	wire [7:0] din = DI[7:0];
	wire       go = enable && rdy && res_n;

	always @(posedge clk) begin
		if (!res_n) begin
			st <= 3'd4; rw <= 1'b1; rst_seq <= 2'd0;
			pc <= 16'hFFFD; addr_r <= 24'h00FFFC;  // PC = FFFD (invariant), fetch FFFC
		end else if (go) begin
			if (rst_seq == 2'd0) begin            // fetched FFFC -> vector lo
				pc[7:0] <= din;
				addr_r  <= 24'h00FFFD;
				rst_seq <= 2'd1;
			end else if (rst_seq == 2'd1) begin   // fetched FFFD -> vector hi; PC = entry+1
				pc     <= {8'h00, din, pc[7:0]} + 16'd1;
				addr_r <= {8'h00, din, pc[7:0]};
				st     <= 3'd0;
				rst_seq <= 2'd2;
			end else begin
				case (st)
					3'd0: begin // opcode in din; PC = entry+1 = operand/next addr
						op <= din;
						rw <= 1'b1; addr_r <= pc;
						case (din)
							8'hA9, 8'hA2, 8'h8D, 8'h4C, 8'hD0: begin st <= 3'd1; pc <= pc + 16'd1; end
							default:                           begin st <= 3'd0; pc <= pc + 16'd1; end // NOP
						endcase
					end
					3'd1: begin // operand byte in din
						case (op)
							8'hA9: begin acc <= din; st <= 3'd0; rw <= 1'b1; addr_r <= pc; pc <= pc + 16'd1; end
							8'hA2: begin xreg <= din; st <= 3'd0; rw <= 1'b1; addr_r <= pc; pc <= pc + 16'd1; end
							8'h8D, 8'h4C: begin ea[7:0] <= din; st <= 3'd2; rw <= 1'b1; addr_r <= pc; pc <= pc + 16'd1; end
							8'hD0: begin
								if (xreg != 8'h00) begin
									addr_r <= pc + {{8{din[7]}}, din};
									pc     <= pc + {{8{din[7]}}, din} + 16'd1;
								end else begin
									addr_r <= pc;
									pc     <= pc + 16'd1;
								end
								st <= 3'd0; rw <= 1'b1;
							end
							default: begin st <= 3'd0; rw <= 1'b1; addr_r <= pc; pc <= pc + 16'd1; end
						endcase
					end
					3'd2: begin // operand hi in din
						ea[15:8] <= din;
						if (op == 8'h4C) begin
							addr_r <= {din, ea[7:0]};
							pc     <= {din, ea[7:0]} + 16'd1;
							st     <= 3'd0; rw <= 1'b1;
						end else begin
							addr_r <= {din, ea[7:0]};
							dout_r <= acc;
							rw     <= 1'b0;          // STA write cycle
							st     <= 3'd3;
						end
					end
					3'd3: begin // write cycle finished -> next opcode fetch
						st <= 3'd0; rw <= 1'b1; addr_r <= pc;
					end
					default: begin st <= 3'd0; rw <= 1'b1; addr_r <= pc; end
				endcase
			end
		end
	end

wire unused = &{1'b0, mode, BCD_en, pwr_n, clk, abort_n, IRQ_n, NMI_n, so_n, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_load};
endmodule

module eReg_SavestateV #(
	parameter [9:0]  IDX = 10'd0,
	parameter [63:0] DEF = 64'd0
) (
	input        clk,
	input [63:0] din,
	input [9:0]  adr,
	input        wren,
	input        rst,
	output [63:0] dout,
	input [63:0] back,
	output [63:0] reg_out
);
	assign dout    = 64'b0;
	assign reg_out = back;
	wire unused = &{1'b0, clk, din, adr, wren, rst, IDX, DEF};
endmodule

module dpram #(
	parameter widthad_a = 10,
	parameter width_a   = 8,
	parameter widthad_b = widthad_a,
	parameter width_b   = width_a,
	parameter use_byteena = 1
) (
	input                    clock_a,
	input  [widthad_a-1:0]   address_a,
	input  [width_a-1:0]     data_a,
	input                    wren_a,
	input  [(use_byteena ? (width_a+7)/8 : 1)-1:0] byteena_a,
	output reg [width_a-1:0] q_a,
	input                    clock_b,
	input  [widthad_b-1:0]   address_b,
	input  [width_b-1:0]     data_b,
	input                    wren_b,
	input  [(use_byteena ? (width_b+7)/8 : 1)-1:0] byteena_b,
	output reg [width_b-1:0] q_b
);
	always @(posedge clock_a) q_a <= data_a;
	always @(posedge clock_b) q_b <= data_b;
	wire unused = &{1'b0, address_a, wren_a, byteena_a, address_b, wren_b, byteena_b};
endmodule

module eseopll (
	input        clk,
	input        ena,
	input        ce,
	input        wr,
	input        req,
	output reg   ack,
	input        wr2,
	input [15:0] adr,
	input [7:0]  dbo,
	output reg [13:0] audio
);
	always @(posedge clk) begin
		ack   <= req;
		audio <= 14'd0;
	end
	wire unused = &{1'b0, ena, ce, wr, wr2, adr, dbo};
endmodule

module savestates (
	input        clk,
	input        reset_in,
	input        reset_ss,
	input        reset_delay,
	output       load_done,
	input        increaseSSHeaderCount,
	input        save,
	input        load,
	input [31:0] savestate_address,
	input        savestate_busy,
	input        paused,
	input [63:0] BUS_Din,
	input [9:0]  BUS_Adr,
	input        BUS_wren,
	input        BUS_rst,
	input [63:0] BUS_Dout,
	output       loading_savestate,
	output       saving_savestate,
	output       sleep_savestate,
	output [24:0] Save_RAMAddr,
	output        Save_RAMRdEn,
	output        Save_RAMWrEn,
	output [7:0]  Save_RAMWriteData,
	input  [7:0]  Save_RAMReadData,
	output [2:0]  Save_RAMType,
	output [7:0]  bus_out_Din,
	input  [7:0]  bus_out_Dout,
	output [25:0] bus_out_Adr,
	output        bus_out_rnw,
	output        bus_out_ena,
	output [7:0]  bus_out_be,
	input         bus_out_done
);
	assign load_done = 1'b0;
	assign loading_savestate = 1'b0;
	assign saving_savestate = 1'b0;
	assign sleep_savestate = 1'b0;
	assign Save_RAMAddr = 25'd0;
	assign Save_RAMRdEn = 1'b0;
	assign Save_RAMWrEn = 1'b0;
	assign Save_RAMWriteData = 8'd0;
	assign Save_RAMType = 3'd0;
	assign bus_out_Din = 8'd0;
	assign bus_out_Adr = 26'd0;
	assign bus_out_rnw = 1'b0;
	assign bus_out_ena = 1'b0;
	assign bus_out_be = 8'd0;
	wire unused = &{1'b0, clk, reset_in, reset_ss, reset_delay, increaseSSHeaderCount, save, load, savestate_address, savestate_busy, paused, BUS_Din, BUS_Adr, BUS_wren, BUS_rst, BUS_Dout, Save_RAMReadData, bus_out_Dout, bus_out_done};
endmodule

module statemanager #(
	parameter SS_ADDR = 0,
	parameter SS_SIZE = 0
) (
	input        clk,
	input        reset,
	input        rewind_on,
	input        rewind_active,
	input [1:0]  savestate_number,
	input        save,
	input        load,
	output       sleep_rewind,
	input        vsync,
	input        request_savestate,
	input        request_loadstate,
	input [31:0] request_address,
	output       request_busy
);
	assign sleep_rewind = 1'b0;
	assign request_busy = 1'b0;
	wire unused = &{1'b0, clk, reset, rewind_on, rewind_active, savestate_number, save, load, vsync, request_savestate, request_loadstate, request_address, SS_ADDR, SS_SIZE};
endmodule

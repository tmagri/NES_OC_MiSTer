// Channel-faithful behavioral replacement for rtl/sdram.sv (SIM ONLY).
// Same port list so NES.sv's `.*` connections still bind.
// Protocol modeled from rtl/sdram.sv:
//   - request = rising edge of rd|wr per channel; held requests are
//     accepted when the channel is free (old_rd ack semantics)
//   - accept priority ch0 > ch1 > ch2 (IDLE branch order)
//   - busy pulses while servicing; read data valid when busy drops
//   - byte lane = addr[0]; byte-addressed 32MB memory
//   - ss_load injects dout values

module sdram_sim (
	inout  reg [15:0] SDRAM_DQ,
	output reg [12:0] SDRAM_A,
	output reg        SDRAM_DQML,
	output reg        SDRAM_DQMH,
	output reg  [1:0] SDRAM_BA,
	output reg        SDRAM_nCS,
	output reg        SDRAM_nWE,
	output reg        SDRAM_nRAS,
	output reg        SDRAM_nCAS,
	output            SDRAM_CLK,
	output            SDRAM_CKE,

	input             init,
	input             clk,

	input      [24:0] ch0_addr,
	input             ch0_rd,
	input             ch0_wr,
	input       [7:0] ch0_din,
	output reg  [7:0] ch0_dout,
	output reg        ch0_busy,

	input      [24:0] ch1_addr,
	input             ch1_rd,
	input             ch1_wr,
	input       [7:0] ch1_din,
	output reg  [7:0] ch1_dout,
	output reg        ch1_busy,

	input      [24:0] ch2_addr,
	input             ch2_rd,
	input             ch2_wr,
	input       [7:0] ch2_din,
	output reg  [7:0] ch2_dout,
	output reg        ch2_busy,

	input             refresh,
	input      [15:0] ss_in,
	input             ss_load,
	output     [15:0] ss_out
);

	assign SDRAM_nCS  = 1'b0;
	assign SDRAM_CKE  = 1'b1;
	assign SDRAM_DQ   = 16'hZZZZ;
	assign SDRAM_A    = 13'h0;
	assign SDRAM_DQML = 1'b0;
	assign SDRAM_DQMH = 1'b0;
	assign SDRAM_BA   = 2'b00;
	assign SDRAM_nWE  = 1'b1;
	assign SDRAM_nRAS = 1'b1;
	assign SDRAM_nCAS = 1'b1;
	assign SDRAM_CLK  = clk;

	reg [7:0] mem [0:(1<<25)-1];

	reg [24:0] svc_addr;
	reg [7:0]  svc_din;
	reg        svc_we;
	reg [1:0]  svc_ch;
	reg [2:0]  svc_cnt;
	reg        servicing = 0;

	wire [2:0] rd  = {ch2_rd, ch1_rd, ch0_rd};
	wire [2:0] wr  = {ch2_wr, ch1_wr, ch0_wr};
	wire [2:0] req = rd | wr;

	reg [2:0] prev_req = 3'b000;   // request lines as seen last cycle
	reg [2:0] acked    = 3'b000;   // held requests already accepted (index by channel)

	wire [2:0] new_req = req & ~prev_req;   // fresh requests this cycle

	integer i;
	initial for (i = 0; i < (1<<25); i = i + 1) mem[i] = 8'h00;

	always @(posedge clk) begin
		prev_req <= req;

		if (!servicing) begin
			// pending = fresh request OR held request not yet acked
			if ((new_req[0] || (req[0] && !acked[0]))) begin
				servicing <= 1; svc_we <= wr[0]; svc_ch <= 2'd0;
				svc_addr <= ch0_addr; svc_din <= ch0_din; svc_cnt <= 3'd5;
				ch0_busy <= 1'b1;
				acked[0] <= 1'b1;
			end else if ((new_req[1] || (req[1] && !acked[1]))) begin
				servicing <= 1; svc_we <= wr[1]; svc_ch <= 2'd1;
				svc_addr <= ch1_addr; svc_din <= ch1_din; svc_cnt <= 3'd5;
				ch1_busy <= 1'b1;
				acked[1] <= 1'b1;
			end else if ((new_req[2] || (req[2] && !acked[2]))) begin
				servicing <= 1; svc_we <= wr[2]; svc_ch <= 2'd2;
				svc_addr <= ch2_addr; svc_din <= ch2_din; svc_cnt <= 3'd5;
				ch2_busy <= 1'b1;
				acked[2] <= 1'b1;
			end
		end else begin
			svc_cnt <= svc_cnt - 3'd1;
			if (svc_cnt == 3'd1) begin
				if (svc_we) mem[svc_addr] <= svc_din;
				case (svc_ch)
					2'd0: begin ch0_busy <= 1'b0; if (!svc_we) ch0_dout <= mem[svc_addr]; end
					2'd1: begin ch1_busy <= 1'b0; if (!svc_we) ch1_dout <= mem[svc_addr]; end
					2'd2: begin ch2_busy <= 1'b0; if (!svc_we) ch2_dout <= mem[svc_addr]; end
				endcase
				servicing <= 0;
			end
		end

		// clear ack when the request line falls (re-arms for the next request)
		for (i = 0; i < 3; i = i + 1)
			if (!req[i]) acked[i] <= 1'b0;

		if (ss_load) begin
			ch0_dout <= ss_in[7:0];
			ch1_dout <= ss_in[15:8];
		end
	end

	assign ss_out = {ch1_dout, ch0_dout};

	wire unused = &{1'b0, init, refresh, SDRAM_DQ[0], acked_req_unused};
	wire acked_req_unused = &req; // placeholder to keep widths obvious
endmodule

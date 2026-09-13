// ============================================================================
// ce_gen — Central Clock-Enable Generator (single master clock, no PLLs)
//
// Everything in the core runs on the one 21.477272 MHz master clock (clk).
// This module owns every clock divider and emits the clock enables (CEs):
//
//   ppu_ce    clk/4   — PPU dot clock (5.369 MHz), fixed in every mode
//   cpu_ce    clk/12  — CPU clock (1.789 MHz) during rendering. Inside the
//                     turbo window (post-render + vblank, non-visible
//                     scanlines) div_cpu_n_req tightens this to clk/6, /4
//                     or /3 (2x/3x/4x). The ratio is applied ONLY on the
//                     div_cpu reload edge (cpu_ce), so the CPU CE always
//                     lands on the same phase grid and ratio switches are
//                     glitchless. During rendering the window input is low
//                     and the strict 1:3 CPU:PPU ratio is preserved.
//   native_ce clk/12  — native-rate 1.789 MHz that never pauses on CPU
//                     wait-states. Drives the APU, expansion audio and the
//                     cycle-based mapper IRQ timers, so music pitch and IRQ
//                     periods are independent of the CPU turbo.
//
// All subsystems stay on 'clk'; CEs only gate state updates — no clock
// gating, no second clock domain, no CDC.
//
// Gating (pause) conditions, in priority order (later overrides earlier,
// matching the original monolithic always block in nes.v):
//   hold_ppu      — dejitter freeze; everything pauses except the one PPU
//                   tick that is replaced by the fake pixel.
//   cpumem_stall  — SDRAM ch1 busy; ONLY the CPU divider pauses (the PPU
//                   must keep running: freezing it mid-fetch would hold the
//                   PPU's own SDRAM request high and starve the CPU request,
//                   since ch0 has accept priority). Native keeps counting
//                   so audio never stretches.
//   cpu_ppu_stall — PPU-access wait-state; only the CPU divider pauses so
//                   the PPU can accept a $2000-$3FFF transaction.
//   skip_ppu_cycle— PAL APU-alignment skip.
//   realign       — force all counters to their start-of-cycle values
//                   (system-type change, reset edge, core-pause entry).
//   ss_load       — savestate restore of the counter values.
// ============================================================================

module ce_gen (
	input        clk,
	input        reset_nes,
	input        sys_pal,          // PAL: one extra CPU tick every 5 CPU cycles
	input        hold_ppu,         // dejitter freeze gate
	input        cpumem_stall,     // SDRAM busy gate
	input        cpu_ppu_stall,    // PPU-access wait-state gate
	input        skip_ppu_cycle,   // PAL skip gate
	input        realign,          // force counters back to start values
	input        ss_load,
	input [4:0]  ss_div_cpu,
	input [4:0]  ss_div_native_cpu,
	input [4:0]  ss_div_cpu_n,
	input [2:0]  ss_div_ppu,
	input [1:0]  ss_ppu_tick,
	input [1:0]  ss_div_sys,
	input [2:0]  ss_cpu_tick_count,
	input [4:0]  div_cpu_n_req,    // requested CPU divider (12 / 6 / 4 / 3)

	output       cpu_ce,
	output       ppu_ce,
	output       native_ce,

	output reg [4:0] div_cpu        = 5'd1,
	output reg [4:0] div_native_cpu = 5'd1,
	output reg [4:0] div_cpu_n      = 5'd12,
	output reg [2:0] div_ppu        = 3'd1,
	output reg [1:0] div_sys        = 2'd0,
	output reg [1:0] ppu_tick       = 2'd0,  // PPU ticks since the last cpu_ce
	output reg [2:0] cpu_tick_count = 3'd0   // PAL extra-tick counter
);

	localparam [2:0] DIV_PPU_N = 3'd4;   // PPU is always clk/4 (5.369 MHz)

	assign cpu_ce    = (div_cpu == div_cpu_n);
	assign ppu_ce    = (div_ppu == DIV_PPU_N);
	assign native_ce = (div_native_cpu == 5'd12);

	always @(posedge clk) begin
		// SDRAM clock phase: free-runs ALWAYS, including while reset_nes is
		// asserted — the original nes.v ran this assignment after the reset
		// branch, and the MiSTer ROM loader (NES.sv) paces its SDRAM writes
		// with nes_ce==3 during the download. The savestate-load and
		// realign branches below must keep winning over this, which they do
		// by assigning later (same always-block ordering as the original).
		div_sys <= div_sys + 2'd1;

		if (reset_nes) begin
			div_cpu        <= 5'd1;
			div_native_cpu <= 5'd1;
			div_cpu_n      <= 5'd12;
			div_ppu        <= 3'd1;
			ppu_tick       <= 2'd0;
			cpu_tick_count <= 3'd0;
		end else begin
			if (~hold_ppu) begin
				// Native counter: never pauses on CPU wait-states (audio pitch
				// must stay constant). The ">12" resync recovers from a reload
				// that was blocked by skip_ppu_cycle.
				if (~skip_ppu_cycle)
					div_native_cpu <= (native_ce || (ppu_ce && div_native_cpu > 5'd12)) ? 5'd1 : div_native_cpu + 5'd1;

				// CPU divider: pauses while the SDRAM services our request
				// (cpumem_stall) or while the PPU is consuming a register
				// access (cpu_ppu_stall). The PPU divider KEEPS RUNNING here:
				// freezing it mid-fetch would hold the PPU's ch0 SDRAM request
				// high forever and starve the CPU's ch1 request (ch0 has
				// accept priority) — a permanent deadlock. The legacy design
				// never gated the PPU on CPU wait-states either.
				if (~cpumem_stall && ~cpu_ppu_stall) begin
					if (~skip_ppu_cycle) begin
						// The ">div_cpu_n" resync recovers from a cpu_ce
						// reload blocked by skip_ppu_cycle.
						div_cpu <= (cpu_ce || (ppu_ce && div_cpu > div_cpu_n)) ? 5'd1 : div_cpu + 5'd1;
						// Ratio switch applies only on the reload edge so
						// cpu_ce stays on its phase grid (glitchless).
						if (cpu_ce)
							div_cpu_n <= div_cpu_n_req;
					end
				end

				div_ppu <= ppu_ce ? 3'd1 : div_ppu + 3'd1;

				// reset the ticker on the first ppu tick at or after a cpu tick
				if (cpu_ce)
					ppu_tick <= 2'd0;
				else if (ppu_ce)
					ppu_tick <= ppu_tick + 2'd1;
			end

			// Add one extra PPU tick every 5 cpu cycles for PAL (ungated).
			if (cpu_ce && sys_pal)
				cpu_tick_count <= cpu_tick_count[2] ? 3'd0 : cpu_tick_count + 3'd1;

			// Savestate restore.
			if (ss_load) begin
				div_cpu        <= ss_div_cpu;
				div_native_cpu <= ss_div_native_cpu;
				div_cpu_n      <= ss_div_cpu_n;
				div_ppu        <= ss_div_ppu;
				div_sys        <= ss_div_sys;
				ppu_tick       <= ss_ppu_tick;
				cpu_tick_count <= ss_cpu_tick_count;
			end

			// Realignment has the final word (matches the original block order).
			if (realign) begin
				div_cpu        <= 5'd1;
				div_native_cpu <= 5'd1;
				div_ppu        <= 3'd1;
				div_sys        <= 2'd0;
				ppu_tick       <= 2'd0;
				cpu_tick_count <= 3'd0;
			end
		end
	end

endmodule

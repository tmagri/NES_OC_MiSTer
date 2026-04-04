// audio_stretch.sv
//
// NCO-based Linear Interpolation Audio Stretcher for NES CPU Overclocking.
//
// When the CPU (and APU) is overclocked, the APU generates samples at a higher
// rate than normal. Without correction this raises the pitch of every channel
// proportionally to the overclock ratio.
//
// This module performs fractional sample-rate conversion using:
//  1. A Numerically Controlled Oscillator (NCO) for smooth linear interpolation
//     between consecutive APU samples.
//  2. An OUTPUT RATE LIMITER that commits a new value to sample_out only at the
//     original (non-OC) rate. This is the key to pitch correction: the MiSTer
//     sigma-delta DAC "sees" transitions only at the native APU rate, so the
//     perceived pitch is correct regardless of OC mode.
//
// Conceptually this is the audio equivalent of VBlank extension: just as the
// PPU pads extra blank scanlines to maintain 60fps, this module inserts
// interpolated hold samples to maintain correct audio pitch.
//
// Overclock ratios and derived parameters:
//   Off   (÷12) : passthrough, no modification
//   Mild  (÷9)  : APU runs 4/3× faster → commit output 3 of every 4 input ticks
//   Full  (÷6)  : APU runs 2× faster   → commit output every 2nd input tick
//
// NCO step values (16-bit 0.16 fixed-point, advance per input sample):
//   Off   : 16'hFFFF  (overflow every tick → passthrough)
//   Mild  : 16'hC000  (3/4 advance → consumes 4 inputs per 3 outputs... reversed)
//   Full  : 16'h8000  (1/2 advance → 2 inputs per output)

module audio_stretch (
	input  logic        clk,
	input  logic        sample_ce,    // one pulse per new APU sample (= apu_ce = cpu_ce)
	input  logic [15:0] sample_in,
	input  logic [1:0]  overclock,    // 0=off, 1=mild (+33%), 2=full (+100%)
	output logic [15:0] sample_out
);

// ---------------------------------------------------------------------------
// Sample window: s0=older, s1=newer input sample
// ---------------------------------------------------------------------------
logic [15:0] s0 = 16'h0;
logic [15:0] s1 = 16'h0;

// ---------------------------------------------------------------------------
// NCO phase accumulator (16-bit unsigned 0.16 fixed point)
// Phase represents fractional position between s0 and s1.
// ---------------------------------------------------------------------------
logic [15:0] phase     = 16'h0;
logic        phase_ovf;               // 1 when phase crossed 1.0 this tick

// Step: how far to advance per input sample tick
//   Full (+100%): 0x8000 = 0.5  → overflow every 2 ticks (consume 1 new sample per 2 inputs)
//   Mild (+33%) : 0xC000 = 0.75 → overflow every ~1.33 ticks
//   Off         : 0xFFFF        → passthrough
logic [15:0] step;
always_comb begin
	case (overclock)
		2'd1:    step = 16'hC000;
		2'd2:    step = 16'h8000;
		default: step = 16'hFFFF;
	endcase
end

// ---------------------------------------------------------------------------
// Interpolated value: out = s0 + (s1 - s0) * phase[15:8] / 256
// Uses properly-sized intermediates with saturation to avoid truncation.
// ---------------------------------------------------------------------------
logic signed [16:0] delta;       // s1 - s0, 17-bit signed
logic signed [24:0] blend;       // delta * frac, 25-bit signed
logic signed [17:0] result;      // s0 + (blend >> 8), 18-bit with headroom
logic        [15:0] interp;      // saturated to unsigned 16-bit

assign delta  = $signed({1'b0, s1}) - $signed({1'b0, s0});
assign blend  = delta * $signed({1'b0, phase[15:8]});
assign result = $signed({2'b00, s0}) + blend[24:8];
assign interp = result[17] ? 16'h0000 :   // negative underflow → 0
               result[16] ? 16'hFFFF :    // positive overflow  → max
               result[15:0];              // normal range

// ---------------------------------------------------------------------------
// Output rate limiter
//
// The key insight: even though interp updates every apu_ce, we must only
// commit a NEW value to sample_out at the ORIGINAL (non-OC) rate. This means:
//   Full (+100%): commit every 2nd apu_ce tick
//   Mild (+33%) : commit 3 out of every 4 apu_ce ticks  (skip the 4th)
//   Off         : commit every tick (passthrough)
//
// Only gating the OUTPUT register causes the sigma-delta DAC to see transitions
// at the native rate, giving correct pitch regardless of OC mode.
// ---------------------------------------------------------------------------
logic [1:0] out_cnt = 2'd0;   // rolling counter over apu_ce ticks
logic       hold_ce;          // 1 on ticks where we commit to sample_out

always_ff @(posedge clk) begin
	if (sample_ce) begin
		out_cnt <= out_cnt + 2'd1;

		// Advance NCO and consume new input when phase overflows
		{phase_ovf, phase} <= {1'b0, phase} + {1'b0, step};
		if (phase_ovf) begin
			s0 <= s1;
			s1 <= sample_in;
		end
	end
end

// hold_ce: 1 when we should commit interp to sample_out
// Full: every 2nd tick (out_cnt[0] == 0)
// Mild: 3 of 4 ticks (skip when out_cnt == 3)
// Off : every tick
assign hold_ce = sample_ce & (
	(overclock == 2'd2) ? (out_cnt[0] == 1'b0)  :   // Full: every 2nd
	(overclock == 2'd1) ? (out_cnt != 2'd3)      :   // Mild: 3 of 4
	                      1'b1                        // Off:  every
);

// Output register: only advances at the gated 1x rate
always_ff @(posedge clk) begin
	if (hold_ce)
		sample_out <= (overclock == 2'd0) ? sample_in : interp;
end

endmodule

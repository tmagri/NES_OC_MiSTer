// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

// Sprite DMA Works as follows.
// When the CPU writes to $4014 DMA is initiated ASAP.
// DMA runs for 512 cycles, the first cycle it reads from address
// xx00 - xxFF, into a latch, and the second cycle it writes to $2004.

// Facts:
// 1) Sprite DMA always does reads on even cycles and writes on odd cycles.
// 2) There are 1-2 cycles of cpu_read=1 after cpu_read=0 until Sprite DMA starts (pause_cpu=1, aout_enable=0)
// 3) Sprite DMA reads the address value on the last clock of cpu_read=0
// 4) If DMC interrupts Sprite, then it runs on the even cycle, and the odd cycle will be idle (pause_cpu=1, aout_enable=0)
// 5) When DMC triggers && interrupts CPU, there will be 2-3 cycles (pause_cpu=1, aout_enable=0) before DMC DMA starts.

// https://wiki.nesdev.com/w/index.php/PPU_OAM
// https://wiki.nesdev.com/w/index.php/APU_DMC
// https://forums.nesdev.com/viewtopic.php?f=3&t=6100
// https://forums.nesdev.com/viewtopic.php?f=3&t=14120

module DmaController(
	input clk,
	input ce,
	input reset,
	input put_cycle,               // Current cycle even or odd?
	input put_ce,                  // CE on a PUT cycle from APU
	input get_ce,                  // CE on a GET cycle from APU
	input sprite_trigger,          // Sprite DMA trigger?
	input dmc_trigger,             // DMC DMA trigger?
	input cpu_read,                // CPU is in a read cycle?
	input [7:0] data_from_cpu,     // Data written by CPU?
	input [7:0] dma_data_to_ram,   // Data read from RAM?
	input [15:0] dmc_dma_addr,     // DMC DMA Address
	output [15:0] aout,            // Address to access
	output aout_enable,            // DMA controller wants bus control
	output read,                   // 1 = read, 0 = write
	output [7:0] data_to_ram,      // Value to write to RAM
	output dmc_ack,                // ACK the DMC DMA
	output pause_cpu               // CPU is paused
);

reg dmc_state;
reg [1:0] spr_state;
reg [7:0] sprite_dma_lastval;
reg [15:0] sprite_dma_addr;     // sprite dma source addr
wire [8:0] new_sprite_dma_addr = sprite_dma_addr[7:0] + 8'h01;

always @(posedge clk) if (reset) begin
	dmc_state <= 0;
	spr_state <= 0;
	sprite_dma_lastval <= 0;
	sprite_dma_addr <= 0;
end else if (ce) begin
	if (dmc_state == 0 && dmc_trigger && cpu_read && put_ce) dmc_state <= 1;
	if (dmc_state == 1 && put_ce) dmc_state <= 0;

	if (sprite_trigger) begin sprite_dma_addr <= {data_from_cpu, 8'h00}; spr_state <= 1; end
	if (spr_state == 1 && cpu_read && get_ce) spr_state <= 3;
	if (spr_state[1] && put_ce && dmc_state == 1) spr_state <= 1;
	if (spr_state[1] && get_ce) sprite_dma_addr[7:0] <= new_sprite_dma_addr[7:0];
	if (spr_state[1] && get_ce && new_sprite_dma_addr[8]) spr_state <= 0;
	if (spr_state[1]) sprite_dma_lastval <= dma_data_to_ram;
end

assign pause_cpu = (spr_state[0] || dmc_trigger || dmc_state == 1);
assign dmc_ack   = (dmc_state == 1 && !put_cycle && dmc_trigger); // a DMC hardware bug can make trigger fall before it's done
assign aout_enable = dmc_ack || spr_state[1];
assign read = !put_cycle;
assign data_to_ram = sprite_dma_lastval;
assign aout = dmc_ack ? dmc_dma_addr : !put_cycle ? sprite_dma_addr : 16'h2004;

endmodule

module NES(
	input         clk,
	input         reset_nes,
	input         ppu_rst_behavior,
	input         cold_reset,
	input         pausecore,
	output        corepaused,
	input   [1:0] sys_type,
	output  [1:0] nes_div,
	input  [63:0] mapper_flags,
	output [15:0] sample,         // sample generated from APU
	output  [5:0] color,          // pixel generated from PPU
	output        is_obj,         // 1 = sprite pixel, 0 = background
	output  [1:0] joypad_clock,   // Set to 1 for each joypad to clock it.
	output  [2:0] joypad_out,     // Set to 1 to strobe joypads. Then set to zero to keep the value.
	input   [4:0] joypad1_data,   // Port1
	input   [4:0] joypad2_data,   // Port2
	input         fds_busy,       // FDS Disk Swap Busy
	input         fds_eject,      // FDS Disk Swap Pause
	input         fds_auto_eject,
	input   [1:0] max_diskside,
	input         fds_fast,
	output  [1:0] diskside,

	input   [4:0] audio_channels, // Enabled audio channels
	output [15:0] sample_sq1,
	output [15:0] sample_sq2,
	output [15:0] sample_tri,
	output [15:0] sample_noi,
	output [15:0] sample_dmc,
	output [15:0] sample_ext,
	input         ex_sprites,
	input   [1:0] mask,
	input 		  dejitter_timing,

	// Access signals for the SDRAM.
	output [24:0] cpumem_addr,
	output        cpumem_read,
	output        cpumem_write,
	output  [7:0] cpumem_dout,
	input   [7:0] cpumem_din,
	input         cpumem_busy,     // SDRAM ch1 busy: stall source for async CPU overclock
	output [21:0] ppumem_addr,
	output        ppumem_read,
	output        ppumem_write,
	output  [7:0] ppumem_dout,
	input   [7:0] ppumem_din,
	output        refresh,

	input  [20:0] prg_mask,
	input  [19:0] chr_mask,

	// Override for BRAM
	output [17:0] bram_addr,      // address to access
	input   [7:0] bram_din,       // Data from BRAM
	output  [7:0] bram_dout,
	output        bram_write,     // is a write operation
	output        bram_override,

	output  [8:0] cycle,
	output  [9:0] scanline,
	input         int_audio,
	input         ext_audio,
	input         stereo_en,
	input         smooth_audio,
	input         smooth_noise,
	input		  swap_duty,
	input  [1:0]  scale_mode,
	input  [3:0]  root_key,
	output [3:0]  detected_key,
	output        native_is_minor,
	output        ppu_ce_out,
	input         gg,
	input [128:0] gg_code,
	output        gg_avail,
	input         gg_reset,
	output  [2:0] emphasis,
	output        save_written,
	output        mapper_has_flashsaves,
	input         debug_dots,
	input         disable_oam_corruption,

	// savestates
	output        mapper_has_savestate,
	input         increaseSSHeaderCount,
	input         save_state,
	input         load_state,
	input  [1:0]  savestate_number,
	output        sleep_savestate,
	output        state_loaded,

	output        hsync,
	output        hblank,
	output        vsync,
	output        vblank,

	output [24:0] Savestate_SDRAMAddr,
	output        Savestate_SDRAMRdEn,
	output        Savestate_SDRAMWrEn,
	output [7:0]  Savestate_SDRAMWriteData,
	input  [7:0]  Savestate_SDRAMReadData,

	output [63:0] SaveStateExt_Din,
	output [9:0]  SaveStateExt_Adr,
	output        SaveStateExt_wren,
	output        SaveStateExt_rst,
	input  [63:0] SaveStateExt_Dout,
	output        SaveStateExt_load,

	output [63:0] SAVE_out_Din,  	// data read from savestate
	input  [63:0] SAVE_out_Dout, 	// data written to savestate
	output [25:0] SAVE_out_Adr,  	// all addresses are DWORD addresses!
	output        SAVE_out_rnw,   // read = 1, write = 0
	output        SAVE_out_ena,   // one cycle high for each action
	output  [7:0] SAVE_out_be,
	input         SAVE_out_done,   // should be one cycle high when write is done or read value is valid
	input   [1:0] overclock,       // CE Turbo ratio: 0=off, 1=Plus (clk/6), 2=Turbo (clk/4), 3=Maximum (clk/3)
	input   [1:0] oc_method        // Turbo window: 0=VBlank only, 1=Postrender, 2=CE Turbo (incl. pre-render)
);


/**********************************************************/
/*************            Clocks            ***************/
/**********************************************************/

// Master clock speed: NTSC/Dendy: 21.477272, PAL: 21.2813696

// Cyc 123456789ABC123456789ABC123456789ABC123456789ABC
// CPU ----M------C----M------C----M------C----M------C
// PPU ---P---P---P---P---P---P---P---P---P---P---P---P
//                2000011112222
//  M: M2 Tick, C: CPU Tick, P: PPU Tick -: Idle Cycle
//
// On Mister, we must pre-fetch data from memory 4 cycles before it is needed.
// Memory requests are aligned to the PPU clock and there are two types: CPU pre-fetch
// and PPU pre-fetch. The CPU pre-fetch needs to be completed before the end of the CPU cycle, and
// the PPU pre-fetch needs to be completed before each PPU CE is ticked.
// The PPU_CE that acknowledges reads and writes always occurs after the M2 rising edge, and cart/mapper
// CE's are always triggered on the rising edge of M2, which means that PPU will always see
// any changes made by the cart mappers. Because the mapper on MiSTer is capable of changing the data that
// is given to the CPU (banking, etc) the best time to run it is the first PPU cycle where the data from the
// CPU is visible on the bus.
//
// The obvious issue is that the CPU and PPU pre-fetches will collide. Fortunately, because Nintendo
// wanted to save pins, the ppu has to take two PPU ticks for every read, meaning there will always be
// a minimum of one free PPU cycle in which to fit the CPU read. This does however create the issue that
// we always need perfect alignment.
//
// Therefore, we can dervive the following order of operations:
// - CPU pre-fetch should happen during first free PPU tick in a CPU cycle.
// - Cart CE should happen on the second PPU tick in a CPU cycle always
// - PPU read/write should happen on the last PPU tick in a CPU cycle (usually third)

assign nes_div = div_sys;
// The APU always runs on the native-rate clk/12 enable so audio pitch is
// independent of the CPU turbo. Bus writes into the APU are rate-matched by
// the phi2_native / DMC-hold handshakes below.
wire apu_ce = native_ce;

wire [7:0] from_data_bus;
wire [7:0] cpu_dout;

// odd or even apu cycle, AKA div_apu or apu_/clk2. This is actually not 50% duty cycle. It is high for 18
// master cycles and low for 6 master cycles. It is considered active when low or "even".
reg odd_or_even = 1; // 1 == odd, 0 == even
// Async OC: a native-rate odd/even (get/put) phase used to clock the APU audio.
reg native_odd_or_even = 1;

// -----------------------------------------------------------------------
// Clock Dividers — synchronous CE turbo (rtl/ce_gen.sv)
//
// PPU   : fixed clk/4 (5.369 MHz) in every mode — the 1:3 CPU:PPU ratio
//         required for raster effects is never violated while rendering.
// CPU   : clk/12 (1.789 MHz) during the visible frame. Outside it (turbo
//         window: post-render + vblank), the ratio tightens to clk/6, /4
//         or /3 (2x/3x/4x). The new ratio is applied ONLY on the div_cpu
//         reload edge (cpu_ce), so every CPU cycle keeps the same internal
//         layout (prefetch window, cart_ce, end-of-cycle strobes) and ratio
//         switches are glitchless.
// Native: clk/12, never pauses on CPU wait-states. Drives the APU, the
//         expansion-audio chips and the cycle-based mapper IRQ timers, so
//         music pitch and IRQ periods are turbo-independent.
//
// There are no other clock domains and no CDC: all subsystems sit on 'clk'
// and are paced purely by these clock enables.
// -----------------------------------------------------------------------

// Latch the turbo level and window at reset so neither ever changes
// mid-frame (a live method change is applied by the ~2 frame reset in
// NES.sv, after which the latched value takes effect — same as the ratio).
reg [1:0] overclock_latched = 2'd0;
reg [1:0] oc_method_latched = 2'd0;

// Counters / clock enables — owned by the ce_gen instance below.
wire [4:0] div_cpu, div_native_cpu, div_cpu_n;
wire [2:0] div_ppu;
wire [1:0] div_sys;
wire [1:0] ppu_tick;          // PPU ticks since the last cpu_ce
wire [2:0] cpu_tick_count;    // PAL extra-tick counter
wire cpu_ce, ppu_ce, native_ce;

// Native-rate 1.789 MHz: APU, expansion audio and mapper IRQ timers.
wire mapper_ce = (div_native_cpu == 5'd10);
wire audio_ce  = native_ce;

assign ppu_ce_out = ppu_ce;

// Late SDRAM/mapper trigger while a turbo ratio is active. At clk/12 this is
// bit-identical to the legacy Off mode (cart_ce at n-2, prefetch at n-6);
// inside the turbo window it reproduces the shipped small-divider timing
// (cart_ce at n-1, prefetch from 1).
wire cart_ce_sel    = (div_cpu_n != 5'd12);
wire cart_ce        = (div_cpu == (cart_ce_sel ? div_cpu_n - 5'd1 : div_cpu_n - 5'd2));
wire [4:0] cart_pre_start = cart_ce_sel ? 5'd1 : (div_cpu_n - 5'd6);
wire cart_pre = (div_cpu >= cart_pre_start) && (div_cpu <= (cart_ce_sel ? div_cpu_n - 5'd1 : div_cpu_n - 5'd2));

// PPU output: 1 = outside the visible frame (post-render / vblank / pre-render).
wire turbo_window;


// -----------------------------------------------------------------------
// CPU-Only Overclocking (Vblank Extension)
// The PPU is locked at clk/4 in every mode, so the frame is never padded:
// the turbo instead gives the CPU more cycles inside the normal-length
// vblank. The extra_lines plumbing is kept (the PPU and pause ClockGen
// still accept it) but always driven to 0.
// -----------------------------------------------------------------------
wire [9:0] oc_extra_lines = 10'd0;

wire [9:0] max_native_sl = (sys_type == 2'b00) ? 10'd261 : 10'd311;
wire mapper_irq_pause = (scanline > max_native_sl);

// The infamous NES jitter is important for accuracy, but wreks havok on modern devices and scalers,
// so what I do here is pause the whole system for one PPU clock and insert a "fake" ppu clock to
// replace the missing pixel. Thus the system runs accurately (ableit a few nanoseconds per frame slower)
// but all video devices stay happy.

wire skip_pixel;
reg freeze_clocks = 0;
reg [4:0] faux_pixel_cnt;

wire use_fake_h = freeze_clocks && faux_pixel_cnt < 6;

reg [1:0] last_sys_type;

wire skip_ppu_cycle = (cpu_tick_count == 4) && (ppu_tick == 0);

reg hold_reset = 0;
reg bootvector_flag;
wire cpu_reset = reset_ss | hold_reset;
wire reset = cpu_reset | bootvector_flag;
wire reset_noSS = reset_nes | hold_reset | bootvector_flag;

// pause
reg corepause_active       = 0;
reg corepause_active_delay = 0;
reg skip_pause_ce          = 0;
reg  [7:0] corepause_delay = 8'd0;
reg  [2:0] div_ppu_pause = 0;
wire skip_pixel_pause;
localparam [2:0] DIV_PPU_N = 3'd4;   // PPU is always clk/4 (mirrors ce_gen)
wire ppu_ce_pause = corepause_active ? (div_ppu_pause == DIV_PPU_N) : ppu_ce;



wire render_ena;
wire [8:0] cycle_paused;
wire [9:0] scanline_paused;
wire       is_in_vblank_paused;
wire       evenframe;
wire       evenframe_paused;

reg        reset_nes_last;

assign corepaused = corepause_active;
assign refresh    = corepause_active_delay && ppu_ce_pause;

// -----------------------------------------------------------------------
// Wait-state / stall logic (same-clock CE-phase handshakes — no CDC).
// These are safety nets that stretch a CPU cycle when a consumer cannot
// keep up. At clk/12 they are inert by timing; inside the turbo window
// (clk/6, /4, /3) they bound SDRAM and PPU register latency. Crucially,
// both stalls pause the CPU against the SAME master clock and never
// desynchronize the CPU:PPU phase relationship.
// -----------------------------------------------------------------------
// SDRAM cache-miss stall: guarantee a minimum delay between a CPU memory
// request and the end of its cycle, so the SDRAM (clocked at 4x this clock)
// always has time to accept and complete the access before the CPU latches
// the data. Deterministic countdown — no handshake to miss: the SDRAM's
// busy pulse lives in the 4x domain and can be shorter than one of our
// clock periods, so sampling it directly is unreliable. The countdown is
// 3 master cycles after the request rises; the SDRAM accepts within one
// clk85 cycle and completes within ~10 clk85 (~2.5 master cycles), so 3
// always suffices. Only the CPU divider pauses; the PPU keeps running so
// its own ch0 requests keep flowing (freezing the PPU mid-fetch would hold
// its request high and starve ch1, which has lower accept priority).
wire cpumem_req = cpumem_read || cpumem_write;
reg  cpumem_req_d;
reg  [1:0] cpumem_wait;
always @(posedge clk) begin
	cpumem_req_d <= cpumem_req;
	if (cpu_ce)                                  cpumem_wait <= 2'd0;
	else if (cpumem_req && !cpumem_req_d)        cpumem_wait <= 2'd3; // fresh request
	else if (|cpumem_wait)                       cpumem_wait <= cpumem_wait - 2'd1;
end
wire cpumem_stall = cart_ce && (cpumem_busy | (|cpumem_wait));

wire ppu_read  = (ppu_tick == 2'd1);   // legacy PPU access strobe (ratio-relative:
wire ppu_write = (ppu_tick == 2'd1);   // ppu_tick resets at every cpu_ce)

// phi2 (M2 high phase): rises after address-setup time and falls at cpu_ce.
// The setup time scales as div_cpu_n/3 so phi2 always spans the same
// relative window at every CE ratio (12/6/4/3).
wire phi2 = (div_cpu > (div_cpu_n / 3)) && (div_cpu < div_cpu_n);

// PPU-access handshake: the PPU accepts a $2000-$3FFF transaction on its
// next ce — but only once phi2 is high (6502 write data is guaranteed
// valid in phi2). Qualifying with phi2 makes the consumption land on the
// same dot as the legacy ppu_tick==1 strobe at clk/12, and holds the CPU
// (via cpu_ppu_stall) until consumption at the tightened turbo ratios.
reg  ppu_acc_done;
wire ppu_cs_sync = ppu_cs && phi2 && !ppu_acc_done;
always @(posedge clk) begin
	if (reset_nes)                    ppu_acc_done <= 1'b0;
	else if (cpu_ce)                  ppu_acc_done <= 1'b0; // reset for the next CPU cycle
	else if (ppu_ce && ppu_cs_sync)   ppu_acc_done <= 1'b1; // PPU accepted the transaction
end
// PPU-access wait (turbo only): the legacy strobe (ppu_tick==1) is sampled
// by the PPU at the SECOND ppu_ce after cpu_ce. At clk/12 that lands inside
// the CPU cycle (div_cpu=8) — bit-exact legacy, the wait never fires. At
// the turbo ratios the 2nd ppu_ce would fall into the NEXT CPU cycle, so
// the cycle is held at its last master until the strobe has been consumed
// (ppu_tick >= 2). Bounded: the next ppu_ce always arrives within 4
// masters. The PPU divider keeps running (no starvation path).
wire cpu_ppu_stall = (div_cpu == (div_cpu_n - 5'd1)) && ppu_cs && (ppu_tick < 2'd2);

// -----------------------------------------------------------------------
// CE Turbo ratio decode. The level is latched at reset (overclock_latched)
// and the window comes from the PPU, so div_cpu_n_req is stable within a
// frame. ce_gen applies the new ratio only on a div_cpu reload edge.
// -----------------------------------------------------------------------
reg [4:0] turbo_div;
always @* begin
	case (overclock_latched)
		2'd1:    turbo_div = 5'd6;   // Plus    2x (3.58 MHz)
		2'd2:    turbo_div = 5'd4;   // Turbo   3x (5.37 MHz)
		2'd3:    turbo_div = 5'd3;   // Maximum 4x (7.16 MHz)
		default: turbo_div = 5'd12;  // Off
	endcase
end
wire [4:0] div_cpu_n_req = (overclock_latched != 2'd0 && turbo_window) ? turbo_div : 5'd12;

// Force the counters back to their start values: system-type change, the
// edge at the end of reset, or core-pause entry (which holds them there).
wire pause_cpu;       // driven by the DMA controller below
wire cpu_Instrnew;    // driven by the CPU core below
wire pause_realign = corepause_active ||
	(pausecore && (div_cpu == 5'd1) && (div_ppu == 3'd1) && (div_sys == 2'd0) &&
	 (cpu_tick_count == 3'd0) && ~freeze_clocks && is_in_vblank_paused && ~pause_cpu && cpu_Instrnew);
wire realign = pause_realign || (last_sys_type != sys_type) || (reset_nes_last && !reset_nes);

// Central clock-enable generator (rtl/ce_gen.sv).
ce_gen clockgen (
	.clk               (clk),
	.reset_nes         (reset_nes),
	.sys_pal           (sys_type == 2'b01),
	.hold_ppu          (freeze_clocks && (div_ppu == (DIV_PPU_N - 3'd1))),
	.cpumem_stall      (cpumem_stall),
	.cpu_ppu_stall     (cpu_ppu_stall),
	.skip_ppu_cycle    (skip_ppu_cycle),
	.realign           (realign),
	.ss_load           (loading_savestate),
	.ss_div_cpu        (SS_TOP[21:17]),
	.ss_div_native_cpu (SS_TOP[26:22]),
	.ss_div_cpu_n      (SS_TOP[43:39]),
	.ss_div_ppu        (SS_TOP[29:27]),
	.ss_ppu_tick       (SS_TOP[31:30]),
	.ss_div_sys        (SS_TOP[36:35]),
	.ss_cpu_tick_count (SS_TOP[34:32]),
	.div_cpu_n_req     (div_cpu_n_req),
	.div_cpu           (div_cpu),
	.div_native_cpu    (div_native_cpu),
	.div_cpu_n         (div_cpu_n),
	.div_ppu           (div_ppu),
	.div_sys           (div_sys),
	.ppu_tick          (ppu_tick),
	.cpu_tick_count    (cpu_tick_count),
	.cpu_ce            (cpu_ce),
	.ppu_ce            (ppu_ce),
	.native_ce         (native_ce)
);

always @(posedge clk) begin
	if (reset_nes) begin
		hold_reset     <= 1;
		freeze_clocks  <= 0;
		faux_pixel_cnt <= 0;
		overclock_latched <= overclock;
		oc_method_latched <= oc_method;
	end
	if (cpu_ce && !reset_nes) hold_reset <= 0;

	// NOTE: div_cpu / div_native_cpu / div_cpu_n / div_ppu / div_sys /
	// ppu_tick / cpu_tick_count all advance inside the ce_gen instance
	// above (central CE generator).

	// De-Jitter shenanigans
	if (faux_pixel_cnt == 3)
		freeze_clocks <= 1'b0;

	if (|faux_pixel_cnt)
		faux_pixel_cnt <= faux_pixel_cnt - 1'b1;

	if ((((skip_pixel && ~corepause_active) || (skip_pixel_pause && corepause_active)) && (faux_pixel_cnt == 0)) && !dejitter_timing) begin
		freeze_clocks <= 1'b1;
		faux_pixel_cnt <= 5'd7;   // one full PPU tick at clk/4
	end


	if (reset_nes | hold_reset) begin
		bootvector_flag <= 1;
		odd_or_even <= 1;
		native_odd_or_even <= 1;
	end else if (loading_savestate) begin
		odd_or_even    <= SS_TOP[0];
		// Restore saved OC level/window so the core runs at the settings it was saved under
		overclock_latched <= SS_TOP[38:37];
		oc_method_latched <= SS_TOP[45:44];
		native_odd_or_even <= SS_TOP[53];
		// (counter restores happen inside ce_gen via ss_load)
	end else begin
		if (cpu_ce) begin
			odd_or_even <= ~odd_or_even;
			bootvector_flag <= 0;
		end
		if (native_ce) begin
			native_odd_or_even <= ~native_odd_or_even;
		end
	end

	// Realign if the system type changes or reset just finished. The
	// counters themselves are reset inside ce_gen via the realign input.
	last_sys_type <= sys_type;
	reset_nes_last <= reset_nes;

	// pause
	if (ppu_ce_pause) skip_pause_ce <= 0; // must skip the first CE after pause to sync back to correct ppu

	if (reset_nes) begin
		corepause_active       <= 0;
		corepause_active_delay <= 0;
	end else begin
		if (pause_realign) begin
			// ce_gen holds the counters at their start values while this is
			// asserted (see the realign wire above).
			corepause_active  <= 1;
			div_ppu_pause     <= div_ppu + 3'd1;
		end

		if (corepause_active) begin

			if (corepause_delay < 8'hFF) begin
				corepause_delay <= corepause_delay + 1'd1;
			end else begin
				corepause_active_delay <= 1;
			end

			if (~freeze_clocks | ~(div_ppu_pause == (DIV_PPU_N - 3'd1))) begin
				div_ppu_pause <= ppu_ce_pause ? 3'd1 : div_ppu_pause + 3'd1;
				if (~pausecore && ppu_ce_pause && (cycle_paused == ppu_cycle) && (scanline_paused == scanline_ppu) && (evenframe == evenframe_paused)) begin
					corepause_active       <= 0;
					corepause_active_delay <= 0;
					skip_pause_ce          <= 1;
				end
			end
		end else begin
			corepause_delay <= 8'd0;
		end
	end

end


ClockGen clockgen_pause(
	.clk                 (clk),
	.ce                  (ppu_ce_pause && ~skip_pause_ce),
	.reset               (reset_noSS),
	.sys_type            (sys_type),
	.is_rendering        (render_ena),
	.extra_lines         (oc_extra_lines),
	.scanline            (scanline_paused),
	.cycle               (cycle_paused),
	.is_in_vblank        (is_in_vblank_paused),
	//.end_of_line         (end_of_line),
	//.at_last_cycle_group (at_last_cycle_group),
	//.exiting_vblank      (exiting_vblank),
	//.entering_vblank     (entering_vblank),
	//.is_pre_render       (is_pre_render_line),
	.short_frame         (skip_pixel_pause),
	.oc_method           (oc_method_latched[0]),
	//.is_vbe_sl           (is_vbe_sl)
	.evenframe           (evenframe_paused)
);

/**********************************************************/
/*************              CPU             ***************/
/**********************************************************/

// TODO: At some point the CPU, APU, and DMA need to be isolated into their own unit, as in the
// actual system they were part of the same package and the internal bus was isolated in a variety
// of ways from the external bus. This is represented here in the code, but in a way that is pretty
// unintuitive to anyone who looks at it.

wire [15:0] cpu_addr;
wire cpu_rnw;
// pause_cpu / cpu_Instrnew are forward-declared with the CE generator above
wire nmi;
wire mapper_irq;
wire apu_irq;
// If the external bus is driven, electrically it will overwhelm the internal bus of register
// 4015's output.
wire apu_reg_cs = (apu_cs && addr[4:0] == 5'h15);
wire [7:0] apu_reg_value = {apu_dout[7:6], from_data_bus[5], apu_dout[4:0]}; // Fill in the undriven bit with bus.
wire [7:0] internal_data_bus = (apu_reg_cs ? apu_reg_value : from_data_bus);

T65 cpu(
	.mode   (0),
	.BCD_en (0),

	.res_n  (~cpu_reset && ~cold_reset),
	.pwr_n  (~cold_reset), // Cold boot, power reset, must be paired with reset
	.clk    (clk),
	.enable (cpu_ce),
	.rdy    (~pause_cpu),

	.IRQ_n  (~(apu_irq | mapper_irq)),
	.NMI_n  (~nmi),
	.R_W_n  (cpu_rnw),

	.A      (cpu_addr),
	.DI     (cpu_rnw ? internal_data_bus : cpu_dout),
	.DO     (cpu_dout),

	.Instrnew (cpu_Instrnew),

	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ),
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (loading_savestate ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[0])
);

wire [15:0] dma_aout;
wire dma_aout_enable;
wire dma_read;
wire [7:0] dma_data_to_ram;
wire apu_dma_request, apu_dma_ack;
wire [15:0] apu_dma_addr;

// Determine the values on the bus outgoing from the CPU chip (after DMA / APU)
wire [15:0] addr = dma_aout_enable ? dma_aout  : cpu_addr;
wire [7:0] dma_data_bus = (joypad1_cs && dma_aout_enable) ? {from_data_bus[7:5], joypad1_data[4:0]} :
	(joypad2_cs && dma_aout_enable) ? {from_data_bus[7:5], joypad2_data[4:0]} :
	from_data_bus;
wire [7:0]  dbus = dma_aout_enable ? dma_data_to_ram : cpu_dout;
wire mr_int      = dma_aout_enable ? dma_read  : cpu_rnw;
wire mw_int      = dma_aout_enable ? !dma_read : !cpu_rnw;
wire get_ce, put_ce;
wire apu_get_ce, apu_put_ce; // APU get/put phase outputs (native-rate: apu_put_ce == aclk1_d)
// DMA and joypads always run at the full CPU rate. The APU is on the native
// clock, so the two rate domains meet only through the handshakes below.
assign get_ce = cpu_ce &  odd_or_even;
assign put_ce = cpu_ce & ~odd_or_even;

// -----------------------------------------------------------------------
// DMC DMA ack hold. The DMA controller fetches the DMC sample byte at CPU
// rate (dmc_ack is a CPU-cycle level, data valid at the cpu_ce that ends
// the fetch). The APU can only consume it on a native-rate aclk1_d edge
// (apu_put_ce). At clk/12 the phases align and the combinational term
// delivers the byte on the exact legacy consume edge. Inside the turbo
// window the native put edge may fall after the fetch, so the byte is
// held until it is consumed. Single-consumption is guaranteed:
//  - the hold is only set when the native put edge did NOT already consume,
//  - dma_req stays asserted (have_buffer only sets at the consume edge), so
//    any re-fetch before consumption simply re-reads the same address.
// -----------------------------------------------------------------------
reg       dmc_hold_valid;
reg [7:0] dmc_hold_data;
wire      dmc_capture = apu_dma_ack && cpu_ce;
always @(posedge clk) begin
	if (reset_nes)                        dmc_hold_valid <= 1'b0;
	else if (dmc_capture && !apu_put_ce) begin
		dmc_hold_data  <= dma_data_bus;
		dmc_hold_valid <= 1'b1;
	end else if (apu_put_ce)              dmc_hold_valid <= 1'b0; // consumed via hold
end
wire       apu_dma_ack_eff  = dmc_hold_valid | dmc_capture;
wire [7:0] apu_dma_data_eff = (dmc_hold_valid && !dmc_capture) ? dmc_hold_data : dma_data_bus;

// -----------------------------------------------------------------------
// Native PHI2 + $4017 write hold. $4017 is the only APU register latched
// on write_ce (write & phi2 rising), so during turbo a $4017 write can
// fall between native phi2 edges. The write (addr/data) is captured and
// presented to the APU until the next native phi2 rising edge consumes
// it. At clk/12 the live write cycle contains a native phi2 rise, so
// behavior is legacy-equivalent. All other APU registers latch on the
// write LEVEL (addr/data stable for the whole CPU cycle) and $4015 reads
// are combinational, so they need no handshake at any ratio.
// -----------------------------------------------------------------------
wire phi2_native = (div_native_cpu > 5'd4) && (div_native_cpu < 5'd12);
reg  phi2_native_old;
always @(posedge clk) phi2_native_old <= phi2_native;
wire phi2_ce_native = phi2_native & ~phi2_native_old;

reg        apu4017_held;
reg  [7:0] apu4017_data;
// (declared here because the handshakes above need it; the APU/joypad
// sections below share it)
wire apu_cs = cpu_addr[15:5] == 11'b0100_0000_000;
wire       apu_wr_live = apu_cs && (addr[4:0] == 5'h17) && mw_int;
reg        apu_wr_live_q;
always @(posedge clk) apu_wr_live_q <= apu_wr_live;
always @(posedge clk) begin
	if (reset_nes)                                                 apu4017_held <= 1'b0;
	else if (apu_wr_live && !apu_wr_live_q && !apu4017_held) begin
		apu4017_data <= dbus;
		apu4017_held <= 1'b1;
	end else if (apu4017_held && phi2_ce_native)                   apu4017_held <= 1'b0; // consumed
end
// While held (<= ~2 native cycles), the APU CS/address/data are forced to
// the held $4017 write; a simultaneous live $4000-$401F access is shadowed
// for that window (deterministic, and $4017 writes are rare).
wire       apu_cs_eff   = apu_cs    | apu4017_held;
wire       apu_rw_eff   = apu4017_held ? 1'b0         : cpu_rnw;
wire [4:0] apu_addr_eff = apu4017_held ? 5'h17        : addr[4:0];
wire [7:0] apu_din_eff  = apu4017_held ? apu4017_data : dbus;

DmaController dma(
	.clk            (clk),
	.ce             (cpu_ce),
	.reset          (reset_noSS),
	.put_cycle      (odd_or_even),                // Even or odd cycle
	.sprite_trigger (apu_cs && addr[4:0] == 5'h14 && ~cpu_rnw), // Sprite trigger
	.dmc_trigger    (apu_dma_request),            // DMC Trigger
	.cpu_read       (cpu_rnw),                    // CPU in a read cycle?
	.data_from_cpu  (cpu_dout),                   // Data from cpu
	.dma_data_to_ram  (internal_data_bus),              // Data from RAM etc.
	.dmc_dma_addr   (apu_dma_addr),               // DMC addr
	.aout           (dma_aout),
	.aout_enable    (dma_aout_enable),
	.read           (dma_read),
	.data_to_ram    (dma_data_to_ram),
	.dmc_ack        (apu_dma_ack),
	.pause_cpu      (pause_cpu),
	.get_ce         (get_ce),
	.put_ce         (put_ce)
);




/**********************************************************/
/*************             APU              ***************/
/**********************************************************/

// The APU is part of the 2A03 and parts of it are not exposed to external busses.
// (apu_cs is declared with the DMC/4017 handshakes above.)
wire [7:0] apu_dout;
wire [15:0] sample_apu;

APU apu(
	.MMC5           (1'b0),
	.clk            (clk),
	.PHI2           (phi2_native),        // native-rate phi2 (write_ce / aclk2 align here)
	.CS             (apu_cs_eff),         // includes the held $4017 write
	.PAL            (sys_type == 2'b01),
	.ce             (apu_ce),             // native clk/12, never stalls
	// overclock=0 keeps pitch_ce=1 so all audio dividers tick natively.
	.overclock      (2'd0),
	.reset          (reset),
	.cold_reset     (cold_reset),
	.ADDR           (apu_addr_eff),
	.RW             (apu_rw_eff),
	.DIN            (apu_din_eff),
	.DOUT           (apu_dout),
	.audio_channels (audio_channels),
	.Sample         (sample_apu),
	.sample_sq1     (sample_sq1),
	.sample_sq2     (sample_sq2),
	.sample_tri     (sample_tri),
	.sample_noi     (sample_noi),
	.sample_dmc     (sample_dmc),
	.DmaReq         (apu_dma_request),
	.DmaAck         (apu_dma_ack_eff),    // CPU-rate fetch held for the native put edge
	.DmaAddr        (apu_dma_addr),
	.DmaData        (apu_dma_data_eff),
	.get_or_put     (native_odd_or_even), // native-rate get/put phase
	.IRQ            (apu_irq),
	.put_ce         (apu_put_ce),
	.get_ce         (apu_get_ce),
	.smooth_audio   (smooth_audio),
	.smooth_noise   (smooth_noise),
	.swap_duty		(swap_duty),
	.scale_mode		(scale_mode),
	.root_key		(root_key),
	.detected_key   (detected_key),
	.native_is_minor(native_is_minor),
	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ),
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (loading_savestate ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[1])
);

// Output raw APU audio directly to the top level mixer
assign sample = sample_apu;

// ALWAYS mute internal APU audio routing to cart expansion.
// This forces the mappers to output PURE expansion audio on `sample_ext`,
// allowing NES.sv to safely handle all scaling and mixing (Mono and Stereo) without clipping.
wire [15:0] audio_mappers = 16'd0;


// Joypads are mapped into the APU's range.
wire joypad1_cs = apu_cs && addr[4:0] == 5'h16;
wire joypad2_cs = apu_cs && addr[4:0] == 5'h17;

reg [2:0] joy_out;
reg [2:0] joy_latch;
always @(posedge clk) begin
	if (put_ce) joy_out <= joy_latch;
	if (joypad1_cs && ~cpu_rnw) begin
		joy_latch <= cpu_dout[2:0];
		if (put_ce) joy_out <= cpu_dout[2:0];
	end
end

assign joypad_out = joy_out;
assign joypad_clock = {joypad2_cs && cpu_rnw, joypad1_cs && cpu_rnw};


/**********************************************************/
/*************             PPU              ***************/
/**********************************************************/

// The PPU accepts a $2000-$3FFF transaction at any point in the CPU cycle
// (cs is held until the PPU's next ce consumes it — see the ppu_acc_done
// handshake above), which is deterministic at every CPU ratio.
wire mr_ppu     = mr_int && ppu_read; // Read *from* the PPU.
wire mw_ppu     = mw_int && ppu_write; // Write *to* the PPU.
wire ppu_cs = addr >= 'h2000 && addr < 'h4000;
wire [7:0] ppu_dout;            // Data from PPU to CPU
wire chr_read, chr_write, chr_read_ex;       // If PPU reads/writes from VRAM
wire [13:0] chr_addr, chr_addr_ex;           // Address PPU accesses in VRAM
wire [7:0] chr_from_ppu;        // Data from PPU to VRAM
wire [7:0] chr_to_ppu;
wire [8:0] ppu_cycle;
wire [9:0] scanline_ppu;
assign cycle    = use_fake_h ? 9'd340 : (corepause_active) ? cycle_paused : ppu_cycle;
assign scanline = (corepause_active) ? scanline_paused : scanline_ppu;

PPU ppu(
	.clk              (clk),
	// Legacy access timing (known-good on hardware): consumed at the
	// ppu_tick==1 strobe inside the phi2-high window. The strobe is
	// ratio-relative (ppu_tick resets at every cpu_ce), so it works
	// identically at clk/12 and at the turbo ratios.
	.cs               (addr[15:13] == 3'b001 && phi2),
	.RWn              (mr_int && !mw_int),
	.rst_behavior     (ppu_rst_behavior),
	.ce               (ppu_ce),
	.reset            (reset),
	.sys_type         (sys_type),
	.debug_dots       (debug_dots),
	.disable_oam_corruption(disable_oam_corruption),
	.color            (color),
	.is_obj           (is_obj),
	.din              (dbus),
	.dout             (ppu_dout),
	.ain              (addr[2:0]),
	.read             (ppu_cs && mr_ppu),
	.write            (ppu_cs && mw_ppu),
	.nmi              (nmi),
	.vram_r           (chr_read),
	.vram_r_ex        (chr_read_ex),
	.vram_w           (chr_write),
	.vram_addr        (chr_addr),
	.vram_a_ex        (chr_addr_ex),
	.vram_dbus_in     (chr_to_ppu),
	.vram_dout        (chr_from_ppu),
	.scanline         (scanline_ppu),
	.cycle            (ppu_cycle),
	.emphasis         (emphasis),
	.short_frame      (skip_pixel),
	.extra_sprites    (ex_sprites),
	.mask             (mask),
	.extra_lines      (oc_extra_lines),
	.render_ena_out   (render_ena),
	.evenframe        (evenframe),
	.hblank           (hblank),
	.vblank           (vblank),
	.hsync            (hsync),
	.vsync            (vsync),
	.oc_method        (oc_method_latched),
	.turbo_window     (turbo_window),   // 1 = outside the visible frame (CE Turbo window)
	// savestates
	.SaveStateBus_Din       (SaveStateBus_Din        ),
	.SaveStateBus_Adr       (SaveStateBus_Adr        ),
	.SaveStateBus_wren      (SaveStateBus_wren       ),
	.SaveStateBus_rst       (SaveStateBus_rst        ),
	.SaveStateBus_load      (loading_savestate       ),
	.SaveStateBus_Dout      (SaveStateBus_wired_or[2]),
	.Savestate_OAMAddr      (Savestate_OAMAddr       ),
	.Savestate_OAMRdEn      (Savestate_OAMRdEn       ),
	.Savestate_OAMWrEn      (Savestate_OAMWrEn       ),
	.Savestate_OAMWriteData (Savestate_OAMWriteData  ),
	.Savestate_OAMReadData  (Savestate_OAMReadData   )
);


/**********************************************************/
/*************             Cart             ***************/
/**********************************************************/

wire [15:0] prg_addr = addr;
wire [7:0] prg_din = (dbus & (prg_conflict ? cpumem_din : 8'hFF)) | (prg_conflict_d0 ? cpumem_din & 8'h01 : 8'h00);

wire prg_read  = mr_int && cart_pre && (addr[15:5] != 11'b0100_0000_000) && !ppu_cs;
wire prg_write = mw_int && cart_pre;

wire prg_allow, vram_a10, vram_ce, chr_allow;
wire [24:0] prg_linaddr;
wire [21:0] chr_linaddr;
wire [7:0] prg_dout_mapper, chr_from_ppu_mapper;
wire has_chr_from_ppu_mapper, prg_bus_write, prg_conflict, prg_conflict_d0, has_flashsaves;

assign save_written = has_flashsaves ? (!prg_linaddr[24] && prg_write && prg_allow) :                            // Flash save: writes to PRG-ROM
                      (mapper_flags[7:0] == 8'h14) ? (prg_linaddr[21:18] == 4'b1111 && prg_write && prg_allow) : // Mapper 20/FDS
                      (prg_addr[15:13] == 3'b011 && prg_write) | bram_write;                                     // Default - $6000-$7FFF or BRAM

assign mapper_has_flashsaves = has_flashsaves;

cart_top multi_mapper (
	// FPGA specific
	.clk               (clk),
	.reset             (reset_noSS),
	.flags             (mapper_flags),            // iNES header data (use 0 while loading)
	.paused            (freeze_clocks),
	// Cart pins (slightly abstracted)
	.ce                (cart_ce & ~reset_noSS),   // M2 (held in high impedance during reset)
	.cpu_ce            (cpu_ce),                  // Serves as M2 Inverted
	.prg_ain           (prg_addr),                // CPU Address in (a15 abstracted from ROMSEL)
	.prg_read          (prg_read),                // CPU RnW split
	.prg_write         (prg_write),               // CPU RnW split
	.prg_din           (prg_din),                 // CPU Data bus in (split from bid)
	.prg_dout          (prg_dout_mapper),         // CPU Data bus out (split from bid)
	.chr_ex            (chr_read_ex),             // Flag indicating to use extra sprite addr
	.chr_ain_orig      (chr_addr),                // PPU address in
	.chr_ain_ex        (chr_addr_ex),             // PPU address for extra sprites
	.chr_read          (chr_read),                // PPU read (inverted, active high)
	.chr_write         (chr_write),               // PPU write (inverted, active high)
	.chr_din           (chr_from_ppu),            // PPU data bus in (split from bid)
	.chr_dout          (chr_from_ppu_mapper),     // PPU data bus in (split from bid)
	.vram_a10          (vram_a10),                // CIRAM a10 line
	.vram_ce           (vram_ce),                 // CIRAM chip enable
	.irq               (mapper_irq),              // IRQ (inverted, active high)
	.audio_in          (audio_mappers),           // Amplified and inverted APU audio
	.audio             (sample_ext),              // Mixed audio output from cart
	.mapper_irq_pause  (mapper_irq_pause),        // Pause cycle-based mappers during OC extended Vblank
	.mapper_ce         (mapper_ce),               // Native 1.78MHz for cycle-based IRQ timers
	.audio_ce          (audio_ce),                // Native 1.78MHz, never stalls (expansion audio)
	.put_ce            (apu_put_ce),              // Native-rate put phase for expansion audio
	.overclock         (2'd0),                    // Turbo never pitch-shifts expansion audio
	.smooth_audio      (smooth_audio),            // Option toggle
	.scale_mode        (scale_mode),              // Force scale
	.root_key          (root_key),                // Synced dynamic root key
	// SDRAM Communication
	.prg_aout          (prg_linaddr),             // SDRAM adjusted PRG RAM address
	.prg_allow         (prg_allow),               // Simulates internal CE/Locking
	.chr_aout          (chr_linaddr),             // SDRAM adjusted CHR RAM address
	.chr_allow         (chr_allow),               // Simulates internal CE/Locking
	.prg_mask          (prg_mask),                // PRG Mask for SDRAM translation
	.chr_mask          (chr_mask),                // CHR Mask for SDRAM translation
	// External hardware interface (EEPROM)
	.mapper_addr       (bram_addr),
	.mapper_data_in    (bram_din),
	.mapper_data_out   (bram_dout),
	.mapper_prg_write  (bram_write),
	.mapper_ovr        (bram_override),
	// Cheats
	.prg_from_ram      (from_data_bus),           // Hacky cpu din <= get rid of this!
	// Behavior helper flags
	.has_chr_dout      (has_chr_from_ppu_mapper), // Output specific data for CHR rather than from SDRAM
	.prg_bus_write     (prg_bus_write),           // PRG data driven to bus
	.prg_conflict      (prg_conflict),            // Simulate bus conflicts
	.has_savestate     (mapper_has_savestate),    // Mapper supports savestates
	.prg_conflict_d0   (prg_conflict_d0),         // Simulate bus conflicts for Mapper 144
	.has_flashsaves    (has_flashsaves),          // Homebrew mapper that saves to PRG-ROM in flash memory
	// User input/FDS controls
	.fds_eject         (fds_eject),               // Used to trigger FDS disk changes
	.fds_busy          (fds_busy),                // Used to trigger FDS disk changes
	.fds_fast          (fds_fast),
	.diskside          (diskside),
	.max_diskside      (max_diskside),
	.fds_auto_eject    (fds_auto_eject),

	// savestates
	.SaveStateBus_Din  (SaveStateBus_Din ),
	.SaveStateBus_Adr  (SaveStateBus_Adr ),
	.SaveStateBus_wren (SaveStateBus_wren),
	.SaveStateBus_rst  (SaveStateBus_rst ),
	.SaveStateBus_load (loading_savestate ),
	.SaveStateBus_Dout (SaveStateBus_wired_or[3]),

	.Savestate_MAPRAMactive   (Savestate_MAPRAMactive),
	.Savestate_MAPRAMAddr     (Savestate_MAPRAMAddr),
	.Savestate_MAPRAMRdEn     (Savestate_MAPRAMRdEn),
	.Savestate_MAPRAMWrEn     (Savestate_MAPRAMWrEn),
	.Savestate_MAPRAMWriteData(Savestate_MAPRAMWriteData),
	.Savestate_MAPRAMReadData (Savestate_MAPRAMReadData)
);

wire genie_ovr;
wire [7:0] genie_data;

CODES codes (
	.clk        (clk),
	.reset      (gg_reset),
	.enable     (~gg),
	.addr_in    (addr),
	.data_in    (prg_allow ? cpumem_din : prg_dout_mapper),
	.code       (gg_code),
	.available  (gg_avail),
	.genie_ovr  (genie_ovr),
	.genie_data (genie_data)
);


/**********************************************************/
/*************       Bus Arbitration        ***************/
/**********************************************************/

assign chr_to_ppu = has_chr_from_ppu_mapper ? chr_from_ppu_mapper : ppumem_din;

assign cpumem_addr  = prg_linaddr;
assign cpumem_read  = (prg_read & prg_allow) | (prg_write && prg_conflict);
assign cpumem_write = prg_write && prg_allow;
assign cpumem_dout  = prg_din;
assign ppumem_addr  = chr_linaddr;
assign ppumem_read  = chr_read;
assign ppumem_write = chr_write && (chr_allow || vram_ce);
assign ppumem_dout  = chr_from_ppu;

reg [7:0] open_bus_data;

always @(posedge clk) begin
	if (loading_savestate) begin
		open_bus_data <= SS_TOP[8:1];
	end else begin
		if (!cpu_ce)
			open_bus_data <= mw_int ? dbus : dma_data_bus;
	end
end

assign from_data_bus = genie_ovr ? genie_data : external_data_bus;

reg [7:0] external_data_bus;

always @* begin
	if (reset) begin
		external_data_bus = SS_TOP[16:9]; // 0;
	end else if (joypad1_cs && ~dma_aout_enable) begin   // Joypad1 Read
		external_data_bus = {open_bus_data[7:5], joypad1_data};
	end else if (joypad2_cs && ~dma_aout_enable) begin   // Joypad2 Read
		external_data_bus = {open_bus_data[7:5], joypad2_data};
	end else if (ppu_cs) begin                          // PPU Read
		external_data_bus = ppu_dout;
	end else if (prg_allow) begin                       // PRG Read
		external_data_bus = cpumem_din;
	end else if (prg_bus_write) begin                   // PRG/CPU Write
		external_data_bus = prg_dout_mapper;
	end else begin                                      // Open Bus
		external_data_bus = open_bus_data;
	end
end

assign SS_TOP_BACK[ 0]    = odd_or_even;
assign SS_TOP_BACK[ 8: 1] = open_bus_data;
assign SS_TOP_BACK[16: 9] = external_data_bus;
assign SS_TOP_BACK[21:17] = div_cpu;
assign SS_TOP_BACK[26:22] = div_native_cpu;
assign SS_TOP_BACK[29:27] = div_ppu;
assign SS_TOP_BACK[31:30] = ppu_tick;
assign SS_TOP_BACK[34:32] = cpu_tick_count;
assign SS_TOP_BACK[36:35] = div_sys;
// OC parameters: restored on load so core always runs at the OC level it was saved under
assign SS_TOP_BACK[38:37] = overclock_latched;
assign SS_TOP_BACK[43:39] = div_cpu_n;
assign SS_TOP_BACK[45:44] = oc_method_latched;
assign SS_TOP_BACK[   53] = native_odd_or_even;  // native-rate APU phase
// Bits 44..52 were used by the removed PPU/mapper OC dividers and are now free.
assign SS_TOP_BACK[63:54] = 10'b0; // free to be used
assign SS_TOP_BACK[52:46] = 7'b0;

/**********************************************************/
/*************       Savestates             ***************/
/**********************************************************/

wire [63:0] SaveStateBus_Din;
wire [9:0] SaveStateBus_Adr;
wire SaveStateBus_wren, SaveStateBus_rst;

wire [7:0]  Savestate_RAMWriteData;
wire [7:0]  Savestate_RAMReadData;
wire [24:0] Savestate_RAMAddr;
wire        Savestate_RAMRdEn;
wire        Savestate_RAMWrEn;
wire [2:0]  Savestate_RAMType;

localparam SAVESTATE_MODULES    = 5;
wire [63:0] SaveStateBus_wired_or[0:SAVESTATE_MODULES-1];

wire reset_ss;
wire reset_delay;
wire savestate_savestate;
wire savestate_loadstate;
wire [31:0] savestate_address;
wire savestate_busy;

wire [63:0] SS_TOP;
wire [63:0] SS_TOP_BACK;
eReg_SavestateV #(SSREG_INDEX_TOP, SSREG_DEFAULT_TOP) iREG_SAVESTATE_TOP (clk, SaveStateBus_Din, SaveStateBus_Adr, SaveStateBus_wren, SaveStateBus_rst, SaveStateBus_wired_or[4], SS_TOP_BACK, SS_TOP);

wire [63:0] SaveStateBus_Dout  = SaveStateBus_wired_or[0] | SaveStateBus_wired_or[1] | SaveStateBus_wired_or[2] | SaveStateBus_wired_or[3] | SaveStateBus_wired_or[4] | SaveStateExt_Dout;

wire loading_savestate;
wire saving_savestate;
wire sleep_savestates;
wire sleep_rewind;

assign Savestate_SDRAMAddr      = Savestate_RAMAddr;
assign Savestate_SDRAMRdEn      = Savestate_RAMRdEn && (Savestate_RAMType > 1);
assign Savestate_SDRAMWrEn      = Savestate_RAMWrEn && (Savestate_RAMType > 1);
assign Savestate_SDRAMWriteData = Savestate_RAMWriteData;

wire [7:0] Savestate_OAMAddr      = Savestate_RAMAddr[7:0];
wire       Savestate_OAMRdEn      = Savestate_RAMRdEn && (Savestate_RAMType == 0);
wire       Savestate_OAMWrEn      = Savestate_RAMWrEn && (Savestate_RAMType == 0);
wire [7:0] Savestate_OAMWriteData = Savestate_RAMWriteData;
wire [7:0] Savestate_OAMReadData;

wire        Savestate_MAPRAMactive    = loading_savestate | saving_savestate;
wire [12:0] Savestate_MAPRAMAddr      = Savestate_RAMAddr[12:0];
wire        Savestate_MAPRAMRdEn      = Savestate_RAMRdEn && (Savestate_RAMType == 1);
wire        Savestate_MAPRAMWrEn      = Savestate_RAMWrEn && (Savestate_RAMType == 1);
wire [7:0]  Savestate_MAPRAMWriteData = Savestate_RAMWriteData;
wire [7:0]  Savestate_MAPRAMReadData;

assign Savestate_RAMReadData = (Savestate_RAMType == 0) ? Savestate_OAMReadData :
										 (Savestate_RAMType == 1) ? Savestate_MAPRAMReadData :
										 Savestate_SDRAMReadData;

assign SaveStateExt_Din  = SaveStateBus_Din;
assign SaveStateExt_Adr  = SaveStateBus_Adr;
assign SaveStateExt_wren = SaveStateBus_wren;
assign SaveStateExt_rst  = SaveStateBus_rst;
assign SaveStateExt_load = loading_savestate;


savestates savestates (
	.clk                    (clk),
	.reset_in               (reset_nes),
	.reset_ss               (reset_ss),
	.reset_delay            (reset_delay),

	.load_done              (state_loaded),

	.increaseSSHeaderCount  (increaseSSHeaderCount),
	.save                   (savestate_savestate),
	.load                   (savestate_loadstate),
	.savestate_address      (savestate_address),
	.savestate_busy         (savestate_busy),

	.paused                 (corepause_active_delay),

	.BUS_Din                (SaveStateBus_Din),
	.BUS_Adr                (SaveStateBus_Adr),
	.BUS_wren               (SaveStateBus_wren),
	.BUS_rst                (SaveStateBus_rst),
	.BUS_Dout               (SaveStateBus_Dout),

	.loading_savestate      (loading_savestate),
	.saving_savestate       (saving_savestate),
	.sleep_savestate        (sleep_savestates),

	.Save_RAMAddr           (Savestate_RAMAddr),
	.Save_RAMRdEn           (Savestate_RAMRdEn),
	.Save_RAMWrEn           (Savestate_RAMWrEn),
	.Save_RAMWriteData      (Savestate_RAMWriteData),
	.Save_RAMReadData       (Savestate_RAMReadData),
	.Save_RAMType           (Savestate_RAMType),

	.bus_out_Din            (SAVE_out_Din),
	.bus_out_Dout           (SAVE_out_Dout),
	.bus_out_Adr            (SAVE_out_Adr),
	.bus_out_rnw            (SAVE_out_rnw),
	.bus_out_ena            (SAVE_out_ena),
	.bus_out_be             (SAVE_out_be),
	.bus_out_done           (SAVE_out_done)
);

statemanager #(58720256, 33554432) statemanager (
	.clk                 (clk),
	.reset               (reset_nes),

	.rewind_on           (1'b0),
	.rewind_active       (1'b0),

	.savestate_number    (savestate_number),
	.save                (save_state),
	.load                (load_state),

	.sleep_rewind        (sleep_rewind),
	.vsync               (1'b0),

	.request_savestate   (savestate_savestate),
	.request_loadstate   (savestate_loadstate),
	.request_address     (savestate_address),
	.request_busy        (savestate_busy)
);

assign sleep_savestate = sleep_rewind | sleep_savestates;

endmodule
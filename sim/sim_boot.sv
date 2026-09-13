// Boot test for the NES core (verilator --binary --timing sim/sim_boot.sv ...)
// Models the SDRAM sidebands behaviorally: 32K NROM PRG + 8K work RAM +
// always-0xFF CHR/CIRAM data. Program enables rendering and fills the
// palette with 0x21, then self-loops. SUCCESS = color output becomes 0x21
// while scanline advances.

module sim_top;

	reg clk = 0;
	always #23.25 clk = ~clk;  // ~21.5 MHz

	reg reset_nes = 1;
	reg ppu_rst_behavior = 0;
	reg cold_reset = 0;
	reg pausecore = 0;
	reg [1:0] sys_type = 0;
	reg [63:0] mapper_flags = 0;
	reg dejitter_timing = 0;
	reg [1:0] overclock = 3;   // user's likely saved level: Maximum
	reg [1:0] oc_method = 3;   // user's likely saved method: old Async slot -> CE Turbo

	wire [15:0] sample;
	wire [5:0]  color;
	wire        is_obj;
	wire [1:0]  joypad_clock;
	wire [2:0]  joypad_out;
	wire [1:0]  diskside;
	wire [15:0] sample_sq1, sample_sq2, sample_tri, sample_noi, sample_dmc, sample_ext;
	wire [8:0]  cycle_o;
	wire [9:0]  scanline_o;
	wire        hsync, hblank, vsync, vblank;
	wire [2:0]  emphasis;
	wire        ppu_ce_out;
	wire        corepaused;
	wire [1:0]  nes_div;

	// SDRAM sidebands
	wire [24:0] cpumem_addr;
	wire        cpumem_read, cpumem_write;
	wire [7:0]  cpumem_dout;
	reg  [7:0]  cpumem_din = 8'h00;
	wire [21:0] ppumem_addr;
	wire        ppumem_read, ppumem_write;
	wire [7:0]  ppumem_dout;
	reg  [7:0]  ppumem_din = 8'hFF;   // all-ones tiles + nametable => solid BG when rendering

	wire [17:0] bram_addr;
	reg  [7:0]  bram_din = 0;
	wire [7:0]  bram_dout;
	wire        bram_write, bram_override;
	wire        refresh;
	wire        ss_ext_load;

	NES dut (
		.clk(clk), .reset_nes(reset_nes), .ppu_rst_behavior(ppu_rst_behavior),
		.cold_reset(cold_reset), .pausecore(pausecore), .corepaused(corepaused),
		.sys_type(sys_type), .nes_div(nes_div), .mapper_flags(mapper_flags),
		.sample(sample), .color(color), .is_obj(is_obj),
		.joypad_clock(joypad_clock), .joypad_out(joypad_out),
		.joypad1_data(5'b0), .joypad2_data(5'b0),
		.fds_busy(1'b0), .fds_eject(1'b0), .fds_auto_eject(1'b0),
		.max_diskside(2'd0), .fds_fast(1'b0), .diskside(diskside),
		.audio_channels(5'b11111),
		.sample_sq1(sample_sq1), .sample_sq2(sample_sq2), .sample_tri(sample_tri),
		.sample_noi(sample_noi), .sample_dmc(sample_dmc), .sample_ext(sample_ext),
		.ex_sprites(1'b0), .mask(2'b00), .dejitter_timing(dejitter_timing),
		.cpumem_addr(cpumem_addr), .cpumem_read(cpumem_read), .cpumem_write(cpumem_write),
		.cpumem_dout(cpumem_dout), .cpumem_din(cpumem_din), .cpumem_busy(cpumem_busy),
		.ppumem_addr(ppumem_addr), .ppumem_read(ppumem_read), .ppumem_write(ppumem_write),
		.ppumem_dout(ppumem_dout), .ppumem_din(ppumem_din),
		.refresh(refresh),
		.prg_mask(21'h1FFFFF), .chr_mask(20'hFFFFF),
		.bram_addr(bram_addr), .bram_din(bram_din), .bram_dout(bram_dout),
		.bram_write(bram_write), .bram_override(bram_override),
		.cycle(cycle_o), .scanline(scanline_o),
		.int_audio(1'b1), .ext_audio(1'b1), .stereo_en(1'b0),
		.smooth_audio(1'b0), .smooth_noise(1'b0), .swap_duty(1'b0),
		.scale_mode(2'b00), .root_key(4'd0),
		.detected_key(), .native_is_minor(),
		.ppu_ce_out(ppu_ce_out),
		.gg(1'b0), .gg_code(129'b0), .gg_avail(), .gg_reset(1'b0),
		.emphasis(emphasis), .save_written(), .mapper_has_flashsaves(),
		.debug_dots(1'b0), .disable_oam_corruption(1'b0),
		.mapper_has_savestate(), .increaseSSHeaderCount(1'b0),
		.save_state(1'b0), .load_state(1'b0), .savestate_number(2'd0),
		.sleep_savestate(), .state_loaded(),
		.hsync(hsync), .hblank(hblank), .vsync(vsync), .vblank(vblank),
		.Savestate_SDRAMAddr(), .Savestate_SDRAMRdEn(), .Savestate_SDRAMWrEn(),
		.Savestate_SDRAMWriteData(), .Savestate_SDRAMReadData(8'h00),
		.SaveStateExt_Din(), .SaveStateExt_Adr(), .SaveStateExt_wren(),
		.SaveStateExt_rst(), .SaveStateExt_Dout(), .SaveStateExt_load(ss_ext_load),
		.SAVE_out_Din(), .SAVE_out_Dout(64'h0), .SAVE_out_Adr(), .SAVE_out_rnw(),
		.SAVE_out_ena(), .SAVE_out_be(), .SAVE_out_done(1'b0),
		.overclock(overclock), .oc_method(oc_method)
	);

	// ---- behavioral SDRAM: 32K PRG + 8K work RAM ----
	reg [7:0] prg [0:32767];
	reg [7:0] ram [0:8191];

	// Test program: fill palette with 0x21, enable BG+SPR, self-loop
	initial begin
		integer i;
		for (i = 0; i < 32768; i = i + 1) prg[i] = 8'hEA; // NOP fill
		// $8000 (index 0)
		prg[16'h00] = 8'hA9; prg[16'h01] = 8'h3F;             // LDA #$3F
		prg[16'h02] = 8'h8D; prg[16'h03] = 8'h06; prg[16'h04] = 8'h20; // STA $2006
		prg[16'h05] = 8'hA9; prg[16'h06] = 8'h00;             // LDA #$00
		prg[16'h07] = 8'h8D; prg[16'h08] = 8'h06; prg[16'h09] = 8'h20; // STA $2006
		prg[16'h0A] = 8'hA2; prg[16'h0B] = 8'h00;             // LDX #$00
		prg[16'h0C] = 8'hA9; prg[16'h0D] = 8'h21;             // LDA #$21
		prg[16'h0E] = 8'h8D; prg[16'h0F] = 8'h07; prg[16'h10] = 8'h20; // STA $2007
		prg[16'h11] = 8'hE8;                                  // INX
		prg[16'h12] = 8'hD0; prg[16'h13] = 8'hF8;             // BNE $800C
		prg[16'h14] = 8'hA9; prg[16'h15] = 8'h18;             // LDA #$18
		prg[16'h16] = 8'h8D; prg[16'h17] = 8'h01; prg[16'h18] = 8'h20; // STA $2001
		prg[16'h19] = 8'h4C; prg[16'h1A] = 8'h19; prg[16'h1B] = 8'h80; // JMP $8019
		prg[16'h7FFC] = 8'h00; prg[16'h7FFD] = 8'h80;         // reset vector -> $8000
	end

	// ---- behavioral SDRAM channel (models rtl/sdram.sv ch1 protocol) ----
	// request = rising edge of (read|write); busy pulses while servicing;
	// read data is valid in the cycle busy drops. Requests held while the
	// channel is busy are queued (like sdram.sv's old_rd ack tracking).
	reg        svc_busy = 0;
	reg [2:0]  svc_cnt = 0;
	reg [24:0] svc_addr = 0;
	reg        svc_we = 0;
	reg [7:0]  svc_data = 0;
	reg        req_seen = 0;   // a request edge has been latched, awaiting service
	reg        prev_req = 0;
	reg        req_acked = 0;  // the currently-held request has been latched
	wire       mem_req = cpumem_read | cpumem_write;

	always @(posedge clk) begin
		// new request edge: a fresh request that must be serviced
		if (mem_req && !prev_req)
			req_acked <= 1'b0;
		prev_req <= mem_req;

		// accept the held request when the channel is free (sdram.sv accepts
		// in STATE_IDLE; a request held through busy still gets served)
		if (!svc_busy && mem_req && !req_acked) begin
			req_acked <= 1'b1;
			svc_addr  <= cpumem_addr;
			svc_we    <= cpumem_write;
			svc_data  <= cpumem_dout;
			svc_busy  <= 1'b1;
			svc_cnt   <= 3'd4;
		end
		if (svc_busy) begin
			svc_cnt <= svc_cnt - 3'd1;
			if (svc_cnt == 3'd1) begin
				if (!svc_we)
					cpumem_din <= svc_addr[24] ? ram[svc_addr[12:0]] : prg[svc_addr[14:0]];
				else if (svc_addr[24])
					ram[svc_addr[12:0]] <= svc_data;
				svc_busy <= 1'b0;
			end
		end
	end
	assign cpumem_busy = svc_busy;

	// ---- monitors ----
	longint unsigned t = 0;
	reg [9:0] last_scanline = 10'h3FF;
	longint unsigned scanline_change_t = 0;
	longint unsigned rd_count = 0;
	integer seen_color21 = 0;

	always @(posedge clk) begin
		t = t + 1;
		if (cpumem_read) rd_count = rd_count + 1;

		if (scanline_o != last_scanline) begin
			scanline_change_t = t;
			last_scanline = scanline_o;
		end

		// released reset at t=1000
		if (t == 1000) reset_nes = 0;

		// success: palette color visible while rendering
		if (reset_nes == 0 && t > 200000 && color == 6'h21) begin
			if (!seen_color21) begin
				seen_color21 = 1;
				$display("[PASS t=%0d] color=0x21 visible, scanline=%0d cycle=%0d", t, scanline_o, cycle_o);
				$finish;
			end
		end

		// hang detection: no scanline movement for 5M clocks after boot
		if (t == 6000000 && !seen_color21) begin
			$display("[FAIL t=%0d] hang/timeout: scanline=%0d (last change t=%0d) rd_count=%0d color=%0d",
			          t, scanline_o, scanline_change_t, rd_count, color);
			$finish;
		end
	end

	initial begin
		#200000000;
		$display("[FAIL] global timeout");
		$finish;
	end

	// debug probes into the DUT
	wire [4:0] dbg_div_cpu      = dut.div_cpu;
	wire [4:0] dbg_div_cpun     = dut.div_cpu_n;
	wire [2:0] dbg_div_ppu      = dut.div_ppu;
	wire       dbg_realign      = dut.realign;
	wire       dbg_freeze       = dut.freeze_clocks;
	wire       dbg_cms          = dut.cpumem_stall;
	wire       dbg_cps          = dut.cpu_ppu_stall;
	wire       dbg_cpu_ce       = dut.cpu_ce;
	wire       dbg_ppu_ce       = dut.ppu_ce;
	wire       dbg_hold_reset   = dut.hold_reset;
	wire       dbg_bootvector   = dut.bootvector_flag;
	wire       dbg_reset        = dut.reset;
	wire       dbg_preread      = dut.prg_read;
	wire       dbg_prallow      = dut.prg_allow;
	wire       dbg_turbowin     = dut.turbo_window;
	wire       dbg_pause_reali  = dut.pause_realign;
	wire       dbg_active       = dut.cpumem_wait;
	wire       dbg_pending      = dut.cpumem_stall;
	wire       dbg_busy         = cpumem_busy;
	wire       dbg_req          = cpumem_read | cpumem_write;
	wire [2:0] dbg_svc          = svc_cnt;
	wire [15:0] dbg_cpu_addr    = dut.cpu_addr;
	wire       dbg_rendering    = dut.ppu.rendering_regs;
	wire [14:0] dbg_vram_v      = dut.ppu.vram;
	wire       dbg_cs_sync      = dut.ppu_cs_sync;
	wire       dbg_ppu_write    = dut.ppu.write;

	// detailed trace at t=3000, 5000, then every 500k
	always @(posedge clk) begin
		if (t % 100000 == 50000)
			$display("[cpu t=%0d] cpu_addr=%h rendering=%b vram_v=%h cs_sync=%b ppu_write=%b",
				t, dbg_cpu_addr, dbg_rendering, dbg_vram_v, dbg_cs_sync, dbg_ppu_write);
		if (t == 3000 || t == 5000 || t == 20000 || (t % 500000 == 0))
			$display("[t=%0d] rst_in=%b rst=%b hold_rst=%b bootvec=%b div_cpu=%0d/%0d div_ppu=%0d cpu_ce=%b ppu_ce=%b realign=%b pause_re=%b freeze=%b cms=%b cps=%b prg_read=%b prg_allow=%b twin=%b",
				t, reset_nes, dbg_reset, dbg_hold_reset, dbg_bootvector,
				dbg_div_cpu, dbg_div_cpun, dbg_div_ppu, dbg_cpu_ce, dbg_ppu_ce,
				dbg_realign, dbg_pause_reali, dbg_freeze, dbg_cms, dbg_cps,
				dbg_preread, dbg_prallow, dbg_turbowin);
		if ((t >= 1000 && t <= 1030) || (t >= 1055 && t <= 1062))
			$display("[t=%0d] div_cpu=%0d req=%b read=%b busy=%b reqwait=%b stall=%b svc_cnt=%0d acked=%b",
				t, dbg_div_cpu, dbg_req, cpumem_read, dbg_busy, dbg_active, dbg_pending, dbg_cms, dbg_svc, req_acked);
	end

	// progress trace every 1M clocks
	always @(posedge clk) begin
		if (t % 1000000 == 0)
			$display("[t=%0d] scanline=%0d cycle=%0d rd=%0d color=%0d", t, scanline_o, cycle_o, rd_count, color);
	end

endmodule

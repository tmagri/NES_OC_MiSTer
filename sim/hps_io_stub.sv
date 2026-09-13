// Behavioral HPS replacement (SIM ONLY). Performs a MiSTer-style ROM
// download: raises ioctl_download, streams the bytes at ioctl_addr with
// ioctl_wr pulses, and honors ioctl_wait flow control — exactly what
// hps_io does for the real HPS.

module hps_io_stub (
	input         clk_sys,
	inout  [48:0] HPS_BUS,

	output reg [1:0]  buttons,
	output reg        forced_scandoubler,
	output reg        new_vmode,
	output reg [31:0] joystick_0,
	output reg [31:0] joystick_1,
	output reg [31:0] joystick_2,
	output reg [31:0] joystick_3,
	output reg [15:0] joystick_l_analog_0,
	output reg [15:0] joystick_l_analog_1,
	output reg [7:0]  paddle_0,
	output reg [7:0]  paddle_1,
	output reg [7:0]  paddle_2,
	output reg [7:0]  paddle_3,
	output reg [127:0] status,
	input  [8:0]      status_menumask,
	input  [31:0]     status_in,
	input             status_set,
	input             info_req,
	output reg [7:0]  info,
	output reg [21:0] gamma_bus,
	output reg        ioctl_download,
	output reg [31:0] ioctl_addr,
	output reg        ioctl_wr,
	output reg [7:0]  ioctl_dout,
	input             ioctl_wait,
	output reg [7:0]  ioctl_index,
	input  [31:0]     sd_lba [0:0],
	input             sd_rd,
	input             sd_wr,
	input             sd_ack,
	output reg [8:0]  sd_buff_addr,
	output reg [7:0]  sd_buff_dout,
	input  [7:0]      sd_buff_din [0:0],
	output reg        sd_buff_wr,
	output reg        img_mounted,
	output reg        img_readonly,
	output reg [63:0] img_size,
	output reg [10:0] ps2_key,
	input             ps2_kbd_led_use,
	input             ps2_kbd_led_status,
	output reg [24:0] ps2_mouse
);

	initial begin
		buttons = 0; forced_scandoubler = 0; new_vmode = 0;
		joystick_0 = 0; joystick_1 = 0; joystick_2 = 0; joystick_3 = 0;
		joystick_l_analog_0 = 0; joystick_l_analog_1 = 0;
		paddle_0 = 0; paddle_1 = 0; paddle_2 = 0; paddle_3 = 0;
		status = 128'b0; info = 0; gamma_bus = 0;
		ioctl_download = 0; ioctl_addr = 0; ioctl_wr = 0; ioctl_dout = 0; ioctl_index = 0;
		sd_buff_addr = 0; sd_buff_dout = 0; sd_buff_wr = 0;
		img_mounted = 0; img_readonly = 0; img_size = 0;
		ps2_key = 0; ps2_mouse = 0;
	end

	// ---- the ROM to download: iNES header + PRG + CHR ----
	localparam int HDRLEN  = 16;
	localparam int PRGLEN  = 32*1024;
	localparam int CHRLEN  = 8*1024;
	localparam int ROMLEN  = HDRLEN + PRGLEN + CHRLEN;
	reg [7:0] rom [0:ROMLEN-1];

	initial begin
		int k;
		for (k = 0; k < ROMLEN; k = k + 1) rom[k] = 8'h00;
		// iNES header: NES\x1A, 2x16K PRG, 1x8K CHR, mapper 0
		rom[0] = "N"; rom[1] = "E"; rom[2] = "S"; rom[3] = "\x1A";
		rom[4] = 2; rom[5] = 1; rom[6] = 0; rom[7] = 0;
		for (k = 8; k < 16; k = k + 1) rom[k] = 0;
		// program (loaded at $8000 by GameLoader for mapper 0)
		rom[HDRLEN+16'h00] = 8'hA9; rom[HDRLEN+16'h01] = 8'h3F;             // LDA #$3F
		rom[HDRLEN+16'h02] = 8'h8D; rom[HDRLEN+16'h03] = 8'h06; rom[HDRLEN+16'h04] = 8'h20; // STA $2006
		rom[HDRLEN+16'h05] = 8'hA9; rom[HDRLEN+16'h06] = 8'h00;             // LDA #$00
		rom[HDRLEN+16'h07] = 8'h8D; rom[HDRLEN+16'h08] = 8'h06; rom[HDRLEN+16'h09] = 8'h20; // STA $2006
		rom[HDRLEN+16'h0A] = 8'hA2; rom[HDRLEN+16'h0B] = 8'h00;             // LDX #$00
		rom[HDRLEN+16'h0C] = 8'hA9; rom[HDRLEN+16'h0D] = 8'h21;             // LDA #$21
		rom[HDRLEN+16'h0E] = 8'h8D; rom[HDRLEN+16'h0F] = 8'h07; rom[HDRLEN+16'h10] = 8'h20; // STA $2007
		rom[HDRLEN+16'h11] = 8'hE8;                                          // INX
		rom[HDRLEN+16'h12] = 8'hD0; rom[HDRLEN+16'h13] = 8'hF8;             // BNE
		rom[HDRLEN+16'h14] = 8'hA9; rom[HDRLEN+16'h15] = 8'h18;             // LDA #$18
		rom[HDRLEN+16'h16] = 8'h8D; rom[HDRLEN+16'h17] = 8'h01; rom[HDRLEN+16'h18] = 8'h20; // STA $2001
		rom[HDRLEN+16'h19] = 8'h4C; rom[HDRLEN+16'h1A] = 8'h19; rom[HDRLEN+16'h1B] = 8'h80; // JMP $8019
		rom[HDRLEN+16'h7FFC] = 8'h00; rom[HDRLEN+16'h7FFD] = 8'h80;         // reset vector
		for (k = 0; k < CHRLEN; k = k + 1) rom[HDRLEN+PRGLEN+k] = 8'hFF;    // CHR: all-ones tiles
	end

	// ---- download sequence ----
	initial begin
		int idx;
		// let the core come out of its own boot reset first
		repeat (2000) @(posedge clk_sys);

		ioctl_index    <= 8'h40;    // filetype[7:6]=01 -> type_nes
		ioctl_download <= 1'b1;

		// the real HPS has file-I/O latency between download start and the
		// first data byte; give the core's loader time to leave reset
		repeat (4000) @(posedge clk_sys);

		for (idx = 0; idx < ROMLEN; idx = idx + 1) begin
			ioctl_addr <= idx;
			ioctl_dout <= rom[idx];
			@(posedge clk_sys);
			ioctl_wr <= 1'b1;
			@(posedge clk_sys);
			ioctl_wr <= 1'b0;
			// honor flow control
			@(posedge clk_sys);
			while (ioctl_wait) @(posedge clk_sys);
		end

		repeat (100) @(posedge clk_sys);
		ioctl_download <= 1'b0;
		$display("[HPS] download complete (%0d bytes)", ROMLEN);
	end
endmodule

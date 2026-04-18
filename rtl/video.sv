// Copyright (c) 2012-2013 Ludvig Strigeus
// This program is GPL Licensed. See COPYING for the full license.

module video
(
	input        clk,
	input        reset,
	input        ce_in,
	input  [5:0] color,
	input  [8:0] count_h,
	input  [8:0] count_v,
	input  [1:0] hide_overscan,
	input  [3:0] palette,
	input  [2:0] emphasis,
	input  [1:0] reticle,
	input  [1:0] sys_type,
	input        pal_video,
	input        nes_hblank,
	input        nes_hsync,
	input        nes_vsync,
	input        nes_vblank,

	input        load_color,
	input [23:0] load_color_data,
	input  [5:0] load_color_index,

	input        anti_epilepsy_en,
	input        is_obj,

	output   reg hold_reset,

	output       ce_pix,
	output       HSync,
	output       VSync,
	output       HBlank,
	output       VBlank,
	output [7:0] R,
	output [7:0] G,
	output [7:0] B
);

reg vsync_reg, hsync_reg, hblank_reg, vblank_reg;
reg [1:0] hsync_shift, vsync_shift, hblank_shift, vblank_shift;

assign HSync = hsync_shift[1];
assign VSync = vsync_shift[1];
assign HBlank = hblank_shift[1];
assign VBlank = vblank_shift[1];

wire hsync_out = hsync_reg | nes_hsync;
wire vsync_out = vsync_reg | nes_vsync;
wire hblank_out = hblank_reg | nes_hblank;
wire vblank_out = vblank_reg | nes_vblank;

reg pix_ce;
wire [5:0] color_ef = reticle[0] ? (reticle[1] ? 6'h21 : 6'h15) : color;

always @(posedge clk) begin
	pix_ce   <= ce_in;
end

assign ce_pix = pix_ce;
// Kitrinx 34 palette by Kitrinx
wire [23:0] pal_kitrinx_lut[64] = '{
	'h666666, 'h01247B, 'h1B1489, 'h39087C, 'h520257, 'h5C0725, 'h571300, 'h472300,
	'h2D3300, 'h0E4000, 'h004500, 'h004124, 'h003456, 'h000000, 'h000000, 'h000000,
	'hADADAD, 'h2759C9, 'h4845DB, 'h6F34CA, 'h922B9B, 'hA1305A, 'h9B4018, 'h885400,
	'h686700, 'h3E7A00, 'h1B8213, 'h0D7C57, 'h136C99, 'h000000, 'h000000, 'h000000,
	'hFFFFFF, 'h78ABFF, 'h9897FF, 'hC086FF, 'hE27DEF, 'hF281AF, 'hED916D, 'hDBA43B,
	'hBDB825, 'h92CB33, 'h6DD463, 'h5ECEA8, 'h65BEEA, 'h525252, 'h000000, 'h000000,
	'hFFFFFF, 'hCADBFF, 'hD8D2FF, 'hE7CCFF, 'hF4C9F9, 'hFACBDF, 'hF7D2C4, 'hEEDAAF,
	'hE1E3A5, 'hD0EBAB, 'hC2EEBF, 'hBDEBDB, 'hC0E4F7, 'hB8B8B8, 'h000000, 'h000000
};

// Smooth palette from FirebrandX
wire [23:0] pal_smooth_lut[64] = '{
	'h6A6D6A, 'h001380, 'h1E008A, 'h39007A, 'h550056, 'h5A0018, 'h4F1000, 'h3D1C00,
	'h253200, 'h003D00, 'h004000, 'h003924, 'h002E55, 'h000000, 'h000000, 'h000000,
	'hB9BCB9, 'h1850C7, 'h4B30E3, 'h7322D6, 'h951FA9, 'h9D285C, 'h983700, 'h7F4C00,
	'h5E6400, 'h227700, 'h027E02, 'h007645, 'h006E8A, 'h000000, 'h000000, 'h000000,
	'hFFFFFF, 'h68A6FF, 'h8C9CFF, 'hB586FF, 'hD975FD, 'hE377B9, 'hE58D68, 'hD49D29,
	'hB3AF0C, 'h7BC211, 'h55CA47, 'h46CB81, 'h47C1C5, 'h4A4D4A, 'h000000, 'h000000,
	'hFFFFFF, 'hCCEAFF, 'hDDDEFF, 'hECDAFF, 'hF8D7FE, 'hFCD6F5, 'hFDDBCF, 'hF9E7B5,
	'hF1F0AA, 'hDAFAA9, 'hC9FFBC, 'hC3FBD7, 'hC4F6F6, 'hBEC1BE, 'h000000, 'h000000
};

// PC-10 Better by Kitrinx
wire [23:0] pal_pc10_lut[64] = '{
	'h6D6D6D, 'h10247C, 'h0A06B3, 'h6950C2, 'h6A0F62, 'h831264, 'h872F0F, 'h774C11,
	'h5E490F, 'h2C430A, 'h1E612A, 'h258011, 'h164244, 'h000000, 'h000000, 'h000000,
	'hB6B6B6, 'h2767C0, 'h1F48DA, 'h7114DA, 'h8A17DC, 'hB71987, 'hB0150F, 'hB37219,
	'h806C15, 'h3E8313, 'h258011, 'h34A46F, 'h2C8589, 'h000000, 'h000000, 'h000000,
	'hFFFFFF, 'h87B2ED, 'h9795EB, 'hC07BEB, 'hBD1DE1, 'hD97EED, 'hD59620, 'hDFB624,
	'hCFD326, 'h84CA20, 'h41E11D, 'h7FEED6, 'h4EE9EF, 'h000000, 'h000000, 'h000000,
	'hFFFFFF, 'hC3D8F6, 'hD2BBF4, 'hECBEF6, 'hE29EF2, 'hE8BCBA, 'hF0DBA0, 'hF5F969,
	'hF7FA87, 'hC3F364, 'hACF180, 'h7FEED6, 'hAAD5F4, 'h000000, 'h000000, 'h000000
};

// Wavebeam by NakedArthur
wire [23:0] pal_wavebeam_lut[64] = '{
	'h6B6B6B, 'h001B88, 'h21009A, 'h40008C, 'h600067, 'h64001E, 'h590800, 'h481600,
	'h283600, 'h004500, 'h004908, 'h00421D, 'h003659, 'h000000, 'h000000, 'h000000,
	'hB4B4B4, 'h1555D3, 'h4337EF, 'h7425DF, 'h9C19B9, 'hAC0F64, 'hAA2C00, 'h8A4B00,
	'h666B00, 'h218300, 'h008A00, 'h008144, 'h007691, 'h000000, 'h000000, 'h000000,
	'hFFFFFF, 'h63B2FF, 'h7C9CFF, 'hC07DFE, 'hE977FF, 'hF572CD, 'hF4886B, 'hDDA029,
	'hBDBD0A, 'h89D20E, 'h5CDE3E, 'h4BD886, 'h4DCFD2, 'h525252, 'h000000, 'h000000,
	'hFFFFFF, 'hBCDFFF, 'hD2D2FF, 'hE1C8FF, 'hEFC7FF, 'hFFC3E1, 'hFFCAC6, 'hF2DAAD,
	'hEBE3A0, 'hD2EDA2, 'hBCF4B4, 'hB5F1CE, 'hB6ECF1, 'hBFBFBF, 'h000000, 'h000000
};

// Sony CXA by FirebrandX
wire [23:0] pal_sonycxa_lut[64] = '{
	'h585858, 'h00238C, 'h00139B, 'h2D0585, 'h5D0052, 'h7A0017, 'h7A0800, 'h5F1800,
	'h352A00, 'h093900, 'h003F00, 'h003C22, 'h00325D, 'h000000, 'h000000, 'h000000,
	'hA1A1A1, 'h0053EE, 'h153CFE, 'h6028E4, 'hA91D98, 'hD41E41, 'hD22C00, 'hAA4400,
	'h6C5E00, 'h2D7300, 'h007D06, 'h007852, 'h0069A9, 'h000000, 'h000000, 'h000000,
	'hFFFFFF, 'h1FA5FE, 'h5E89FE, 'hB572FE, 'hFE65F6, 'hFE6790, 'hFE773C, 'hFE9308,
	'hC4B200, 'h79CA10, 'h3AD54A, 'h11D1A4, 'h06BFFE, 'h424242, 'h000000, 'h000000,
	'hFFFFFF, 'hA0D9FE, 'hBDCCFE, 'hE1C2FE, 'hFEBCFB, 'hFEBDD0, 'hFEC5A9, 'hFED18E,
	'hE9DE86, 'hC7E992, 'hA8EEB0, 'h95ECD9, 'h91E4FE, 'hACACAC, 'h000000, 'h000000
};


wire [23:0] mem_data;

spram #(.addr_width(6), .data_width(24), .mem_name("pal"), .mem_init_file("rtl/tao.mif")) pal_ram
(
	.clock(clk),
	.address(load_color ? load_color_index : color_ef),
	.data(load_color_data),
	.wren(load_color),
	.q(mem_data)
);

reg [23:0] pixel;

reg hbl, vbl;

always @(posedge clk) begin
	if(pix_ce) begin
		case (palette)
			0: pixel <= pal_kitrinx_lut[color_ef][23:0];
			1: pixel <= pal_smooth_lut[color_ef][23:0];
			2: pixel <= pal_wavebeam_lut[color_ef][23:0];
			3: pixel <= pal_sonycxa_lut[color_ef][23:0];
			4: pixel <= pal_pc10_lut[color_ef][23:0];
			5: pixel <= mem_data;
			default:pixel <= pal_kitrinx_lut[color_ef][23:0];
		endcase
	end
end

wire hblank_period;
wire disengaged = reset || hold_reset;
reg  [8:0] h, v;
wire [8:0] hc = disengaged ? h : count_h;
wire [8:0] vc = disengaged ? v : count_v;
reg [7:0] ro,go,bo;

// -----------------------------------------------------------------------
// Epileptic-Friendly Filter (Option A: Temporal Frame Blending)
// FIXED: Flawless 2D Coordinate Addressing (No Scanline Overflows)
// -----------------------------------------------------------------------

wire [7:0] ri = pixel[23:16];
wire [7:0] gi = pixel[15:8];
wire [7:0] bi = pixel[7:0];

reg [25:0] frame_luma;
reg [25:0] prev_frame_luma;
reg [3:0]  strobe_counter;
wire       strobe_active = (strobe_counter > 0) & anti_epilepsy_en;

wire [9:0] pixel_luma = {2'b00, ri} + {2'b00, gi} + {2'b00, bi};
wire in_active_display = (vc < 9'd240) && !hblank_period;

// Per-channel frame sums for chrominance flash detection
// SMB2 bomb explosions cycle the background through different-hued colors
// of similar brightness (red/green/blue). Luma-only detection misses these
// "chrominance flashes" entirely, so we track R, G, B sums separately.
reg [23:0] frame_r_sum, frame_g_sum, frame_b_sum;
reg [23:0] prev_frame_r_sum, prev_frame_g_sum, prev_frame_b_sum;

// --- Bulletproof 2D Coordinate Tracking ---
// We directly use the native horizontal counter (hc) because the NES hardware 
// handles the wrapping perfectly. This guarantees we don't desync on skipped dots.
// Pipeline the X, Y coordinates to match the exact delay of the ro, go, bo pixels
reg [8:0] hc_d1;
reg [7:0] vc_d1;
reg in_active_display_d1, in_active_display_d2;
reg is_obj_d1, is_obj_d2;

always @(posedge clk) begin
	if (pix_ce) begin
		hc_d1 <= hc;
		
		vc_d1 <= vc[7:0];
		
		in_active_display_d1 <= in_active_display;
		in_active_display_d2 <= in_active_display_d1;

		is_obj_d1 <= is_obj;
		is_obj_d2 <= is_obj_d1;
	end
end

// Calculate exact memory addresses (Y * 384 + X) to guarantee NO overlap.
// 384 is strictly larger than the max NES hc value (340), which completely prevents
// the right edge of one scanline from wrapping around and bleeding into the 
// left edge of the next scanline.
// Math: 384 = 256 + 128 = (Y << 8) + (Y << 7). 17-bit resulting address.
wire [16:0] fb_addr = {1'b0, vc_d1, 8'b00000000} + {2'b00, vc_d1, 7'b0000000} + {8'b0, hc_d1};

// Temporal Blending Framebuffer
// Sized to safely hold 240 lines * 384 columns (92,160 pixels)
reg [23:0] fb_ram [0:98303]; 
reg [23:0] prev_rgb;

// Pipeline the read address one stage so the write-back targets the same
// pixel whose history we just read (read at cycle N, write-back at cycle N+1).
reg [16:0] fb_addr_d;

// -----------------------------------------------------------------------
// Compounding Temporal Blending Math (IIR Filter)
// 12.5% Current Frame, 87.5% Accumulated History Frame (2-frame blur)
// By feeding the blended pixel back into the framebuffer, the blur 
// continuously compounds across multiple frames, completely suppressing 
// 3+ color sequences like Zelda II's death screen.
// -----------------------------------------------------------------------

// Math: (ro + prev_rgb*7) / 8 -> Ensures no overflow
// Combinational: prev_rgb and ro are both registered and stable between
// pix_ce edges, so these wires are glitch-free. Keeping blend combinational
// ensures it has identical latency to ro (both 1 pix_ce behind hc),
// eliminating any horizontal shift when strobe engages/disengages.
wire [10:0] sum_r = {3'b000, ro} + {3'b000, prev_rgb[23:16]} + {2'b00, prev_rgb[23:16], 1'b0} + {1'b0, prev_rgb[23:16], 2'b00};
wire [10:0] sum_g = {3'b000, go} + {3'b000, prev_rgb[15:8]}  + {2'b00, prev_rgb[15:8],  1'b0} + {1'b0, prev_rgb[15:8],  2'b00};
wire [10:0] sum_b = {3'b000, bo} + {3'b000, prev_rgb[7:0]}   + {2'b00, prev_rgb[7:0],   1'b0} + {1'b0, prev_rgb[7:0],   2'b00};

wire [7:0] blend_r = sum_r[10:3];
wire [7:0] blend_g = sum_g[10:3];
wire [7:0] blend_b = sum_b[10:3];

// -----------------------------------------------------------------------
// Framebuffer Read/Write Pipeline (latency-matched to ro/go/bo)
//
// Cycle N   (pix_ce): hc_d1 captured, fb_addr = addr(hc_d1).
//                     prev_rgb <= fb_ram[fb_addr] — read history for this pixel.
//                     ro <= emphasis(pixel) — current frame pixel (same position).
//                     fb_addr_d <= fb_addr — save address for write-back.
//
// Cycle N+1 (pix_ce): blend_r (wire) = f(ro, prev_rgb) — both now settled.
//                     fb_ram[fb_addr_d] <= blend — write back to SAME address
//                     we read from, so no spatial shift in the framebuffer.
// -----------------------------------------------------------------------

always @(posedge clk) begin
	if (pix_ce) begin
		// Synchronous read: sample previous frame's pixel at current address
		prev_rgb <= fb_ram[fb_addr];
		
		// Pipeline the address so next cycle's write-back goes to same location
		fb_addr_d <= fb_addr;
		
		// Write-back: uses fb_addr_d (address from last cycle = same pixel we read)
		// and blend_r/ro (combinational/registered, both for that same pixel)
		// Skip blending for sprite pixels — only blend background pixels
		if (in_active_display_d2) begin
			if (strobe_active && !is_obj_d2)
				fb_ram[fb_addr_d] <= {blend_r, blend_g, blend_b};
			else
				fb_ram[fb_addr_d] <= {ro, go, bo};
		end
	end
end

// Strobe calculation: detect both brightness AND color flashes
wire [25:0] luma_delta = (frame_luma > prev_frame_luma) ? 
                         (frame_luma - prev_frame_luma) : 
                         (prev_frame_luma - frame_luma);

// Per-channel deltas catch chrominance flashes (e.g. SMB2 bomb: cycles
// red→green→blue background colors of similar brightness)
wire [23:0] r_delta = (frame_r_sum > prev_frame_r_sum) ?
                      (frame_r_sum - prev_frame_r_sum) :
                      (prev_frame_r_sum - frame_r_sum);
wire [23:0] g_delta = (frame_g_sum > prev_frame_g_sum) ?
                      (frame_g_sum - prev_frame_g_sum) :
                      (prev_frame_g_sum - frame_g_sum);
wire [23:0] b_delta = (frame_b_sum > prev_frame_b_sum) ?
                      (frame_b_sum - prev_frame_b_sum) :
                      (prev_frame_b_sum - frame_b_sum);

wire flash_detected = (luma_delta > 26'd7_000_000) ||
                      (r_delta > 24'd2_000_000) ||
                      (g_delta > 24'd2_000_000) ||
                      (b_delta > 24'd2_000_000);

always @(posedge clk) begin
	if (reset) begin
		frame_luma <= 0;
		prev_frame_luma <= 0;
		frame_r_sum <= 0;
		frame_g_sum <= 0;
		frame_b_sum <= 0;
		prev_frame_r_sum <= 0;
		prev_frame_g_sum <= 0;
		prev_frame_b_sum <= 0;
		strobe_counter <= 0;
	end else if (pix_ce) begin
		if (in_active_display) begin
			frame_luma <= frame_luma + pixel_luma;
			frame_r_sum <= frame_r_sum + {16'b0, ri};
			frame_g_sum <= frame_g_sum + {16'b0, gi};
			frame_b_sum <= frame_b_sum + {16'b0, bi};
		end
		
		if (vc == 9'd240 && hc == 9'd0) begin
			prev_frame_luma <= frame_luma;
			prev_frame_r_sum <= frame_r_sum;
			prev_frame_g_sum <= frame_g_sum;
			prev_frame_b_sum <= frame_b_sum;
			frame_luma <= 0;
			frame_r_sum <= 0;
			frame_g_sum <= 0;
			frame_b_sum <= 0;

			if (flash_detected) begin
				strobe_counter <= 4'd6; 
			end else if (strobe_counter > 0) begin
				strobe_counter <= strobe_counter - 1'd1;
			end
		end
	end
end

// -----------------------------------------------------------------------
// Video timing and emphasis logic
// -----------------------------------------------------------------------

reg  hblank, vblank;

wire [8:0] vblank_start, vblank_end, hblank_start, hblank_end, hsync_start, hsync_end;
wire [8:0] vblank_start_sl, vblank_end_sl, vsync_start_sl;

always_comb begin
	case (sys_type)
		2'b00,2'b11: begin // NTSC/Vs.
			vblank_start_sl = 9'd241;
			vblank_end_sl   = 9'd260;
			vsync_start_sl = 9'd244;
		end

		2'b01: begin       // PAL
			vblank_start_sl = 9'd241;
			vblank_end_sl   = 9'd310;
			vsync_start_sl = 9'd269;
		end

		2'b10: begin       // Dendy
			vblank_start_sl = 9'd241; // Vblank starts here allegedly, even though the flag is set at 291
			vblank_end_sl   = 9'd310;
			vsync_start_sl = 9'd269; // Guessing it's the same as PAL
		end
	endcase

	case (hide_overscan)
		2'b00: begin // Normal, trim to 224 lines, 256 dots
			hblank_period = (hc >= 257 || (hc <= 9'd0));
			vblank_start = vblank_start_sl - 9'd10;
			vblank_end = 9'd7;
		end
		2'b01: begin // "full" trim to 240 lines, 256 dots
			hblank_period = (hc >= 257 || (hc <= 9'd0));
			vblank_start = vblank_start_sl - 9'd2;
			vblank_end = 9'd511;
		end
		2'b10: begin // show border trim to 240 lines, 282 dots
			hblank_period = (hc >= 270 && hc <= 327);
			vblank_start = vblank_start_sl - 9'd2;
			vblank_end = 9'd511;
		end
		default: begin // Just show everything for the masochists
			hblank_period = (hc >= 270 && hc <= 326);
			vblank_start = vblank_start_sl;
			vblank_end = 9'd511;
		end
	endcase
end

wire hsync_period = (hc >= 278 && hc <= 302);


always @(posedge clk) begin
	reg [2:0] emph;

	if (pix_ce) begin
		hsync_shift <= {hsync_shift[0], hsync_out};
		vsync_shift <= {vsync_shift[0], vsync_out};
		hblank_shift <= {hblank_shift[0], hblank_out};
		vblank_shift <= {vblank_shift[0], vblank_out};

		if (h == 0 && v == 0)
			hold_reset <= 1'b0;
		else if (reset)
			hold_reset <= 1'b1;

		h <= h + 1'd1;
		if (h >= 340) begin
			h <= 0;
			v <= v + 1'd1;
			if (v == vblank_end_sl)
				v <= 9'd511;
		end

		if (count_h == 5 && count_v == 0) begin // Resync the counters in case of skipped dots
			h <= 6'd0;
			v <= 0;
		end

		hsync_reg <= hsync_period;
		hblank_reg <= hblank_period;

		if (vc == vsync_start_sl && hsync_period)
			vsync_reg <= 1;
		if (vc == (vsync_start_sl + 2'd3) && hsync_period)
			vsync_reg <= 0;

		if (vc == vblank_start && hsync_period)
			vblank_reg <= 1;
		if (vc == vblank_end && hsync_period)
			vblank_reg <= 0;

		ro <= ri;
		go <= gi;
		bo <= bi;
		emph <= 0;
		if (~&color_ef[3:1]) begin // Only applies in draw range
			emph <= emphasis; // Standard NES emphasis behavior
		end

		case(emph)
			1: begin
					ro <= ri;
					go <= gi - gi[7:2];
					bo <= bi - bi[7:2];
				end
			2: begin
					ro <= ri - ri[7:2];
					go <= gi;
					bo <= bi - bi[7:2];
				end
			3: begin
					ro <= ri - ri[7:3];
					go <= gi - gi[7:3];
					bo <= bi - bi[7:2] - bi[7:3];
				end
			4: begin
					ro <= ri - ri[7:3];
					go <= gi - gi[7:3];
					bo <= bi;
				end
			5: begin
					ro <= ri - ri[7:3];
					go <= gi - gi[7:2];
					bo <= bi - bi[7:3];
				end
			6: begin
					ro <= ri - ri[7:2];
					go <= gi - gi[7:3];
					bo <= bi - bi[7:3];
				end
			7: begin
					ro <= ri - ri[7:2];
					go <= gi - gi[7:2];
					bo <= bi - bi[7:2];
				end
		endcase
	end
end

// -----------------------------------------------------------------------
// Output assignments with temporal blending
// -----------------------------------------------------------------------

// Output: sprite pixels bypass the blend, background pixels get blended
assign R = (strobe_active && !is_obj_d2) ? blend_r : ro;
assign G = (strobe_active && !is_obj_d2) ? blend_g : go;
assign B = (strobe_active && !is_obj_d2) ? blend_b : bo;

endmodule
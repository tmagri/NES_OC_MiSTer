// AUTO-GENERATED full-emu harness (sim_full.sv)
module sim_full;

	reg clk = 0;
	always #23.28 clk = ~clk;

	reg CLK_50M = 0;
	reg RESET = 1;
	wire [48:0] HPS_BUS;
	wire CLK_VIDEO;
	wire CE_PIXEL;
	wire [12:0] VIDEO_ARX;
	wire [12:0] VIDEO_ARY;
	wire [7:0] VGA_R;
	wire [7:0] VGA_G;
	wire [7:0] VGA_B;
	wire VGA_HS;
	wire VGA_VS;
	wire VGA_DE;
	wire VGA_F1;
	wire [1:0] VGA_SL;
	wire VGA_SCALER;
	wire VGA_DISABLE;
	wire [11:0] HDMI_WIDTH = 12'h0;
	wire [11:0] HDMI_HEIGHT = 12'h0;
	wire HDMI_FREEZE;
	wire HDMI_BLACKOUT;
	wire HDMI_BOB_DEINT;
	wire LED_USER;
	wire [1:0] LED_POWER;
	wire [1:0] LED_DISK;
	wire [1:0] BUTTONS;
	wire CLK_AUDIO = 1'b0;
	wire [15:0] AUDIO_L;
	wire [15:0] AUDIO_R;
	wire AUDIO_S;
	wire [1:0] AUDIO_MIX;
	wire [3:0] ADC_BUS;
	wire SD_SCK;
	wire SD_MOSI;
	wire SD_MISO = 1'b0;
	wire SD_CS;
	wire SD_CD = 1'b0;
	wire DDRAM_CLK;
	wire DDRAM_BUSY = 1'b0;
	wire [7:0] DDRAM_BURSTCNT;
	wire [28:0] DDRAM_ADDR;
	wire [63:0] DDRAM_DOUT = 64'h0;
	wire DDRAM_DOUT_READY = 1'b0;
	wire DDRAM_RD;
	wire [63:0] DDRAM_DIN;
	wire [7:0] DDRAM_BE;
	wire DDRAM_WE;
	wire SDRAM_CLK;
	wire SDRAM_CKE;
	wire [12:0] SDRAM_A;
	wire [1:0] SDRAM_BA;
	wire [15:0] SDRAM_DQ;
	wire SDRAM_DQML;
	wire SDRAM_DQMH;
	wire SDRAM_nCS;
	wire SDRAM_nCAS;
	wire SDRAM_nRAS;
	wire SDRAM_nWE;
	wire UART_CTS = 1'b0;
	wire UART_RTS;
	wire UART_RXD = 1'b0;
	wire UART_TXD;
	wire UART_DTR;
	wire UART_DSR = 1'b0;
	wire [6:0] USER_IN = 7'h0;
	wire [6:0] USER_OUT;
	wire OSD_STATUS = 1'b0;

	emu emu_inst
	(
	.CLK_50M(CLK_50M),
	.RESET(RESET),
	.HPS_BUS(HPS_BUS),
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_DE(VGA_DE),
	.VGA_F1(VGA_F1),
	.VGA_SL(VGA_SL),
	.VGA_SCALER(VGA_SCALER),
	.VGA_DISABLE(VGA_DISABLE),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.HDMI_FREEZE(HDMI_FREEZE),
	.HDMI_BLACKOUT(HDMI_BLACKOUT),
	.HDMI_BOB_DEINT(HDMI_BOB_DEINT),
	.LED_USER(LED_USER),
	.LED_POWER(LED_POWER),
	.LED_DISK(LED_DISK),
	.BUTTONS(BUTTONS),
	.CLK_AUDIO(CLK_AUDIO),
	.AUDIO_L(AUDIO_L),
	.AUDIO_R(AUDIO_R),
	.AUDIO_S(AUDIO_S),
	.AUDIO_MIX(AUDIO_MIX),
	.ADC_BUS(ADC_BUS),
	.SD_SCK(SD_SCK),
	.SD_MOSI(SD_MOSI),
	.SD_MISO(SD_MISO),
	.SD_CS(SD_CS),
	.SD_CD(SD_CD),
	.DDRAM_CLK(DDRAM_CLK),
	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD(DDRAM_RD),
	.DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE),
	.DDRAM_WE(DDRAM_WE),
	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE),
	.SDRAM_A(SDRAM_A),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_DQ(SDRAM_DQ),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nWE(SDRAM_nWE),
	.UART_CTS(UART_CTS),
	.UART_RTS(UART_RTS),
	.UART_RXD(UART_RXD),
	.UART_TXD(UART_TXD),
	.UART_DTR(UART_DTR),
	.UART_DSR(UART_DSR),
	.USER_IN(USER_IN),
	.USER_OUT(USER_OUT),
	.OSD_STATUS(OSD_STATUS)
	);


	longint unsigned t = 0;
	integer seen = 0;

	always @(posedge clk) begin
		t = t + 1;
		if (t == 100) RESET = 0;

		if (seen == 0 && t > 3000000 && VGA_DE && (VGA_R | VGA_G | VGA_B) != 0) begin
			seen = 1;
			$display("[PASS t=%0d] video alive: R=%02h G=%02h B=%02h (DE=1)", t, VGA_R, VGA_G, VGA_B);
			$finish;
		end

		if (t == 30000000 && !seen) begin
			$display("[FAIL t=%0d] no video: DE=%b HS=%b VS=%b R=%02h G=%02h B=%02h",
			          t, VGA_DE, VGA_HS, VGA_VS, VGA_R, VGA_G, VGA_B);
			$finish;
		end
	end

	// debug probes
	wire [63:0] dbg_mflags   = emu_inst.mapper_flags;
	wire        dbg_downld   = emu_inst.downloading;
	wire        dbg_ldone    = emu_inst.loader_done;
	wire [9:0]  dbg_scan     = emu_inst.scanline;
	wire [5:0]  dbg_color    = emu_inst.color;
	wire [15:0] dbg_caddr    = emu_inst.cpu_addr;
	wire        dbg_romload  = emu_inst.rom_loaded;
	wire [3:0]  dbg_ldstate  = emu_inst.loader.state;
	wire [24:0] dbg_ldleft   = emu_inst.loader.bytes_left;
	wire        dbg_ldbusy   = emu_inst.loader.busy;
	wire        dbg_lderr    = emu_inst.loader.error;
	wire        dbg_drst     = emu_inst.download_reset;
	wire [7:0]  dbg_drcnt    = emu_inst.download_reset_cnt;
	wire        dbg_rstnes   = emu_inst.reset_nes;
	wire        dbg_ldreset  = emu_inst.loader_reset;
	wire [4:0]  dbg_divcpu   = emu_inst.nes.div_cpu;
	wire [4:0]  dbg_divcpun  = emu_inst.nes.div_cpu_n;
	wire [2:0]  dbg_divppu   = emu_inst.nes.div_ppu;
	wire        dbg_cpuce    = emu_inst.nes.cpu_ce;
	wire        dbg_ppuce    = emu_inst.nes.ppu_ce;
	wire        dbg_cms      = emu_inst.nes.cpumem_stall;
	wire        dbg_cps      = emu_inst.nes.cpu_ppu_stall;
	wire        dbg_reqwait  = emu_inst.nes.cpumem_wait;
	wire        dbg_cmembusy = emu_inst.cpu_busy;
	wire        dbg_realign  = emu_inst.nes.realign;
	wire        dbg_freeze   = emu_inst.nes.freeze_clocks;
	wire        dbg_holdrst  = emu_inst.nes.hold_reset;
	wire        dbg_bootvec  = emu_inst.nes.bootvector_flag;
	wire        dbg_creset   = emu_inst.nes.reset;
	wire        dbg_ss_svc   = emu_inst.sdram.servicing;
	wire [2:0]  dbg_ss_cnt   = emu_inst.sdram.svc_cnt;
	wire [2:0]  dbg_ss_ack   = emu_inst.sdram.acked;
	wire [2:0]  dbg_ss_req   = emu_inst.sdram.req;
	wire [2:0]  dbg_ss_new   = emu_inst.sdram.new_req;
	wire [1:0]  dbg_ss_ch    = emu_inst.sdram.svc_ch;
	wire        dbg_ch0rd    = emu_inst.sdram.ch0_rd;
	wire        dbg_ch1rd    = emu_inst.sdram.ch1_rd;
	wire        dbg_prgall   = emu_inst.nes.prg_allow;
	wire        dbg_prgrd    = emu_inst.nes.prg_read;

	always @(posedge clk) begin
		if (t % 1000000 == 0)
			$display("[t=%0d] dload=%b ldone=%b rom=%b mflags=%h scan=%0d color=%h cpu=%h | ldstate=%0d left=%0d ldbusy=%b lderr=%b drst=%b drcnt=%02h rstnes=%b ldreset=%b",
			          t, dbg_downld, dbg_ldone, dbg_romload, dbg_mflags, dbg_scan, dbg_color, dbg_caddr,
			          dbg_ldstate, dbg_ldleft, dbg_ldbusy, dbg_lderr, dbg_drst, dbg_drcnt, dbg_rstnes, dbg_ldreset);
		if (t >= 355000 && t <= 362000)
			$display("[fz t=%0d] div=%0d reqw=%b busy=%b reqw=%b cms=%b svc=%b cnt=%0d acked=%b new=%b ch1rd=%b",
			          t, dbg_divcpu, dbg_reqwait, dbg_cmembusy, dbg_reqwait, dbg_cms, dbg_ss_svc, dbg_ss_cnt, dbg_ss_ack, dbg_ss_new, dbg_ch1rd);
		if (t % 50000 == 0 && t > 350000)
			$display("[sd t=%0d] ch0rd=%b ch1rd=%b req=%b new=%b acked=%b svc=%b cnt=%0d ch=%0d prgall=%b prgrd=%b",
			          t, dbg_ch0rd, dbg_ch1rd, dbg_ss_req, dbg_ss_new, dbg_ss_ack, dbg_ss_svc, dbg_ss_cnt, dbg_ss_ch, dbg_prgall, dbg_prgrd);
		if (t % 100000 == 0 && t > 100000)
			$display("[ce t=%0d] div=%0d/%0d ppudiv=%0d cpu_ce=%b ppu_ce=%b cms=%b cps=%b reqw=%b busy=%b realign=%b freeze=%b holdrst=%b bootvec=%b cres=%b",
			          t, dbg_divcpu, dbg_divcpun, dbg_divppu, dbg_cpuce, dbg_ppuce, dbg_cms, dbg_cps,
			          dbg_reqwait, dbg_cmembusy, dbg_realign, dbg_freeze, dbg_holdrst, dbg_bootvec, dbg_creset);
	end

	initial begin
		#900000000;
		$display("[FAIL] global timeout");
		$finish;
	end
endmodule

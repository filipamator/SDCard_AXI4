-- AXI4-Lite to SD interface
-- version 1.0 (12/05/2018)
--
-- Changelog: 
-- 1.0 - initial version
--
--
-- Memory map:
--
-- address				function 			
-- 0x00000000			core status:	bit 0 - busy (high during init, r/w functions and when error)
--															bit 1 - read (high after starting read function)
--															bit 2 - write (high after starting write function)
--															bit 3 - erase 
--															bit 4 - error
--																
-- 
-- 0x00000004			cmd register: 0x01 - read, 					-/W
--															0x02 - write, 
--															0x03 - init card, 
--															0x04 - erase sector
--
-- 0x00000008			sector to read/write								R/W


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity axi_sdcard is
	generic (
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		C_S_AXI_ADDR_WIDTH	: integer	:= 10;
        FREQ_G          : natural       := 50_000;      -- Master clock frequency (kHz).
        INIT_SPI_FREQ_G : natural       := 400;         -- Slow SPI clock freq. during initialization (kHz).
        SPI_FREQ_G      : natural       := 25_000;      -- Operational SPI freq. to the SD card (kHz).
        SIMULATION      : boolean       := TRUE
	);
	port (

		-- AXI4-Lite bus

		S_AXI_ACLK	: in std_logic;
		S_AXI_ARESETN	: in std_logic;
		S_AXI_AWADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		S_AXI_AWPROT	: in std_logic_vector(2 downto 0);
		S_AXI_AWVALID	: in std_logic;
		S_AXI_AWREADY	: out std_logic;
		S_AXI_WDATA	: in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		S_AXI_WSTRB	: in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
		S_AXI_WVALID	: in std_logic;
		S_AXI_WREADY	: out std_logic;
		S_AXI_BRESP	: out std_logic_vector(1 downto 0);
		S_AXI_BVALID	: out std_logic;
		S_AXI_BREADY	: in std_logic;
		S_AXI_ARADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
		S_AXI_ARVALID	: in std_logic;
		S_AXI_ARREADY	: out std_logic;
		S_AXI_RDATA	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		S_AXI_RRESP	: out std_logic_vector(1 downto 0);
		S_AXI_RVALID	: out std_logic;
		S_AXI_RREADY	: in std_logic;


        sdcard_busy     : out std_logic;
        -- I/O to the card
        
        sdcard_cs       : out std_logic                     := '1';  -- Active-low chip-select.
        sdcard_sclk     : out std_logic                     := '0';  -- Serial clock to SD card.
        sdcard_mosi     : out std_logic                     := '1';  -- Serial data output to SD card.
        sdcard_miso     : in  std_logic                     := '0'  -- Serial data input from SD card.

	);
end axi_sdcard;

architecture rtl of axi_sdcard is

    component AXILite_SDCard_v2 is
        generic (
            C_S_AXI_DATA_WIDTH	: integer	:= 32;
            C_S_AXI_ADDR_WIDTH	: integer	:= 10 
        );
        port (
            -- AXI4-Lite bus
            S_AXI_ACLK	: in std_logic;
            S_AXI_ARESETN	: in std_logic;
            S_AXI_AWADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
            S_AXI_AWPROT	: in std_logic_vector(2 downto 0);
            S_AXI_AWVALID	: in std_logic;
            S_AXI_AWREADY	: out std_logic;
            S_AXI_WDATA	: in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
            S_AXI_WSTRB	: in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
            S_AXI_WVALID	: in std_logic;
            S_AXI_WREADY	: out std_logic;
            S_AXI_BRESP	: out std_logic_vector(1 downto 0);
            S_AXI_BVALID	: out std_logic;
            S_AXI_BREADY	: in std_logic;
            S_AXI_ARADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
            S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
            S_AXI_ARVALID	: in std_logic;
            S_AXI_ARREADY	: out std_logic;
            S_AXI_RDATA	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
            S_AXI_RRESP	: out std_logic_vector(1 downto 0);
            S_AXI_RVALID	: out std_logic;
            S_AXI_RREADY	: in std_logic;
            -- An interface to the SD Card controller
            rden_o		: out std_logic;
            wren_o		: out std_logic;
            addr_o		: out std_logic_vector(31 downto 0);
            data_i 		: in std_logic_vector(7 downto 0);
            data_o 		: out std_logic_vector(7 downto 0);
            busy_i		: in std_logic;
            hndShk_i	: in std_logic;
            hndShk_o	: out std_logic;
            errorstate_i: in std_logic;
            initsd_o    : out std_logic;
            continue_o: out  std_logic
        );
    end component AXILite_SDCard_v2;


    component SdCardCtrl is
        generic (
            FREQ_G          : natural       := 50_000;      -- Master clock frequency (kHz).
            INIT_SPI_FREQ_G : natural       := 400;         -- Slow SPI clock freq. during initialization (kHz).
            SPI_FREQ_G      : natural       := 25_000;      -- Operational SPI freq. to the SD card (kHz).
            BLOCK_SIZE_G    : natural       := 512 );           -- Number of bytes in an SD card block or sector.
        port (
            -- Host-side interface signals.
            clk_i      : in  std_logic;                             -- Master clock.
            reset_i    : in  std_logic                     := '1'; -- active-low, synchronous  reset.
            rd_i       : in  std_logic                     := '0';  -- active-high read block request.
            wr_i       : in  std_logic                     := '0';  -- active-high write block request.
            continue_i : in  std_logic                     := '0';  -- If true, inc address and continue R/W.
            addr_i     : in  std_logic_vector(31 downto 0) := x"00000000";  -- Block address.
            data_i     : in  std_logic_vector(7 downto 0)  := x"00";  -- Data to write to block.
            data_o     : out std_logic_vector(7 downto 0)  := x"00";  -- Data read from block.
            busy_o     : out std_logic;  -- High when controller is busy performing some operation.
            hndShk_i   : in  std_logic;  -- High when host has data to give or has taken data.
            hndShk_o   : out std_logic;  -- High when controller has taken data or has data to give.
            error_o    : out std_logic_vector(15 downto 0) := (others => '0');
            debug_o    : out std_logic_vector(7 downto 0);
            fsm_debug_o: out std_logic_vector(4 downto 0);
            sdtype_o     : out std_logic;
            errorstate_o : out std_logic;
            initsd_i    : in std_logic;
            -- I/O signals to the external SD card.
            cs_bo      : out std_logic                     := '1';  -- Active-low chip-select.
            sclk_o     : out std_logic                     := '0';  -- Serial clock to SD card.
            mosi_o     : out std_logic                     := '1';  -- Serial data output to SD card.
            miso_i     : in  std_logic                     := '0'  -- Serial data input from SD card.
        );
    end component SdCardCtrl;

    signal rden        : std_logic;
    signal wren        : std_logic;
    signal addr        : std_logic_vector(31 downto 0);
    signal data_in     : std_logic_vector(7 downto 0);
    signal data_out    : std_logic_vector(7 downto 0);
    signal busy        : std_logic;
    signal hndShk_to_sd    : std_logic;
    signal hndShk_from_sd  : std_logic;
    signal errorstate  : std_logic;
    signal initsd      : std_logic;
    signal continue    : std_logic;

    begin



    sim_false: IF SIMULATION = FALSE generate

        sdcard_busy <= busy;

        inst_AXILite_SDCard_v2 :AXILite_SDCard_v2
            generic map (
                C_S_AXI_DATA_WIDTH	=> C_S_AXI_DATA_WIDTH,
                C_S_AXI_ADDR_WIDTH  => C_S_AXI_ADDR_WIDTH
            )
            port map (
                -- AXI4-Lite bus
                S_AXI_ACLK	    => S_AXI_ACLK,
                S_AXI_ARESETN   => S_AXI_ARESETN,
                S_AXI_AWADDR    => S_AXI_AWADDR,
                S_AXI_AWPROT    => S_AXI_AWPROT,
                S_AXI_AWVALID   => S_AXI_AWVALID,
                S_AXI_AWREADY   => S_AXI_AWREADY,
                S_AXI_WDATA     => S_AXI_WDATA,
                S_AXI_WSTRB     => S_AXI_WSTRB,
                S_AXI_WVALID    => S_AXI_WVALID,
                S_AXI_WREADY    => S_AXI_WREADY,
                S_AXI_BRESP     => S_AXI_BRESP, 
                S_AXI_BVALID    => S_AXI_BVALID,
                S_AXI_BREADY    => S_AXI_BREADY,
                S_AXI_ARADDR    => S_AXI_ARADDR,
                S_AXI_ARPROT    => S_AXI_ARPROT,
                S_AXI_ARVALID   => S_AXI_ARVALID,
                S_AXI_ARREADY   => S_AXI_ARREADY,
                S_AXI_RDATA     => S_AXI_RDATA,
                S_AXI_RRESP     => S_AXI_RRESP,
                S_AXI_RVALID    => S_AXI_RVALID,
                S_AXI_RREADY    => S_AXI_RREADY,
                -- An interface to the SD Card controller
                rden_o		    => rden, -- out std_logic;
                wren_o	        => wren, -- out std_logic;
                addr_o		    => addr,  -- out std_logic_vector(31 downto 0);
                data_i 		    => data_in, -- in std_logic_vector(7 downto 0);
                data_o 		    => data_out, --  out std_logic_vector(7 downto 0);
                busy_i		    => busy, -- in std_logic;
                hndShk_i	    =>  hndShk_from_sd,   -- in std_logic;
                hndShk_o	    =>  hndShk_to_sd,  -- out std_logic;
                errorstate_i    =>  errorstate, -- in std_logic;
                initsd_o        =>  initsd,     -- out std_logic;
                continue_o      =>  continue    --out  std_logic
            );


        inst_SdCardCtrl : SdCardCtrl
            generic map (
                FREQ_G          => FREQ_G,      
                INIT_SPI_FREQ_G => INIT_SPI_FREQ_G, 
                SPI_FREQ_G      => SPI_FREQ_G,
                BLOCK_SIZE_G => 512 )    
            port map (
                -- Host-side interface signals.
                clk_i       => S_AXI_ACLK,
                reset_i     => S_AXI_ARESETN,
                rd_i        => rden,
                wr_i        => wren,
                continue_i  => continue,
                addr_i      => addr,
                data_i      => data_out,
                data_o      => data_in,
                busy_o      => busy,
                hndShk_i    => hndShk_to_sd,
                hndShk_o    => hndShk_from_sd,
                error_o     => open,
                debug_o     => open,
                fsm_debug_o => open,
                sdtype_o    => open,
                errorstate_o => errorstate,
                initsd_i    => initsd,  
                -- I/O signals to the external SD card.
                cs_bo       => sdcard_cs,    
                sclk_o      => sdcard_sclk,
                mosi_o      => sdcard_mosi,
                miso_i      => sdcard_miso
            );
    end generate sim_false;

end rtl;

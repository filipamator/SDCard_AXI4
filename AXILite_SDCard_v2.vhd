-- AXI4-Lite to SD interface
-- version 2.0 (30/05/2018)
--
-- Changelog: 
-- 1.0 - initial version
-- 2.0 - buffer in the BRAM 
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


entity AXILite_SDCard_v2 is
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
end AXILite_SDCard_v2;

architecture arch_imp of AXILite_SDCard_v2 is



COMPONENT blk_mem_gen_0
  PORT (
    clka : IN STD_LOGIC;
    ena : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(6 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    douta : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    clkb : IN STD_LOGIC;
    enb : IN STD_LOGIC;
    web : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    addrb : IN STD_LOGIC_VECTOR(6 DOWNTO 0);
    dinb : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
  );
END COMPONENT;

	-- AXI4LITE signals
	signal axi_awaddr	: std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
	signal axi_awready	: std_logic;
	signal axi_wready	: std_logic;
	signal axi_bresp	: std_logic_vector(1 downto 0);
	signal axi_bvalid	: std_logic;
	signal axi_araddr	: std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
	signal axi_arready	: std_logic;
	signal axi_rdata	: std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal axi_rresp	: std_logic_vector(1 downto 0);
	signal axi_rvalid	: std_logic;

	-- Example-specific design signals
	-- local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	-- ADDR_LSB is used for addressing 32/64 bit registers/memories
	-- ADDR_LSB = 2 for 32 bits (n downto 2)
	-- ADDR_LSB = 3 for 64 bits (n downto 3)
	constant ADDR_LSB  : integer := (C_S_AXI_DATA_WIDTH/32)+ 1;
	constant OPT_MEM_ADDR_BITS : integer := 1;
	------------------------------------------------
	---- Signals for user logic register space example
	--------------------------------------------------

	signal slv_reg_rden	: std_logic;
	signal slv_reg_wren	: std_logic;
	signal reg_data_out	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal aw_en	: std_logic;


	signal s_loc_addr :std_logic_vector(9 downto 0);

	-- buffer with sector to read/write
	type buff_t is array (0 to 511) of std_logic_vector(7 downto 0);
	--signal buff : buff_t;

	signal op_reg				: std_logic_vector(31 downto 0);
	signal status_reg		: std_logic_vector(31 downto 0);
	signal sector_addr	: std_logic_vector(31 downto 0);

	alias status_busy		: std_logic is status_reg(0);
	alias status_read		: std_logic is status_reg(1);
	alias status_write	: std_logic is status_reg(2);
	alias status_erase	: std_logic is status_reg(3);
	alias status_error	: std_logic is status_reg(4);

	signal op_write			: std_logic;
	signal op_read			: std_logic;
	signal op_erase			: std_logic;
	signal op_init			: std_logic;

	type state_t is (ST_IDLE, ST_READ, ST_WRITE, ST_INIT, ST_ERASE, ST_WAIT);
	signal state : state_t := ST_IDLE;
	signal nextstate : state_t := ST_IDLE;
	
	signal hndShk_r,hndShk_prev,hndShk_rr,hndShk_rrr : std_logic;

    -- commands 
	constant CMD_READ : std_logic_vector(31 downto 0) := x"00000001";
	constant CMD_WRITE : std_logic_vector(31 downto 0) := x"00000002";
	constant CMD_INIT : std_logic_vector(31 downto 0) := x"00000003";
	constant CMD_ERASE : std_logic_vector(31 downto 0) := x"00000004";

    -- register map
	constant STAT_REG 	: std_logic_vector(9 downto 0) := "0000000000";     -- 0x00
	constant CMD_REG 		: std_logic_vector(9 downto 0) := "0000000100"; -- 0x04
	constant SECTOR_REG : std_logic_vector(9 downto 0) := "0000001000";    -- 0x08
	constant TEST_REG  : std_logic_vector(9 downto 0) := "0000001100";     -- 0x0C
	
  -- signal ena			: STD_LOGIC;
  -- signal wea			: STD_LOGIC_VECTOR(3 DOWNTO 0);
  -- signal addra		: STD_LOGIC_VECTOR(6 DOWNTO 0);
  -- signal dina			: STD_LOGIC_VECTOR(31 DOWNTO 0);
  -- signal doutb		: STD_LOGIC_VECTOR(31 DOWNTO 0);
  -- signal addrb		: STD_LOGIC_VECTOR(6 DOWNTO 0);
  -- signal enb			: STD_LOGIC;


	-- BRAM memory
  signal  ena :  STD_LOGIC;
  signal  wea :  STD_LOGIC_VECTOR(3 DOWNTO 0);
  signal  addra :  STD_LOGIC_VECTOR(6 DOWNTO 0);
  signal  dina :  STD_LOGIC_VECTOR(31 DOWNTO 0);
  signal  douta :  STD_LOGIC_VECTOR(31 DOWNTO 0);
  signal  enb :  STD_LOGIC;
  signal  web :  STD_LOGIC_VECTOR(3 DOWNTO 0);
  signal  addrb :  STD_LOGIC_VECTOR(6 DOWNTO 0);
  signal  dinb :  STD_LOGIC_VECTOR(31 DOWNTO 0);
  signal  doutb :  STD_LOGIC_VECTOR(31 DOWNTO 0);


	signal byte_index	: integer range 0 to 511; 

	-- used for addressing into BRAM
	signal byte_addr_up : std_logic_vector(6 downto 0);
	signal byte_addr_down : std_logic_vector(1 downto 0);
	signal byte_addr 		: std_logic_vector(8 downto 0);

	signal data_ff_o 		: std_logic_vector(7 downto 0);


	signal douta_ready : std_logic := '0';
	signal doutb_ready : std_logic := '0';
	

begin



	-- I/O Connections assignments

	S_AXI_AWREADY	<= axi_awready;
	S_AXI_WREADY	<= axi_wready;
	S_AXI_BRESP	<= axi_bresp;
	S_AXI_BVALID	<= axi_bvalid;
	S_AXI_ARREADY	<= axi_arready;
	S_AXI_RDATA	<= axi_rdata;
	S_AXI_RRESP	<= axi_rresp;
	S_AXI_RVALID	<= axi_rvalid;


	status_busy <= busy_i;
	status_error <= errorstate_i;
	

	-- Implement axi_awready generation
	-- axi_awready is asserted for one S_AXI_ACLK clock cycle when both
	-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
	-- de-asserted when reset is low.
	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_awready <= '0';
	      aw_en <= '1';
	    else
	      if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' and aw_en = '1') then
	        -- slave is ready to accept write address when
	        -- there is a valid write address and write data
	        -- on the write address and data bus. This design 
	        -- expects no outstanding transactions. 
	        axi_awready <= '1';
	        elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then
	            aw_en <= '1';
	        	axi_awready <= '0';
	      else
	        axi_awready <= '0';
	      end if;
	    end if;
	  end if;
	end process;

	-- Implement axi_awaddr latching
	-- This process is used to latch the address when both 
	-- S_AXI_AWVALID and S_AXI_WVALID are valid. 
	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_awaddr <= (others => '0');
	    else
	      if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' and aw_en = '1') then
	        -- Write Address latching
	        axi_awaddr <= S_AXI_AWADDR;
	      end if;
	    end if;
	  end if;                   
	end process; 

	-- Implement axi_wready generation
	-- axi_wready is asserted for one S_AXI_ACLK clock cycle when both
	-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is 
	-- de-asserted when reset is low. 

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_wready <= '0';
	    else
	      if (axi_wready = '0' and S_AXI_WVALID = '1' and S_AXI_AWVALID = '1' and aw_en = '1') then
	          -- slave is ready to accept write data when 
	          -- there is a valid write address and write data
	          -- on the write address and data bus. This design 
	          -- expects no outstanding transactions.           
	          axi_wready <= '1';
	      else
	        axi_wready <= '0';
	      end if;
	    end if;
	  end if;
	end process; 

	-- Implement memory mapped register select and write logic generation
	-- The write data is accepted and written to memory mapped registers when
	-- axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
	-- select byte enables of slave registers while writing.
	-- These registers are cleared when reset (active low) is applied.
	-- Slave register write enable is asserted when valid address and data are available
	-- and the slave is ready to accept the write address and write data.
	slv_reg_wren <= axi_wready and S_AXI_WVALID and axi_awready and S_AXI_AWVALID ;

	--ena <= slv_reg_wren or slv_reg_rden;
  --wea(0) <= slv_reg_wren;

	process (S_AXI_ACLK)
		variable loc_addr :std_logic_vector(9 downto 0);
		variable byte_addr_up : std_logic_vector(6 downto 0);
		variable byte_addr_down : std_logic_vector(1 downto 0);
		variable byte_addr 		: std_logic_vector(8 downto 0);

	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
				op_write 	<= '0';
				op_read		<= '0';
				op_init 	<= '0';
				op_erase 	<= '0';
				byte_index <= 0;
				hndShk_r <= '0';
				ena <= '0';
				--enb <= '0';
				wea <= (others => '0');
				addra <= (others => '0');
				douta_ready <= '0';
	   		--addrb <= (others => '0');
		  else
					op_write 	<= '0';
					op_read		<= '0';
					op_init 	<= '0';
					op_erase 	<= '0';

					

					----- write from the bus ----------
					wea <= (others => '0');
					ena <= '0';
					if (slv_reg_wren = '1') then
						
						
						if (axi_awaddr(9)='0') then			-- write into control registers
							loc_addr := axi_awaddr(9 downto 2) & "00";
							case (loc_addr) is
								when "0000000000" =>		-- address 0x00: core status
									null;	-- READ ONLY
								when "0000000100" =>		-- address 0x04: operation to perform
									op_reg <= S_AXI_WDATA;
									case (S_AXI_WDATA) is
										when CMD_READ =>
											op_read <= '1';
										when CMD_WRITE =>
											op_write <= '1';
										when CMD_INIT =>
											op_init <= '1';
										when CMD_ERASE =>
											op_erase <= '1';
										when others =>
											null;										
									end case;
								when "0000001000" =>		-- address 0x08: sector to read/write
									sector_addr <= S_AXI_WDATA;
								when others =>
									null;							
							end case;
						else
							-- write into sector buffer
							loc_addr := "0" & axi_awaddr(8 downto 2) & "00";
							--buff(to_integer(unsigned(loc_addr))+3)	<= S_AXI_WDATA(31 downto 24);
							--buff(to_integer(unsigned(loc_addr))+2) 	<= S_AXI_WDATA(23 downto 16);
							--buff(to_integer(unsigned(loc_addr))+1) 	<= S_AXI_WDATA(15 downto 8);
							--buff(to_integer(unsigned(loc_addr)))	<= S_AXI_WDATA(7 downto 0);
							
							-- write into BRAM
							addra <= axi_awaddr(8 downto 2);
							dina <= S_AXI_WDATA;							-- little endian or big endian?
							wea <= (others => '1');
							ena <= '1';

							
							
						end if;
					end if;
					----- end write from the bus ----------

					hndShk_o <= hndShk_rr;	-- delay one clock cycle
					--hndShk_rrr <= hndShk_rr;
					hndShk_rr <= hndShk_r;
					hndShk_prev <= hndShk_i;
					--data_o <= data_ff_o;

					
					if (state=ST_READ) then									----- read data from SD CARD and store it in the buffer -----
						
						if (hndShk_prev='0' and hndShk_i='1') then
							
							--buff(byte_index) <= data_i;
							hndShk_r <= '1';
						
							-------------- BRAM ------------
							byte_addr := std_logic_vector(to_unsigned(byte_index, byte_addr'length));
							byte_addr_down := byte_addr(1 downto 0);
							byte_addr_up := byte_addr(8 downto 2);
							addra <= byte_addr(8 downto 2);
							ena <= '1';
							case byte_addr_down is
								when "00" =>
									wea <= "0001";
									dina <= x"000000" & data_i;
								when "01" =>
									wea <= "0010";
									dina <= x"0000" & data_i & x"00";
								when "10" =>
									wea <= "0100";
									dina <= x"00" & data_i & x"0000";
								when "11" =>
									wea <= "1000";
									dina <= data_i & x"000000";
								when others =>	
									wea <= (others => '0');
							end case;
							-------------- BRAM ------------

						
						elsif (hndShk_prev='1' and hndShk_i='0') then
							byte_index <= byte_index + 1;
							hndShk_r <= '0';
						end if;
					
					elsif (state=ST_WRITE)	then								------ write data form buffer to sdcard
						
						if (hndShk_prev='0' and hndShk_i='1') then
							
							-- data_o <= buff(byte_index);
							hndShk_r <= '1';
							
							-------------- BRAM ------------
							byte_addr := std_logic_vector(to_unsigned(byte_index, byte_addr'length));
							byte_addr_down := byte_addr(1 downto 0);
							byte_addr_up := byte_addr(8 downto 2);
							addra <= byte_addr(8 downto 2);
							ena <= '1';
							
							-------------- BRAM ------------
						
						elsif (hndShk_prev='1' and hndShk_i='0') then
							byte_index <= byte_index + 1;
							hndShk_r <= '0';
						end if;
			
						case byte_addr_down is
							when "00" =>
									data_o <= douta(7 DOWNTO 0);
							when "01" =>
									data_o <= douta(15 DOWNTO 8);
							when "10" =>
									data_o <= douta(23 DOWNTO 16);
							when "11" =>
									data_o <= douta(31 DOWNTO 24);
							when others =>	
									null;
						end case;


					else  
					
						byte_index <= 0;
					
					end if;

	    end if;
	  end if;                   
	end process; 






	-- Implement write response logic generation
	-- The write response and response valid signals are asserted by the slave 
	-- when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.  
	-- This marks the acceptance of address and indicates the status of 
	-- write transaction.

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_bvalid  <= '0';
	      axi_bresp   <= "00"; --need to work more on the responses
	    else
	      if (axi_awready = '1' and S_AXI_AWVALID = '1' and axi_wready = '1' and S_AXI_WVALID = '1' and axi_bvalid = '0'  ) then
	        axi_bvalid <= '1';
	        axi_bresp  <= "00"; 
	      elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then   --check if bready is asserted while bvalid is high)
	        axi_bvalid <= '0';                                 -- (there is a possibility that bready is always asserted high)
	      end if;
	    end if;
	  end if;                   
	end process; 

	-- Implement axi_arready generation
	-- axi_arready is asserted for one S_AXI_ACLK clock cycle when
	-- S_AXI_ARVALID is asserted. axi_awready is 
	-- de-asserted when reset (active low) is asserted. 
	-- The read address is also latched when S_AXI_ARVALID is 
	-- asserted. axi_araddr is reset to zero on reset assertion.

	
	addrb <= S_AXI_ARADDR(8 downto 2);
	enb <= '1';
	web <= (others=>'0');
	
	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_arready <= '0';
	      axi_araddr  <= (others => '1');
			else
	      if (axi_arready = '0' and S_AXI_ARVALID = '1') then
	        -- indicates that the slave has acceped the valid read address
					axi_arready <= '1';
	        -- Read Address latching 
	        axi_araddr  <= S_AXI_ARADDR;           
				else
					axi_arready <= '0';
	      end if;
	    end if;
	  end if;                   
	end process; 

	-- Implement axi_arvalid generation
	-- axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both 
	-- S_AXI_ARVALID and axi_arready are asserted. The slave registers 
	-- data are available on the axi_rdata bus at this instance. The 
	-- assertion of axi_rvalid marks the validity of read data on the 
	-- bus and axi_rresp indicates the status of read transaction.axi_rvalid 
	-- is deasserted on reset (active low). axi_rresp and axi_rdata are 
	-- cleared to zero on reset (active low).  
	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then
	    if S_AXI_ARESETN = '0' then
	      axi_rvalid <= '0';
	      axi_rresp  <= "00";
	    else
	      if (axi_arready = '1' and S_AXI_ARVALID = '1' and axi_rvalid = '0') then
	        -- Valid read data is available at the read data bus
	        axi_rvalid <= '1';
	        axi_rresp  <= "00"; -- 'OKAY' response
	      elsif (axi_rvalid = '1' and S_AXI_RREADY = '1') then
	        -- Read data is accepted by the master
	        axi_rvalid <= '0';
	      end if;            
	    end if;
	  end if;
	end process;

	-- Implement memory mapped register select and read logic generation
	-- Slave register read enable is asserted when valid address is available
	-- and the slave is ready to accept the read address.
	slv_reg_rden <= axi_arready and S_AXI_ARVALID and (not axi_rvalid) ;

	process (axi_araddr, S_AXI_ARESETN, slv_reg_rden)
	variable loc_addr :std_logic_vector(9 downto 0);
	begin 
		loc_addr := "0" & axi_araddr(8 downto 2) & "00";
		case loc_addr is
			
			when STAT_REG =>	
			-- when "0000000000" =>		-- address 0x00: core status
					reg_data_out  <= status_reg;
			
			when CMD_REG =>
			--when "0000000100" =>		-- address 0x04: operation to perform	
					reg_data_out  <= op_reg;
				
			when SECTOR_REG =>	
			--when "0000001000" =>		-- address 0x08: sector to read/write
					reg_data_out <= sector_addr;
				
			when "0000001100" =>         -- 0x0C : a test register 
				    reg_data_out <= x"00000055";
				
			when others =>
					reg_data_out  <= (others => '0');
		end case;
		
	end process; 




	-- Output register or memory read data
	process( S_AXI_ACLK ) is
	begin
	  if (rising_edge (S_AXI_ACLK)) then
	    if ( S_AXI_ARESETN = '0' ) then
	      axi_rdata  <= (others => '0');
	    else
	      if (slv_reg_rden = '1') then
	        -- When there is a valid read address (S_AXI_ARVALID) with 
	        -- acceptance of read address by the slave (axi_arready), 
	        -- output the read dada 
	        -- Read address mux

					if (axi_araddr(9)='1') then
						axi_rdata <= doutb;

					else 
	        	axi_rdata <= reg_data_out;     -- register read data
	      	end if;
				
				end if;   
	    end if;
	  end if;
	end process;


	-- Add user logic here

	process( S_AXI_ACLK ) is
		variable delay : integer;
	begin
	  if (rising_edge (S_AXI_ACLK)) then
	    if ( S_AXI_ARESETN = '0' ) then
				delay := 0;
				-- status_reg <= (others => '0');
				rden_o <= '0';
				wren_o <= '0';
				continue_o <= '0';
				initsd_o <= '0';
	    	state <= ST_IDLE;
			else
				case (state) is

					when ST_IDLE =>
						
						initsd_o <= '0';

						if (op_read='1') then
							
							status_read <= '1';
							addr_o <= sector_addr;
							rden_o <= '1';
							delay := 0;
							state <= ST_WAIT;
							nextstate <= ST_READ;

						elsif (op_write='1') then
							
							status_write <= '1';
							addr_o <= sector_addr;
							wren_o <= '1';
							delay := 0;
							state <= ST_WAIT;
						  nextstate <= ST_WRITE;
						
						elsif (op_init='1') then
							
							initsd_o <= '1';
							delay := 8;
							state <= ST_WAIT;
							nextstate <= ST_IDLE;

						elsif (op_erase='1') then
							status_erase <= '1';
							delay := 1023;
							state <= ST_ERASE;
						else
							status_read <= '0';
							status_write <= '0';
							status_erase <= '0';
							state <= ST_IDLE;
						end if;
					
					when ST_WAIT =>

						if (delay=0) then
							state <= nextstate;
						else 
							delay := delay - 1;
							state <= ST_WAIT;
						end if;
					
					when ST_READ =>
						
						rden_o <= '0';
						if (busy_i='1') then
							state <= ST_READ;
						else 
							state <= ST_IDLE;
						end if;

					when ST_WRITE =>

						wren_o <= '0';
						if (busy_i='1') then
							state <= ST_WRITE;
						else 
							state <= ST_IDLE;
						end if;

					when ST_ERASE =>
						if (delay = 0) then
							state <= ST_IDLE;
						else 
							delay := delay - 1;
						end if;
					when others =>
						state <= ST_IDLE;
				end case;
	    end if;
	  end if;
	end process;


-- sector_buff : blk_mem_gen_0
--   PORT MAP (
--     clka => S_AXI_ACLK,
--     ena => ena,					-- IN STD_LOGIC;
--     wea => wea,					-- IN STD_LOGIC_VECTOR(0 DOWNTO 0);
--     addra => addra,			-- IN STD_LOGIC_VECTOR(8 DOWNTO 0);
--     dina => dina,				-- IN STD_LOGIC_VECTOR(7 DOWNTO 0);
--     douta => douta			-- OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
--   );


inst_blk_mem_gen_0 : blk_mem_gen_0
  PORT MAP (
    clka => S_AXI_ACLK,
    ena => ena,
    wea => wea,
    addra => addra,
    dina => dina,
    douta => douta,
    clkb => S_AXI_ACLK,
    enb => enb,
    web => web,
    addrb => addrb,
    dinb => dinb,
    doutb => doutb
  );
	-- User logic ends

end arch_imp;

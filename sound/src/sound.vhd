--   __   __     __  __     __         __
--  /\ "-.\ \   /\ \/\ \   /\ \       /\ \
--  \ \ \-.  \  \ \ \_\ \  \ \ \____  \ \ \____
--   \ \_\\"\_\  \ \_____\  \ \_____\  \ \_____\
--    \/_/ \/_/   \/_____/   \/_____/   \/_____/
--   ______     ______       __     ______     ______     ______
--  /\  __ \   /\  == \     /\ \   /\  ___\   /\  ___\   /\__  _\
--  \ \ \/\ \  \ \  __<    _\_\ \  \ \  __\   \ \ \____  \/_/\ \/
--   \ \_____\  \ \_____\ /\_____\  \ \_____\  \ \_____\    \ \_\
--    \/_____/   \/_____/ \/_____/   \/_____/   \/_____/     \/_/
--
-- https://joshbassett.info
-- https://twitter.com/nullobject
-- https://github.com/nullobject
--
-- Copyright (c) 2020 Josh Bassett
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.common.all;

entity sound is
  port (
    reset : in std_logic;

    -- clock signals
    clk : in std_logic;
    cen : in std_logic;

    -- request
    req  : in std_logic;
    data : in byte_t;

    -- audio data
    audio : out audio_t
  );
end entity sound;

architecture arch of sound is
  -- CPU signals
  signal cpu_addr   : unsigned(CPU_ADDR_WIDTH-1 downto 0);
  signal cpu_din    : byte_t;
  signal cpu_dout   : byte_t;
  signal cpu_mreq_n : std_logic;
  signal cpu_rd_n   : std_logic;
  signal cpu_wr_n   : std_logic;
  signal cpu_rfsh_n : std_logic;
  signal cpu_nmi_n  : std_logic := '1';
  signal cpu_int_n  : std_logic := '1';

  -- chip select signals
  signal sound_rom_cs : std_logic;
  signal sound_ram_cs : std_logic;
  signal opl_cs       : std_logic;
  signal req_cs       : std_logic;
  signal req_off_cs   : std_logic;

  -- data signals
  signal sound_rom_data : byte_t;
  signal sound_ram_data : byte_t;
  signal opl_data       : byte_t;
  signal req_data       : byte_t;

  -- registers
  signal data_reg : byte_t;
begin
  cpu : entity work.T80s
  port map (
    RESET_n     => not reset,
    CLK         => clk,
    CEN         => cen,
    INT_n       => cpu_int_n,
    NMI_n       => cpu_nmi_n,
    MREQ_n      => cpu_mreq_n,
    IORQ_n      => open,
    RD_n        => cpu_rd_n,
    WR_n        => cpu_wr_n,
    RFSH_n      => cpu_rfsh_n,
    HALT_n      => open,
    BUSAK_n     => open,
    unsigned(A) => cpu_addr,
    DI          => cpu_din,
    DO          => cpu_dout
  );

  sound_rom : entity work.single_port_rom
  generic map (
    ADDR_WIDTH => SOUND_ROM_1_ADDR_WIDTH,
    INIT_FILE  => "rom/cpu_4h.mif"
  )
  port map (
    clk  => clk,
    cs   => sound_rom_cs,
    addr => cpu_addr(SOUND_ROM_1_ADDR_WIDTH-1 downto 0),
    dout => sound_rom_data
  );

  sound_ram : entity work.single_port_ram
  generic map (ADDR_WIDTH => SOUND_RAM_ADDR_WIDTH)
  port map (
    clk  => clk,
    cs   => sound_ram_cs,
    addr => cpu_addr(SOUND_RAM_ADDR_WIDTH-1 downto 0),
    din  => cpu_dout,
    dout => sound_ram_data,
    we   => not cpu_wr_n
  );

  opl : entity work.opl
  port map (
    reset  => reset,
    clk    => clk,
    irq_n  => cpu_int_n,
    cs     => opl_cs,
    addr   => ('0' & cpu_addr(0)),
    din    => cpu_dout,
    dout   => opl_data,
    we     => not cpu_wr_n,
    sample => audio
  );

  nmi : process (clk, reset)
  begin
    if reset = '1' then
      cpu_nmi_n <= '1';
    elsif rising_edge(clk) then
      if req_off_cs = '1' and cpu_wr_n = '0' then
        -- clear NMI
        cpu_nmi_n <= '1';
      elsif req = '1' then
        -- set NMI
        cpu_nmi_n <= '0';

        -- latch data
        data_reg <= data;
      end if;
    end if;
  end process;

  --  address    description
  -- ----------+-----------------
  -- 0000-3fff | sound ROM
  -- 4000-47ff | sound RAM
  -- 8000-8001 | OPL
  -- c000-c000 | request
  -- f000-f000 | request off
  sound_rom_cs <= '1' when cpu_addr >= x"0000" and cpu_addr <= x"3fff" and cpu_rfsh_n = '1' else '0';
  sound_ram_cs <= '1' when cpu_addr >= x"4000" and cpu_addr <= x"47ff" and cpu_rfsh_n = '1' else '0';
  opl_cs       <= '1' when cpu_addr >= x"8000" and cpu_addr <= x"8001" and cpu_rfsh_n = '1' else '0';
  req_cs       <= '1' when cpu_addr >= x"c000" and cpu_addr <= x"c000" and cpu_rfsh_n = '1' else '0';
  req_off_cs   <= '1' when cpu_addr >= x"f000" and cpu_addr <= x"f000" and cpu_rfsh_n = '1' else '0';

  -- set request data
  req_data <= data_reg when req_cs = '1' and cpu_rd_n = '0' else (others => '0');

  -- mux CPU data input
  cpu_din <= sound_rom_data or
             sound_ram_data or
             opl_data or
             req_data;
end architecture arch;

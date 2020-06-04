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

library pll;

use work.common.all;
use work.types.all;

entity top is
  port (
    -- 50MHz reference clock
    clk : in std_logic;

    key : in std_logic_vector(1 downto 0);

    -- VGA signals
    vga_r, vga_g, vga_b : out std_logic_vector(5 downto 0);
    vga_csync           : out std_logic
  );
end top;

architecture arch of top is
  -- clock signals
  signal sys_clk : std_logic;
  signal cen_6   : std_logic;

  -- RAM signals
  signal ram_addr : unsigned(RAM_ADDR_WIDTH-1 downto 0);
  signal ram_data : std_logic_vector(RAM_DATA_WIDTH-1 downto 0);

  -- ROM signals
  signal rom_addr : unsigned(ROM_ADDR_WIDTH-1 downto 0);
  signal rom_data : std_logic_vector(ROM_DATA_WIDTH-1 downto 0);

  -- video signals
  signal video : video_t;

  -- tilemap data
  signal tilemap_data : byte_t;

  -- pixel data
  signal pixel : pixel_t;
  signal pixel_reg : pixel_t;
begin
  -- generate a 12MHz clock signal
  my_pll : entity pll.pll
  port map (
    refclk   => clk,
    rst      => '0',
    outclk_0 => sys_clk,
    outclk_1 => open,
    locked   => open
  );

  -- generate a 6MHz clock enable signal
  clock_divider_6 : entity work.clock_divider
  generic map (DIVISOR => 8)
  port map (clk => sys_clk, cen => cen_6);

  tile_ram : entity work.single_port_rom
  generic map (
    ADDR_WIDTH => RAM_ADDR_WIDTH,
    DATA_WIDTH => RAM_DATA_WIDTH,
    INIT_FILE  => "rom/tiles.mif",

    -- XXX: for debugging
    ENABLE_RUNTIME_MOD => "YES"
  )
  port map (
    clk  => clk,
    addr => ram_addr,
    dout => ram_data
  );

  tile_rom : entity work.single_port_rom
  generic map (
    ADDR_WIDTH => ROM_ADDR_WIDTH,
    DATA_WIDTH => ROM_DATA_WIDTH,
    INIT_FILE  => "rom/cpu_8k.mif"
  )
  port map (
    clk  => clk,
    addr => rom_addr,
    dout => rom_data
  );

  -- video timing generator
  video_gen : entity work.video_gen
  port map (
    clk   => sys_clk,
    cen   => cen_6,
    video => video
  );

  -- tilemap layer
  char_layer : entity work.char_layer
  generic map (
    RAM_ADDR_WIDTH => RAM_ADDR_WIDTH,
    RAM_DATA_WIDTH => RAM_DATA_WIDTH,
    ROM_ADDR_WIDTH => ROM_ADDR_WIDTH,
    ROM_DATA_WIDTH => ROM_DATA_WIDTH
  )
  port map (
    config => DEFAULT_TILE_CONFIG,

    clk => sys_clk,
    cen => cen_6,

    ram_addr => ram_addr,
    ram_data => ram_data,
    rom_addr => rom_addr,
    rom_data => rom_data,

    video => video,
    flip  => not key(0),

    data => tilemap_data
  );

  -- latch pixel data
  latch_pixel_data : process (sys_clk)
  begin
    if rising_edge(sys_clk) then
      if cen_6 = '1' then
        pixel_reg <= pixel;
      end if;
    end if;
  end process;

  -- set the pixel data
  pixel <= tilemap_data(3 downto 0);

  vga_r <= "111111"                          when video.enable = '1' and ((video.pos.x(7 downto 0) = 0) or (video.pos.x(7 downto 0) = 255) or (video.pos.y(7 downto 0) = 16) or (video.pos.y(7 downto 0) = 239)) else
           pixel_reg & pixel_reg(3 downto 2) when video.enable = '1' else
           (others => '0');

  -- vga_r <= pixel_reg & pixel_reg(3 downto 2) when video.enable = '1' else (others => '0');
  vga_g <= pixel_reg & pixel_reg(3 downto 2) when video.enable = '1' else (others => '0');
  vga_b <= pixel_reg & pixel_reg(3 downto 2) when video.enable = '1' else (others => '0');

  -- composite sync
  vga_csync <= not (video.hsync xor video.vsync);
end arch;

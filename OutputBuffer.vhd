library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity OutputBuffer is
    generic (
        WIDTH : integer := 32;  -- Ancho (número de píxeles) de la línea de salida
        BITS  : integer := 18     -- Bits por píxel de salida
    );
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        write_en   : in  std_logic;
        data_in    : in  std_logic_vector(BITS-1 downto 0);
        buffer_out : out std_logic_vector((WIDTH*BITS)-1 downto 0);
		  data_valid   : out std_logic
    );
end entity;

architecture Behavioral of OutputBuffer is
    type mem_type is array (0 to WIDTH-1) of std_logic_vector(BITS-1 downto 0);
    signal buffer_mem : mem_type;
    signal idx        : integer range 0 to WIDTH-1 := 0;
	 signal valid        : std_logic := '0';

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                idx <= 0;
					 valid <= '0';
            else
                if write_en = '1' then
                    buffer_mem(idx) <= data_in;
                    if idx = WIDTH-1 then
                        idx <= 0;
								valid <= '1';
                    else
                        idx <= idx + 1;
								valid <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
	 
	 data_valid <= valid;
--    -- Empaquetar toda la línea de salida como vector
--    buffer_out <= buffer_mem(0) & buffer_mem(1) & 
--                  -- … hasta
--                  buffer_mem(WIDTH-1);

    -- Empaquetar la salida de forma genérica
    process(buffer_mem)
        variable temp : std_logic_vector((WIDTH*BITS)-1 downto 0);
    begin
        for i in 0 to WIDTH-1 loop
		      --Esta linea invierte el orden de los pixeles ya que los toma del mas significativo al menos
            --temp(((WIDTH-1 - i)*BITS) + BITS - 1 downto (WIDTH-1 - i)*BITS) := buffer_mem(i);
				  temp((i*BITS) + BITS - 1 downto i*BITS) := buffer_mem(i);

        end loop;
        buffer_out <= temp;
    end process;

end architecture;

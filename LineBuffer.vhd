library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity LineBuffer is
    generic (
        WIDTH : integer := 32;  -- Ancho de la imagen en píxeles
        BITS  : integer := 9      -- Bits por píxel
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        pixel_in  : in  std_logic_vector(BITS-1 downto 0);
        write_en  : in  std_logic; -- Señal que indica cuándo almacenar pixel_in
        line_out  : out std_logic_vector((WIDTH*BITS)-1 downto 0)
    );
end entity;

architecture Behavioral of LineBuffer is

    -- Memoria interna para almacenar una línea completa
    type ram_type is array (0 to WIDTH-1) of std_logic_vector(BITS-1 downto 0);
    signal line_mem : ram_type;
    signal idx      : integer range 0 to WIDTH-1 := 0;

    -- Función para empaquetar el arreglo en un solo vector
    function pack_line(mem: ram_type) return std_logic_vector is
        variable result : std_logic_vector((WIDTH*BITS)-1 downto 0);
    begin
        for i in 0 to WIDTH-1 loop
            result(((i+1)*BITS)-1 downto i*BITS) := mem(i);
        end loop;
        return result;
    end function;

begin

    -- Escritura en la memoria de línea
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                idx <= 0;
            else
                if write_en = '1' then
                    line_mem(idx) <= pixel_in;
                    if idx = WIDTH-1 then
                        idx <= 0;
                    else
                        idx <= idx + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Asignación de salida empaquetada
    line_out <= pack_line(line_mem);

end architecture;

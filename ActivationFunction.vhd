library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity ActivationFunction is
    generic (
			OUTW: integer := 18;
			F_MAX: integer := 5
			);
    port (
        clk: in std_logic;
        reset: in std_logic;
        type_sel: in integer range 0 to 1;  -- 0: none, 1: ReLU
        effective_F: in integer;
        data_in: in std_logic_vector((F_MAX*OUTW)-1 downto 0);
        data_out: out std_logic_vector((F_MAX*OUTW)-1 downto 0)
    );
end entity;

architecture Behavioral of ActivationFunction is
    type pixel_array is array (0 to F_MAX-1) of signed(OUTW-1 downto 0);
begin
    process(clk)
        variable in_pixels : pixel_array;
        variable out_pixels : pixel_array;
    begin
        if rising_edge(clk) then
            -- Unpack data_in
            for f in 0 to F_MAX-1 loop
                in_pixels(f) := signed(data_in((f+1)*OUTW-1 downto f*OUTW));
            end loop;
            
            if type_sel = 1 then  -- ReLU
                for f in 0 to F_MAX-1 loop
                    if f < effective_F then
                        if in_pixels(f) < 0 then
                            out_pixels(f) := (others => '0');
                        else
                            out_pixels(f) := in_pixels(f);
                        end if;
                    else
                        out_pixels(f) := (others => '0');
                    end if;
                end loop;
            else
                for f in 0 to F_MAX-1 loop
                    if f < effective_F then
                        out_pixels(f) := in_pixels(f);
                    else
                        out_pixels(f) := (others => '0');
                    end if;
                end loop;
            end if;
            
            -- Pack to data_out
            for f in 0 to F_MAX-1 loop
                data_out((f+1)*OUTW-1 downto f*OUTW) <= std_logic_vector(out_pixels(f));
            end loop;
        end if;
    end process;
end architecture;
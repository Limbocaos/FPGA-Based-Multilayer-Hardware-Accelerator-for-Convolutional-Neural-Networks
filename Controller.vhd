library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Controller is
	generic (
        WIDTH  : integer := 32;  -- Image width
        HEIGHT : integer := 32;  -- Image height
        K_MAX  : integer := 5     -- Maximum kernel size
    );
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        start      : in  std_logic;
		  effective_K: in  integer range 1 to K_MAX;  -- Effective kernel size
        stride     : in  integer range 1 to 4;  -- Stride configurable (mínimo 1)
        padding    : in  integer range 0 to 2;  -- Padding en píxeles
        -- Señales de control para los módulos
        lb_we      : out std_logic;  -- Write enable LineBuffer
        wr_update  : out std_logic;  -- Update WindowRegister
        conv_start : out std_logic;  -- Iniciar ConvolutionBlock
        conv_done  : in  std_logic;  -- Fin de ConvolutionBlock
        ob_we      : out std_logic;  -- Write enable OutputBuffer
        finished   : out std_logic   -- Señal global de fin
    );
end entity;

architecture Behavioral of Controller is

    type state_type is (IDLE, LOAD_INITIAL, LOAD_PIX, SHIFT_WINDOW, COMPUTE_CONV, WRITE_OUT, DONE);
    signal state    : state_type := IDLE;
	 signal pixel_ct : integer range -2 to WIDTH + 1 := -2;
	 signal line_ct  : integer range -2 to HEIGHT + 1 := -2;
    signal line_loaded : integer range 0 to K_MAX-1 := 0;  -- Contador de líneas iniciales cargadas

begin

    process(clk)
	 variable effective_P : integer;  -- For dynamic calculations
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state      <= IDLE;
                lb_we      <= '0';
                wr_update  <= '0';
                conv_start <= '0';
                ob_we      <= '0';
                finished   <= '0';
                pixel_ct   <= -padding;
                line_ct    <= -padding;
                line_loaded <= 0;
            else
					effective_P := effective_K - 1;  -- For initial loads
                case state is
                    when IDLE =>
                        if start = '1' then
                            state <= LOAD_INITIAL;
                        end if;

                    -- Cargar las primeras (K-1) líneas considerando padding
							when LOAD_INITIAL =>
								 lb_we <= '1';
								 if pixel_ct < WIDTH + padding - 1 then
									  pixel_ct <= pixel_ct + 1;
								 else
									  pixel_ct <= -padding;
									  line_ct <= line_ct + 1;
									  if line_loaded < effective_P then
											line_loaded <= line_loaded + 1;
									  else
											state <= LOAD_PIX;
									  end if;
								 end if;

                    when LOAD_PIX =>
                        lb_we <= '1';
                        if pixel_ct < WIDTH + padding - 1 then
                            pixel_ct <= pixel_ct + 1;
                        else
                            pixel_ct <= -padding;
                            line_ct <= line_ct + 1;
                            state <= SHIFT_WINDOW;
                        end if;

                    when SHIFT_WINDOW =>
                        lb_we     <= '0';
                        wr_update <= '1';  -- Actualizar WindowRegister
                        state     <= COMPUTE_CONV;

                    when COMPUTE_CONV =>
                        wr_update  <= '0';
                        conv_start <= '1';
                        if conv_done = '1' then
                            conv_start <= '0';
                            state      <= WRITE_OUT;
                        end if;

                    when WRITE_OUT =>
                        ob_we <= '1';
                        -- Escribir resultado y avanzar según stride
                        ob_we <= '0';
                        if pixel_ct + stride <= WIDTH + padding - effective_K then
                            pixel_ct <= pixel_ct + stride;
                            state <= SHIFT_WINDOW;
                        elsif line_ct + stride <= HEIGHT + padding - effective_K then
                            pixel_ct <= -padding;
                            line_ct <= line_ct + stride;
                            state <= LOAD_PIX;
                        else
                            state <= DONE;
                        end if;

                    when DONE =>
                        finished <= '1';
                        state    <= IDLE;
                        pixel_ct <= -padding;
                        line_ct  <= -padding;
                        line_loaded <= 0;
                end case;
            end if;
        end if;
    end process;

end architecture;
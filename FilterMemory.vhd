library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity FilterMemory is
    generic (
        F_MAX    : integer := 5;  -- Número de filtros varibles 
        K_MAX    : integer := 5;   -- Tamaño del kernel KxK corresponde a todos los demas 
        BITS : integer := 9    -- Bits por coeficiente
    );
    port (
	     clk          : in  std_logic;
        load_en      : in  std_logic;  -- Señal para cargar coeficientes
        effective_F  : in  integer range 1 to F_MAX;
        effective_K  : in  integer range 1 to K_MAX;
        coeffs_load  : in  std_logic_vector((F_MAX*K_MAX*K_MAX*BITS)-1 downto 0);  -- Input para carga
        coeffs_out   : out std_logic_vector((F_MAX*K_MAX*K_MAX*BITS)-1 downto 0)
    );
end entity;

architecture Behavioral of FilterMemory is
    -- Cada filtro contiene K*K coeficientes de BITS bits
    type filter_array is array (0 to F_MAX-1) of std_logic_vector((K_MAX*K_MAX*BITS)-1 downto 0);
	 signal mem : filter_array := (others => (others => '0'));
    -- Memoria de filtros Manuales
--    signal mem : filter_array := (
--		0 => 
--			"111111111" & "000000000" & "000000001" &
--			"111111110" & "000000000" & "000000010" &
--			"111111111" & "000000000" & "000000001",
			 
			 ---------------------------------------------
--			 Filtro Promediador
--				1 1 1
--				1 1 1
--				1 1 1
--			 Este filtro hace un suavizado promedio simple
			 ---------------------------------------------
--    1  =>
--			"000000001" & "000000001" & "000000001" &
--			"000000001" & "000000001" & "000000001" &
--			"000000001" & "000000001" & "000000001"
			 
			 
			 ---------------------------------------------
--			 Filtro Detecta Bordes (Sobel horizontal)
--			 -1  0  1
--			 -2  0  2
--			 -1  0  1
--			 Muy usado para detectar bordes horizontales en imágenes(Usa complemento a 2)
			 ---------------------------------------------
--    2  =>
--			"111111111" & "000000000" & "000000001" &
--			"111111110" & "000000000" & "000000010" &
--			"111111111" & "000000000" & "000000001"


			 ---------------------------------------------
--			 Filtro Sharpen (Afilado)
--				 0 -1  0
--				-1  5 -1
--				 0 -1  0
--			 Realza bordes y detalles.
			 ---------------------------------------------
--    3  =>
--			"000000000" & "111111111" & "000000000" &
--			"111111111" & "000000101" & "111111111" &
--			"000000000" & "111111111" & "000000000"


			 ---------------------------------------------
--			 Filtro de Paso Alto
--				-1 -1 -1
--				-1  8 -1
--				-1 -1 -1
--			 Elimina componentes de baja frecuencia (suavizados), resalta bordes.
			 ---------------------------------------------
--    4  =>
--			"111111111" & "111111111" & "111111111" &
--			"111111111" & "000001000" & "111111111" &
--			"111111111" & "111111111" & "111111111"


			 ---------------------------------------------
--			 Filtro Gaussiano Aproximado (suavizado más suave que promedio simple)
--				1 2 1
--				2 4 2
--				1 2 1
			 ---------------------------------------------
--    5  =>
--			"000000001" & "000000010" & "000000001" &
--			"000000010" & "000000100" & "000000010" &
--			"000000001" & "000000010" & "000000001"

--
--        1  => (others => '1'),
--        2  => (others => '1'),
--        3  => (others => '1'),
--        4  => (others => '1'),
--        5 => (others => '1'),
--
--
--
--        6  => (others => '1'),
--        7  => (others => '1'),
--        8  => (others => '1'),
--        9  => (others => '1'),
--        10 => (others => '1'),
--        11 => (others => '1'),
--        12 => (others => '1'),
--        13 => (others => '1'),
--        14 => (others => '1'),
--        15 => (others => '1')
--    );
begin
 process(clk)
		  variable P_eff : integer := 0;
        --variable concat_filters : std_logic_vector((F*K*K*BITS)-1 downto 0);
    begin
			if rising_edge(clk) then
            P_eff := effective_K * effective_K;  -- Siempre calcular aquí
            if load_en = '1' then
                -- Cargar desde coeffs_load, usando effective sizes
                for f in 0 to F_MAX-1 loop
                    if f < effective_F then
                        for p in 0 to (K_MAX*K_MAX -1) loop
                            if p < P_eff then
                                mem(f)(((p+1)*BITS)-1 downto p*BITS) <= coeffs_load(((f * P_eff + p + 1)*BITS)-1 downto (f * P_eff + p)*BITS);
                            else
                                mem(f)(((p+1)*BITS)-1 downto p*BITS) <= (others => '0');
                            end if;
                        end loop;
                    else
                        mem(f) <= (others => '0');
                    end if;
                end loop;
            end if;
            -- Salida: Concatenar mem hasta effective_F
            for i in 0 to F_MAX-1 loop
                if i < effective_F then
                    for p in 0 to (K_MAX*K_MAX -1) loop
                        if p < P_eff then
                            coeffs_out(((i * P_eff + p + 1)*BITS)-1 downto (i * P_eff + p)*BITS) <= mem(i)(((p+1)*BITS)-1 downto p*BITS);
                        else
                            coeffs_out(((i * P_eff + p + 1)*BITS)-1 downto (i * P_eff + p)*BITS) <= (others => '0');
                        end if;
                    end loop;
                else
                    for p in 0 to (K_MAX*K_MAX -1) loop
                        coeffs_out(((i * P_eff + p + 1)*BITS)-1 downto (i * P_eff + p)*BITS) <= (others => '0');
                    end loop;
                end if;
            end loop;
        end if;
    end process;

	 
	 --Si quieres usar valores reales en vez de ceros, puedes cargar mem(i) con vectores que representen tus filtros, por ejemplo:
	 
	 
--				 mem : filter_array := (
--					 0 => x"01_02_03_04_05_06_07_08_09", -- Filtro 0: 9 coeficientes de 8 bits
--					 1 => x"FF_FE_FD_FC_FB_FA_F9_F8_F7", -- Filtro 1
--					 ...
--					 15 => (others => '0')
--					);
	
	 	 
	 
	 
	 
	 
	 
	 
end architecture;
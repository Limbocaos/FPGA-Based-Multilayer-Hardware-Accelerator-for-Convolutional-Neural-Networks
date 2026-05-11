--convolutionblock
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ConvolutionBlock is
    generic (
		  K_MAX  : integer := 5;    -- Máximo tamaño del kernel
        F_MAX  : integer := 5;   -- Máximo número de filtros
        P_MAX  : integer := 25;   -- Max operaciones por filtro (K_MAX*K_MAX)
        BITS   : integer := 9;    -- Bits por píxel
        COEFFW : integer := 9;    -- Bits por coeficiente
        OUTW   : integer := 18     -- Bits de salida por píxel convolucionado
    );
    port (
        clk         : in  std_logic;
        reset       : in  std_logic;
		  ----------------------------------
		--Señales para multicapa
		  ----------------------------------
		  effective_K   : in  integer range 1 to K_MAX;  -- Tamaño efectivo
        effective_F   : in  integer range 1 to F_MAX;  -- Filtros efectivos
        window_in     : in  std_logic_vector((K_MAX*K_MAX*BITS)-1 downto 0);  -- Max size
        coeffs_in     : in  std_logic_vector((F_MAX*K_MAX*K_MAX*COEFFW)-1 downto 0);  -- Max size
		  
        --window_in   : in  std_logic_vector((K*K*BITS)-1 downto 0);      --Coeficientes de la ventana en un solo vector
        --coeffs_in   : in  std_logic_vector((F*K*K*COEFFW)-1 downto 0);  --Coeficientes de todos los filtros en un solo vector
        start       : in  std_logic;
        done        : out std_logic;
        --pixel_out   : out std_logic_vector((F*OUTW)-1 downto 0)		  --Vector de (F*OUTW) bits con los resultados de la convolución para cada filtro.
		  pixel_out     : out std_logic_vector((F_MAX*OUTW)-1 downto 0)  -- Max size
	 );
end entity;

architecture Behavioral of ConvolutionBlock is

   -- constant P : integer := K * K;

    -- Tipos Aqui se cambio los k f y p por P_MAX F_MAX
    type pixel_array is array (0 to P_MAX-1) of signed(BITS-1 downto 0);
    type coeff_array is array (0 to P_MAX-1) of signed(COEFFW-1 downto 0);
    type product_array is array (0 to P_MAX-1) of signed(COEFFW + BITS - 1 downto 0);

    type filter_coeff_array is array (0 to F_MAX-1) of coeff_array;
    type filter_product_array is array (0 to F_MAX-1) of product_array;
    type filter_sums_array is array (0 to F_MAX-1) of signed(OUTW-1 downto 0);

    -- Señales internas
    signal pixels      : pixel_array;
    signal coeffs      : filter_coeff_array;                               --Arreglo multidimensional de coeficientes por filtro (F filtros, cada uno con K*K coeficientes).
    signal products    : filter_product_array;										--Arreglo de productos (resultados de multiplicaciones) por filtro.
    signal sums        : filter_sums_array;											--Arreglo de sumas finales por filtro.
    signal result_out  : std_logic_vector((F_MAX*OUTW)-1 downto 0);		--Aqui duda entre F_MAX y effective_F		

		function ceil_log2(n : integer) return integer is
			 variable temp : integer := n;
			 variable log : integer := 0;
		begin
			 if n <= 1 then return 0; end if;
			 while temp > 1 loop
				  temp := temp / 2;
				  log := log + 1;
			 end loop;
			 if (2**log < n) then
				  return log + 1;
			 else
				  return log;
			 end if;
		end function;
	 
begin



    -------------------------------------------------------------------
    -- Proceso de extracción de píxeles y coeficientes
    -------------------------------------------------------------------
	 
	 --Los píxeles se extraen en un bucle concurrente y se almacenan 
	 
	 --Los coeficientes se organizan por filtro en el arreglo coeffs(f)(i), donde f es el índice del filtro e i el índice del coeficiente dentro del filtro.
	 -- En extract_proc: Se sustituye K por effective_K para loops
  extract_proc: process(window_in, coeffs_in, effective_K, effective_F) 
	 variable P_eff : integer;
    begin
        P_eff := effective_K * effective_K;
        -- Extraer pixeles
        for i in 0 to P_MAX-1 loop
            if i < P_eff then
                pixels(i) <= signed(window_in((i+1)*BITS-1 downto i*BITS));
            else
                pixels(i) <= (others => '0');
            end if;
        end loop;

        -- Extraer coeficientes por filtro
        for f in 0 to F_MAX-1 loop
            for i in 0 to P_MAX-1 loop
                if (f < effective_F and i < P_eff) then
                    coeffs(f)(i) <= signed(coeffs_in( ((f*P_MAX + i +1)*COEFFW -1) downto (f*P_MAX + i)*COEFFW ));
                else
                    coeffs(f)(i) <= (others => '0');
                end if;
            end loop;
        end loop;
    end process;
    -------------------------------------------------------------------
    -- Proceso de multiplicación
    -------------------------------------------------------------------
	 
	 --P = K*K es el número de elementos en el kernel.
	 	 
	 --Paralelismo:
			--Por Filtros: Las multiplicaciones para los F filtros se realizan en paralelo, ya que el bucle externo (f) no tiene dependencias entre iteraciones.
			--Por Operaciones: Dentro de cada filtro, las K*K multiplicaciones se realizan simultáneamente en el bucle interno (i), sin dependencias entre ellas.
	 
	 
	mult_proc: process(clk)
	 variable P_eff : integer; --El mismo cambio aqui
    begin
        if rising_edge(clk) then
            if reset = '1' then
                for f in 0 to F_MAX-1 loop
                    for i in 0 to P_MAX-1 loop
                        products(f)(i) <= (others => '0');
                    end loop;
                end loop;
            elsif start = '1' then
					P_eff := effective_K * effective_K; --Aqui tambien se cambiaria a P variable
                for f in 0 to F_MAX-1 loop
                    for i in 0 to P_MAX-1 loop
                        if f < effective_F and i < P_eff then
                            products(f)(i) <= pixels(i) * coeffs(f)(i);
                        else
                            products(f)(i) <= (others => '0');
                        end if;
                    end loop;
                end loop;
            end if;
        end if;
    end process;

    -------------------------------------------------------------------
    -- Proceso de suma (acumulación por filtro)
    -------------------------------------------------------------------
	 
	 
	 --Paralelismo:
		--	Por Filtros: Las sumas para los F filtros se realizan en paralelo, ya que el bucle externo (f) es independiente entre filtros.
		--	Por Operaciones: Dentro de cada filtro, la suma es secuencial debido al bucle interno (i). temp_sum se actualiza iterativamente, lo que implica que cada adición depende del resultado de la anterior.
	 
	 

-------------------------------------------------------------------------------------------	 
-- Proceso de suma con Árbol de Sumadores (paralelismo logarítmico por operaciones)
-------------------------------------------------------------------------------------------
    sum_proc: process(clk)
        variable P_eff : integer;
        -- Para árbol: Niveles log(P_eff), suma pares en paralelo
        type sum_level is array (0 to F_MAX-1, 0 to P_MAX-1) of signed(OUTW-1 downto 0);  -- Niveles intermedios
        variable levels : sum_level;
        constant MAX_LEVELS : integer := ceil_log2(P_MAX);
        variable current_size : integer;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                for f in 0 to F_MAX-1 loop
                    sums(f) <= (others => '0');
                end loop;
                done <= '0';
            elsif start = '1' then
                P_eff := effective_K * effective_K;
                --num_levels := integer(ceil(log2(real(P_eff))));  -- Niveles del árbol
					 --num_levels := ceil_log2(P_eff);
	
                for f in 0 to F_MAX-1 loop
						if f < effective_F then
                    -- Nivel 0: Resize products a OUTW
                    for i in 0 to P_MAX-1 loop
                        levels(f, i) := resize(products(f)(i), OUTW);
                    end loop;

                    -- Construir árbol: Suma pares en niveles paralelos
							current_size := P_eff;
                        for lvl in 1 to MAX_LEVELS loop
                            if current_size > 1 then
                                for i in 0 to (P_MAX/2)-1 loop
                                    if i < (current_size/2) then
                                        levels(f, i) := levels(f, 2*i) + levels(f, 2*i + 1);
                                    end if;
                                end loop;
                                if current_size mod 2 = 1 then
                                    if (current_size/2) < P_MAX then
                                        levels(f, current_size/2) := levels(f, current_size-1);
                                    end if;
                                end if;
                                current_size := (current_size + 1) / 2;  -- Reduce tamaño
                            end if;
                        end loop;

                    sums(f) <= levels(f, 0);  -- Resultado final en raíz del árbol
                 else
						  sums(f) <= (others => '0');
					  end if;  
					 end loop;
                done <= '1';
            else
                done <= '0';
            end if;
        end if;
    end process;
	 
	 
	 

    -------------------------------------------------------------------
    -- Proceso de empaquetado de salidas
    -------------------------------------------------------------------
	 -- Para output_proc: Solo empaqueta hasta effective_F
		 
		 
    output_proc: process(sums,effective_F)
    begin
        for f in 0 to F_MAX-1 loop
		   if f< effective_F then
            result_out((f+1)*OUTW -1 downto f*OUTW) <= std_logic_vector(sums(f));
         else
			   result_out((f+1)*OUTW -1 downto f*OUTW) <= (others => '0');
         end if;
		  end loop;

		  
        pixel_out <= result_out;
    end process;

end architecture;
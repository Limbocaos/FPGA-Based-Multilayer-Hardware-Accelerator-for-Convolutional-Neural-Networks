library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity WindowRegister is
    generic (
        K_MAX    : integer := 5;  -- Tamaño del kernel (KxK) 
        BITS : integer := 9   -- Bits por píxel generico
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
		  effective_K : in  integer range 1 to K_MAX;  -- Tamaño efectivo del kernel
		  update_en : in  std_logic;  -- Nuevo: Habilitar shift solo cuando sea válido correccion de warning
        -- Recibe K nuevos píxeles cada ciclo (una nueva columna de la ventana)
        data_in   : in  std_logic_vector((K_MAX*BITS)-1 downto 0);
        -- Salida: toda la ventana de K*K píxeles, en orden fila por fila
        window    : out std_logic_vector((K_MAX*K_MAX*BITS)-1 downto 0)
    );
end entity;

architecture Behavioral of WindowRegister is
    -- Creamos una matriz de registros para la ventana
    type reg_array is array (0 to K_MAX-1, 0 to K_MAX-1) of std_logic_vector(BITS-1 downto 0); --De igual forma crea un arreglo de vectores de longitud BITS-1
    signal regs : reg_array := (others => (others => (others => '0'))); --Crea los registros en cero para guardas los datos posteriormente
	 -- Declarar tipo del arreglo antes del process
	 type pixel_array_t is array (0 to K_MAX-1) of std_logic_vector(BITS-1 downto 0);

begin

    process(clk)
         variable pixel_col : pixel_array_t;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                -- Reiniciar todos los registros a 0
                for i in 0 to K_MAX-1 loop
                    for j in 0 to K_MAX-1 loop
                        regs(i, j) <= (others => '0');
                    end loop;
                end loop;
            elsif update_en = '1' then  -- Wrap shift logic en update_en (Fix 2 Option A)
                -- Separar data_in en K píxeles verticales
                for i in 0 to K_MAX-1 loop
					 if i < effective_K then  
                    pixel_col(i) := data_in((i+1)*BITS-1 downto i*BITS);
						else
							pixel_col(i) := (others => '0');
						end if;	
                end loop;

					 -- Hacer shift de cada fila hacia abajo
                for row in K_MAX-1 downto 1 loop
                    for col in 0 to K_MAX-1 loop
                        if row < effective_K and col < effective_K then
                            regs(row, col) <= regs(row-1, col);
                        end if;
                    end loop;
                end loop;
                -- Cargar nueva columna en la fila 0
					for col in 0 to K_MAX-1 loop
                    if col < effective_K then
                        regs(0, col) <= pixel_col(col);
                    else
                        regs(0, col) <= (others => '0');
                    end if;
                end loop;
					 
				    -- Rellenar partes no usadas (si effective_K < K_MAX) con ceros
                if effective_K < K_MAX then
                    for row in 0 to K_MAX-1 loop
                        if row >= effective_K then
                            for col in 0 to K_MAX-1 loop
                                regs(row, col) <= (others => '0');
                            end loop;
                        end if;
                    end loop;
                    for col in 0 to K_MAX-1 loop
                        if col >= effective_K then
                            for row in 0 to K_MAX-1 loop
                                if row < effective_K then
                                    regs(row, col) <= (others => '0');
                                end if;
                            end loop;
                        end if;
                    end loop;
                end if;			 
            end if;
        end if;
    end process;

    -- Empaquetar la ventana completa (fila por fila)
--    window <= regs(0,0) & regs(0,1) & ... & regs(0,K-1)
--            & regs(1,0) & regs(1,1) & ... & regs(1,K-1)
--            -- … hasta regs(K-1, K-1)
--            & regs(K-1,0) & regs(K-1,1) & ... & regs(K-1,K-1);

---------------------------------------------------------------------
   --Pero de forma generica seria:
---------------------------------------------------------------------	
	-- Proceso concurrente para aplanar la matriz de registros en un solo vector de salida
	
	
flatten_window: process(regs,effective_K)
    -- Se declara una variable temporal para construir el vector plano.
    -- El process se ejecuta cada vez que 'regs' cambia.
    variable temp_window : std_logic_vector((K_MAX*K_MAX*BITS)-1 downto 0);
	 type flat_array_t is array (0 to K_MAX*K_MAX -1) of std_logic_vector(BITS-1 downto 0);
    variable flat : flat_array_t := (others => (others => '0'));
    variable idx : integer := 0;
	 
begin
--	 temp_window := (others => '0');  -- Inicializar todo a cero
--    -- Itera sobre la matriz de registros 2D 'regs'
--    for r in 0 to effective_K-1 loop       -- r = fila
--        for c in 0 to effective_K-1 loop   -- c = columna
--            -- Asigna cada pixel 'regs(r, c)' a su lugar correcto en el vector plano 'temp_window'.
--            -- Los índices se calculan directamente en la asignación de slice.
--            temp_window( (((r*effective_K + c) + 1) * BITS) - 1   downto   (r*effective_K + c) * BITS ) := regs(r, c);
--        end loop;
--    end loop;
	 
	 
	 -- Empaquetar de forma consecutiva solo las partes usadas
    for r in 0 to K_MAX-1 loop
        for c in 0 to K_MAX-1 loop
            if r < effective_K and c < effective_K then
                flat(idx) := regs(r, c);
                idx := idx + 1;
            end if;
        end loop;
    end loop;
    
    -- Aplanar el array intermedio con bounds constantes
    for i in 0 to (K_MAX*K_MAX -1) loop
        temp_window( (i+1)*BITS -1 downto i*BITS ) := flat(i);
    end loop;
    
    -- Asigna el vector plano completo a la señal de salida
    window <= temp_window;
	 
end process flatten_window;


end architecture;
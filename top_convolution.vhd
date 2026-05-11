library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_convolution is
    generic (
        WIDTH 		: integer := 32;  -- Ancho de la imagen en píxeles
        HEIGHT		: integer := 32;  -- Alto de la imagen (para contar líneas)
        K_MAX     : integer := 5;     -- Tamaño del kernel
        F_MAX     : integer := 5;    -- Número de filtros
        BITS  		: integer := 9;     -- Bits por píxel
        COEFFW		: integer := 9;      -- Bits por coeficiente
		  OUTW      : integer := 18     -- Output bits per convolved pixel (adjusted for max)
    );
    port (
		  clk             : in  std_logic;
        reset           : in  std_logic;
        start           : in  std_logic;
        -- Dynamic configuration ports for multi-layer support
        effective_K     : in  integer range 1 to K_MAX;  -- Effective kernel size
        effective_F     : in  integer range 1 to F_MAX;  -- Effective number of filters
        stride_in       : in  integer range 1 to 4;      -- Stride value
        padding_in      : in  integer range 0 to 2;      -- Padding value
        activation_type : in  integer range 0 to 1;      -- 0: none, 1: ReLU (for post-convolution activation)
        -- Coefficients loading for dynamic weights
        coeffs_load_en  : in  std_logic;
        coeffs_load     : in  std_logic_vector((F_MAX*K_MAX*K_MAX*COEFFW)-1 downto 0);
        -- Input pixel interface (one per clock cycle)
        pixel_in        : in  std_logic_vector(BITS-1 downto 0);
        -- Output interface
        pixel_out       : out std_logic_vector((F_MAX*OUTW)-1 downto 0);
        data_valid      : out std_logic;    
        done            : out std_logic
    );
end entity;

architecture Structural of top_convolution is

    -- Señales internas de interconexión
	 
    --signal lb_line       : std_logic_vector((WIDTH*BITS)-1 downto 0);
	 --Señales para el Line Buffer
	 signal line1_out        : std_logic_vector((WIDTH*BITS)-1 downto 0);
    signal line2_out        : std_logic_vector((WIDTH*BITS)-1 downto 0);
   
	 --Señales extras del linebuffer para usar Generate
	 --type line_array is array (0 to effective_K-1) of std_logic_vector((WIDTH*BITS)-1 downto 0); --Aqui duda si es effective_K o K_MAX
	 signal lb_pixel_in : std_logic_vector(BITS-1 downto 0);

	 
   -- signal fm_coeffs     : std_logic_vector((F*K*K*COEFFW)-1 downto 0); --Elimino la F de la multiplicacion ya que se aplica un filtro a la vez en el convolution block (F*K*K*COEFFW)
   -- signal fm_coeffs : std_logic_vector((F*K*K*COEFFW)-1 downto 0);

   -- signal conv_pixel    : std_logic_vector((F*16)-1 downto 0);
   -- signal ob_line       : std_logic_vector((WIDTH*16)-1 downto 0);
	
		 -- Type definitions
    type line_array is array (0 to K_MAX-1) of std_logic_vector((WIDTH*BITS)-1 downto 0);
	
	
	
	 -- Señal interna para data_valid
	 signal ob_data_valid : std_logic;
	 
	 -- Internal interconnection signals
    signal line_outs        : line_array;  -- Defined as type line_array is array (0 to K_MAX-1) of std_logic_vector((WIDTH*BITS)-1 downto 0);
    signal column_to_window : std_logic_vector((K_MAX*BITS)-1 downto 0);
    signal wr_window        : std_logic_vector((K_MAX*K_MAX*BITS)-1 downto 0);
    signal fm_coeffs        : std_logic_vector((F_MAX*K_MAX*K_MAX*COEFFW)-1 downto 0);
    signal conv_start       : std_logic;
    signal conv_done        : std_logic;
    signal conv_pixel       : std_logic_vector((F_MAX*OUTW)-1 downto 0);
    signal activated_pixel  : std_logic_vector((F_MAX*OUTW)-1 downto 0);  -- After activation
    signal ob_line          : std_logic_vector((WIDTH*OUTW)-1 downto 0);  -- Adjusted for single filter output; multiplex if needed for F_MAX
    signal lb_we, wr_upd, ob_we : std_logic;
    signal global_done      : std_logic;

	 


begin

    ------------------------------------------------------------------------
    -- Instanciación: LineBuffer's
    ------------------------------------------------------------------------
    
	 
		-- Instanciación: LineBuffer 1 (Retrasa 1 línea)
--		u_LineBuffer1: entity work.LineBuffer
--			 generic map (
--				  WIDTH => WIDTH,
--				  BITS  => BITS
--			 )
--			 port map (
--				  clk      => clk,
--				  reset    => reset,
--				  pixel_in => pixel_in, -- Píxel de entrada actual (línea n)
--				  write_en => lb_we,
--				  line_out => line1_out
--			 );
--
--		-- Instanciación: LineBuffer 2 (Retrasa 2 líneas)
--		u_LineBuffer2: entity work.LineBuffer
--			 generic map (
--				  WIDTH => WIDTH,
--				  BITS  => BITS
--			 )
--			 port map (
--				  clk      => clk,
--				  reset    => reset,
--				  pixel_in => line1_out((BITS-1) downto 0), -- Salida del buffer 1 (línea n-1)
--				  write_en => lb_we,
--				  line_out => line2_out
--			 );
--			 
--	-- Construir la columna de 3 pixeles (24 bits) para la ventana
--	column_to_window <= line2_out((BITS-1) downto 0) &   -- Píxel de línea n-2 (el más antiguo)
--							  line1_out((BITS-1) downto 0) &   -- Píxel de línea n-1
--							  pixel_in;                        -- Píxel de línea n   (el más nuevo)

			 
--------------------------------------------------------------------------------------------------

-- Instanciación dinámica de (K_MAX-1) LineBuffers usando generate
lb_gen: for i in 1 to K_MAX-1 generate
	signal lb_pixel_in : std_logic_vector(BITS-1 downto 0); -- Local a cada instancia
	
	begin
    lb_pixel_in <= pixel_in when i = 1 else line_outs(i-1)((BITS-1) downto 0);
	 
	 
    u_LineBuffer: entity work.LineBuffer
        generic map (
            WIDTH => WIDTH,
            BITS  => BITS
        )
        port map (
            clk      => clk,
            reset    => reset,
            -- Entrada: para i=1, usa pixel_in; para i>1, usa el píxel delayed (LSB) del buffer anterior
            --pixel_in => pixel_in when i = 1 else line_outs(i-1)((BITS-1) downto 0),
				pixel_in => lb_pixel_in,
            write_en => lb_we,  -- Controlado por el módulo de sincronización
            line_out => line_outs(i)
        );
end generate lb_gen;

-- Proceso para construir column_to_window de forma genérica
	build_column: process(line_outs, pixel_in, effective_K)
		 variable temp_col : std_logic_vector((K_MAX*BITS)-1 downto 0):= (others => '0');
		 type pixel_array_t is array (0 to K_MAX-1) of std_logic_vector(BITS-1 downto 0);
       variable pixels : pixel_array_t := (others => (others => '0'));
	begin	
	-- Inicializar el array con ceros y asignar pixel_in en la posición 0 (LSB)
    pixels(0) := pixel_in;
	 
	 
--		 -- Concatenar del más antiguo al más nuevo
--		 for i in effective_K-1 downto 1 loop
--			  temp_col(((effective_K-i)*BITS) + BITS - 1 downto (effective_K-i)*BITS) := line_outs(i)((BITS-1) downto 0);
--		 end loop;

-- Asignar las salidas de los line buffers al array de manera dinámica basada en effective_K
    for i in 1 to K_MAX-1 loop
        if i < effective_K then
            pixels(effective_K - i) := line_outs(i)((BITS-1) downto 0);
        end if;
    end loop;
	 
-- Aplanar el array en temp_col con slices de bounds constantes (bucle fijo sobre K_MAX)
    for j in 0 to K_MAX-1 loop
        temp_col(((j+1)*BITS)-1 downto j*BITS) := pixels(j);
    end loop;
		 
		 -- Añadir la línea actual (pixel_in) en los bits más bajos o ajusta según orden
	--	 temp_col(BITS-1 downto 0) := pixel_in;
		 column_to_window <= temp_col;
	end process build_column;

--------------------------------------------------------------------------------------------------			 

    ------------------------------------------------------------------------
    -- Instanciación: WindowRegister
    ------------------------------------------------------------------------
    u_WindowRegister: entity work.WindowRegister
        generic map (
            K_MAX    => K_MAX,
            BITS => BITS
        )
        port map (
            clk     => clk,
            reset   => reset,
				effective_K => effective_K,
				update_en => wr_upd, --Correccion del warning wr_upd
            data_in => column_to_window,
				window  => wr_window
        );

    ------------------------------------------------------------------------
    -- Instanciación: FilterMemory
    ------------------------------------------------------------------------
    u_FilterMemory: entity work.FilterMemory
        generic map (
            F_MAX    => F_MAX,
            K_MAX    => K_MAX,
            BITS => COEFFW
        )
        port map (
			   clk         => clk,
            load_en     => coeffs_load_en,
            effective_F => effective_F,
            effective_K => effective_K,
            coeffs_load => coeffs_load,
            coeffs_out  => fm_coeffs
        );

    ------------------------------------------------------------------------
    -- Instanciación: ConvolutionBlock
    ------------------------------------------------------------------------
    u_ConvolutionBlock: entity work.ConvolutionBlock
        generic map (
            K_MAX      => K_MAX,
            F_MAX      => F_MAX,
				P_MAX      => K_MAX*K_MAX,
            BITS   => BITS,
            COEFFW => COEFFW,
            OUTW   => OUTW
        )
        port map (
				clk         => clk,
            reset       => reset,
            effective_K => effective_K,
            effective_F => effective_F,
            window_in   => wr_window,
            coeffs_in   => fm_coeffs,
            start       => conv_start,
            done        => conv_done,
            pixel_out   => conv_pixel
        );

		  
	    ------------------------------------------------------------------------
    -- ReLU:  (Rectified Linear Unit), que es la más común en CNNs(post-convolution)
      ------------------------------------------------------------------------
  		  
    u_Activation: entity work.ActivationFunction
        generic map (
            OUTW   => OUTW,
            F_MAX  => F_MAX
        )
        port map (
            clk        => clk,
            reset      => reset,
            type_sel   => activation_type,
            effective_F=> effective_F,
            data_in    => conv_pixel,
            data_out   => activated_pixel
        );
		  
		 
    ------------------------------------------------------------------------
    -- Instanciación: OutputBuffer
    ------------------------------------------------------------------------
--    u_OutputBuffer: entity work.OutputBuffer
--        generic map (
--            WIDTH => WIDTH,
--            BITS  => OUTW
--        )
--        port map (
--            clk        => clk,
--            reset      => reset,
--            write_en   => ob_we,
--            data_in    => activated_pixel((OUTW-1) downto 0), -- asumiendo un filtro; si F>1, multiplexar
--            buffer_out => ob_line,
--				data_valid => ob_data_valid
--        );

    ------------------------------------------------------------------------
    -- Instanciación: Controller (FSM)
    ------------------------------------------------------------------------
    u_Controller: entity work.Controller
	
	
		generic map (
            WIDTH  => WIDTH,
            HEIGHT => HEIGHT,
            K_MAX  => K_MAX
        )
	 
        port map (
				clk        => clk,
            reset      => reset,
            start      => start,
            effective_K=> effective_K,
            stride     => stride_in,
            padding    => padding_in,
            lb_we      => lb_we,
            wr_update  => wr_upd,
            conv_start => conv_start,
            conv_done  => conv_done,
            ob_we      => ob_we,
            finished   => global_done
        );

    -- Conectar salida final
    pixel_out <= activated_pixel;
    done      <= global_done;
--	 data_valid <= ob_data_valid;
	 data_valid <= Ob_we;

end architecture;

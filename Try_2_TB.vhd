library IEEE;
use ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL; 

entity Try_2_TB is
end Try_2_TB;

architecture Behavioral of Try_2_TB is
    -- Parameters (max values as generics in DUT)
    constant WIDTH     : integer := 32;
    constant HEIGHT    : integer := 32;
    constant K_MAX     : integer := 5;
    constant F_MAX     : integer := 5;
    constant BITS      : integer := 9;
    constant COEFFW    : integer := 9;
    constant OUTW      : integer := 18;  -- Output bits
    constant CLK_PERIOD: time := 10 ns;  -- 100 MHz

    -- DUT signals
    signal clk             : std_logic := '0';
    signal reset           : std_logic := '0';
    signal start           : std_logic := '0';
    signal effective_K     : integer range 1 to K_MAX := 5;
    signal effective_F     : integer range 1 to F_MAX := 5;
    signal stride_in       : integer range 1 to 4 := 1;
    signal padding_in      : integer range 0 to 2 := 0;
    signal activation_type : integer range 0 to 1 := 0;  -- 0: none, 1: ReLU
    signal coeffs_load_en  : std_logic := '0';
    signal coeffs_load     : std_logic_vector((F_MAX*K_MAX*K_MAX*COEFFW)-1 downto 0) := (others => '0');
    signal pixel_in        : std_logic_vector(BITS-1 downto 0) := (others => '0');
    signal pixel_out       : std_logic_vector((F_MAX*OUTW)-1 downto 0);
    signal data_valid      : std_logic;
    signal done            : std_logic;

    -- Multi-layer control
    constant NUM_LAYERS    : integer := 2;  -- Example: 2 layers (Los ajusten van aqui)

begin
    -- DUT instantiation
    UUT: entity work.top_convolution
        generic map (
            WIDTH  => WIDTH,
            HEIGHT => HEIGHT,
            K_MAX  => K_MAX,
            F_MAX  => F_MAX,
            BITS   => BITS,
            COEFFW => COEFFW,
            OUTW   => OUTW
        )
        port map (
            clk             => clk,
            reset           => reset,
            start           => start,
            effective_K     => effective_K,
            effective_F     => effective_F,
            stride_in       => stride_in,
            padding_in      => padding_in,
            activation_type => activation_type,
            coeffs_load_en  => coeffs_load_en,
            coeffs_load     => coeffs_load,
            pixel_in        => pixel_in,
            pixel_out       => pixel_out,
            data_valid      => data_valid,
            done            => done
        );

    -- Clock generator
    clk_gen: process
    begin
        while true loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
    end process;

    -- Stimulus process for multi-layer simulation
    stimulus: process
        variable line_in, line_out, config_line, weights_line : line;
        variable temp_pixel : std_logic_vector(BITS-1 downto 0);
        variable temp_out   : std_logic_vector(OUTW-1 downto 0);  -- Salida por filtro se ajusta si F> 1
        variable temp_coeff : std_logic_vector(COEFFW-1 downto 0);
        variable layer_idx  : integer;
		  
--        variable config_file: file_open_kind := read_mode;
--        variable weights_file: file_open_kind := read_mode;
--        variable input_file : file_open_kind := read_mode;
--        variable output_file: file_open_kind := write_mode;
		  file config_file   : text open read_mode is "";
		  file weights_file  : text open read_mode is "";
		  file input_file    : text open read_mode is "";
		  file output_file   : text open write_mode is "";

        variable config_key : string(1 to 12);  -- Increased length to cover "activation="
        variable config_val : integer;
        variable P_eff      : integer;  -- Effective P = K*K
        variable coeff_idx  : integer := 0;

        constant BASE_PATH : string := "C:/Users/Farab/Documents/Maestria/Tesis/Archivos VHDL/Try 2/Archivos txt/";  -- Ruta base con / al final

    begin
        -- Reset DUT
        reset <= '1';
        wait for CLK_PERIOD * 2; 
        reset <= '0';
        wait for CLK_PERIOD;

        -- Loop over layers
        for layer_idx in 1 to NUM_LAYERS loop
            report "Starting Layer " & integer'image(layer_idx);
				
				
				----------------------------------------------------------------------
			 --Carga las cofiguraciones de cada capa (Layer)
			   ----------------------------------------------------------------------

            -- Aqui abre el archivo de configuracion de cada layer ("layer1_config.txt")
            file_open(config_file, BASE_PATH & "layer" & integer'image(layer_idx) & "_config.txt", read_mode); -- separa el nombre ''layer'' ''numero'' y ''_config'' para poder leer diferentes archivos txt
            while not endfile(config_file) loop
                readline(config_file, config_line);
                read(config_line, config_key);  -- Read key ("K=")
                read(config_line, config_val);  -- Read value
                if config_key(1 to 2) = "K=" then        --Asigna los valores del txt a cada elemento de la arquitectura
                    effective_K <= config_val;
                elsif config_key(1 to 2) = "F=" then
                    effective_F <= config_val;
                elsif config_key(1 to 7) = "stride=" then
                    stride_in <= config_val;
                elsif config_key(1 to 8) = "padding=" then
                    padding_in <= config_val;
                elsif config_key(1 to 11) = "activation=" then
                    activation_type <= config_val;
                end if;
            end loop;
            file_close(config_file);

            -- Calculate effective P
            P_eff := effective_K * effective_K; --Otra vez utiliza el k*k

				----------------------------------------------------------------------
			 --Carga de valores de filtros
			   ----------------------------------------------------------------------
			
			-- Abre y carga los datos del TXT (un coeficiente por linea, y lo asigna a std_logic_vector(COEFFW-1 downto 0))
            file_open(weights_file, BASE_PATH & "pesos_layer" & integer'image(layer_idx) & ".txt", read_mode);           --Los pesos_layer1,2 etc son los valores de los filtros. 
            coeff_idx := 0;
            while not endfile(weights_file) loop
                readline(weights_file, weights_line);
                read(weights_line, temp_coeff);
                coeffs_load((coeff_idx + 1)*COEFFW - 1 downto coeff_idx*COEFFW) <= temp_coeff;
                coeff_idx := coeff_idx + 1;
                if coeff_idx >= effective_F * P_eff then  -- Stop at effective size
                    exit;
                end if;
            end loop;
            file_close(weights_file);

            -- Load weights into DUT
            coeffs_load_en <= '1';
            wait for CLK_PERIOD;
            coeffs_load_en <= '0';
            wait for CLK_PERIOD;

            -- Set input file: For layer 1, use "G.txt" or "input.txt"; for others, previous output
            if layer_idx = 1 then
                file_open(input_file, BASE_PATH & "G.txt", read_mode);
            else
                file_open(input_file, BASE_PATH & "output_layer" & integer'image(layer_idx-1) & ".txt", read_mode);
            end if;

            -- Open output file for this layer
            file_open(output_file, BASE_PATH & "output_layer" & integer'image(layer_idx) & ".txt", write_mode);

            -- Start processing
            start <= '1';
            wait for CLK_PERIOD;
            start <= '0';

            -- Read pixels from input file and feed to DUT
            while not endfile(input_file) loop
                readline(input_file, line_in);
                read(line_in, temp_pixel);
                pixel_in <= temp_pixel;
                wait for CLK_PERIOD * 2;  -- Se ajusta el tiempo aqui, 100MHz
            end loop;
            file_close(input_file);

            -- Wait for done, and capture outputs when data_valid='1'
            while done = '0' loop
                wait for CLK_PERIOD;
                if data_valid = '1' then
                    for f in 0 to effective_F-1 loop  -- Write per filter output
                        temp_out := pixel_out((f+1)*OUTW-1 downto f*OUTW);
                        write(line_out, temp_out);
                        writeline(output_file, line_out);
                    end loop;
                end if;
            end loop;
            file_close(output_file);

            -- Reset for next layer if needed
            reset <= '1';
            wait for CLK_PERIOD;
            reset <= '0';
            wait for CLK_PERIOD;
        end loop;

        -- End simulation
        report "Simulation completed for all layers.";
        wait;
    end process;

end Behavioral;
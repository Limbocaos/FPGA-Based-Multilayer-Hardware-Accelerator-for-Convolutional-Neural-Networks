# FPGA-Based-Multilayer-Hardware-Accelerator-for-Convolutional-Neural-Networks
A fully generic, multi-layer 2D convolution accelerator implemented in VHDL, designed for FPGA deployment in CNN (Convolutional Neural Network) inference pipelines. The architecture supports configurable kernel sizes, multiple filters, stride, padding, and ReLU activation — all runtime-configurable without resynthesis.

***

## 📖 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Module Descriptions](#module-descriptions)
  - [top\_convolution](#top_convolution-top-level)
  - [Controller](#controller-fsm)
  - [LineBuffer](#linebuffer)
  - [WindowRegister](#windowregister)
  - [FilterMemory](#filtermemory)
  - [ConvolutionBlock](#convolutionblock)
  - [ActivationFunction](#activationfunction)
  - [OutputBuffer](#outputbuffer)
- [Generic Parameters](#generic-parameters)
- [Port Interfaces](#port-interfaces)
- [Supported Filter Types](#supported-filter-types)
- [Simulation & Testbench](#simulation--testbench)
- [File Structure](#file-structure)
- [How to Run](#how-to-run)
- [Design Notes](#design-notes)

***

## Overview

This project implements a **hardware 2D convolution block** in VHDL, targeting digital image processing tasks on FPGA. It can process images by sliding a configurable K×K kernel across the input, applying up to F filters in parallel, and optionally applying a ReLU activation function.

Key features:
- **Fully parametric**: kernel size (K), number of filters (F), image dimensions (WIDTH × HEIGHT), and bit widths are all generic.
- **Runtime-configurable**: `effective_K`, `effective_F`, `stride`, `padding`, and `activation_type` are input ports — no re-synthesis required between layers.
- **Multi-layer support**: the testbench drives sequential layers by reloading weights and feeding the previous layer's output as the next layer's input.
- **Parallel computation**: the ConvolutionBlock uses a logarithmic adder-tree to compute all F filter sums in parallel each clock cycle.
- **Synthesizable VHDL**: all modules use only synthesizable constructs from `ieee.std_logic_1164` and `ieee.numeric_std`.

***

## Architecture

The design follows a **structural top-level** (`top_convolution`) that instantiates and interconnects the following sub-modules:

```
pixel_in ──► [LineBuffer × (K_MAX-1)] ──► build_column
                                              │
                                              ▼
                                       [WindowRegister]
                                              │
                           ┌──────────────────┘
                           │         (K×K window)
                           ▼
         [FilterMemory] ──► [ConvolutionBlock] ──► [ActivationFunction] ──► pixel_out
                                    ▲
                               [Controller FSM]
                         (generates lb_we, wr_update,
                          conv_start, ob_we, finished)
```

The **Controller FSM** coordinates all control signals. It cycles through seven states:

| State | Description |
|---|---|
| `IDLE` | Waits for `start = '1'` |
| `LOAD_INITIAL` | Preloads first (K-1) lines into LineBuffers |
| `LOAD_PIX` | Loads one full pixel row into the LineBuffers |
| `SHIFT_WINDOW` | Asserts `wr_update` to shift WindowRegister |
| `COMPUTE_CONV` | Asserts `conv_start`; waits for `conv_done` |
| `WRITE_OUT` | Asserts `ob_we`; advances pixel/line counters by stride |
| `DONE` | Asserts `finished`; returns to `IDLE` |

***

## Module Descriptions

### `top_convolution` (Top Level)

**File:** `top_convolution-9.vhd`

The structural wrapper that connects all sub-modules. It instantiates `K_MAX-1` LineBuffers using a `generate` statement, builds the pixel column combinatorially, and wires all control signals from the Controller.

**Notable internal signals:**

| Signal | Width | Description |
|---|---|---|
| `line_outs` | `K_MAX × (WIDTH×BITS)` | Delayed line outputs from LineBuffers |
| `column_to_window` | `K_MAX × BITS` | Current pixel column fed into WindowRegister |
| `wr_window` | `K_MAX² × BITS` | Flattened K×K pixel window |
| `fm_coeffs` | `F_MAX × K_MAX² × COEFFW` | All filter coefficients |
| `conv_pixel` | `F_MAX × OUTW` | Raw convolution results (before activation) |
| `activated_pixel` | `F_MAX × OUTW` | Post-activation results |

***

### `Controller` (FSM)

**File:** `Controller-4.vhd`

A synchronous FSM that drives all write-enable and control signals. It manages pixel and line counters with configurable `stride` and `padding`. The controller supports runtime adjustment of `effective_K` to handle kernels smaller than `K_MAX`.

**Generics:** `WIDTH`, `HEIGHT`, `K_MAX`

**Ports (key outputs):**

| Port | Direction | Description |
|---|---|---|
| `lb_we` | out | LineBuffer write enable |
| `wr_update` | out | WindowRegister shift trigger |
| `conv_start` | out | Start convolution computation |
| `conv_done` | in | Completion signal from ConvolutionBlock |
| `ob_we` | out | OutputBuffer write enable |
| `finished` | out | Signals end of full image processing |

***

### `LineBuffer`

**File:** `LineBuffer-7.vhd`

Stores one complete image row (WIDTH pixels × BITS bits) in a circular RAM array. On each rising edge where `write_en = '1'`, the current `pixel_in` is written and the index advances. The entire stored line is always available on `line_out` as a packed vector.

**Generics:** `WIDTH` (pixels per row), `BITS` (bits per pixel)

The `K_MAX-1` LineBuffer instances create an effective delay line that presents the last K rows simultaneously, enabling column extraction.

***

### `WindowRegister`

**File:** `WindowRegister-2.vhd`

Maintains a K×K sliding window as a 2D register array (`K_MAX × K_MAX`). On each `update_en` pulse, the register matrix shifts right by one column and the new pixel column from the LineBuffers is loaded into row 0. A separate combinatorial process (`flatten_window`) packs the 2D register into a flat `K_MAX²×BITS` vector.

**Generics:** `K_MAX`, `BITS`

**Key behavior:** Rows and columns beyond `effective_K` are zeroed out, allowing the same hardware to handle any kernel size from 1×1 to K_MAX×K_MAX.

***

### `FilterMemory`

**File:** `FilterMemory-6.vhd`

Stores up to `F_MAX` filters, each of `K_MAX × K_MAX × COEFFW` bits. When `load_en = '1'`, new coefficients are loaded from `coeffs_load` using `effective_F` and `effective_K` to fill only the relevant positions; unused entries are zeroed. The packed output `coeffs_out` is always available to the ConvolutionBlock.

Supports the following filter types (loaded externally via the testbench):

| Filter | Kernel |
|---|---|
| Identity/Pass-through | Center = 1, rest = 0 |
| Averaging (Box Blur) | All 1s |
| Sobel (Edge detect H) | [−1 0 1; −2 0 2; −1 0 1] |
| Sharpen | [0 −1 0; −1 5 −1; 0 −1 0] |
| High-Pass | [−1 −1 −1; −1 8 −1; −1 −1 −1] |
| Gaussian (approx.) | [1 2 1; 2 4 2; 1 2 1] |

***

### `ConvolutionBlock`

**File:** `ConvolutionBlock-5.vhd`

Performs the multiply-accumulate operations for all F filters in parallel using a **logarithmic adder tree** (`sum_proc`) for O(log K²) latency instead of sequential O(K²) accumulation.

**Pipeline stages (all clocked):**
1. `extract_proc` — unpacks pixel window and filter coefficients into typed arrays.
2. `mult_proc` — computes all K²×F products in parallel when `start = '1'`.
3. `sum_proc` — sums each filter's K² products using an adder tree; asserts `done = '1'` when complete.
4. `output_proc` — packs results into the flat `pixel_out` vector.

**Generics:** `K_MAX`, `F_MAX`, `P_MAX` (= K_MAX²), `BITS`, `COEFFW`, `OUTW`

***

### `ActivationFunction`

**File:** `ActivationFunction-3.vhd`

Applies a post-convolution activation function to all F filter outputs. Selected via the `type_sel` port:

| `type_sel` | Function |
|---|---|
| `0` | None (pass-through) |
| `1` | ReLU: `max(0, x)` |

All arithmetic is done in signed fixed-point (`signed(OUTW-1 downto 0)`). Outputs beyond `effective_F` are zeroed.

***

### `OutputBuffer`

**File:** `OutputBuffer-8.vhd`

A circular RAM buffer that stores one output line (WIDTH × OUTW bits). When `write_en = '1'`, each result pixel is stored sequentially. When the buffer completes a full row (index wraps to 0), `data_valid` is asserted for one clock cycle. **Note:** This module is instantiated but currently bypassed in `top_convolution` — `data_valid` is driven directly from `ob_we` for simplicity; the buffer can be re-enabled for full line-buffered output.

***

## Generic Parameters

These are set at synthesis time on `top_convolution`:

| Generic | Default | Description |
|---|---|---|
| `WIDTH` | 32 | Image width in pixels |
| `HEIGHT` | 32 | Image height in pixels |
| `K_MAX` | 5 | Maximum kernel dimension (K×K) |
| `F_MAX` | 5 | Maximum number of convolution filters |
| `BITS` | 9 | Bits per input pixel (signed) |
| `COEFFW` | 9 | Bits per filter coefficient (signed) |
| `OUTW` | 18 | Bits per output pixel (accumulator width) |

> **Tip:** `OUTW` should be at least `BITS + COEFFW + ceil(log2(K_MAX²))` to avoid overflow.

***

## Port Interfaces

### `top_convolution` ports

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | System clock |
| `reset` | in | 1 | Active-high synchronous reset |
| `start` | in | 1 | Begin processing pulse |
| `effective_K` | in | int [1..K_MAX] | Active kernel size |
| `effective_F` | in | int [1..F_MAX] | Number of active filters |
| `stride_in` | in | int [1..4] | Convolution stride |
| `padding_in` | in | int [0..2] | Zero-padding pixels |
| `activation_type` | in | int [0..1] | 0 = none, 1 = ReLU |
| `coeffs_load_en` | in | 1 | Load filter coefficients |
| `coeffs_load` | in | F_MAX×K_MAX²×COEFFW | Packed filter weights |
| `pixel_in` | in | BITS | Input pixel (one per clock) |
| `pixel_out` | out | F_MAX×OUTW | Output per filter (packed) |
| `data_valid` | out | 1 | Output is valid this cycle |
| `done` | out | 1 | Full image processed |

***

## Supported Filter Types

Filters are loaded at runtime via `coeffs_load` / `coeffs_load_en`. Each coefficient is a signed `COEFFW`-bit value in two's complement. Example 3×3 filters:

```
Sobel Horizontal:    Gaussian Approx:    Sharpen:
 -1  0  1            1  2  1             0 -1  0
 -2  0  2            2  4  2            -1  5 -1
 -1  0  1            1  2  1             0 -1  0
```

***

## Simulation & Testbench

**File:** `Try_2_TB.vhd`

The testbench drives the DUT (`top_convolution`) for multiple sequential layers. It reads configuration, weights, and pixel data from plain-text `.txt` files.

### Required `.txt` Files

For each layer `N`, place the following files in `BASE_PATH`:

| File | Format | Description |
|---|---|---|
| `layerN_config.txt` | Key=value pairs | Layer configuration |
| `pesos_layerN.txt` | One binary vector per line | Filter coefficients |
| `G.txt` (layer 1) | One binary vector per line | Input image pixels |
| `output_layerN.txt` | (auto-generated) | Convolution output |

### `layerN_config.txt` Format

```
K=3
F=2
stride=1
padding=0
activation=1
```

### Simulation Parameters

| Constant | Value | Description |
|---|---|---|
| `CLK_PERIOD` | 10 ns | 100 MHz clock |
| `NUM_LAYERS` | 2 | Number of sequential CNN layers |
| `WIDTH/HEIGHT` | 32 | Image dimensions |
| `K_MAX / F_MAX` | 5 / 5 | Maximum kernel/filter count |

### Waveform Signals to Monitor

- `clk`, `reset`, `start`, `done`, `data_valid`
- `pixel_in`, `pixel_out`
- `lb_we`, `wr_update`, `conv_start`, `conv_done`, `ob_we`

***

## File Structure

```
project/
├── top_convolution-9.vhd      # Top-level structural wrapper
├── Controller-4.vhd           # FSM controller
├── LineBuffer-7.vhd           # Single-row pixel delay buffer
├── WindowRegister-2.vhd       # K×K sliding window register
├── FilterMemory-6.vhd         # Loadable filter coefficient memory
├── ConvolutionBlock-5.vhd     # MAC engine with adder tree
├── ActivationFunction-3.vhd   # ReLU / pass-through activation
├── OutputBuffer-8.vhd         # Output line buffer
├── Try_2_TB.vhd               # Testbench (multi-layer simulation)
└── Archivos txt/              # (Not included) Simulation data files
    ├── layer1_config.txt
    ├── pesos_layer1.txt
    ├── G.txt
    └── output_layer1.txt
```

***

## How to Run

### In Xilinx Vivado

1. Create a new RTL project and add all `.vhd` files as design sources.
2. Set `Try_2_TB.vhd` as the simulation source.
3. Update `BASE_PATH` in the testbench to point to your `.txt` data files.
4. Run Behavioral Simulation (`Run Simulation → Run Behavioral Simulation`).
5. Add signals of interest to the waveform viewer and observe `pixel_out` when `data_valid = '1'`.

### In ModelSim / Questa

```tcl
vcom -work work Controller-4.vhd
vcom -work work LineBuffer-7.vhd
vcom -work work WindowRegister-2.vhd
vcom -work work FilterMemory-6.vhd
vcom -work work ConvolutionBlock-5.vhd
vcom -work work ActivationFunction-3.vhd
vcom -work work OutputBuffer-8.vhd
vcom -work work top_convolution-9.vhd
vcom -work work Try_2_TB.vhd
vsim work.Try_2_TB
add wave -recursive *
run -all
```

***

## Design Notes

- **Pixel data format:** Pixels and coefficients are treated as signed integers in two's complement. Ensure your input `.txt` files use binary vectors of the correct width (`BITS` and `COEFFW`).
- **OutputBuffer bypass:** The `u_OutputBuffer` instantiation is commented out in the current top level. `data_valid` is driven directly by `ob_we` from the Controller. Uncomment and reconnect to enable full line-buffered output.
- **Overflow:** With default `BITS=9`, `COEFFW=9`, and a 5×5 kernel, the maximum product width is 18 bits and the accumulator needs up to 23 bits for 25 products. The `OUTW=18` default may saturate for large kernels with large coefficients — adjust accordingly.
- **Stride & Padding:** The Controller supports stride values 1–4 and padding 0–2. Padding is implemented implicitly by adjusting pixel/line counter initialization; the LineBuffers do not physically pad with zeros.
- **Multi-layer inference:** Between layers, perform a full `reset` and reload `coeffs_load` with the new layer's weights before asserting `start` again, as shown in the testbench.

***

## License

This project is provided for academic and research purposes. Feel free to adapt and extend it for your own FPGA or CNN acceleration work.

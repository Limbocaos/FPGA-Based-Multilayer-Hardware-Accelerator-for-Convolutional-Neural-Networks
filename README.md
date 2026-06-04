# FPGA CNN Convolution Accelerator

Hardware-reconfigurable VHDL architecture for efficient convolution processing in CNNs, developed as a master's thesis project focused on filter-level and operation-level parallelism in FPGA implementations.[1][2][3]

## Project context

This repository contains the implementation associated with the thesis **"Procesamiento eficiente de redes neuronales de convolución a través de aceleradores hardware"**, presented at Tecnológico Nacional de México en Celaya in August 2025.[1] The work proposes an FPGA-based accelerator for convolution layers, with emphasis on reducing processing time while balancing hardware resource usage through configurable parallelism.[1]

The thesis frames convolution as the dominant computational load in CNNs and motivates FPGA use because it allows hardware exploration with lower cost, lower energy, and acceptable development time compared with alternatives such as CPU, GPU, or ASIC solutions.[1] The main hypothesis is that a reconfigurable FPGA accelerator with adjustable parallelism and multicapa support can reduce convolution processing time while improving resource reuse.[1]

## Main contribution

The project implements a modular streaming convolution architecture in VHDL that processes one input pixel per clock cycle and supports runtime reconfiguration of kernel size, number of filters, stride, padding, and activation mode.[1][2] The architecture is structured around Line Buffers, a Window Register, Filter Memory, a Convolution Block, a Controller FSM, and an activation stage, matching the thesis methodology and the source files in this repository.[1][2][4][5][6]

Two kinds of parallelism are central to the thesis and to this codebase:[1]
- **Filter parallelism**: several filters can be processed in parallel through the `effective_F` path and packed outputs.[1][2][3]
- **Operation parallelism**: the multiply-accumulate operations inside each convolution are parallelized using a matrix of products and an adder-tree strategy.[1][3]

## Architecture overview

The proposed architecture is designed as a real-time streaming system for convolution over input images.[1] At the top level, `top_convolution` connects the complete datapath and control path, including dynamic parameter inputs for `effective_K`, `effective_F`, `stride_in`, `padding_in`, and `activation_type`.[2]



### Dataflow

1. **Input preprocessing** converts image pixels into the fixed-point format used by the hardware path.[1]
2. **LineBuffer blocks** retain previous image rows, enabling simultaneous access to the rows required by a KxK window.[1][7]
3. **WindowRegister** builds and updates the active convolution window from the incoming pixel column.[1][5]
4. **FilterMemory** stores the coefficients for up to `F_MAX` filters and loads only the active subset defined by `effective_F` and `effective_K`.[1][6]
5. **ConvolutionBlock** performs parallel multiplication and accumulation using an adder tree to reduce the accumulation latency.[1][3]
6. **ActivationFunction** optionally applies ReLU to each filter output.[1][8]
7. **Controller** synchronizes the full process using an FSM that manages loading, shifting, convolution start, output write, stride, and finish conditions.[1][4]

### Repository module map

| File | Function |
|---|---|
| `top_convolution-9.vhd` | Top-level structural module connecting all blocks.[2] |
| `Controller-4.vhd` | FSM for synchronization, stride, padding, and flow control.[4][1] |
| `LineBuffer-7.vhd` | Stores one image row and outputs a packed line vector.[7][1] |
| `WindowRegister-2.vhd` | Maintains the sliding KxK convolution window.[5][1] |
| `FilterMemory-6.vhd` | Stores and reloads filter coefficients dynamically.[6][1] |
| `ConvolutionBlock-5.vhd` | Parallel multiply-accumulate engine with adder-tree summation.[3][1] |
| `ActivationFunction-3.vhd` | Optional ReLU activation stage.[8][1] |
| `OutputBuffer-8.vhd` | Output line buffer for post-processing or output staging.[9][1] |
| `Try_2_TB.vhd` | Testbench for multi-layer simulation using text-based I/O.[10][1] |

## Hardware model

The architecture is parameterized at synthesis time by maximum image size, kernel size, filter count, and word widths.[2] The current top-level generics are `WIDTH`, `HEIGHT`, `K_MAX`, `F_MAX`, `BITS`, `COEFFW`, and `OUTW`.[2]

At runtime, the design accepts dynamic configuration values for the active kernel size, number of filters, stride, padding, and activation function, which is one of the main thesis contributions because it allows reuse of the same hardware under different layer configurations without recompilation.[1][2]

### Top-level generics

| Generic | Default value | Description |
|---|---:|---|
| `WIDTH` | 32 | Input image width in pixels.[2] |
| `HEIGHT` | 32 | Input image height in pixels.[2] |
| `K_MAX` | 5 | Maximum supported kernel dimension.[2] |
| `F_MAX` | 5 | Maximum number of filters processed by the architecture.[2] |
| `BITS` | 9 | Bit width for input pixels.[2] |
| `COEFFW` | 9 | Bit width for filter coefficients.[2] |
| `OUTW` | 18 | Bit width for each convolved output pixel.[2] |

### Runtime configuration ports

| Port | Meaning |
|---|---|
| `effective_K` | Effective kernel size from 1 to `K_MAX`.[2] |
| `effective_F` | Effective number of filters from 1 to `F_MAX`.[2] |
| `stride_in` | Stride value from 1 to 4.[2] |
| `padding_in` | Padding value from 0 to 2.[2] |
| `activation_type` | Activation selector, where 0 is pass-through and 1 is ReLU.[2][8] |

## Convolution engine details

The `ConvolutionBlock` is the computational core of the design.[3] It unpacks the active window and the filter coefficients, computes all products, and then reduces them using a summation tree instead of a simple sequential accumulator, which aligns with the thesis analysis of operation-level parallelism.[1][3]

This block supports up to `P_MAX = K_MAX*K_MAX` operations per filter, and outputs up to `F_MAX` results in packed form.[3] The code explicitly distinguishes between the maximum static hardware dimensions and the active runtime dimensions using `effective_K` and `effective_F`.[3]

### Why the adder tree matters

The thesis compares sequential summation with tree-based summation and uses the adder tree as the preferred structure for reducing accumulation depth.[1] In practice, this lowers the effective reduction latency for the KxK partial products and improves the suitability of the architecture for real-time streaming designs.[1][3]

## Input stage and sliding window generation

A key part of the thesis is the input stage, because convolution in streaming hardware depends on continuously reconstructing the local neighborhood around the current pixel.[1] The design solves this with `K-1` line buffers and one window register, which together create the active KxK mask used by the convolution block.[1][7][5]

The `LineBuffer` stores a complete row of pixels using an internal RAM-like array and exports the full line as a packed vector.[7] The `WindowRegister` then shifts data and inserts the newest column when `update_en` is asserted, while zeroing the inactive region when `effective_K < K_MAX`.[5]

## Control, stride, and padding

The Controller is implemented as a finite-state machine with the states `IDLE`, `LOAD_INITIAL`, `LOAD_PIX`, `SHIFT_WINDOW`, `COMPUTE_CONV`, `WRITE_OUT`, and `DONE`.[4] This follows the thesis description of the synchronization block and controller state machine used to coordinate the datapath.[1]

Stride and padding are part of the thesis analysis because they directly affect output dimensions, processing time, and control complexity.[1] In the implementation, `stride` and `padding` influence pixel and line counters and determine when the controller advances the window or finishes the image traversal.[4]

## Activation and multicapa support

The thesis extends the architecture toward multicapa operation and adds a ReLU block for post-convolution activation.[1] In the code, `ActivationFunction` applies either pass-through or ReLU per active filter, zeroing inactive packed outputs beyond `effective_F`.[8]

The testbench also reflects the multicapa thesis direction by iterating through several layers, loading a new configuration and set of weights for each one, and using the previous output as the next layer input.[10][1]

## Simulation methodology

The thesis validates the design in simulation using Quartus and QuestaSim.[1] The repository testbench `Try_2_TB.vhd` reads configuration, weights, and image data from text files, writes results to output text files, and resets the architecture between layers.[10]

### Input files expected by the testbench

| File | Purpose |
|---|---|
| `layerN_config.txt` | Layer configuration such as kernel size, filters, stride, padding, and activation.[10][1] |
| `pesos_layerN.txt` | Packed filter coefficients for layer `N`.[10] |
| `G.txt` | Initial input image values for the first layer.[10] |
| `output_layerN.txt` | Output generated after each simulated layer.[10] |

### Example layer configuration

```txt
K=3
F=2
stride=1
padding=0
activation=1
```

## Main results from the thesis

According to the thesis conclusions, the architecture was validated in Quartus and QuestaSim, and the simulated processing times were very close to the theoretical estimates.[1] One example reported is `K=3`, `F=1`, `P=9`, where the theoretical time was 0.0207 s and the simulated time was 0.0208 s at 100 MHz.[1]

The thesis also reports that the optimal parallelism point was reached when `P = K²`, minimizing clock cycles and keeping times nearly constant when scaling `F` or `K`, although at the cost of more hardware resources.[1] The document cites configurations up to 784 MAC units and 103680 bits of memory for large multicapa scenarios.[1]

Compared with sequential software execution, the VHDL architecture outperformed Python and MATLAB implementations in the thesis discussion, highlighting its value for real-time image processing and CNN-style convolution workloads on FPGA.[1]

## Figures from the thesis to add manually

The thesis contains several figures that would improve the GitHub page if exported manually from the PDF and placed in a `docs/thesis-figures/` folder.[1] The most useful ones for the repository are the following:

| Suggested filename | Thesis reference | Why it is useful |
|---|---|---|
| `fig-3-1-rtl-architecture.png` | Figure 3.1, complete RTL diagram.[1] | Best full-system block diagram for the repository README. |
| `fig-3-6-linebuffer-cycle.png` | Figure 3.6, Line Buffer cycle.[1] | Helps explain the streaming input stage. |
| `fig-3-7-windowregister.png` | Figure 3.7, WindowRegister concept.[1] | Good for showing sliding-window extraction. |
| `fig-3-9-convolution-block.png` | Figure 3.9, convolution block.[1] | Explains the compute core. |
| `fig-3-13-adder-tree.png` | Figure 3.13, adder tree.[1] | Important to explain the parallel reduction. |
| `fig-3-15-controller-fsm.png` | Figure 3.15, controller FSM.[1] | Useful for the control section. |
| `fig-3-18-multilayer-structure.png` | Figure 3.18, general multicapa structure.[1] | Good for future-work and scalability sections. |
| `fig-4-2-questasim-waveform.png` | Figure 4.2, waveform in QuestaSim.[1] | Useful as validation evidence. |
| `fig-4-11-clock-cycles-vs-p.png` | Figure 4.11, clock cycles used depending on `P`.[1] | Great for performance discussion. |
| `fig-5-1-future-architecture.png` | Figure 5.1, future architecture.[1] | Good for roadmap/future work. |

### Suggested markdown for thesis figures

```md
## Thesis figures

### Complete RTL architecture
![Complete RTL architecture](docs/thesis-figures/fig-3-1-rtl-architecture.png)

### Window extraction process
![WindowRegister concept](docs/thesis-figures/fig-3-7-windowregister.png)

### Adder tree
![Adder tree](docs/thesis-figures/fig-3-13-adder-tree.png)
```

## New generated figure included here

This repository update includes one new clean diagram created specifically for GitHub documentation:
- `docs/generated-architecture-overview.png`: simplified architecture overview based on the implemented VHDL modules and thesis structure.[1][2]

This figure is intentionally simpler than the thesis RTL diagram so it works well in GitHub's narrow README layout.[1][2]

## How to upgrade the GitHub post

1. Replace the current repository `README.md` with this updated version or merge the sections you prefer.[1]
2. Create a folder named `docs/` in the repository root.[1]
3. Put the generated architecture image in `docs/generated-architecture-overview.png`.[1]
4. Export the recommended figures manually from the thesis PDF and place them under `docs/thesis-figures/` using the suggested filenames.[1]
5. Commit and push the changes to GitHub so the new README renders automatically.

Example commands:

```bash
git add README.md docs/
git commit -m "Upgrade README with thesis-based documentation"
git push origin main
```

## Suggested repository structure

```txt
.
├── README.md
├── top_convolution-9.vhd
├── Controller-4.vhd
├── LineBuffer-7.vhd
├── WindowRegister-2.vhd
├── FilterMemory-6.vhd
├── ConvolutionBlock-5.vhd
├── ActivationFunction-3.vhd
├── OutputBuffer-8.vhd
├── Try_2_TB.vhd
└── docs/
    ├── generated-architecture-overview.png
    └── thesis-figures/
        ├── fig-3-1-rtl-architecture.png
        ├── fig-3-6-linebuffer-cycle.png
        ├── fig-3-7-windowregister.png
        ├── fig-3-9-convolution-block.png
        ├── fig-3-13-adder-tree.png
        ├── fig-3-15-controller-fsm.png
        ├── fig-3-18-multilayer-structure.png
        ├── fig-4-2-questasim-waveform.png
        ├── fig-4-11-clock-cycles-vs-p.png
        └── fig-5-1-future-architecture.png
```

## Future improvements

The thesis proposes extending the architecture toward deeper multicapa systems with external interfaces, shared memory, pooling, and normalization blocks for more complete CNN implementations.[1] A strong next GitHub improvement would be adding a `docs/performance.md` file summarizing the thesis timing/resource tables and a `results/` folder containing waveform screenshots and input-output examples.[1]

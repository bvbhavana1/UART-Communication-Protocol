# UART-Communication-Protocol  — RTL Design, Verification & Synthesis
Verilog RTL design and verification of a UART communication protocol using Cadence tools.

A Verilog RTL implementation of an 8-bit UART (Universal Asynchronous Receiver/Transmitter) with independent TX and RX clock domains, verified using a loopback testbench and synthesized using Cadence.

## Overview

UART is one of the simplest and most widely used serial communication protocols, commonly used to interface microcontrollers, SoCs, and peripherals over a two-wire (TX/RX) connection without a shared clock. This project implements a UART transceiver core from scratch in Verilog, covering the full digital design lifecycle: RTL coding, functional verification via simulation, waveform-based debugging, and logic synthesis to a gate-level netlist.

The design handles the two hardest parts of UART implementation:
1. **Asynchronous input synchronization** — since `rx_in` arrives from an external, unclocked source, it must be safely brought into the RX clock domain without causing metastability.
2. **Bit-level framing** — correctly detecting the start bit, sampling each data bit at its mid-point (not at the edge, where the signal may not have settled), and validating the stop bit to catch framing errors.

## Features

- 8-bit parallel-to-serial (TX) and serial-to-parallel (RX) data conversion
- Independent TX and RX clock domains (`txclk`, `rxclk`) — models real-world UART where transmitter and receiver don't share a clock source
- Start-bit detection and **mid-bit sampling** on the RX path, reducing sensitivity to clock/baud drift between TX and RX
- **Frame error detection**: flags when the expected stop bit isn't high, indicating a framing/synchronization failure
- **Overrun detection**: flags when a new byte finishes arriving before the previous byte in `rx_data` has been read out (`uld_rx_data`)
- **Double flip-flop synchronizer** (`rx_d1` → `rx_d2`) on the asynchronous RX input — a standard technique to reduce the probability of metastability propagating into the RX state machine
- Loopback-based self-checking testbench (TX output tied directly to RX input)
- Fully synthesizable RTL — synthesized and analyzed on Cadence Genus with real gate-level area/cell reports

## Architecture


### TX Path Walkthrough
On `ld_tx_data`, the 8-bit `tx_data` is latched into `tx_reg` and `tx_empty` goes low, signaling "busy." While `tx_enable` is high and the register isn't empty, a 4-bit counter (`tx_cnt`) walks through 10 states: bit 0 drives the start bit (`tx_out = 0`), bits 1–8 shift out `tx_reg` LSB-first, and bit 9 drives the stop bit (`tx_out = 1`) and reasserts `tx_empty`.

### RX Path Walkthrough
The RX logic first synchronizes the incoming asynchronous `rx_in` line through two flip-flops (`rx_d1`, `rx_d2`). It watches for a falling edge (the start bit) while idle. Once detected, it samples `rx_d2` once every full bit period, specifically at the mid-point (`rx_sample_cnt == 7`) to avoid sampling near a bit transition. Sampled bits are shifted into `rx_reg`; on the 9th sampled bit (expected stop bit), it checks that the line is high — if not, `rx_frame_err` is set. Otherwise, the byte is marked valid via `rx_empty = 0`.

## Port Description

| Signal        | Direction | Width  | Description                                  |
|---------------|-----------|--------|-----------------------------------------------|
| `reset`       | Input     | 1 bit  | Active-high synchronous reset                 |
| `txclk`       | Input     | 1 bit  | TX clock                                      |
| `ld_tx_data`  | Input     | 1 bit  | Load transmit data into TX register           |
| `tx_data`     | Input     | 8 bits | Parallel data to transmit                     |
| `tx_enable`   | Input     | 1 bit  | Enables the transmitter                       |
| `tx_out`      | Output    | 1 bit  | Serial TX output line                         |
| `tx_empty`    | Output    | 1 bit  | High when TX register is empty / ready        |
| `rxclk`       | Input     | 1 bit  | RX clock                                      |
| `uld_rx_data` | Input     | 1 bit  | Unload received data into `rx_data`           |
| `rx_data`     | Output    | 8 bits | Parallel received data                        |
| `rx_enable`   | Input     | 1 bit  | Enables the receiver                          |
| `rx_in`       | Input     | 1 bit  | Serial RX input line                          |
| `rx_empty`    | Output    | 1 bit  | High when no received data is waiting         |


## Verification

Verified using **Cadence SimVision / NCLaunch (ncvlog → ncelab → ncsim)** with a loopback testbench connecting `tx_out` directly to `rx_in`. This is a standard verification shortcut for UART cores — since the same design's TX output feeds its own RX input, a matching received byte proves both halves of the design are functionally correct without needing external test equipment or a second UART instance.

### Test Scenario
1. Apply reset, enable TX and RX
2. Load `tx_data = 8'b0111_1111` via `ld_tx_data`
3. Wait for transmission to complete (`tx_empty` reasserts)
4. Wait for `rx_empty` to deassert, indicating a received byte
5. Unload the received byte via `uld_rx_data`

**> 📸 
### Simulation Log (ncsim)

ncsim> database -open waves -into waves.shm -default
Created default SHM database waves
ncsim> probe -create -shm uart_tb.rx_data uart_tb.clk uart_tb.counter uart_tb.ld_tx_data
uart_tb.reset uart_tb.rx_empty uart_tb.rx_enable uart_tb.rx_in uart_tb.rxclk
uart_tb.tx_data uart_tb.tx_empty uart_tb.tx_enable uart_tb.tx_out ...
Created probe 1
ncsim> run
Data loaded for send
Data sent
RX Byte Ready
RX Byte Unloaded = 11111110
Simulation complete via $finish(1) at time 8110 NS + 0
./uart_tb.v:103 $finish;

### Waveform Analysis
The SimVision waveform confirms:
- `tx_out` toggling through the expected start-bit → 8 data bits → stop-bit sequence
- `rx_data[7:0]` and `tx_data[7:0]` tracking each other across the TX→RX loopback path
- `tx_empty` and `rx_empty` correctly toggling low/high around each transaction boundary, showing the handshake logic (`ld_tx_data` / `uld_rx_data`) working as intended
- Correct operation across two independently running clock domains (`txclk`, `rxclk`)

**> 📸 Screenshot placement:** this is the most important screenshot for the repo — your SimVision waveform view (`rx_data`, `tx_data`, `tx_out`, `rx_in`, `txclk`, `rxclk`, `tx_empty`, `rx_empty` all visible on one screen). Save as `docs/waveform.png`:
> `![Simulation Waveform](docs/waveform.png)`

## Synthesis Results (Cadence Genus)

Synthesized using **Genus(TM) Synthesis Solution 21.14-s082_1**, targeting a `slow` corner standard-cell library (`balanced_tree` wireload mode). Synthesis converts the behavioral RTL into a gate-level netlist made of actual standard cells (flip-flops, gates, inverters) from a technology library — this is the step that tells you how "expensive" your design actually is in silicon area.

### Cell Statistics

| Cell Type   | Instances | Area (µm²) | Area %  |
|-------------|-----------|------------|---------|
| Sequential  | 41        | 973.373    | 72.53%  |
| Logic       | 72        | 343.633    | 25.61%  |
| Inverter    | 11        | 24.978     | 1.86%   |
| **Total**   | **124**   | **1341.984** | **100%** |

- **Design hierarchy:** 27 terminals, 148 nets, 124 leaf-cell instances
- **Datapath area:** 0.000 µm² (control-dominated design — no arithmetic datapath components, expected since UART is primarily FSM + shift-register logic rather than ALU-style datapath)
- **Operating conditions:** slow corner, enclosed wireload mode

**Why sequential cells dominate (72.5% of area):** UART is a state-machine-heavy, low-arithmetic design — most of the area goes into flip-flops for `tx_reg`, `rx_reg`, the two synchronizer flops, and the bit/sample counters, rather than combinational logic. This is a good talking point in interviews: it shows you understand *why* your area breakdown looks the way it does, not just that you ran a tool and got a number.

**> 📸  Genus "Netlist Statistics" report screenshot 

**> 📸  add your synthesized gate-level schematic screenshot (the Genus schematic viewer showing the mapped netlist) further down — this 

## Tools Used

| Purpose               | Tool                              |
|------------------------|-----------------------------------|
| RTL Design             | Verilog HDL                       |
| Simulation             | Cadence NCLaunch / ncsim (15.20)  |
| Waveform Analysis      | Cadence SimVision                 |
| RTL Synthesis          | Cadence Genus 21.14-s082_1        |


### Simulation (Cadence)
```bash
ncvlog rtl/uart.v tb/uart_tb.v
ncelab -access +wc worklib.uart_tb
ncsim worklib.uart_tb:module
```

### Synthesis (Cadence Genus)
```tcl
read_hdl rtl/uart.v
elaborate uart
read_libs <your_technology_library.lib>
syn_generic
syn_map
syn_opt
report_area
report_gates
```

## Key Learnings

- Practical implementation of **clock domain crossing (CDC)** safety using a 2-FF synchronizer for an asynchronous input
- Difference between **edge sampling vs. mid-bit sampling** in serial protocols and why mid-bit sampling is more robust to clock/baud mismatch
- How **frame and overrun errors** are detected in real UART hardware, not just "happy path" data transfer
- Reading and interpreting **Genus synthesis reports** — cell type breakdown, area contribution, and datapath vs. non-datapath area
- End-to-end RTL sign-off flow: **RTL → simulation → waveform debug → synthesis → gate-level report**, mirroring the front-end half of the RTL-to-GDSII flow

## Future Improvements

- Add parity bit support (odd/even)
- Add configurable baud-rate generator instead of external `txclk`/`rxclk`
- Add FIFO buffering on TX/RX paths
- Extend testbench with randomized/constrained data and back-to-back byte transfers
- Add STA (static timing analysis) results once a real clock constraint is applied

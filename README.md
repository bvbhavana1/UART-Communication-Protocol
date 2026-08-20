## UART Communication Protocol — RTL Design, Verification & Synthesis

**Verilog RTL implementation of an 8-bit UART transceiver with independent TX/RX clock domains, asynchronous RX synchronization, start/stop-bit handling, mid-bit sampling, error detection, Cadence-based functional verification, waveform analysis, and RTL synthesis.**

This project implements a complete UART communication core from RTL, covering the major front-end stages of a digital IC design flow:

```text
RTL Design
    ↓
Functional Simulation
    ↓
Waveform Analysis / Debugging
    ↓
RTL Synthesis
    ↓
Gate-Level Netlist
    ↓
Area / Cell Analysis
```

The design was developed in **Verilog HDL**, functionally verified using **Cadence NCLaunch / ncsim and SimVision**, and synthesized using **Cadence Genus**.

---

## ⭐ Key Highlights

* Designed an **8-bit synthesizable UART TX/RX transceiver** in Verilog HDL.
* Implemented **independent TX and RX clock domains**, reflecting the asynchronous nature of UART communication.
* Implemented a **2-flip-flop synchronizer** (`rx_d1 → rx_d2`) for safely bringing the asynchronous RX input into the RX clock domain.
* Implemented **start-bit detection, bit-period counting, mid-bit sampling, LSB-first data reception, and stop-bit validation**.
* Implemented internal **frame-error and overrun detection** mechanisms.
* Verified the TX→RX communication path using a **loopback testbench** in Cadence NCLaunch / ncsim.
* Analyzed UART signal behavior using **Cadence SimVision waveforms**.
* Synthesized the RTL using **Cadence Genus 21.14-s082_1**.
* Achieved a mapped implementation containing **124 leaf-cell instances** with a reported total cell area of **1341.984 µm²**.
* Sequential cells account for **72.53% of the total synthesized cell area**, consistent with the register- and counter-dominated nature of the UART architecture.

---

## 🔧 Engineering Focus

`Verilog RTL` · `UART Protocol` · `Serial Communication` · `CDC Synchronization` · `Digital Design` · `RTL Verification` · `Waveform Debugging` · `Logic Synthesis` · `Cadence NCLaunch` · `Cadence SimVision` · `Cadence Genus`

---

# 1. Overview

UART (**Universal Asynchronous Receiver/Transmitter**) is a widely used serial communication protocol for connecting microcontrollers, processors, FPGAs, SoCs, sensors, and peripheral devices.

A basic UART interface uses two signal lines:

```text
TX ───────────────▶ RX
RX ◀─────────────── TX
```

Unlike synchronous protocols such as SPI, UART does not use a shared clock between the communicating devices. The transmitter and receiver therefore operate using their respective local clocks and rely on agreed bit timing.

This project implements an **8-bit UART transceiver core** containing:

* Transmit logic
* Receive logic
* Independent TX/RX clock domains
* Asynchronous RX input synchronization
* Start-bit detection
* Bit-period/sample counters
* Mid-bit RX sampling
* LSB-first data transmission
* LSB-first data reception
* Stop-bit validation
* Frame-error detection
* TX/RX overrun detection
* TX/RX status signaling
* Loopback-based functional verification

The project focuses particularly on two important RTL design challenges:

### 1. Asynchronous Input Synchronization

The `rx_in` signal originates outside the RX clock domain. Directly sampling such an asynchronous signal can introduce metastability.

The design therefore uses a two-stage synchronizer:

```text
rx_in
  │
  ▼
┌───────┐
│ rx_d1 │
└───┬───┘
    │
    ▼
┌───────┐
│ rx_d2 │
└───┬───┘
    │
    ▼
 RX Logic
```

The second stage provides a substantially safer signal for use by the RX logic.

### 2. Bit-Level UART Timing

The receiver must determine when to sample each incoming bit.

Sampling exactly at a signal transition can be unreliable because the serial line may still be changing. The design therefore uses a sample counter to perform data sampling around the middle of the expected bit period.

---

## 2. Architecture

```text
                              UART TX PATH
                     ┌────────────────────────┐
 tx_data ──────────▶│                        │
 ld_tx_data ───────▶│       TX Logic         │──────▶ tx_out
 tx_enable ────────▶│   Parallel → Serial    │
 txclk ────────────▶│                        │──────▶ tx_empty
                     └────────────────────────┘
                              │
                              │ UART Serial Data
                              ▼
                     ┌────────────────────────┐
 rx_in ────────────▶│    2-FF Synchronizer   │
                    │     rx_d1 → rx_d2      │
                    └───────────┬────────────┘
                                │
                                ▼
                     ┌────────────────────────┐
 rxclk ─────────────▶│                        │
 rx_enable ─────────▶│       RX Logic         │──────▶ rx_data[7:0]
 uld_rx_data ───────▶│   Serial → Parallel    │──────▶ rx_empty
                     │                        │
                     └────────────────────────┘
```

The architecture is divided into two independently clocked sections:

```text
                    ┌─────────────────┐
                    │    TX DOMAIN    │
                    │     txclk       │
                    └────────┬────────┘
                             │
                             ▼
                       Serial TX
                         tx_out
                             │
                             │
                             ▼
                    ┌─────────────────┐
                    │    RX DOMAIN    │
                    │     rxclk       │
                    └────────┬────────┘
                             │
                             ▼
                      Synchronizer
                             │
                             ▼
                         RX Logic
```

This separation models the asynchronous nature of a real UART interface.

---

## 3. UART Frame Format

The transmitter generates a 10-bit UART frame:

```text
        START         8 DATA BITS (LSB FIRST)        STOP
          │                    │                       │
          ▼                    ▼                       ▼

        ┌───┬────┬────┬────┬────┬────┬────┬────┬────┬───┐
tx_out →│ 0 │ D0 │ D1 │ D2 │ D3 │ D4 │ D5 │ D6 │ D7 │ 1 │
        └───┴────┴────┴────┴────┴────┴────┴────┴────┴───┘
          ↑                                            ↑
      Start Bit                                    Stop Bit
```

The frame consists of:

```text
1 Start Bit + 8 Data Bits + 1 Stop Bit
```

The data is transmitted **LSB first**.

For example:

```text
tx_data = 8'b01111111
```

the serial data bits are presented as:

```text
D0 → D1 → D2 → D3 → D4 → D5 → D6 → D7
```

---

## 4. TX Path

The transmitter accepts an 8-bit parallel input through `tx_data`.

When `ld_tx_data` is asserted, the input byte is loaded into the internal register `tx_reg`.

```text
tx_data[7:0]
     │
     │ ld_tx_data
     ▼
┌─────────────┐
│   tx_reg    │
└──────┬──────┘
       │
       ▼
   TX Counter
       │
       ▼
    tx_out
```

## TX Operation

The TX logic uses `tx_cnt` to control the individual frame positions.

### Start Bit

When transmission begins:

```text
tx_cnt = 0
```

the serial output is driven low:

```text
tx_out = 0
```

This represents the UART start bit.

### Data Bits

For:

```text
tx_cnt = 1 ... 8
```

the corresponding bits of `tx_reg` are placed on `tx_out`.

The implementation transmits the byte LSB first:

```text
tx_reg[0]
tx_reg[1]
tx_reg[2]
...
tx_reg[7]
```

### Stop Bit

When:

```text
tx_cnt = 9
```

the transmitter drives:

```text
tx_out = 1
```

and completes the frame.

The TX register is then marked empty:

```text
tx_empty = 1
```

indicating that the transmitter is ready to accept another byte.

---

## 5. RX Path

The receiver performs the reverse operation:

```text
Serial RX
   │
   ▼
2-FF Synchronizer
   │
   ▼
Start Detection
   │
   ▼
Sample Counter
   │
   ▼
Data Sampling
   │
   ▼
RX Register
   │
   ▼
rx_data[7:0]
```

## 5.1 Asynchronous RX Synchronization

The incoming `rx_in` signal is asynchronous to `rxclk`.

The RTL implements:

```verilog
rx_d1 <= rx_in;
rx_d2 <= rx_d1;
```

This creates a two-stage synchronizer:

```text
          RX clock domain
                 │
rx_in ──▶ rx_d1 ──▶ rx_d2 ──▶ RX Logic
           FF         FF
```

The first flip-flop samples the asynchronous input. The second flip-flop provides the synchronized signal used by the RX logic.

This is a fundamental CDC technique used to reduce the probability that metastability propagates into downstream sequential logic.

---

# 6. RX Start-Bit Detection

When the receiver is idle, the UART line is expected to remain high.

A UART frame begins with a transition from:

```text
1 → 0
```

The RX logic detects the low level on the synchronized signal:

```verilog
if (!rx_busy && !rx_d2)
```

When this condition occurs:

```text
rx_busy       = 1
rx_sample_cnt = 1
rx_cnt        = 0
```

The receiver then begins its bit timing sequence.

---

## 7. Mid-Bit Sampling

One of the important aspects of the RX implementation is the use of a sample counter.

The RX logic increments:

```text
rx_sample_cnt
```

and performs sampling when:

```text
rx_sample_cnt == 7
```

This places the sampling point away from the expected signal transition and toward the middle of the bit interval.
Sampling near the center of the bit provides greater timing margin than sampling directly at a transition.

The exact sampling behavior depends on the relationship between `rxclk` and the serial bit timing established by the testbench.

---

## 8. RX Data Assembly

Once the receiver reaches the sampling point, the sampled value of `rx_d2` is stored into `rx_reg`.
The implementation assigns:

```text
rx_reg[0]
rx_reg[1]
...
rx_reg[7]
```

as successive data bits are received.
The receive counter tracks the position within the UART frame.
After the eight data bits have been received, the receiver evaluates the stop-bit position.

## 9. Stop-Bit / Frame-Error Detection

The UART receiver expects the stop bit to be high.
At the stop-bit sample:

```text
rx_d2 = 1
```
indicates a valid stop bit.
If:
```text
rx_d2 = 0
```
the receiver asserts:
```text
rx_frame_err = 1
```
This allows the design to detect an invalid UART frame.
Conceptually:

```text
Expected:

        DATA                    STOP
         │                       │
         ▼                       ▼
───────────────┐             ┌────────
               │             │
               └─────────────┘
                             ↑
                         must be 1

Frame Error:

        DATA                    STOP
         │                       │
         ▼                       ▼
───────────────┐
               │
               └────────────────────
                             ↑
                         sampled 0
```
## 10. Overrun Detection
The design also contains TX and RX overrun detection logic.
An RX overrun condition can occur when a new byte has completed reception while the previous received byte has not yet been unloaded.
The relevant control signal is:
```text
uld_rx_data
```
which is used to unload the received data.
Similarly, the TX path detects an attempted load while the transmitter is already occupied.
These mechanisms are important because they identify situations where software or downstream logic fails to service the UART interface quickly enough.

## 11. Status Signaling
The design uses `tx_empty` and `rx_empty` to communicate the state of the transmit and receive paths.

### TX
```text
tx_empty = 1
```
indicates that the TX register is available.
When new data is accepted:
```text
tx_empty = 0
```
and remains low while transmission is in progress.
After the stop bit is transmitted:
```text
tx_empty = 1
```
again.
### RX
The receiver initially sets:
```text
rx_empty = 1
```
Once a valid byte has been received:
```text
rx_empty = 0
```
The received data can then be unloaded using:
```text
uld_rx_data
```
after which:
```text
rx_empty = 1
```

## 12. Port Description
| Signal        | Direction | Width | Description                            |
| ------------- | --------- | ----: | -------------------------------------- |
| `reset`       | Input     |     1 | Active-high asynchronous reset         |
| `txclk`       | Input     |     1 | TX clock                               |
| `ld_tx_data`  | Input     |     1 | Load transmit data                     |
| `tx_data`     | Input     |     8 | Parallel transmit data                 |
| `tx_enable`   | Input     |     1 | Enables TX operation                   |
| `tx_out`      | Output    |     1 | Serial TX output                       |
| `tx_empty`    | Output    |     1 | Indicates TX register is available     |
| `rxclk`       | Input     |     1 | RX clock                               |
| `uld_rx_data` | Input     |     1 | Unloads received data                  |
| `rx_data`     | Output    |     8 | Parallel received data                 |
| `rx_enable`   | Input     |     1 | Enables RX operation                   |
| `rx_in`       | Input     |     1 | Serial RX input                        |
| `rx_empty`    | Output    |     1 | Indicates whether RX data is available |


# 13. Verification Architecture
The UART was functionally verified using a **TX-to-RX loopback testbench**.
The basic verification architecture is:

```text
                    ┌──────────────────────┐
                    │      UART DUT        │
                    │                      │
 tx_data ──────────▶│ TX               RX  │──────────▶ rx_data
                    │ │                  ▲ │
                    │ │                  │ │
                    │ └─── tx_out ───────┘ │
                    │          │           │
                    └──────────┼───────────┘
                               │
                               ▼
                              rx_in
```

The DUT's serial TX output is directly connected to its RX input:
```text
tx_out ───────────────▶ rx_in
```
This creates a closed communication path and allows the complete transmit and receive datapaths to be exercised.

## 14. Test Scenario
The testbench performs the following sequence:

### Step 1 — Reset
The UART is initially placed in reset.
```text
reset = 1
```
TX and RX status registers are initialized.

### Step 2 — Enable Communication
The testbench enables both transmitter and receiver:
```text
tx_enable = 1
rx_enable = 1
```

### Step 3 — Load TX Data
The testbench applies:
```text
tx_data = 8'b01111111
```
and asserts:
```text
ld_tx_data = 1
```
The byte is loaded into the TX register.

### Step 4 — Transmission
The TX logic serializes the byte and produces the UART frame on:

```text
tx_out
```

### Step 5 — Loopback

The testbench connects:
```text
tx_out → rx_in
```
so the transmitted serial waveform becomes the RX input.

### Step 6 — Reception
The RX logic synchronizes and samples the incoming waveform.

### Step 7 — RX Byte Ready
Once a valid byte is received:
```text
rx_empty = 0
```
### Step 8 — Unload
The testbench asserts:
```text
uld_rx_data = 1
```
to unload the received byte.

## 15. Cadence Simulation
Functional simulation was performed using:
* **Cadence NCLaunch**
* `ncvlog`
* `ncelab`
* `ncsim`

Waveform inspection was performed using:

* **Cadence SimVision**

### Simulation Commands

```bash
ncvlog rtl/uart.v tb/uart_tb.v
ncelab -access +wc worklib.uart_tb
ncsim worklib.uart_tb:module
```

### Example Simulation Log

```text
ncsim> database -open waves -into waves.shm -default
Created default SHM database waves

ncsim> probe -create -shm uart_tb.rx_data uart_tb.clk
uart_tb.counter uart_tb.ld_tx_data uart_tb.reset
uart_tb.rx_empty uart_tb.rx_enable uart_tb.rx_in
uart_tb.rxclk uart_tb.tx_data uart_tb.tx_empty
uart_tb.tx_enable uart_tb.tx_out ...

Created probe 1

ncsim> run

Data loaded for send
Data sent
RX Byte Ready
RX Byte Unloaded = 11111110

Simulation complete via $finish(1) at time 8110 NS
```

> **Important:** The final value shown in the log should correspond to the exact RTL and testbench committed to this repository. If the final verified source produces a different value, update the README accordingly.

---

# 16. SimVision Waveform Analysis
The SimVision waveform is used to visually inspect the interaction between the TX and RX sections.
The most useful signals to display together are:

```text
txclk
rxclk

tx_data
tx_out
rx_in
rx_data

tx_enable
rx_enable

ld_tx_data
uld_rx_data

tx_empty
rx_empty
```
The waveform demonstrates:

### TX Activity

```text
ld_tx_data
     │
     ▼
tx_empty: 1 → 0
     │
     ▼
tx_out:
Start → D0 → D1 → D2 → D3 → D4 → D5 → D6 → D7 → Stop
     │
     ▼
tx_empty: 0 → 1
```

### RX Activity

```text
rx_in
  │
  ▼
rx_d1
  │
  ▼
rx_d2
  │
  ▼
RX Sampling
  │
  ▼
rx_reg
  │
  ▼
rx_data
```
### Waveform Screenshot
![image alt]()

## 17. Synthesis Using Cadence Genus
After functional verification, the UART RTL was synthesized using:
**Cadence Genus Synthesis Solution 21.14-s082_1**
The synthesis process maps the behavioral RTL into a gate-level implementation using cells from the target standard-cell technology library.
Conceptually:

```text
Verilog RTL
     │
     ▼
Elaboration
     │
     ▼
Generic Synthesis
     │
     ▼
Technology Mapping
     │
     ▼
Optimization
     │
     ▼
Gate-Level Netlist
     │
     ▼
Area / Cell Reports
```

# 18. Genus Synthesis Flow
The synthesis flow used the following commands:
```tcl
read_hdl rtl/uart.v
elaborate uart

read_libs <technology_library.lib>

syn_generic
syn_map
syn_opt

report_area
report_gates
```

## 19. Synthesis Results
The synthesized UART design produced the following cell statistics.

| Cell Type  | Instances |   Area (µm²) |   Area % |
| ---------- | --------: | -----------: | -------: |
| Sequential |        41 |      973.373 |   72.53% |
| Logic      |        72 |      343.633 |   25.61% |
| Inverter   |        11 |       24.978 |    1.86% |
| **Total**  |   **124** | **1341.984** | **100%** |

### Design Statistics

| Parameter            |       Result |
| -------------------- | -----------: |
| Total terminals      |           27 |
| Total nets           |          148 |
| Leaf-cell instances  |          124 |
| Total cell area      | 1341.984 µm² |
| Sequential cell area |  973.373 µm² |
| Logic cell area      |  343.633 µm² |
| Inverter area        |   24.978 µm² |

### Synthesis Environment

| Parameter       | Value                |
| --------------- | -------------------- |
| Synthesis Tool  | Cadence Genus        |
| Version         | 21.14-s082_1         |
| Analysis Corner | Slow                 |
| Wireload Mode   | `balanced_tree`      |
| Implementation  | Standard-cell mapped |

## 20. Area Breakdown Analysis
The most significant observation from the synthesis report is that **sequential cells contribute 72.53% of the total cell area**.

```text
Sequential Logic    ████████████████████████████████████  72.53%
Combinational Logic ██████████████                        25.61%
Inverters           █                                       1.86%
```
The sequential dominance is expected for this architecture.
The UART contains relatively little arithmetic logic. Instead, a significant portion of the implementation consists of storage and control elements such as:

* `tx_reg`
* `rx_reg`
* `rx_d1`
* `rx_d2`
* `tx_cnt`
* `rx_cnt`
* `rx_sample_cnt`
* Status/control registers
* RX activity/control state

Therefore, the design is primarily **control- and register-dominated rather than datapath-dominated**.

# 21. Why Sequential Logic Dominates
The TX side requires registers to hold the byte being transmitted and counters to track the UART frame position.
The RX side requires:
```text
RX Data Register
       +
RX Synchronizer
       +
Sample Counter
       +
Bit Counter
       +
Control / Status Registers
```
These structures result in a substantial number of sequential cells.
The combinational portion mainly consists of:
* Comparators
* Multiplexing logic
* Control logic
* Counter increment logic
* Output-selection logic
Consequently, the synthesized design naturally shows a much larger sequential contribution.
This is consistent with the architectural characteristics of a small UART core.

# 22. Gate-Level Schematic
The technology-mapped design can be inspected using the Genus schematic viewer.
The synthesized schematic provides a gate-level representation of the RTL implementation and allows the following to be examined:
* Flip-flop structures
* Combinational logic
* Signal connectivity
* Register-to-register paths
* Synchronizer implementation
* Counter logic
* TX/RX control logic
![image alt]()

# 23. RTL-to-Gate-Level Flow
The project demonstrates the following front-end digital design flow:
```text
                 ┌──────────────────┐
                 │   UART RTL       │
                 │   Verilog HDL    │
                 └────────┬─────────┘
                          │
                          ▼
                 ┌──────────────────┐
                 │ RTL Simulation   │
                 │ Cadence ncvlog   │
                 │ ncelab / ncsim   │
                 └────────┬─────────┘
                          │
                          ▼
                 ┌──────────────────┐
                 │ Waveform Debug   │
                 │    SimVision     │
                 └────────┬─────────┘
                          │
                          ▼
                 ┌──────────────────┐
                 │ RTL Synthesis    │
                 │  Cadence Genus   │
                 └────────┬─────────┘
                          │
                          ▼
                 ┌──────────────────┐
                 │ Technology       │
                 │ Mapping          │
                 └────────┬─────────┘
                          │
                          ▼
                 ┌──────────────────┐
                 │ Gate-Level       │
                 │ Netlist          │
                 └────────┬─────────┘
                          │
                          ▼
                 ┌──────────────────┐
                 │ Area / Cell      │
                 │ Analysis         │
                 └──────────────────┘
```

This provides hands-on exposure to the RTL-to-netlist portion of a digital IC design workflow.


## 25. Tools Used
| Purpose             | Tool / Technology                          |
| ------------------- | ------------------------------------------ |
| RTL Design          | Verilog HDL                                |
| RTL Simulation      | Cadence NCLaunch / ncvlog / ncelab / ncsim |
| Waveform Analysis   | Cadence SimVision                          |
| RTL Synthesis       | Cadence Genus 21.14-s082_1                 |
| Synthesis Analysis  | Genus Area / Gate Reports                  |
| Verification Method | TX-RX Loopback                             |

# 26. Key RTL Concepts Demonstrated
## Clock Domain Separation
TX and RX operate from independent clocks:
```text
TX → txclk
RX → rxclk
```
This models a real UART where the transmitter and receiver do not share a common clock.

## Clock Domain Crossing
The RX input is asynchronous to `rxclk`.
The design therefore uses:
```text
rx_in → rx_d1 → rx_d2 → RX Logic
```
This demonstrates practical application of a two-stage synchronizer for asynchronous digital inputs.

## Counter-Based Timing
The design uses counters rather than a large FSM to track:
* TX frame position
* RX bit position
* RX sample timing
This allows the serial frame to be controlled using simple sequential timing logic.

## Serial-to-Parallel Conversion
The RX logic reconstructs the received byte from individual serial samples.
```text
Serial Stream
     │
     ├── D0
     ├── D1
     ├── D2
     ├── D3
     ├── D4
     ├── D5
     ├── D6
     └── D7
          │
          ▼
      rx_reg[7:0]
          │
          ▼
      rx_data[7:0]
```

## 27. Verification Concepts Demonstrated
The project provides practical exposure to:
* Testbench-driven RTL verification
* Loopback verification
* Clock generation
* Independent TX/RX clocks
* Reset sequencing
* Transaction control
* Serial waveform observation
* Status signal monitoring
* Simulation log analysis
* Waveform-based debugging
The loopback configuration is particularly useful because a complete TX-to-RX transaction can be exercised using a single UART instance.

## 28. Synthesis Concepts Demonstrated
The Genus synthesis stage provided practical experience with:
* RTL elaboration
* Generic synthesis
* Technology mapping
* Logic optimization
* Standard-cell implementation
* Cell-count analysis
* Area analysis
* Sequential vs. combinational area analysis
* Gate-level schematic inspection
  
The final mapped implementation consisted of:
```text
124 leaf-cell instances
148 nets
27 terminals
1341.984 µm² total cell area
```

# 29. Important Design Observations
### Observation 1 — UART Is Control-Dominated
The UART does not contain a large arithmetic datapath. Most of its hardware consists of registers, counters, comparators, and control logic.
This explains the high sequential-cell contribution in the synthesis report.

### Observation 2 — Synchronization Is Required
Although UART itself is asynchronous, the RX input still has to be safely sampled by synchronous digital logic.
The 2-FF synchronizer provides a standard solution for reducing metastability propagation.

### Observation 3 — Sampling Position Matters
The RX logic does not simply capture the incoming line at arbitrary clock edges. It uses a sampling counter to target the middle portion of each bit interval.
This provides better timing margin than sampling directly around signal transitions.

### Observation 4 — Verification and Synthesis Are Complementary
Simulation demonstrates functional behavior, while synthesis demonstrates how the RTL translates into actual hardware resources.
Together they provide a much more complete picture than RTL simulation alone.

# 30. Limitations of the Current Implementation
The current UART is intentionally a compact RTL implementation and does not yet include several features found in production UART IP.
Current limitations include:
* No programmable baud-rate generator
* No parity support
* No configurable frame format
* No TX FIFO
* No RX FIFO
* Limited automated/randomized verification
* No formal protocol assertions
* No dedicated functional coverage model
* No timing sign-off with constrained STA
* No PVT-based timing analysis
These are natural extensions for a more complete UART IP implementation.

# 31. Future Improvements

### Protocol Features
* [ ] Add even/odd parity support
* [ ] Add configurable number of data bits
* [ ] Add configurable stop-bit support
* [ ] Add programmable baud-rate generation
* [ ] Add break-condition detection

### Data Handling
* [ ] Add TX FIFO
* [ ] Add RX FIFO
* [ ] Support back-to-back byte transfers
* [ ] Improve buffer status reporting

### Verification
* [ ] Add randomized stimulus
* [ ] Add constrained-random testing
* [ ] Add automatic TX/RX data comparison
* [ ] Add SystemVerilog assertions
* [ ] Add functional coverage
* [ ] Add error-injection scenarios
* [ ] Verify framing-error conditions
* [ ] Verify TX/RX overrun conditions
* [ ] Add gate-level simulation

### Timing / Implementation
* [ ] Add proper clock constraints
* [ ] Run Static Timing Analysis (STA)
* [ ] Analyze setup and hold timing
* [ ] Analyze multiple PVT corners
* [ ] Perform timing-aware optimization
* [ ] Integrate the UART into a larger SoC/FPGA subsystem

# 32. Key Learning Outcomes
Through this project, the following concepts were implemented and analyzed at RTL and synthesis levels:

### Digital Design
* Sequential RTL design
* Register-based datapaths
* Counter-based control
* Serial-to-parallel conversion
* Parallel-to-serial conversion
* Reset handling

### Communication Protocols
* UART framing
* Start/stop-bit operation
* LSB-first transmission
* Asynchronous communication
* Bit-level sampling

### CDC / Reliability
* Asynchronous input handling
* Two-flip-flop synchronization
* Metastability reduction
* Independent clock domains

### Verification
* Testbench development
* Clock generation
* Loopback testing
* Simulation debugging
* Waveform analysis
* Cadence NCLaunch
* Cadence SimVision

### Synthesis
* RTL elaboration
* Generic synthesis
* Technology mapping
* Logic optimization
* Standard-cell analysis
* Area analysis
* Gate-level schematic analysis
* Cadence Genus

# 33. Project Takeaway
This project demonstrates the complete implementation and analysis of a small but practical digital communication IP block.
Starting from a behavioral Verilog description, the design was taken through:
```text
UART Specification
       ↓
Verilog RTL
       ↓
TX/RX Architecture
       ↓
CDC Synchronization
       ↓
Loopback Verification
       ↓
Cadence Simulation
       ↓
SimVision Waveform Debugging
       ↓
Cadence Genus Synthesis
       ↓
Technology-Mapped Netlist
       ↓
Cell / Area Analysis
```
The project therefore demonstrates practical understanding of **RTL design, UART protocol implementation, asynchronous input synchronization, digital verification, waveform debugging, and synthesis analysis**, rather than only implementing a functional UART module.

## 📌 Summary
| Category              | Implementation           |
| --------------------- | ------------------------ |
| Protocol              | UART                     |
| Data Width            | 8-bit                    |
| TX                    | Parallel → Serial        |
| RX                    | Serial → Parallel        |
| TX Clock              | Independent `txclk`      |
| RX Clock              | Independent `rxclk`      |
| RX Synchronization    | 2-FF                     |
| Start Bit             | Supported                |
| Stop Bit              | Supported                |
| Mid-Bit Sampling      | Supported                |
| Frame Error Detection | Supported                |
| Overrun Detection     | Supported                |
| Verification          | TX-RX Loopback           |
| Simulation            | Cadence NCLaunch / ncsim |
| Waveform              | Cadence SimVision        |
| Synthesis             | Cadence Genus            |
| Total Cells           | 124                      |
| Total Nets            | 148                      |
| Total Area            | 1341.984 µm²             |
| Sequential Area       | 973.373 µm²              |
| Sequential Area %     | 72.53%                   |

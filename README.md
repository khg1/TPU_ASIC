# NPU-ASIC

A fixed-point neural processing unit in SystemVerilog, built around an 8×8
weight-stationary systolic array with vector post-processing and LUT-based
activation functions.

This repository holds the NPU/TPU compute datapath. The ANN (IRIS classifier +
AXI SoC) design lives in its own separate repository.

---

## Architecture

`npu_core` chains three compute stages into a single inference transaction:

```
                  weights ─┐
  data_in ──► [ CAPTURE ]  ├─► [ systolic_array ] ──► [ vector_unit ] ──► [ activation_unit ] ──► data_out
   (valid)      buffers    │      8×8 MAC grid          bias / scale         ReLU / GELU        (out_valid)
                  acts ────┘     weight-stationary       + saturation         / Sigmoid
                  bias
```

| Stage | Function |
| --- | --- |
| `systolic_array` | `result[c] = Σ_r act[r] · W[r][c]` — 8×8 grid of MAC processing elements, weight-stationary, activations skewed in by per-row shift registers |
| `vector_unit` | Per-lane `ADD` (bias), `MUL` (gain), or `SCALE`, with saturation into Q8.8 range |
| `activation_unit` | ReLU exactly; GELU / Sigmoid via 256-entry Q8.8 lookup table with linear interpolation |

The core FSM sequences: `IDLE → CAPTURE → LOADW → MAC → VECTOR → ACTIVATION → IDLE`.

---

## Number format — Q8.8

All datapath values are **Q8.8 fixed point**: 16 bits total, 8 integer bits
(including sign, two's complement) and 8 fractional bits. A raw value `v`
represents `v / 256`.

| | Value |
| --- | --- |
| Range | −128.0 … +127.99609375 |
| Resolution | 1/256 ≈ 0.0039 |
| `0x7FFF` | +127.996 (Q_MAX) |
| `0x8000` | −128.0 (Q_MIN) |
| `0x0100` | +1.0 |

Multiplying two Q8.8 values yields Q16.16, so products are shifted right by 8
(`>>> 8`) to return to Q8.8. Accumulators are 32 bits wide (`ACC_WIDTH`) to hold
un-saturated MAC results; the vector unit saturates them back into Q8.8 range
before activation.

---

## Repository layout

```
rtl/                        synthesizable design
  npu_core.sv                 top level: beat capture, FSM, pipeline
  systolic_array.sv           8×8 MAC grid + weight loading
  processing_element.sv       single MAC cell
  shift_register.sv           parameterized delay line (activation skew)
  vector_unit.sv              ADD / MUL / SCALE with saturation
  activation_unit.sv          ReLU / GELU / Sigmoid (LUT + interpolation)

tb/                         self-checking testbenches (plain SystemVerilog)
  tb_systolic.sv              systolic array vs. reference dot-product model
  tb_vector_unit.sv           all ops, saturation corners, random regression
  tb_npu_core.sv              full end-to-end transaction vs. software model

uvm/ACT_UNIT/               UVM environment for activation_unit
sva/activation_sva.sv       assertions bound into activation_unit

LUT/                        activation lookup tables
  gelu.py sigmoid.py exp.py   generators (write ./lut/*.hex)
  lut/*.hex                   256-entry Q8.8 tables

Simulation/Makefile         VCS compile/run flow
```

---

## Transaction protocol

With default parameters (`DATA_WIDTH=32`, `GRID_DIM=8`, `WT_WIDTH=ACT_WIDTH=8`,
`ACC_WIDTH=32`), one inference is **26 beats** on `data_in`, each qualified by
`valid`, streamed after `ready` goes high:

| Beats | Content | Packing |
| --- | --- | --- |
| 0 – 15 | Weights, row-major | 4 weights per beat, lowest byte = lowest column |
| 16 – 17 | Activations | 4 per beat, lowest byte = lowest lane |
| 18 – 25 | Bias | one sign-extended 32-bit Q8.8 word per beat, lane 0 first |

`vec_op_sel`, `act_fn_sel`, and `vect_scale` must be held stable for the whole
transaction. Results appear on `data_out` qualified by a **one-cycle
`out_valid` pulse**, and hold until the next transaction.

### Operation encodings

| `vec_op_sel` | Vector op | | `act_fn_sel` | Activation |
| --- | --- | --- | --- | --- |
| `2'b00` | `ADD` — bias + accumulator | | `2'b00` | ReLU |
| `2'b01` | `MUL` — bias × accumulator (Q8.8) | | `2'b01` | GELU |
| `2'b10` | `SCALE` — bias × `vect_scale` | | `2'b10` | Sigmoid |

---

## Running simulations

All flows run from `Simulation/`. This directory matters: the RTL and
testbenches load `../LUT/lut/*.hex` relative to the simulation run directory.

```bash
cd Simulation

make tb_systolic     # systolic array testbench
make tb_vector       # vector unit testbench
make tb_npu          # end-to-end npu_core testbench
make tb_all          # all three

make all             # UVM activation_unit regression (compile + run)
make verdi           # open waves/coverage in Verdi
make clean           # remove build artifacts
```

Each module testbench prints, per test, the input stimulus, the expected value
from an independent reference model, the actual DUT output, and PASS/FAIL per
lane, followed by a summary:

```
[TEST 4] positive saturation (mac = 129032 -> 32767)  (vec_op=ADD, act_fn=RELU)
  activations :    127    127 ...
  lane      expected       actual   status
  0            32767        32767   PASS
  ...
  => TEST PASSED
```

---

## Regenerating the activation LUTs

```bash
cd LUT
python gelu.py        # -> lut/gelu_q88.hex
python sigmoid.py     # -> lut/sigmoid_q88.hex
python exp.py         # -> lut/exp_q88.hex
```

Each table has 256 entries of Q8.8, addressed by the **raw two's-complement
upper byte** of the input: index `0x00`–`0x7F` covers x = 0…+127 and `0x80`–`0xFF`
covers x = −128…−1. The activation unit interpolates between adjacent entries
using the lower byte as the fractional weight. The `0xFF → 0x00` wrap is the
correct neighbour step (x = −1 → x = 0); only index `0x7F` (x = +127) is clamped.

---

## Verification status

| Block | Status |
| --- | --- |
| `activation_unit` | UVM regression passing (0 errors), full signed input range, SVA bound for latency/ready checks |
| `systolic_array` | Self-checking testbench: orientation, signed values, ±127/−128 extremes, random regression |
| `vector_unit` | Self-checking testbench: all ops, both saturation directions, random regression |
| `npu_core` | Self-checking end-to-end testbench: all activations, saturation corners, back-to-back and valid-gap transactions |

---

## Known limitations

- **Softmax is not implemented.** The code paths and `exp_q88.hex` exist but are
  commented out in `activation_unit.sv`; softmax needs a division by a runtime
  sum, which requires a reciprocal LUT or multi-cycle divider.
- **LUTs load via `$readmemh` in an `initial` block**, which is simulation/FPGA
  only. An ASIC target needs these synthesized as constant ROMs.
- **LUT paths are relative to the simulation run directory** (`../LUT/lut/…`),
  so simulations must be launched from `Simulation/`.

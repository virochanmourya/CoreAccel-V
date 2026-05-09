# The Engineering Crucible
### How We Fought Through Physical Silicon Realities to Close Timing at 100 MHz

---

## Preamble

This document is not about what the CoreAccel-V architecture *is*. That story is told in *The CoreAccel-V Architecture*. This document is about what the architecture *became* — and the four brutal encounters with physical FPGA reality that forged it.

Every digital design begins as an RTL simulation that works perfectly. The gap between "simulates correctly" and "meets timing on silicon" is where engineering happens. For CoreAccel-V, that gap was measured in nanoseconds, LUT fanout counts, and Vivado methodology violations. Each of the following sections describes a specific moment where the design hit a physical wall, the diagnostic process that identified the root cause, and the architectural decision that resolved it.

The battles are presented in chronological order — the order in which they were encountered during the implementation flow.

---

## Section 1: The Synthesis Annihilation

### The Problem

During the first attempt to run the Vivado implementation flow on the CoreAccel-V pipeline, the design passed synthesis without warnings — and then failed catastrophically at the `opt_design` stage with:

```
[Place 30-494] The design is empty.
```

The entire processor — 12 modules, hundreds of registers, the ALU, the MAC unit, the TCM, the forwarding unit — had been **completely optimized away**. The placed design contained zero logic, zero registers, zero BRAM.

### The Root Cause

Vivado's `opt_design` pass performs aggressive dead-logic elimination. It traces the design backward from every physical output pin. If an internal signal cannot influence any output pin, it is removed. In the initial design, `cpu_pipeline_top` had only two input ports (`clk`, `reset`) and **no output ports**. The processor was a closed system — it fetched instructions, executed them, and wrote results to the register file, but no internal value ever reached a physical I/O pin.

From the optimizer's perspective, the entire design was dead code.

### Rejected Alternatives

| Alternative | Why Rejected |
|-------------|-------------|
| Mark all registers with `(* DONT_TOUCH = "true" *)` | Prevents optimization globally; hostile to synthesis quality. Vivado cannot retime, replicate, or absorb registers it cannot touch. This is a sledgehammer that damages every path in the design, not just the dead-logic elimination. |
| Use `(* KEEP = "true" *)` on select signals | Finer-grained, but still fights the optimizer. Requires marking dozens of signals manually, and any omission results in partial removal. Fragile across design iterations. |
| Instantiate an ILA (Integrated Logic Analyzer) | Adds debug infrastructure that consumes BRAM and routing resources. Useful during debugging but creates a permanent dependency on Vivado's debug hub. Not appropriate for a production-path constraint. |

### The Correction: Anchor Logic

We added two 8-bit debug output buses to `cpu_pipeline_top`:

```systemverilog
output logic [7:0] debug_pc,       // Lower 8 bits of PC
output logic [7:0] debug_wb        // Lower 8 bits of WB data
```

These are connected to the 16 on-board LEDs of the Basys 3 via the XDC constraint file:

```tcl
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {debug_pc[0]}]
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports {debug_wb[0]}]
// ... (14 more pin assignments)
```

The key insight is **what these signals depend on**:

- `debug_pc = pc_current[7:0]` — The PC register drives instruction fetch, which drives decode, which drives the control unit, which drives the ALU, which drives the forwarding unit, which drives the hazard detection unit. By observing the PC, the optimizer must preserve the **entire front-end** of the pipeline.

- `debug_wb = wb_data[7:0]` — The write-back mux selects between the ALU result, the memory read data (from Data Memory or TCM BRAM), the MAC sliced result, and the PC+4 link address. By observing WB data, the optimizer must preserve **every execution path** in the processor, including the MAC unit, the TCM, and the register file.

Two 8-bit signals. Sixteen physical pins. The entire 12-module processor preserved.

The debug outputs are declared as false paths in the XDC (`set_false_path -to [get_ports {debug_pc[*]}]`) so they do not affect internal timing analysis. They serve purely as anchor logic — a dependency chain that keeps the synthesizer honest.

---

## Section 2: The BRAM Latency Hazard

### The Problem

The Tightly Coupled Memory is implemented using a Xilinx BRAM36E1 tile. Unlike the Data Memory (which uses distributed LUTRAM with combinational reads), BRAM has an inherent physical constraint: **all reads are synchronous**. The address is captured on the clock edge, and the data appears on the output port *after* the clock-to-output delay (Tco ≈ 1.5 ns for 7-series BRAM).

In the standard 5-stage pipeline, the memory address is computed in the EX stage, registered into the EX/MEM pipeline register, and presented to memory in the MEM stage. With BRAM, this creates a fatal timing problem:

```
Cycle N   (EX):   ALU computes address → registered into EX/MEM
Cycle N+1 (MEM):  ex_mem_alu_result presented to BRAM addra
                   At posedge: BRAM captures address, douta <= mem[addr]
                   At SAME posedge: MEM/WB latches douta — but douta is STALE
                   (it still holds the value from the PREVIOUS cycle's address)
Cycle N+2 (WB):   MEM/WB contains WRONG data ✗
```

The MEM/WB register and the BRAM output register update on the *same* clock edge. Due to non-blocking assignment semantics, MEM/WB sees the *old* `douta`, not the new one. The data arrives one cycle too late.

### Consequence

Without correction, every `LW` from TCM would return stale data. The only software workaround would be inserting a NOP after every TCM load — a crippling penalty that would halve the effective throughput of any load-heavy DSP kernel.

### Rejected Alternatives

| Alternative | Why Rejected |
|-------------|-------------|
| Add a 6th pipeline stage ("MEM2") for BRAM reads | Fundamentally changes the CPI model. All branch, forwarding, and hazard logic must be redesigned for a 6-stage pipeline. The MEM→EX forwarding path gains an extra cycle of latency. Massive architectural change for a single memory type. |
| Use `READ_FIRST` mode with additional output register | Adds another cycle of latency and a secondary output register outside the BRAM. Creates an asymmetry between TCM reads (2-cycle) and Data Memory reads (1-cycle) that complicates the WB mux and forwarding logic. |
| Switch TCM to distributed RAM (combinational read) | Destroys the purpose of using BRAM. A 1024×32-bit distributed RAM consumes ~500 LUT6 cells, creates massive fanout nets, and causes routing congestion. This is precisely the failure we experienced in Section 3. |

### The Correction: EX-Stage Address Presentation

We bypassed the EX/MEM register for TCM read addresses. Instead of waiting for the address to be registered in MEM, the ALU result is fed **combinationally** to the BRAM address port during the EX stage:

```systemverilog
assign tcm_addra = tcm_wea ? ex_mem_alu_result[11:2]  // Write: MEM stage (registered)
                           : alu_result[11:2];          // Read:  EX stage (combinational)
```

This shifts the BRAM address presentation one cycle earlier:

```
Cycle N   (EX):   ALU computes address → presented to BRAM addra (combinational)
                   At posedge: BRAM captures address, douta <= mem[addr]
Cycle N+1 (MEM):  douta now holds CORRECT data for the EX-stage address
                   At posedge: MEM/WB latches douta — CORRECT ✓
Cycle N+2 (WB):   MEM/WB contains correct data ✓
```

The BRAM's internal output register acts as a natural pipeline buffer between the EX and MEM stages. The 1-cycle latency is fully hidden.

**Why this is safe with BRAM**: The `alu_result → BRAM addra` path goes to **dedicated BRAM primitive address inputs** — not LUT-based address decoding. There is no fanout explosion. The routing is a single point-to-point connection from the ALU output to the BRAM tile's address pins. The BRAM setup time (~0.5 ns) is easily met within the 10 ns clock period.

For writes, the address comes from the registered MEM stage (`ex_mem_alu_result`) because the write data (`ex_mem_rs2_data`) is also in the MEM stage, and both must be presented simultaneously.

---

## Section 3: The Inference Failure & LUTRAM Explosion

### The Problem

With the architecture of Section 2 in place, we ran synthesis — and were greeted by **256 SYNTH-5 methodology violations**:

```
SYNTH-5: Mapped onto Distributed RAM due to timing constraints
    u_tcm/mem_reg_0_127_0_0    → RAM64X1D (Distributed)
    u_tcm/mem_reg_0_127_0_1    → RAM64X1D (Distributed)
    u_tcm/mem_reg_0_127_0_2    → RAM64X1D (Distributed)
    ... (253 more)
```

Despite the `(* ram_style = "block" *)` attribute on the memory array, Vivado had **refused to infer a BRAM36E1 tile** and instead decomposed the entire 1024×32-bit TCM into 256 RAMD64E distributed RAM cells.

### The Root Cause

The original `tcm_ram.sv` Port B had a cross-port RAW bypass:

```systemverilog
// Port B: Read-Only — WITH cross-port bypass (ORIGINAL)
always_ff @(posedge clkb) begin
    if (wea && (addra == addrb)) begin
        doutb <= dina;       // Forward new data from Port A
    end else begin
        doutb <= mem[addrb]; // Normal BRAM read
    end
end
```

This code is functionally correct in simulation. But Xilinx BRAM36E1 primitives have **fixed, hardwired cross-port collision behavior** defined by the `WRITE_MODE` parameter. They cannot implement arbitrary conditional forwarding between ports. The `if (wea && (addra == addrb))` condition requires an address comparator and a data mux that **do not exist inside the BRAM primitive**.

Vivado detected this incompatibility, silently overrode the `(* ram_style = "block" *)` attribute, and synthesized the entire memory as distributed LUTRAM.

### The Consequence: A Timing Catastrophe

The distributed RAM implementation had devastating physical consequences:

| Metric | Expected (BRAM) | Actual (Distributed) |
|--------|-----------------|---------------------|
| **Resource Usage** | 1 BRAM36E1 tile | ~512 LUT6 cells |
| **Address Decode** | Internal to BRAM (no LUTs) | LUT-based (external) |
| **Max Fanout** | N/A (internal routing) | **1,537** on address nets |
| **Read Path** | BRAM primitive → output register | RAMD64E → MUXF7 → LUT6 chain |

The address decode fanout of 1,537 was catastrophic. Every one of the 256 RAM64X1D cells needed its own copy of the address bits, creating a routing web that consumed the entire FPGA fabric around the TCM. The resulting critical path had **12–13 logic levels** and **~12 ns data path delay** — 2 ns beyond the 10 ns budget.

```
Timing Report (v1):
    WNS:              -2.024 ns
    TNS:              -784.527 ns
    Failing Endpoints: 1,178 / 12,846
    Logic Delay:       2.432 ns (20%)
    Route Delay:       9.471 ns (80%)  ← Routing-dominated (fanout explosion)
```

### The Correction: Clean BRAM Inference Template

We removed the cross-port bypass logic entirely and replaced it with a clean, BRAM-compatible read template:

```systemverilog
// Port B: Read-Only — CLEAN BRAM template (CORRECTED)
always_ff @(posedge clkb) begin
    doutb <= mem[addrb];
end
```

One line of SystemVerilog. The `if/else` conditional that checked `wea && (addra == addrb)` was deleted. The `always_ff` block now references only Port B signals (`clkb`, `addrb`), with no dependency on Port A signals.

This restored BRAM inference immediately. The synthesis report confirmed the mapping:

```
Timing Report (v2), Hold Path:
    Destination: u_tcm/mem_reg/DIADI[27]  → RAMB36E1  ← BRAM confirmed
```

The 256 SYNTH-5 violations vanished. The ~512 LUT6 cells were freed. The fo=1,537 routing web dissolved. WNS improved from **-2.024 ns to -0.833 ns** — a 1.191 ns recovery (59% improvement) from a single RTL change.

The cross-port collision behavior is now handled by the BRAM's native read-first mode and documented as a software contract (see Section 4 for the full rationale).

---

## Section 4: The Final Static Timing Wall

### WNS: -0.833 ns → +1.139 ns

### The Problem

After the BRAM inference fix, the design was tantalizingly close to timing closure — but not there. The worst negative slack had improved dramatically from -2.024 ns to -0.833 ns, but 347 endpoints still failed.

The new critical path was entirely different from the previous one. It no longer involved distributed RAM fanout. Instead, it terminated at the **reset/flush pin (`/R`)** of the EX/MEM pipeline register:

```
Source:  u_ex_mem/rd_addr_out_reg[2]/C     (EX/MEM pipeline register)
Dest:   u_ex_mem/reg_write_out_reg/R       (EX/MEM flush pin)
Delay:  10.344 ns (logic 2.246 ns + route 8.098 ns)
Levels: 11 (CARRY4=1, LUT3=2, LUT4=1, LUT6=7)
Slack:  -0.833 ns
```

The culprit was a piece of logic we had added as a safety mechanism: the **TCM cross-port collision interlock**.

### The Interlock We Built

To prevent the BRAM cross-port collision scenario (Port A writing the same address Port B is reading), we had implemented a hardware stall:

```systemverilog
assign tcm_collision_stall = tcm_wea          // Port A writing
                           & is_mac_ex        // MAC active in EX
                           & (tcm_addra == tcm_addrb);  // Same address

assign ex_mem_flush_sig = mac_stall_request | tcm_collision_stall;
```

This logic performed a **10-bit address comparison** between `tcm_addra` (computed combinationally from the ALU in the EX stage) and `tcm_addrb` (the MAC's Port B address). The comparison result was then fed into the EX/MEM flush signal, which drove the synchronous reset pin (`/R`) of **all 73 registers** in the EX/MEM pipeline register.

### The Consequence: A Late-Arriving, High-Fanout Control Net

The critical path through the interlock was:

```
rd_addr_out[2] → forwarding_unit compare → forwarding_mux →
ALU input mux → ALU computation → tcm_addra[3] → 
10-bit CARRY4 address comparator → 
collision_stall LUT6 → ex_mem_flush_sig (fo=73) →
reg_write_out_reg/R
```

The collision stall signal arrived at the EX/MEM register's reset pins with only **0.167 ns** of margin before the clock edge — nowhere near enough. The fo=73 fanout on the final flush net required 0.953 ns of routing delay alone, pushing the total path to 10.344 ns against a 10.000 ns budget.

### Rejected Alternatives

We evaluated three alternative approaches before making the final architectural decision:

#### Alternative 1: MAX_FANOUT Register Replication

Adding a `(* MAX_FANOUT = 16 *)` attribute to the flush signal would instruct Vivado to replicate the driving LUT across multiple slices, reducing the routing delay on the fo=73 net.

**Why Rejected**: This addresses only the last routing hop (~0.95 ns). But the combinational path from `rd_addr_out` through the forwarding unit, ALU, address computation, and CARRY4 comparator totals 11 logic levels and 9.4 ns of data path. Even with perfect replication saving 0.5 ns from the last hop, the path would still be ~9.8 ns — marginally over budget with no guaranteed closure. Register replication cannot reduce logic depth.

#### Alternative 2: DONT_TOUCH on BRAM Output Registers

Applying `(* DONT_TOUCH = "true" *)` to the BRAM output registers would prevent Vivado from absorbing them into the fabric or merging them with downstream logic.

**Why Rejected**: This constraint is hostile to FPGA retiming. Vivado's register retiming and register balancing passes move flip-flops across combinational logic to equalize path delays. A blanket DONT_TOUCH prevents these optimizations globally, potentially creating new timing violations on paths that would otherwise close. It addresses a symptom (BRAM register packing) that wasn't even confirmed to be occurring, while risking damage to the rest of the design.

#### Alternative 3: Pipeline the Collision Detection

Registering the collision stall output (`tcm_collision_stall_r <= tcm_collision_stall`) would break the combinational path, allowing the stall to take effect one cycle later.

**Why Rejected**: A 1-cycle-late stall means the MAC unit has already consumed the potentially-invalid Port B data during the cycle when the collision occurred. By the time the stall fires, the damage is done. Correcting this would require a **replay mechanism** — the ability to rewind the MAC FSM to S_INPUT and re-read Port B. This requires adding new states to the MAC FSM, a replay signal path, and additional control logic. The complexity is disproportionate to the frequency of the collision scenario (which requires a specific SW→MAC instruction sequence targeting the same TCM address — an unlikely software pattern).

### The Final Correction: An Architectural Pivot

We stepped back from the implementation details and asked the fundamental question: **Is the CPU obligated to protect against this collision?**

The collision scenario requires:
- A `SW` (store word) instruction in the MEM stage writing to TCM via Port A
- A `MAC` instruction in the EX stage reading the **exact same 10-bit word address** via Port B
- Both occurring **on the same clock edge**

This is not a standard in-pipeline RAW hazard. In a RAW hazard, instruction B depends on the result of instruction A, and the hardware must ensure B sees A's result. Here, the MAC and the store are **independent operations** that happen to access the same memory location simultaneously. The CPU has no way to know (without the comparator) that the programmer intended the MAC to see the value being stored.

This is a **concurrent software data race** — the same class of bug that exists in any multi-threaded system accessing shared memory without locks. The RISC-V specification does not mandate hardware coherence for TCM regions. ARM Cortex-M TCMs, MIPS tightly-coupled memories, and all FPGA soft-core TCM implementations treat this as a software contract: the programmer must ensure proper ordering (e.g., a NOP or fence) between writes and dependent reads.

Furthermore, the Xilinx 7-series TDP BRAM handles the collision **safely at the hardware level**:

> Per Xilinx UG473 (7 Series Memory Resources), Section "Collision Detection and Avoidance": When Port A writes and Port B reads the same address on the same clock edge, Port B returns the **old value** (READ_FIRST) or retains its previous output (NO_CHANGE). **No metastability. No data corruption in the BRAM array.**

The hardware is safe. The data is deterministic (old value). The only risk is a software bug — and hardware should not sacrifice timing closure to protect against software bugs that are, by specification, the programmer's responsibility.

### The Implementation

We completely stripped out the cross-port collision interlock:

```diff
 // Signal declarations:
-    logic        tcm_collision_stall;
 
 // Hazard control wiring:
-    assign tcm_collision_stall = tcm_wea
-                               & is_mac_ex
-                               & (tcm_addra == tcm_addrb);
-
-    assign pc_write        = ~(stall | mac_stall_request | tcm_collision_stall) | pc_redirect;
-    assign if_id_stall     = (stall | mac_stall_request | tcm_collision_stall) & ~pc_redirect;
-    assign id_ex_stall     = mac_stall_request | tcm_collision_stall;
-    assign ex_mem_flush_sig = mac_stall_request | tcm_collision_stall;
+    assign pc_write        = ~(stall | mac_stall_request) | pc_redirect;
+    assign if_id_stall     = (stall | mac_stall_request) & ~pc_redirect;
+    assign id_ex_stall     = mac_stall_request;
+    assign ex_mem_flush_sig = mac_stall_request;
```

The 10-bit CARRY4 address comparator, the collision stall LUT, and the fo=73 flush routing web were all eliminated. The critical path no longer terminates at the EX/MEM flush pin — it now terminates at the BRAM address pins, which have ample slack.

### The Result

```
Timing Report (v3):
    WNS:              +1.139 ns  ← TIMING MET ✓
    Failing Endpoints: 0
```

The design achieved timing closure at 100 MHz.

---

## Epilogue: The Four Lessons

| Battle | Lesson |
|--------|--------|
| **Synthesis Annihilation** | A design that cannot influence the physical world does not exist. Vivado will optimize away perfection if it has no reason to keep it. |
| **BRAM Latency Hazard** | Physical memory has physical latency. The architecture must absorb it — the EX-stage address bypass hides the BRAM's 1-cycle read behind the pipeline's natural timing. |
| **Inference Failure** | Synthesis inference is fragile. One conditional in an `always_ff` block can prevent a 36 Kb memory from mapping to its dedicated silicon. The RTL must match the vendor's template exactly. |
| **The Timing Wall** | Not every hazard deserves a hardware interlock. When the cost of protection exceeds the cost of the error — and when the silicon handles the collision safely — the correct engineering decision is to define the contract and let software uphold it. |

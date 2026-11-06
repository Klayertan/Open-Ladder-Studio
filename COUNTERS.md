# CTU counters and pedestrian example

Select **CTU counter** in Outputs (key **9**). Enter an address such as `C0` and an integer preset from 1 to 32,767 in the Inspector. The canvas shows `CTU` and `K8`; during simulation it shows the live count, for example `5/K8`. The Inspector and simulation panel show live counter values. NO/NC `C` contacts use the retained completion bit. Ordinary and SET coils remain restricted to M/Y; RESET supports C as well.

A CTU increments on an OFF-to-ON input transition, saturates at its preset, and retains its value and completion bit until RESET. RESET clears the count, completion, and input-edge latch. Reset wins over counting for the entire simulation step, regardless of the reset rung's position. If the count input is still held when reset is released, the cleared latch permits one count in that next operating step. Holding the input thereafter does not count again.

The existing simulator advances in fixed 10 ms steps and settles relay logic within each step. Counter inputs are sampled before each settling pass, including timer completion pulses that the feedback circuit subsequently clears. Each counter can increment at most once per step. Repeated settling passes do not create extra counts. Counter reset requests observed during a step remain dominant for that step. This is the editor's deterministic educational model, not a claim of identical Mitsubishi hardware scan timing. Input changes also settle immediately, preserving the existing momentary-input controls.

TON presets remain seconds in the Inspector and milliseconds in JSON. Fractional presets such as 0.5 s retain their exact 500 ms setting; completion occurs at the first 10 ms simulation boundary reaching the preset. No implicit K multiplier is applied in the native editor.

## Saved projects and sessions

`counter` is an additive SymbolKind and `counterPreset` is an optional integer field (default 8). Existing version 1/2 documents still migrate to version 3; existing version 3 files remain readable without changes. Counter configuration survives saving, loading, editing, copy/paste and undo. Runtime count, done, and last-input state belong only to SimulationState and deliberately are not saved into the ladder document. Simulator Reset and creating a new simulation clear them, alongside timers and inputs.

## Complete example

Choose **Example circuits → Eight-flash pedestrian crossing**, or open `Examples/Eight-flash-pedestrian.ladder`. X0 starts and X1 stops. T0/T1/T2/T3 are 5.0/2.0/3.0/12.0 seconds; T4/T5 are 0.5 seconds and T6 is 3.0 seconds. Y0/Y1/Y2 show the first three stages, Y3 the steady pedestrian phase, Y4 eight flashes, and Y5 the final clearance completion. This example remains complete until Stop; Stop clears C0 and timers, then Start begins again.

In the supplied five-rung fragment, M0 must already be ON and T3 must be driven by the surrounding circuit. Otherwise the NC M0 reset is continuously active or T3 never starts. Tests supply those drivers explicitly. With T3 enabling the oscillator at 12,000 ms, counts occur at 13,000, 14,000, …, 20,000 ms and T6 completes at 23,000 ms. Reversing rung order gives the same count events. In the full example T3 enables at 22,000 ms; Y4 flashes eight times, C0 completes at 30,000 ms, and T6 completes at 33,000 ms.

## MBS export

The full example also exports as `Examples/PEDESTRIAN.MBS`. CTU maps to Renri CNT (opcode 0x36), RESET to RST (0x1F), SET to SET (0x1C), and C devices to prefix 0x50000000. These match `Arduino/ESP32sample/cnt.MBS` and `Arduino/M5Sample/setrst.MBS` in the developer's official srenri884 archive. K counts use packed decimal, as do timer constants. Renri TIM uses an explicit fixed 100 ms base in this exporter: 0.5 s becomes K5, 3.0 s K30, and 12.0 s K120. Unsupported fractional values are rejected, never rounded silently.

Export supports complete series rungs (including all instructions in this example) and the existing Exercise 10 self-holding branch. Additional branch layouts are now lowered to series rungs using unused internal M relays; see DRAWING-AND-09KAI.md for bounds and details. Timer export is limited to 0.1–999.9 s in 0.1 s increments; addresses must fit the MBS 16-bit device field and comments must be representable by its existing Shift-JIS encoding rules. The new exporter tests check expanded instruction/data records against official examples. Actual opening/compilation in Windows Renri has not been verified on this Mac; exported programs retain Renri's normal scan order and may differ by a scan from native relay settling.

Official source: https://cah.sakura.ne.jp/sverdownload/ (srenri884 archive).

## Changed implementation areas

- Circuit.swift / CircuitEditing.swift: optional counter preset, validation, default address, atomic edits and Codable compatibility.
- LadderSimulator.swift: independent counter runtime state, edge capture, reset priority and reset API.
- ExampleCircuits.swift / MakeAssets.swift: full example and native/MBS artifacts.
- RenriMBSExporter.swift: C device encoding and CNT/SET/RST records.
- EditorViewModel.swift / InspectorView.swift: preset editing, undo, live current/done/input values.
- ComponentSidebar.swift / LadderCanvasView.swift / DiagramRenderer.swift / SimulationPanel.swift / EditorView.swift: palette, shortcut, live block values, highlighting and example menu.
- Localization generator and English/Japanese resources: new controls and address-error guidance.
- CounterTests.swift / RenriMBSExportTests.swift / EditorIntegrationTests.swift: edge, timing, branch, persistence, reset, full circuit, export, and editor integration coverage.

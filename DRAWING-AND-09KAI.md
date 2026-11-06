# Drawing controls, pulse outputs, and 09カイ review

## Controls

- Scroll over the canvas to zoom at the pointer. Pinch and toolbar zoom still work. Scrolling over the sidebar or Inspector scrolls that panel.
- V selects. Click a symbol to inspect it; drag it to move. Shift-click selects a group. Drag blank canvas to pan, or Option-drag from anywhere. There is no separate Pan tool.
- Choose a component and click the grid, or drag it from the sidebar. Dropping onto a horizontal wire replaces just that cell, retaining connections. Existing symbols are protected from replacement. With a symbol tool active, clicking/dragging an existing component selects/moves it.
- W selects the wire pen. Drag between snapped grid terminals, or click a start and end. Diagonal destinations use an orthogonal bend; Shift flips the bend. A preview shows the route. Esc cancels. Existing contacts and wires are preserved; vertical runs on a power rail reuse the rail. Each committed connection is one undo step.
- B still creates a rectangular branch; legacy horizontal/vertical wire tools remain available in the Circuit menu and through keys 6/7.
- P adds PLS (rising-edge pulse), F adds PLF (falling-edge pulse). Both write numbered M/Y addresses and last one simulator step (10 ms, or one immediate input-change evaluation). Held inputs do not repeat pulses. Runtime edge latches reset with the simulation. Pulse configurations serialize in native documents and export to the official Renri PLS/PLF record forms (0x1D/0x1E).

## Your original 09カイ

Original: `~/Library/Mobile Documents/com~apple~CloudDocs/５年宿題/応用システム/2/09カイ.ladder`.

The original file is unchanged. Its three-way start/self-hold branch, timer chain, CTU C0 K8, NC M0 counter reset, pedestrian-red OR branch and pedestrian-green steady/flashing branch match the worksheet's logic. All seven timer presets were entered as seconds using values that were too large:

| Device | Original seconds | Correct seconds |
| --- | ---: | ---: |
| T0 | 50 | 5 |
| T1 | 20 | 2 |
| T2 | 30 | 3 |
| T3 | 120 | 12 |
| T4 | 50 | 0.5 |
| T5 | 30 | 0.5 |
| T6 | 30 | 3 |

The screenshot also had X001's **Hold pressed** checked. The worksheet uses momentary pushbuttons. A held request can immediately start the next cycle when T6 releases the latch; leave Hold pressed off when testing one cycle.

Corrected copies: `09カイ-確認修正版.ladder` and `09カイ-確認修正版.MBS` beside the original. The native copy keeps your topology and adds device descriptions/lamp colors. Repository fixtures are `Examples/09-kai-pedestrian.ladder` and `.MBS`.

## Verified worksheet sequence

| Time | Vehicle lights | Pedestrian lights |
| --- | --- | --- |
| Idle / 0–5 s | Green | Red |
| 5–7 s | Yellow | Red |
| 7–10 s | Red | Red |
| 10–22 s | Red | Steady green |
| 22–30 s | Red | Eight green flashes, each 0.5 s on / 0.5 s off |
| 30–33 s | Red | Red |
| At 33 s | Return to green | Red |

Flash starts: 22.5, 23.5, …, 29.5 s. Counter increments: 23, 24, …, 30 s. C0 completion starts T6; T6 ends the cycle at 33 s and clears runtime counters/timers. Tests exercise X001 and X002 independently, ensure no conflicting light states, and compare native versus lowered branch logic at every 10 ms step.

## MBS branches

Previously the exporter rejected your three-way latch and the two pedestrian-light branch networks. It now collapses vertical connections, derives the contact expressions leading to each output, and lowers unsupported branch layouts to series rungs. Generated ordinary M relays implement OR using De Morgan's law and precede their destination output in scan order. Existing M addresses (including zero-padded spellings) are reserved; generated relays stay in the free M0–M7999 range. Your original document is never rewritten into that layout.

Known direct series/self-holding layouts retain their existing encoding. PLS/PLF encoding comes from official srenri884 ESP32sample/altplsplf.MBS and M5Sample/plsplf.MBS. Export is bounded to 256 distinct paths per expression and 512 lowered rungs. Unsupported complexity or lack of helper addresses is reported. Timer exports retain the fixed 100 ms Renri base. Windows Renri opening/compilation has not been verified on this Mac; its sequential scans can differ by a scan from native relay settling.

## Verification and files

69 XCTest cases pass, including wire paths, preservation/reuse, drawn-branch simulation, pointer anchoring/zoom limits, atomic undo, symbol placement, PLS/PLF edges and reset, MBS pulse opcodes, long-rung lowering, and the exact worksheet timeline.

New core modules: `RenriLogicLowering.swift`; new native view: `CanvasScrollZoom.swift`. Updated Circuit/CircuitEditing, LadderSimulator, RenriMBSExporter, EditorViewModel, sidebar/canvas/commands/renderer, translations and Xcode project. New test modules: WireEditingTests, PulseSimulationTests and PedestrianWorksheetTests; expanded editor and MBS tests.

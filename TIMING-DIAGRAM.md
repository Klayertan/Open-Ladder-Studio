# Live timing diagram

Opening Simulation now also shows a resizable timing-chart pane below the ladder. The waveform button beside the simulation controls hides/shows it. The chart's expand button opens a larger view; the divider between ladder and chart can be dragged.

Rows include every numbered X, M, T, C and Y device used in the circuit. Each row shows its device comment, live ON indicator, and timer preset or current/preset counter value where relevant. Horizontal high/low steps show the actual recorded bit state. Hatched timer intervals show enabled TON timers still counting. Counter numbers mark increments, and dots on vertical edges mark zero-duration pulses (for example a momentary button or a timer feedback bit consumed within one step).

The chart records inside the simulator, before and during relay settling. It is not a plot of periodic screen samples, so timer completion pulses and press/release events at the same simulation timestamp are preserved. Timer elapsed milliseconds do not create a sample on every tick; only bit, timing-status and count changes are recorded. The last 120 seconds are retained, with one starting-level sample and a maximum of 4,096 transitions per signal. Very high-frequency signals can therefore retain less history. History is runtime-only, cleared by Simulator Reset or document edits, and is not included in native ladder or MBS files.

Choose 10/40/120 seconds for the horizontal scale, or Fit history. Follow automatically scrolls horizontally to current simulation time; disable it to inspect earlier history. Vertical scrolling is independent and is not moved by live follow. Pause freezes both simulation and the chart; Run continues the same history. Reset begins a new recording.

The separate Pan tool, H shortcut, and menu entry have been removed. The cursor tool still selects/moves symbols and pans when dragging blank canvas. Option-drag pans from any tool.

## Verification

- 73 XCTest cases pass, including four new history tests.
- Tests cover instantaneous input events at identical timestamps; complete 09カイ history including eight T5 completion events and C0 increments; timer counting intervals; reset/document isolation; rolling retention and high-frequency bounds.
- Existing counter, pulse, relay, timer, chunk-size, branch, document, editor, and MBS tests continue to pass.
- Rendered and visually inspected the full 33-second 09カイ history in light and dark appearances.
- Updated LadderSimulator.swift and the editor layout/simulation controls. Added TimingDiagramRenderer.swift, TimingDiagramView.swift, SimulationHistoryTests.swift, translations and Xcode project entries. Removed the Pan tool from the sidebar, tool model, commands and keyboard handling.

The chart records this simulator's 10 ms/relay-settling semantics. A brief timer completion consumed during settling appears as a vertical marker rather than an invented finite-duration plateau. This does not claim identical scan timing to a physical PLC.

# Local build and export verification

## Renri green-comment display fix — November 5, 2026

- **81 XCTest cases pass, 0 failures**. Added independent expected-word tests for Renri's per-symbol 0x00080000 comment-display flag and checks across branch-lowered device/instruction kinds.
- Previous exports carried comment text but omitted the visibility flag on most symbols. Native official samples show plain/annotated words 0x801A/0x8801A and 0xC078/0x8C078.
- Re-exported 09カイ and independently verified all 45 comment cells have the flag, preserving sixteen-cell alignment. Instruction regression ignores only this known display bit; executable bits and data operands remain identical.
- Visual appearance in Windows Renri remains unverified locally. Latest log: `build/comment-display-verification.log`.

## Renri comments — November 5, 2026

- **79 XCTest cases pass, 0 failures**. Six new comment tests cover descriptions plus notes, duplicate suppression, branched/repeated-address notes, whitespace/multiline syntax, sixteen-cell comment alignment and unsupported characters.
- The historical Exercise 10 fixture's header/instruction/data records remain byte-identical. Only comment enrichment is allowed by the revised regression assertion; the historical file itself is untouched.
- Latest log: `build/comment-verification.log`. Details: [RENRI-COMMENTS.md](RENRI-COMMENTS.md).

## Timing diagram and cursor-only panning — November 4, 2026

- **73 XCTest cases pass, 0 failures**, including four new transition-history tests.
- Verified same-timestamp input pulses, eight T5 feedback completion events, C0 increment/completion/reset history, timer counting intervals and bounded 120-second recording.
- Full 09カイ chart rendered and visually inspected in light and dark appearances; matches the verified 33-second sequence.
- Removed the separate Pan tool/menu/H shortcut; cursor blank-space dragging and Option-drag remain.
- Latest test log: `build/timing-verification.log`. Details: [TIMING-DIAGRAM.md](TIMING-DIAGRAM.md).

## Drawing and worksheet 09カイ — November 4, 2026

- **69 XCTest cases pass, 0 failures**, including PLS/PLF, wire routes, zoom anchoring, undo, branch lowering and exact worksheet timing.
- Opened the user's saved 168-element 09カイ circuit and confirmed all seven presets were entered too large. Saved a corrected sibling copy and verified the original SHA-256 remained unchanged.
- Corrected file matches the worksheet: eight flashes from 22.5–30 s, counter events at 23–30 s, automatic idle return at 33 s, for either momentary button.
- Compared native and MBS-lowered device states at every 10 ms step over the full 33 s cycle. Export uses free M helpers for general branches rather than unsupported guessed branch records.
- Opened the corrected file in the new app, inspected its labels and timer values, and successfully exported it through the actual native MBS save panel; independently decoded the saved Shift-JIS file (26 instruction rows).
- Added wheel zoom, unified click/drag/pan behavior, sidebar dragging, wire pen, and PLS/PLF controls. CUA's coordinate drag/scroll input returned `noWindowsAvailable`, so end-to-end pointer gestures could not be automated; routing, placement, undo and anchored zoom are covered by tests.
- More details: [DRAWING-AND-09KAI.md](DRAWING-AND-09KAI.md). Latest log: `build/drawing-verification.log`.

## Counter implementation — November 4, 2026

- Native Swift 6 arm64 build succeeds; all **56 core and app XCTest cases pass, 0 failures** (`python3 Scripts/build_native.py --test`).
- Eight new counter test cases plus editor integration and MBS record tests cover edge detection, held inputs, preset completion, NO/NC contacts, reset priority/rearming, independent counters, branches, JSON round trips, simulator reset, timer chunk sizes and the complete crossing sequence.
- The supplied timer-feedback fragment produces eight count events with both forward and reversed rung order. The full example produces eight visible flashes and T6 completes exactly 3 seconds after C0.
- All three existing checked-in native projects decode and initialize simulation successfully.
- Rendered the complete crossing to PNG and visually checked TON/CTU labels and fractional seconds.
- Generated `Examples/Eight-flash-pedestrian.ladder` and `Examples/PEDESTRIAN.MBS`; both are bundled in the app. CNT, C contacts, RESET and SET records match structures in official srenri884 examples. Windows Renri opening/compilation remains unverified; arbitrary MBS branch export remains limited.
- Regenerated the Xcode project to include CounterTests.swift; `plutil -lint` and strict deep code-signature verification pass.
- Latest test log: `build/counter-verification.log`. Details and changed-file summary: [COUNTERS.md](COUNTERS.md).

## Earlier baseline verification

- Native arm64 application and LadderCore framework compile with the installed Xcode 27.1 / Swift 6.4 toolchain, Swift 6 language mode, targeting macOS 14.
- `python3 Scripts/build_native.py --test`: **40 XCTest cases passed, 0 failures** (22 editing, 6 app integration, 8 simulation, 4 MBS format/export).
- Tested exact green/yellow/red boundaries at 0/10/12/17 seconds and repetition, Stop in every phase, stop priority, restart, and timing-independent chunk sizes.
- Opened the Exercise 10 file in the actual app; used Run, Start and Stop; checked live lamps and timer readouts.
- Exported `output/exercise10/KADAI10.MBS` through the app's new native save-panel workflow. Independently read the saved file using CP932, checked CRLF, header, nine 16-cell layout/data records, Japanese X/Y comments, and K100/K20/K50 timer presets.
- The MBS writer uses protocol structures observed in the developer's official Standard 8.84 archive. **It has not been opened or compiled in Renri; application compatibility, including Standard 8.85, remains unverified.** See `output/exercise10/RENRI-COMPATIBILITY.md`.
- Used the system Screenshot utility through its native interface to capture the actual desktop. The original capture shows the running yellow phase at t=214.72 s and the macOS clock at Thu Oct 29 21:26. Wrapped that complete, unedited image in `output/pdf/Exercise-10-Running-Screen.pdf`, rendered the PDF with Poppler and inspected it.
- Verified ad hoc application signing and the embedded framework; structurally checked the Xcode project/property lists.

`xcodebuild` and `xcrun` remain blocked by the machine's unaccepted Xcode license. The compiler, SDK and native XCTest runner were invoked directly without changing that license or any security setting. The Xcode scheme has not been executed through `xcodebuild`, and macOS 14 runtime behaviour has not been tested on a separate macOS 14 system.

Latest test log: `build/renri-export-verification.log`. Built app: `build/Native/Open Ladder Studio.app` (a link to a workspace-specific local cache). Archive: `build/OpenLadderStudio-0.2.0-arm64.zip`.

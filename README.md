# Open Ladder Studio 0.2

A native Swift 6 / SwiftUI ladder logic editor for macOS 14+ on Apple Silicon. The drawing style uses JIS-like contacts and parenthesized output coils, informed by the supplied Renri reference. The app includes an educational relay/TON simulator with connection checks. It does not connect to real PLC hardware or claim formal JIS certification.

## Run the built app

The local build is at `build/Native/Open Ladder Studio.app`. Open it in Finder. No administrator password is required to launch this locally built app. `build/Native` links to a workspace-specific folder under `~/Library/Caches/OpenLadderStudio/`, keeping signed app bundles outside cloud-synchronized Documents metadata. Set `OPEN_LADDER_BUILD_DIR` to override the build location.

To build it again using the installed Xcode toolchain:

```sh
python3 Scripts/build_native.py
```

This script calls the compiler and SDK directly, creates a complete app bundle, and signs it locally with an ad hoc signature. It does not accept Xcode licenses or change system security settings. It requires Xcode at `/Applications/Xcode.app`; set `DEVELOPER_DIR` to use another installation. Python 3 is required. No third-party packages or network access are needed. The app is locally signed, not notarized for distribution.

## Xcode

1. Open `OpenLadderStudio.xcodeproj`.
2. Select the **OpenLadderStudio** scheme and **My Mac**.
3. Run with **⌘R**; test with **⌘U**.
4. Choose a development team if your local signing configuration requests one. The command-line build below disables signing for compilation.

```sh
xcodebuild -project OpenLadderStudio.xcodeproj \
  -scheme OpenLadderStudio -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/Xcode CODE_SIGNING_ALLOWED=NO build test
```

The current machine has an unaccepted Xcode license, so `xcodebuild` and `xcrun` are blocked until the machine owner reviews and accepts it. The direct compiler build above provides a separate way to build and test the sources without changing that license state. Xcode 16+ with Swift 6 is the intended IDE baseline; the local direct build uses the installed Xcode 27.1 / Swift 6.4 compiler in Swift 6 language mode, targeting macOS 14.

## Editing

- **File → New / Open / Save** uses macOS document windows, recent files, autosave, and edited-state tracking. **Save As** is available through the native File menu (hold Option where macOS exposes it).
- Choose a component in the left sidebar, then click a cell. The transparent cursor preview turns red when a cell is occupied. Placement stays active for repeated use.
- Choose **Select**, click a component, and drag to move it. Everything snaps to integer grid cells. **Shift-click** adds or removes elements from the selection. **Arrow keys** move selected elements one cell.
- Edit a selected element's device label and comment in the inspector, then choose **Apply** or press Return. Labels normalize to uppercase and accept 1–16 letters/digits/underscores, beginning with a letter.
- **Delete**, **⌘X**, **⌘C**, **⌘V**, and **⌘A** delete, cut, copy, paste, and select all. Text editing retains standard text shortcuts.
- **⌘Z / ⇧⌘Z** undo and redo all circuit changes, including properties, grid expansion, examples, and paste. A multi-element move or branch is one operation.
- Choose **Pan (H)** and drag. Pinch to zoom, use the toolbar, or use **⌘+ / ⌘− / ⌘0**. **Fit Circuit** frames the full grid.
- Expand the document with **+ 2 rows** and **+ Column** in the inspector. Limits are 128 columns and 512 rows. Expanding columns moves the right rail outward; add the required connections and move coils to the new last column.
- Use **Example circuits** in the toolbar to load a seal-in or SET/RESET example, or clear the diagram. Replacing existing content asks first and remains undoable.

Canvas tool keys work while the canvas has keyboard focus:

| Key | Tool |
| --- | --- |
| V | Select |
| 1 / 2 | Normally open / normally closed contact |
| 3 / 4 / 5 | Output / SET / RESET coil |
| 6 / 7 | Horizontal / vertical wire |
| 8 | TON on-delay timer |
| B | Parallel branch |
| Escape | Return to Select and clear selection |
| ⇧⌘K | Toggle connection checks |

### Connections and branches

Each horizontal symbol occupies one grid edge. A vertical wire joins two adjacent row nodes and can meet a horizontal element at its endpoint. The left and right rails are permanent; no implicit horizontal wires are inserted. Add horizontal wires to complete each rung.

The **Parallel branch** tool makes a rectangular wire bypass one row below the chosen starting cell. Set its span in the inspector. Endpoints must be inside the rails. To put a contact in the bypass, select and delete the corresponding horizontal wire, then place the contact in that cell. Branch creation reuses matching existing wires and atomically rejects collisions with components. Nested branches can be assembled from the same wire primitives.

Copy/paste preserves labels and relative positions and generates new element IDs. Paste starts at the pointer's grid position, or C2/R2 if the pointer is outside the canvas, then searches subsequent rows in that column for free space. It does not overwrite occupied cells.

### Validation and export

**Validate connections** opens a live issue list. Select an issue to reveal the element. Checks detect dangling internal terminals, disconnected rail paths, wire-only rail shorts, invalid labels, and output coils away from the last column. Overlaps and out-of-grid edits are rejected before mutation. Validation describes connectivity. The separate educational simulator displays energized elements; neither function proves PLC safety.

**Export → PNG / PDF** uses a native save panel. Exports include the whole diagram and labels with a white background; grid dots, selection, and issue highlights are omitted. PNG renders at 2×, capped at 8,192 pixels on the longest side for large documents. PDF is a single vector page sized to the full grid.

## Language and appearance

English and Japanese strings are bundled. Use **System Settings → General → Language & Region → Applications** to choose a language for Open Ladder Studio, then relaunch it. **Open Ladder Studio → Settings** lets you follow the system appearance or choose light/dark mode.

## Examples

- `Examples/Motor-seal-in.ladder`: X0 start, X1 normally closed stop, Y0 output, and a parallel Y0 holding contact.
- `Examples/Set-reset-memory.ladder`: X0 SETs M0; X1 RESETs M0.

Both files use the same versioned JSON format as user projects. They can be opened through File → Open or Finder. They are also bundled in the app.

## Architecture

```text
Sources/LadderCore/          Codable value model, pure editing, graph validation,
                            example circuits, relay/TON/CTU simulation, importer protocol
Sources/OpenLadderStudio/    ReferenceFileDocument, MVVM editor, native commands
  Rendering/                Shared SwiftUI Canvas paths and PNG/PDF exporter
  Views/                    Sidebar, canvas interaction, inspector, issue panel
  Resources/                English/Japanese localizations and app icon
Tests/LadderCoreTests/       Atomic editing, topology, serialization, importer tests
Tests/LadderAppTests/        Undo/redo, clipboard, document snapshots, export tests
```

`Circuit` is independent of SwiftUI and AppKit. Stable UUIDs identify elements. Electrical edges connect `GridPoint` nodes, allowing a future simulator to consume the same topology without deriving connections from pixels. Geometry, zoom, pan, selection, and active tools are editor state and are not serialized.

`EditorViewModel` commits validated values, registers inverse transactions with the document window's native `UndoManager`, and mutates the observable document. `LadderDocument` publishes changes on the main actor; a lock protects value snapshots for background serialization. Native `.ladder` document registration is declared in `Info.plist`.

`CircuitImporter` is a separate interface for format adapters. `NativeJSONImporter` works today. `RenriImporter` is a deliberately disabled stub that always reports unsupported import. **Renri `.mbs` export is experimental; opening/compilation compatibility is unverified.** No `.mbs` file association is registered.

## Tests and reproducible assets

Run all core and app integration tests using the installed toolchain:

```sh
python3 Scripts/build_native.py --test
```

This runs the actual XCTest cases using the native XCTest bundle runner, avoiding SwiftPM's `xcrun` dependency. On a configured Xcode installation, use ⌘U or `xcodebuild ... build test` above. Core-only tests are also a Swift package:

```sh
swift test
```

Regenerate project metadata, translations, and source-derived example/icon assets when needed:

```sh
python3 Scripts/generate_project.py
python3 Scripts/generate_localizations.py
python3 Scripts/build_native.py --assets
```

The checked-in Xcode project, translations, examples, and icon require no regeneration for normal builds. `build/` is ignored by Git.

## Version 0.2 boundaries

No PLC connection, Renri import, or verified hardware execution semantics are included. Renri export is limited and experimental. The grid is expandable rather than infinite. Symbol graphics follow the visual conventions shown in the reference; manufacturer-specific device semantics and full JIS compliance have not been verified. Validation uses undirected connectivity and does not prove instruction ordering or PLC execution semantics.


## Exercise 10 and educational simulation

Open `Examples/Exercise-10-Traffic-Light.ladder`, or choose **Example circuits → Exercise 10 - Traffic light**. Use the waveform toolbar button (⇧⌘R) to open Simulation, then choose **Run** and press **X0 スタートPB**. **X1 点滅停止PB** immediately switches every lamp off and resets all three on-delay timers. A fresh Start begins at green. Stop dominates simultaneous held Start/Stop. Repeated Start presses during an active cycle do not restart its timers.

| Address | Comment / purpose |
| --- | --- |
| X0 | スタートPB — momentary Start |
| X1 | 点滅停止PB — momentary Stop, active when pressed |
| Y0 | 青ランプ（10秒）— green lamp |
| Y1 | 黄ランプ（2秒）— yellow lamp |
| Y2 | 赤ランプ（5秒）— red lamp |
| M0 | 運転自己保持 — run latch |
| T0 / T1 / T2 | Non-retentive TONs: 10 / 2 / 5 seconds |

The worksheet fixes the 10/2/5-second sequence. The submission instructions additionally require a stop button but do not define its resulting lamp state. This example explicitly assumes **Stop means all lamps off and timers reset**; restart returns to green. X/Y addresses are assigned here because the supplied page does not prescribe them. Every X/Y occurrence has a Japanese comment.

The simulator evaluates the actual ladder, not the example name. It advances time in 10 ms steps, updates enabled timers once per step, and settles relay logic at that same instant. Horizontal logic flows left to right; vertical branch wires conduct both ways; output instructions terminate a rung and the right rail cannot backfeed another rung. TONs reset when their input becomes false. The T2 completion resets the timer chain, producing green → yellow → red → green at 0, 10, 12, and 17 seconds, repeating every 17 seconds. Non-converging feedback is rejected. This is an educational execution model, not a certified manufacturer's PLC scan model.

Input buttons make one momentary press/release; **Hold pressed** allows testing held inputs. **Pause** freezes time, **Step 0.1 s** advances paused time, and **Reset** clears runtime state. Editing or undoing the circuit pauses and clears simulation. Runtime bits, elapsed timer values, and live inputs are never saved in `.ladder` documents. Select a TON block to edit its preset in seconds and apply the change.

Project JSON is now version 2. Version 1 documents load and migrate automatically; older app versions cannot read version 2 files. Renri `.mbs` compatibility remains unverified; renaming a native file is not conversion. A limited experimental writer is now available as described below.


## Experimental Renri MBS export

Choose **Export → Export Renri MBS (experimental)…** for an eligible circuit. The writer creates actual Shift-JIS, CRLF `mbs-file 3winv.1` records based on the developer's official Standard 8.84 samples. It supports complete series NO/NC rungs with OUT/TIM instructions, and the one-cell self-holding branch in Exercise 10. Unsupported layouts, non-100 ms timer presets, and unsupported comment characters are rejected. This is not a general Renri importer or a verified compatibility claim.

The Exercise 10 export is `output/exercise10/KADAI10.MBS`. Read `output/exercise10/RENRI-COMPATIBILITY.md` for format provenance, supported scope, and the required Renri-side open/compile/run check. No Windows/Renri runtime is available on this Mac, so that final check remains outstanding.


## CTU counters and eight-flash crossing

CTU counters, C contacts, counter RESET, live Inspector/canvas values and CNT/SET/RST MBS export are supported. Choose **Example circuits → Eight-flash pedestrian crossing**. See [COUNTERS.md](COUNTERS.md) for scan/reset semantics, timer units, the complete example, changed files and MBS export limits.


## Wire pen, scroll zoom, PLS/PLF and worksheet 09カイ

Scroll over the canvas to zoom at the pointer. Drag blank space to pan. Use **W** to draw connections by dragging or clicking two terminals; **Shift** changes the bend. Symbols support click placement and dragging from the sidebar. **P/F** select rising/falling pulse coils. Branch networks can now export through generated internal M relays. See [DRAWING-AND-09KAI.md](DRAWING-AND-09KAI.md) for controls, the reviewed 09カイ circuit, timing results and export limits.


## Live timing diagram

Simulation now includes a timing chart for X/M/T/C/Y devices, with timer counting hatching, counter events and brief pulses. Expand it or drag the ladder/chart divider to resize it. Pause preserves history; Reset clears it. The cursor includes panning, so the separate Pan tool and H shortcut have been removed. See [TIMING-DIAGRAM.md](TIMING-DIAGRAM.md).


## Renri comments

MBS exports retain device descriptions and per-symbol notes, including through branch conversion. Distinct descriptions/notes become separate comment lines; ASCII spaces/tabs are rendered as full-width spaces. See [RENRI-COMMENTS.md](RENRI-COMMENTS.md).

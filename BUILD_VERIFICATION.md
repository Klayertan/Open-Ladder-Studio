# Local build and export verification

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

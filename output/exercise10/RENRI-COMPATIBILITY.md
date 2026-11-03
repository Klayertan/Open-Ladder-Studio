# Renri MBS export - compatibility status

`KADAI10.MBS` is a Shift-JIS, CRLF `mbs-file 3winv.1` export of the Exercise 10 circuit. It is not renamed JSON.

The writer is based on actual MBS examples in the developer's official Standard 8.84 package:

- Download page: https://cah.sakura.ne.jp/sverdownload/
- Archive: https://cah.sakura.ne.jp/djy61792/wp-content/uploads/2021/04/srenri884.zip
- `sample/sample1.mbs`: self-holding branch layout.
- `Arduino/ESP32sample/timer.MBS` and generated `timer/timer.ino`: timer fields, packed-decimal K values, 100 ms base.
- `sample/PICSample/SampleA/TIM.mbs`: minimal END instruction and file terminators.

The file contains the same Start/Stop run latch and green 10 s / yellow 2 s / red 5 s repeating sequence as the native project. Every X/Y occurrence has a Japanese comment. The holding rung is redrawn as `(X0 OR M0) AND NOT X1`, equivalent to the native `NOT X1 AND (X0 OR M0)` rung. Layout is normalized to Renri's 16-cell record width.

**Not yet verified by opening/compiling in Renri.** This Mac has no Renri-compatible Windows runtime. Standard 8.85 (shown in the original reference) has not been tested. Matching sample structure and unit tests do not establish application compatibility.

Before submission, open `KADAI10.MBS` using Renri's File > Open, compile the circuit, and test X0/X1 and the three lamp transitions. Renri uses normal PLC scan ordering, so transitions may differ by a scan from the native simulator's relay-settling model. Stop is assumed to mean all lamps off and timers reset; restart begins at green. The supplied assignment does not prescribe the device addresses or the stop lamp state.

Addresses: X0 Start PB; X1 Stop PB; Y0 green; Y1 yellow; Y2 red; M0 run latch; T0/T1/T2 timer presets K100/K20/K50.

The accompanying running-screen PDF is a real, unedited macOS desktop screenshot of Open Ladder Studio, with the macOS system clock visible. It is not evidence of running this file in Renri.

Official archive SHA-256: `1ee72b5768070cd83ee68d06c87c8d204e8eb3fd3577c1339d33232f2b8fd71b`

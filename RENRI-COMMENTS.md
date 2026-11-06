# Renri comment export

MBS exports now set the per-symbol comment-display flag (0x00080000) as well as storing the comment text. The earlier export stored text without enabling this flag on most symbols, so the file could open without displaying the green annotations.

MBS exports include the shared device description on each original contact/output. A distinct per-symbol note is included as a separate Renri comment line. Identical device and symbol text is emitted only once.

Branch lowering now carries contact notes into the generated series rungs, including different notes on repeated uses of the same address. Output notes and the device table are retained. This fixes the earlier loss of contact notes when exporting a branched circuit.

Multiline comments use the doubled-backslash line separator found in official srenri884 examples (for example M5Sample/setrst.MBS's システム / 初期設定 comment). ASCII spaces and tabs are rendered as Japanese full-width spaces so words remain readable without introducing MBS token delimiters. CRLF/CR input line endings are normalized to comment-line separators, not extra MBS records. Native document text is never modified.

Japanese and other Shift-JIS-representable characters are supported. Emoji, unrepresentable characters, literal backslash delimiters and invalid control characters are rejected with a clear error; they are not silently dropped.

The historical Exercise 10 MBS fixture is retained unchanged. Its regression test compares the header, executable instruction bits and data records, masking only the identified comment-display flag. Dedicated tests separately require the flag on annotated contacts, coils, timers, counters and reset instructions. Additional tests check shared descriptions and notes, duplicate suppression, branched contacts/outputs, repeated-address notes, spaces/newlines, sixteen-cell comment-row alignment, and rejection of unsupported characters.

Changed files: RenriMBSExporter.swift, RenriLogicLowering.swift, the localization generator and resources, RenriCommentTests.swift, DeviceTableTests.swift and the generated Xcode project. Actual opening/compilation in Windows Renri remains unverified on this Mac.

Visibility fix: official sample1.mbs and M5Sample/setrst.MBS use annotated contact/coil words 0x0008801A and 0x0008C078, versus plain 0x0000801A and 0x0000C078. All 45 comment cells in the revised 09KAI export were independently checked for the display flag and sixteen-cell comment alignment. 81 XCTest cases pass. The prior text-only tests were insufficient to establish visible annotations. Actual display in Windows Renri still requires external verification.

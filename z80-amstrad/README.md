# writhdeck cpc

Amstrad CPC port of [WrithDeck](https://github.com/luginfow/writhdeck),
started alongside the [ZX Spectrum port](../z80-zxspectrum) on the same
Z80 CPU. `core/` (the platform-independent editing logic) is reused
here **byte-for-byte unchanged** from the Spectrum port — copy it back
in if you ever pull a fresh one, don't hand-edit a fork.

This port exists partly for its own sake, and partly as a diagnostic:
the Spectrum port has an unresolved intermittent freeze reported in
real Fuse usage that automated testing couldn't conclusively
root-cause. Comparing behavior across two platforms that share the
exact same `core/` is a good way to tell whether a future bug lives in
the shared editing logic (would show up on both) or in a
platform-specific layer (would show up on only one).

## Status: early, not yet a finished deliverable

Unlike the Spectrum port (fully working, extensively tested), this one
is at the "gets a document typed into it, unverified beyond that"
stage:

- **Toolchain confirmed working**: `sjasmplus` assembles cleanly with
  `DEVICE AMSTRADCPC464`; the CPU emulation side of `zesarux --machine
  CPC464` runs the result correctly.
- **Confirmed by direct memory inspection in the emulator**: firmware
  init (`scr_init`/`editor_init`) runs correctly (`TEXTEND` correctly
  ends up pointing at `TEXTBUF`, `LINECOUNT`=1 for a fresh document),
  and at least one real keystroke round-trip (character typed →
  reaches `editor_insert_codepoint` → lands in `TEXTBUF`) has been
  observed working end-to-end.
- **Confirmed visually working in `xcpc`**: the real deliverable
  (`cpc/writhdeck.dsk`, see "Building" below) boots and runs --
  screenshot showed the screen clearing and the status bar correctly
  reading `L1 C1` for a fresh document, cursor highlighted. This is
  the strongest verification so far, on a genuine (if GUI-only)
  CPC emulator, not just register/memory inference through zesarux.
- **NOT yet verified**: the exact firmware codes used for cursor
  keys/DEL/CTRL+letter in `cpc/keyboard.asm` are taken from
  documented firmware behavior, not empirically confirmed here (see
  the note at the top of that file); cassette save/load
  (`cpc/tape.asm`) has not been round-tripped at all; typed input
  wasn't re-confirmed in the `xcpc` screenshot test (window-focus
  issue during automation, not a program error -- see below); no
  automated test suite yet (unlike the Spectrum port's `make test`);
  no comparison stress-test against the Spectrum freeze has been run
  yet.

## Why this port looks different from the Spectrum one

Two real, structural simplifications — not just "less code was
written yet" — made possible by CPC hardware/firmware the Spectrum
doesn't have:

- **No hand-rolled keyboard matrix scan or debounce logic.**
  `cpc/keyboard.asm` calls the CPC firmware's `KM_WAIT_CHAR`, a mature
  ROM routine that already handles debounce and repeat correctly. The
  Spectrum port spent a great deal of effort getting a hand-rolled
  scanner+debounce right (see its README's Status section) precisely
  *because* the 48K/128 has no such firmware helper. This should also
  sidestep that whole category of bug here.
- **Real cursor keys and a real CONTROL key.** No CAPS-SHIFT+digit or
  SYMBOL-SHIFT+letter workarounds needed: arrows are the actual arrow
  keys, and Save/Quit/Undo/Redo are CTRL+S/Q/Z/Y (the firmware
  natively translates CONTROL+letter to control codes 1-26) — closer
  to a modern editor's conventions than the Spectrum's forced
  substitutes.
- **No custom attribute-plane handling.** The Spectrum has a separate
  bitmap+attribute memory layout that made `scr_set_attr` a distinct
  operation from drawing text. CPC text is firmware-driven
  character-cell printing with no such separate plane — a character's
  color is fixed the moment it's printed. `cpc/screen.asm` reflects
  this: `scr_put_line` takes the cursor's column directly and
  temporarily swaps ink/paper for just that one character while
  printing the line, in a single pass — there is no separate
  `scr_set_attr` call here, unlike `spectrum/main.asm`.

One deliberate **platform-driven difference from the Spectrum port**:
`_start` here executes `EI` early and relies on interrupts staying on
for the whole run. This is the opposite of the Spectrum port (which
explicitly avoids `EI`/`HALT` after finding it let the ROM's default
interrupt handler corrupt memory). On CPC there's no such conflict:
`KM_WAIT_CHAR`'s debounce/repeat state is *driven* by the firmware's
own 300Hz interrupt, so leaving interrupts enabled here isn't
optional — without it, keyboard input never advances at all (this was
confirmed directly: `TEXTEND` stayed at zero and nothing typed reached
the buffer until `EI` was added).

## Testing notes (why there's no `make test` yet)

The `zesarux` build available in this environment (v8.1) can emulate
the CPC464 CPU/hardware, but its **tape/snapshot loading is Spectrum-only**
in practice — confirmed experimentally: `--tape file.cdt` refuses CPC
cassette images (`Error: Tape format not supported` / `File is not in
ZXTape format!`), and `--snap file.sna` fails to parse a genuine CPC
snapshot produced by `SAVECPCSNA` (`Error: .SNA file corrupt` — its
parser expects the Spectrum `.SNA` layout, not CPC's `MV - SNA`
format, despite the header being valid).

**Workaround used for the manual checks above** (see
`tests/zrcp_harness.py`, not yet wired into automated `test_*.py`
files the way the Spectrum port's are): boot a clean `CPC464` machine
to its normal BASIC-ready state, then use ZRCP `write-memory` to inject
the assembled `.bin` directly into RAM at `0x8000`, and
`set-register PC=<value>` to jump to `_start` (**not** `program_start`
— that address is just the first byte of the first included
subroutine, `cp_hl_de`, not a valid entry point; setting PC there was
an early mistake in this session that produced a very confusing false
lead resembling a crash).

Also observed but not yet resolved: `zesarux`'s `send-keys-ascii` on
this machine type doesn't cleanly map "hold duration" to "one
character" the way it (mostly) does for the Spectrum port's tests —
too short a delay produces nothing, a moderate one can produce several
repeated characters (very possibly the CPC firmware's own key-repeat
triggering on a simulated "hold" that a real quick tap wouldn't
trigger, rather than a bug in this port — not yet confirmed either
way).

## Layout

```
z80-amstrad/
  core/            -- IDENTICAL COPY of ../z80-zxspectrum/core/ (do not fork)
  cpc/             -- Amstrad CPC platform layer
    screen.asm       firmware text-mode rendering (TXT_*/SCR_* ROM calls)
    keyboard.asm      KM_WAIT_CHAR-based input, real cursor/CONTROL keys
    tape.asm            cassette SAVE/LOAD (CAS_* ROM calls) -- unverified
    main.asm               entry point, main loop, screen drawing
  tests/
    zrcp_harness.py  -- memory-injection test harness (see above)
  Makefile
```

## Building

```sh
make writhdeck   # produces cpc/writhdeck.bin (+ .sym)
make dsk         # produces cpc/writhdeck.dsk (real, loadable deliverable)
```

`cpc/writhdeck.dsk` is a standard AMSDOS floppy disk image (built with
[`iDSK`](https://github.com/cpcsdk/iDSK)) containing `WRITHDEK.BIN` --
a genuine binary AMSDOS file with load address `0x8000` and execute
address `_start`, not just a raw dump. To run it: boot the CPC (disk
drive present), then at the BASIC prompt:

```
RUN"WRITHDEK
```

AMSDOS reads the file header itself (load address, exec address,
binary vs. BASIC), loads it to the right place and jumps to `_start`
automatically -- no separate loader program needed, unlike the
Spectrum port's cassette autoloader (`.tap`, hand-tokenized BASIC).

**Verified end-to-end**, visually, in `xcpc` (installed on this
machine; `zesarux` here has no CPC disk drive emulation at all --
checked, only a `+3 DSK` option exists, which is Spectrum +3 disk
emulation, not CPC): booted `xcpc --machine=cpc464
--drive0=cpc/writhdeck.dsk` under a virtual display, typed
`RUN"WRITHDEK` + Enter, and captured a screenshot showing the program
actually running -- screen cleared, status bar correctly reading
`L1 C1` for a fresh empty document, cursor highlight visible at the
top-left cell. This is the real thing working, not just a memory-state
inference. Typed input after that point wasn't confirmed the same way
(the follow-up screenshot attempt lost window focus before the
keystrokes landed) -- worth re-confirming interactively if you have a
GUI session handy.

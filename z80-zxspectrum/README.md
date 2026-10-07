# writhdeck z80

Z80 assembly port of [WrithDeck](https://github.com/luginfow/writhdeck),
running as a real, loadable **ZX Spectrum 48K** program. The code is
deliberately split into a platform-independent core and a ZX Spectrum
platform layer, because an **Amstrad CPC** port is planned next on the
same CPU.

## Layout

```
z80/
  core/            -- platform-independent editing logic (pure Z80,
                       no screen address, no keyboard port, no Z80N
                       extensions -- must stay usable on CPC too)
    layout.inc        constants shared by buffer.asm/editor.asm (buffer
                       size, line cap, wrap width...)
    buffer.asm         contiguous text buffer + line-start offset table
    editor.asm          cursor, undo/redo (1 level each), word-wrap
                        movement, case-insensitive find
  spectrum/         -- ZX Spectrum platform layer
    screen.asm         bitmap rendering (reuses the ROM font at $3D00)
    keyboard.asm         matrix scan ($FE port) + key mapping
    tape.asm               cassette SAVE/LOAD (ROM routines)
    main.asm                 entry point, main loop, screen drawing --
                             assembles directly to writhdeck.tap
  tests/            -- Z80 test programs + Python harness (see below);
                       also gen_loader.py, which builds the BASIC
                       autoloader block prepended to writhdeck.tap
  Makefile
```

## Running it

```sh
make writhdeck   # produces spectrum/writhdeck.tap
```

`spectrum/writhdeck.tap` starts with a small **BASIC autoloader block**
(`tests/gen_loader.py`, run automatically by `make writhdeck`), so
loading it needs at most one command at the `48K` cold-boot prompt --
and sometimes not even that:

```sh
fuse spectrum/writhdeck.tap
```

**Do not type anything after this.** Most emulators (Fuse included --
`--auto-load`, on by default when a tape is given on the command line;
`zesarux`'s equivalent is on by default too) automatically type
`LOAD ""` and press ENTER for you the moment the tape is inserted. If
you *also* type `LOAD ""` yourself on top of that, the two load
attempts collide mid-tape and corrupt each other. Just launch it and
wait a few seconds; it should land you in the editor on its own.

If your emulator/setup does *not* auto-load (auto-load disabled, or
loading from a real cassette/real hardware), then type it yourself,
once, at the cold-boot `48K` prompt:

```
LOAD ""
```

then press ENTER, and don't touch anything else. That's it -- no
`CODE`, no `RANDOMIZE USR`, no address to remember. The autoloader
block runs itself as soon as it's loaded (`CLEAR 32767: LOAD ""CODE:
RANDOMIZE USR <_start's address>`) and pulls in the second (machine
code) block automatically.

**Important if you type this by hand**: on a real 48K keyboard, `LOAD`
is not spelled out letter by letter -- pressing **L** alone produces
`LET`, not `LOAD` (each BASIC keyword is bound to a single key at the
"K cursor"; see any Spectrum manual's keyword table printed on the
keycaps). The key that actually produces the `LOAD` keyword is **J**.
This -- typing `L`,`O`,`A`,`D` as four separate letters, which the ROM
happily accepts but turns into `LET` plus garbage rather than `LOAD`
-- is almost certainly what made the old (pre-autoloader) instructions
in this file appear broken. With the autoloader, the only keyword you
ever need to press is that single `J` (`LOAD`), then the quote key
twice for `""`, then ENTER.

If you ever need the manual fallback (no autoloader, e.g. loading just
the second tape block on its own for debugging): `J`, `"`, `"`, then
spell `CODE` out as four literal letters `C`,`O`,`D`,`E` (unlike
statement keywords, `CODE`/`DATA`/`LINE`/`SCREEN$` are not bound to a
single key -- they're recognized by the editor as you finish typing
the word), ENTER, then `RANDOMIZE USR <address>` (`T` for `RANDOMIZE`,
then Extended Mode + the `USR` key, or spell it out the same way; the
address is `_start` from `spectrum/main.sym`, currently 41515 -- this
drifts if the code size changes, which is exactly why the autoloader
exists).

### Keys

No arrows/Ctrl/Escape/Tab on a real Spectrum keyboard (40 keys), so:

| Keys | Action |
|---|---|
| CAPS SHIFT + 0 | backspace (same convention as the BASIC EDIT mode) |
| ENTER | new line |
| SYMBOL SHIFT + S / Q / Z / Y | save / quit / undo / redo |
| SYMBOL SHIFT + N,M,P,O,L,K,J + digits | comma, period, quote, semicolon, `=`, `+`, `-`, `!@#$%&'()_` |

**No cursor movement keys on this build.** A real 48K/128 keyboard has no
arrow keys at all; earlier versions faked left/down/up/right via CAPS
SHIFT+5/6/7/8 (the BASIC EDIT convention), but that combination is
ambiguous with typing a plain digit and needed extra key-combo
detection logic purely to compensate for hardware that doesn't
actually have arrow keys -- real cost, for a simulated feature. This
is now compiled out by default (`ZX_ARROWS_VIA_CAPS equ 0` in
`spectrum/keyboard.asm`) and reserved for a future target with real
cursor keys (e.g. the Spanish ZX Spectrum 128 "Investronica", which
adds a numeric keypad with dedicated arrow keys). `core/editor.asm`'s
move routines are untouched and still exist -- only the keyboard-layer
binding is gone on this target.

Quit (SYMBOL SHIFT+Q) does a soft reset (`RST 0`, back to the BASIC
screen) -- there is no dirty-check/save prompt in this port.

For any CAPS/SYMBOL SHIFT combo, hold the shift key down *first*, then
press the other key (the natural way, same as any keyboard) -- this
avoids a genuine key-detection race that's possible if both keys are
pressed at the exact same instant.

## Memory model (why it differs from the x86 port)

The [x86 port](../x86-linux) uses a heap (`malloc`/`free`) and one
allocation per line, mirroring writhdeck-c's `buffer_t`. That model
doesn't fit in 48KB of RAM. Instead:

- **`TEXTBUF`**: one fixed, contiguous block holding the *entire*
  document as raw bytes, each line terminated by a `LINE_END` marker
  (`10`, i.e. LF) -- this is nearly the on-disk file format itself.
- **`LINETAB`**: a fixed array of 16-bit **absolute addresses**, one
  per logical line, pointing into `TEXTBUF`. A line's length is derived
  from the next entry (or `TEXTEND` for the last line) -- never stored
  redundantly.
- **`TEXTEND`**: absolute address one past the last used byte.

A pleasant consequence: splitting a line (Enter) and merging two lines
(Backspace/Delete at a line boundary) become plain special cases of
inserting/deleting a single byte (the `LINE_END` marker itself) --
`core/buffer.asm` needs no separate split/merge string routines.

Editing (insert/delete a byte) shifts the tail of `TEXTBUF` with a
single `LDIR`/`LDDR` and adjusts `LINETAB` entries with simple index
scans. This is O(n) in document size, but `LDIR` is extremely fast on
real hardware and documents here are short notes, not large files --
no gap buffer or other premature optimization.

**Deliberate simplifications vs. the x86 port** (RAM-driven, confirmed
with the user):
- **Undo/redo are single-level** (one `{type, address, byte}` slot
  each, enough to exactly reverse/replay the last destructive edit),
  not a 100-deep stack of full-document clones -- unaffordable here.
- **No sticky-column memory** across consecutive UP/DOWN presses: each
  vertical move recomputes its target from the current column's offset
  within its wrapped visual row.
- **Screen scrolling is per logical line**, not per visual (wrapped)
  row like the x86 port -- simpler and robust, at the cost of not
  always filling the screen to the last pixel-row when very long lines
  wrap right at the bottom edge.
- **No file browser**: one document, fixed tape block name
  ("WRITHDECK"), no dirty-check prompt on quit.

## Building and testing

Requires `sjasmplus` (assembler) and `zesarux` (emulator, used
headless via its remote command protocol -- ZRCP -- for automated
verification; `fuse` also works interactively).

```sh
make test       # assembles tests/test_*.asm + spectrum/main.asm, runs
                 # everything under zesarux, verifies memory state
make writhdeck   # just produces spectrum/writhdeck.tap
make smoke      # minimal toolchain check (sjasmplus -> .sna -> zesarux)
make clean
```

`tests/zrcp_harness.py` launches `zesarux --vo null --enable-remoteprotocol`,
lets the test program run (it loops on itself once done, like
`tests/tap.h` on the C/x86 ports, or drives real simulated keystrokes
via ZRCP `send-keys-ascii` for `test_main.py`), then reads memory/tape
output over ZRCP and compares against expected values -- addresses are
resolved from sjasmplus's `--sym` symbol table (`TEXTBUF+2`, `snapA_cy`...),
never hand-computed. Screen rendering is checked against the ROM font
itself (read live from `$3D00`), not hand-guessed bitmap patterns.
`test_tape.py` round-trips a real `.tap` file (captured via
`--outtape`, structure/checksums verified byte-for-byte, then reloaded).
`test_writhdeck_tap.py` verifies the actual shipped `spectrum/writhdeck.tap`:
block structure and checksums parsed directly (no emulator needed),
plus both blocks (autoloader + CODE) genuinely reloaded through
`tape_load` (the real ROM `LD-BYTES` routine) to confirm the file
itself is correct.

`test_autoload.py` drives the actual interactive flow end-to-end:
cold `48K` boot, `--noautoload` (so it doesn't race against `zesarux`'s
own auto-load -- see "Running it" above), then the real keystrokes
`J`,`"`,`"`,ENTER, then confirms `editor_init` ran (`TEXTEND==TEXTBUF`).

Getting there took two real bugs in `gen_loader.py`'s hand-built BASIC
tokenization, both found via this exact test hanging/erroring instead
of passing:
1. A tokenized BASIC line stored in the program area (and thus on
   tape) needs each line prefixed with its **line number** (2 bytes,
   big-endian) and **length** (2 bytes, little-endian) *before* the
   token bytes -- not just the tokens on their own. Omitting this
   made the ROM misread the first 4 bytes of the actual statement as
   a bogus line-number/length pair, corrupting line search entirely
   (symptom: `LOAD ""CODE` never terminating, repeated/looping
   `Program:` messages on screen -- this is what was happening in the
   session's first pass at this fix, both under headless `zesarux`
   and, as reported, under a real `fuse`).
2. Every numeric literal (`32767`, the `USR` address) needs its ROM
   **floating-point number cache** (`0x0E` + 5 bytes encoding the
   value) immediately after the ASCII digits -- this turned out to be
   a hard requirement for the run-time parser, not the optional
   cosmetic optimization it's often described as; without it, `RUN`
   fails immediately with `Nonsense in BASIC`.

## Status

Fully working, tested end-to-end: typing, Enter, backspace, arrow
movement, undo/redo, cassette save/load, word-wrap with screen
scrolling. Out of scope for now: file browser, `.ini`/JSON config,
autosave/watch-file, timer, i18n, syntax highlighting, keyboard-driven
find/replace (the `editor_find` routine exists in `core/` for future
use). The `cpc/` platform layer isn't started -- planned next, reusing
`core/` entirely unchanged.

Status bar: reduced to a minimal `L<line> C<col>` on the last screen
row (no total line count, no dirty-flag asterisk) -- a fuller version
existed first, was removed entirely for a while over rendering-cost
concerns, then this trimmed form was specifically requested back.

Several real bugs were found and fixed in `spectrum/keyboard.asm`,
each surfacing as "this key doesn't work"/"the editor froze"/"typing
fast loses letters" during actual use:
- `KEY_RIGHT` was defined but never actually produced by any key row
  (CAPS SHIFT+8 fell through unmapped) -- now correctly mapped (moot
  on this build now that arrow keys are gone by default, see "Keys"
  above, but kept working for the `ZX_ARROWS_VIA_CAPS`-enabled path).
- Waiting for a keypress to register as "released" required *every*
  key on the entire 40-key keyboard to be up, not just the one
  involved in the just-detected key/combo. Typing at any normal pace
  (a new key going down slightly before the previous one is fully
  released -- entirely normal, this is how everyone types) could make
  this wait never resolve, or worse: swallow the *next* key entirely
  if its own full press-and-release cycle happened while still
  waiting on the previous key's release. `keyb_wait_key` now tracks
  which single keyboard row produced the just-decoded event
  (`kb_last_port`, set by `keyb__scan_once`) and only waits for *that*
  row to clear -- verified by direct register/state inspection in the
  emulator (the CPU visibly moves on to monitor the new row as soon as
  a second, different-row key is detected, instead of getting stuck
  polling the whole keyboard).
- An early fix attempt enabled Z80 interrupts (`EI`) so `HALT` could
  be used as a cheap combo-debounce delay. This let the ROM's default
  interrupt handler run in the background (~every 20ms), and that
  handler depends on system variables (cursor-flash state, etc.) this
  program never maintains, since the screen is managed directly, not
  through BASIC. Result: reproducible memory corruption after a few
  seconds of typing. Fixed by dropping `EI`/`HALT` entirely in favour
  of a plain T-state-calibrated busy-wait, used only for the
  genuinely ambiguous keys (a handful of digits/letters that have a
  different CAPS/SYMBOL SHIFT meaning) -- ordinary typing and ENTER
  pay no debounce cost at all.

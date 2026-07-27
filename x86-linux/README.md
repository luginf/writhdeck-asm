# writhdeck-asm

x86 assembly port (FASM, Intel syntax) of [WrithDeck](https://github.com/luginf/writhdeck),
based on the logic already ported to C in [writhdeck-c](../writhdeck-c).
Hand-written binary: zero libc, zero C toolchain, direct Linux syscalls
(`int 0x80`).

## Target

- **i386 (32-bit)**, protected mode, syscalls via `int 0x80`. A static
  ELF32 built this way runs as-is on real 32-bit hardware *and*,
  unchanged, on any x86_64 Linux thanks to the kernel's IA32
  compatibility layer -- same reasoning as writhdeck-c's
  `writhdeck-ansi-musl-i386` variant.
- **No CMOVcc instruction, nothing past i486**: constraint inherited
  from writhdeck-c (see its `CLAUDE.md`, rounds 20-21), verified on real
  hardware (Toshiba Satellite 2180 / AMD K6, which doesn't implement
  CMOV). Every conditional branch uses a classic jump (`jCC`).

## Current status: working terminal editor

```sh
make writhdeck
./bin/writhdeck [path]     # opens path, or starts an empty draft if omitted
```

Faithful port of `writhdeck-c/src/{buffer,editor,utf8,ui_ansi}.c` and
`common.c:ascii_stristr`, plus a minimal main loop:

- `src/heap.asm` -- malloc/free/realloc (brk-based, implicit list,
  full-pass coalescing on every free)
- `src/strutil.asm` -- memcpy/memmove/memset/strlen/strdup,
  tolower_ascii/ascii_stristr
- `src/utf8.asm` -- UTF-8 decode/encode, column(codepoint)<->byte
  conversions
- `src/buffer.asm` -- dynamic line array: character-level insert/
  delete/merge, file load/save, word/char counting, joining
- `src/editor.asm` -- cursor, undo/redo (100-entry cap, oldest evicted
  first), movement with sticky column across visual (word-wrapped)
  lines, find/replace
- `src/term.asm` -- raw terminal mode (termios via ioctl), window size,
  short poll (used to tell a lone Escape key from an ANSI sequence)
- `src/ui_ansi.asm` -- ANSI/VT100 rendering (frame buffer, flicker-free
  single write per refresh) and keyboard event decoding
- `src/draw.asm` + `src/main.asm` -- screen drawing (word-wrap,
  scrolling, minimal status bar) and the key-dispatch main loop

Supported keys: arrows, Home/End, PgUp/PgDn, Enter, Backspace, Delete,
Tab, Ctrl+Space (word-right), Ctrl+Z/Ctrl+Y (undo/redo), Ctrl+S (save),
Ctrl+Q (quit, unconditionally -- no dirty-check prompt in this port).

Ctrl+S when no file is open yet (started with no path, still `[draft]`
in the status bar) shows an inline "Save as: " prompt on the status
line -- type a name, Enter to save (and remember that path for
subsequent Ctrl+S, no more prompting), Escape to cancel. ASCII
filenames only (see i18n note below). This is a single-line prompt,
not a file browser: no directory navigation, no autocomplete. If the
typed name already exists, a confirmation ("<name> exists - overwrite?
(y/n)") is shown before anything is touched -- `n`/Escape returns to
the name prompt (with what you typed still there, so you can just fix
it), `y` overwrites.

Deliberately out of scope for this port: file browser, `.ini`/JSON
config, autosave/watch-file, timer, i18n, syntax highlighting, quit
confirmation prompt. No SIGWINCH handling either -- terminal size is
re-read every frame, so a resize takes effect on the next keystroke
rather than instantly.

## Building and testing

```sh
make test       # assembles and runs every tests/test_*.asm
make writhdeck   # builds the final editor (bin/writhdeck)
make smoke      # just checks the fasm -> ELF32 -> execution chain
make clean
```

Each binary (tests, and `bin/writhdeck`) is a self-contained FASM entry
point (`format ELF executable`) that `include`s the needed source
modules -- no separate `ld` linking step.

Most of the core (`buffer.asm`, `editor.asm`, `utf8.asm`, `strutil.asm`,
`heap.asm`) is covered by `tests/test_*.asm`, run without any terminal.
The interactive parts (`term.asm`, `ui_ansi.asm`'s `ui_init`) need a
real (or pseudo-) terminal to exercise `ioctl(TCGETS/TCSETSF)`; they
were validated by driving `bin/writhdeck` under a Python `pty`,
scripting keystrokes and checking the saved file's content end-to-end.

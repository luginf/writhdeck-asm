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

Faithful port of `writhdeck-c/src/{buffer,editor,utf8,ui_ansi,highlight}.c`
and ` common.c:ascii_stristr`, plus a minimal main loop:
dsfsf
- `src/heap.asm` -- malloc/free/realloc (brk-based, implicit list,
  full-pass coalescing on every free)
- `src/strutil.asm` -- memcpy/memmove/memset/strlen/strdup,
  tolower_ascii/ascii_stristr
- `src/utf8.asm` -- UTF-8 decode/encode, column(codepoint)<->byte
  conversions
- `src/buffer.asm` -- dynamic line array: character-level insert/
  delete/merge, file load/save, word/char counting, joining
- `src/highlight.asm` -- line classification (heading/comment/list),
  heading level + title extraction, table-of-contents builder
- `src/editor.asm` -- cursor, undo/redo (100-entry cap, oldest evicted
  first), movement with sticky column across visual (word-wrapped)
  lines, find/replace
- `src/term.asm` -- raw terminal mode (termios via ioctl), window size,
  short poll (used to tell a lone Escape key from an ANSI sequence)
- `src/ui_ansi.asm` -- ANSI/VT100 rendering (frame buffer, flicker-free
  single write per refresh) and keyboard event decoding
- `src/draw.asm` + `src/main.asm` -- screen drawing (word-wrap,
  scrolling, per-line syntax coloring, minimal status bar), the
  full-screen table of contents (F11), and the key-dispatch main loop

Supported keys: arrows, Home/End, PgUp/PgDn, Enter, Backspace, Delete,
Tab, Ctrl+Space (word-right), Ctrl+Z/Ctrl+Y (undo/redo), Ctrl+S (save),
Ctrl+F (find -- inline "Find: " prompt on the status line, Enter
confirms even on an empty line which re-searches for the last term
instead, Escape cancels and also falls back to the last term; case-
insensitive, wraps around the whole document; shows "Not found: ..."
if nothing matches), Ctrl+Q (quit -- prompts "Save changes? (y/n)"
first if there are unsaved changes; always quits either way, `y` saves
first), F11 (table of contents).

### Syntax highlighting and table of contents

Each line is classified (heading > comment > list precedence, same as
`writhdeck-c`) and colored accordingly: headings in red/bold, comments
dim, list markers in green. Two title syntaxes are recognized:
txt2tags-style (`= Title =`, `== Title ==`, ...) and Markdown-style
(`# Title` through `###### Title`, Markdown support on by default).
Lines starting with `%` (no leading whitespace) are comments; `- item`
or `* item` are list items.

F11 opens a full-screen table of contents built from every recognized
heading, indented by level; Up/Down/Home/End to navigate, Enter to
jump to that line, Escape or F11 again to cancel.

The heading marker (`=`), comment marker (`%`) and Markdown support
(on) are **fixed constants** in `src/highlight.asm`, matching
`writhdeck-c`'s defaults -- unlike the margins/word goal below, the
`.ini` config parser doesn't read any key for these, so they stay
fixed regardless of `writhd.ini`.

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

Deliberately out of scope for this port: file browser, autosave/
watch-file, timer, i18n. No SIGWINCH handling either -- terminal size
is re-read every frame, so a resize takes effect on the next keystroke
rather than instantly.

### `.ini` config (partial)

`src/config.asm` reads `writhd.ini`/`writhdeck.ini`, at the SAME
precedence as `writhdeck-c/src/main.c`: `writhd.ini` (8.3-compatible
name) in the current directory first; if absent, falls back to
`$HOME/Documents/writhdeck/writhdeck.ini`. First one found wins, no
merging of the two. Same line format as writhdeck-c's own parser
(`[section]` headers, `key = value`, `#`/`%` comments, blank lines
ignored).

Only the keys that map to something this minimal port actually does
are applied -- everything else in a real `writhd.ini` (browser/timer/
autosave/i18n/markdown/GUI profiles/TUI colors/keybindings) is read
without error but silently ignored, same "recognize a subset, ignore
the rest" discipline writhdeck-c itself already applies to the much
larger Tcl-GUI original file:

- `[editor]` `console_margin_cols`/`margin_cols`,
  `console_margin_rows`/`margin_rows` (default 6/4) -- symmetric
  left/right and top/bottom margins around the text area, falls back
  to 0 if the terminal is too small to fit them.
- `[behaviour]` `word_goal` (default 0 = hidden) -- see the `goal`
  token below.
- `[behaviour]` `status_left`/`status_center`/`status_right` -- the
  status bar is composed from three space-separated token lists (same
  defaults as writhdeck-c: `status_left = "workspace filename dirty
  sel ln col words chars"`, `status_center = ""`, `status_right =
  "help_bar clock"`), left-aligned/centered/right-aligned across the
  terminal width. Recognized tokens: `filename` (basename or
  `[draft]`), `dirty` (` [+]` if unsaved changes), `ln` (`  Ln
  <line>/<total>`), `col` (`  Col <col>`, left-padded to width 3),
  `words`/`chars` (document totals, `  <n>w`/`  <n>c`), `goal`
  (`  <words>/<goal>`, hidden if `word_goal` is 0 -- unlike
  writhdeck-c this counts the CURRENT DOCUMENT's total words, not
  "words typed today", which needs a persistent cross-session stats
  file, out of scope here), `clock` (`  HH:MM`, **UTC**, not local
  time -- no timezone database in this port), `space` (a literal
  space, for extra separation). `workspace`/`sel`/`help_bar`/`timer`
  are recognized but produce nothing (no second workspace, no text
  selection, no separate help bar, no timer in this port -- same as
  writhdeck-c itself, which doesn't implement them either). Any other
  token is copied through as-is, so custom separators like `|` work.

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
`heap.asm`, `highlight.asm`, `config.asm`, and `draw.asm`'s status-bar
token builder) is covered by `tests/test_*.asm`, run without any
terminal.
The interactive parts (`term.asm`, `ui_ansi.asm`'s `ui_init`) need a
real (or pseudo-) terminal to exercise `ioctl(TCGETS/TCSETSF)`; they
were validated by driving `bin/writhdeck` under a Python `pty`,
scripting keystrokes and checking the saved file's content end-to-end.

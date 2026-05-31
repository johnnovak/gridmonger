# Gridmonger source tree

Gridmonger is a GUI map editor. The codebase is organized so that **where a
file lives tells you what kind of code it contains and which side effects it
performs**. This document is for orienting yourself — for what an individual
file owns, read the short comment block at the top of the file.

## Folder map

```
src/
├── main.nim                # Entry point (~200 lines: imports + main loop)
│
├── main/                   # Everything that used to be in the giant main.nim
│   ├── appcontext.nim      #   AppContext type + every companion state type
│   ├── constants.nim       #   File extensions, UI dimensions, floor groups
│   ├── shortcuts.nim       #   AppShortcut enum + QuickRefItem types
│   ├── keyboard.nim        #   Keyboard shortcut data + match/dispatch helpers
│   ├── logging.nim         #   Log file rotation + init
│   ├── view.nim            #   Read-only view accessors (currLevel, viewRow, ...)
│   ├── status_msg.nim      #   Status / warning / error message setters
│   ├── cursor.nim          #   Cursor and view-scroll movement
│   ├── modes.nim           #   Pure UI-state mode transitions
│   ├── versioncheck.nim    #   AppContext fields reset for latest-version check
│   ├── themeio.nim         #   Theme load/save/switch + scale-factor helpers
│   ├── configio.nim        #   App config + window-layout persistence (HOCON)
│   ├── mapio.nim           #   Map file (.gmm) load/save/autosave
│   ├── dialogs.nim         #   All 13+ dialog procs (one big file for now)
│   ├── actions_ui.nim      #   UI-side wrappers around domain actions
│   ├── rendering.nim       #   All AppContext-aware render procs
│   ├── events.nim          #   Mouse + keyboard event dispatchers
│   └── init.nim            #   App init/cleanup/splash + window callbacks
│
├── common.nim              # Domain types and constants (Location, Floor, ...)
├── actions.nim             # High-level domain actions on Map/Level
├── undomanager.nim         # Generic undo/redo
├── appevents.nim           # Background threads (autosave, version check, IPC)
├── cfghelper.nim           # HOCON reader helpers
├── cmdline.nim             # argv parsing
├── fieldlimits.nim         # Validation primitives
│
├── domain/                 # Pure data model — no AppContext, no I/O, no UI
│   ├── annotations.nim
│   ├── cellgrid.nim
│   ├── level.nim
│   ├── links.nim
│   ├── map.nim
│   ├── regions.nim
│   └── selection.nim
│
├── ui/                     # Visual primitives — take what they need as args
│   ├── csdwindow.nim       #   Custom client-side decorated window
│   ├── drawlevel.nim       #   Level rendering (nanovg)
│   ├── gfx.nim             #   Stateless image/pattern helpers
│   ├── icons.nim           #   Icon unicode constants
│   └── theme.nim           #   Theme types + HOCON theme parser
│
├── io/
│   └── persistence.nim     # RIFF map (.gmm) read/write
│
├── platform/               # Platform-specific bits
│   ├── macos/fileopener.nim
│   └── windows/
│       ├── console.nim
│       └── ipc.nim
│
└── utils/                  # Reusable utilities (no project-specific types)
    ├── converters.nim      #   Implicit int↔float converters
    ├── hocon.nim           #   HOCON parser
    ├── misc.nim            #   `alias` template, `clampMin`, ...
    ├── naturalsort.nim     #   Alphanumeric ("Level10" after "Level2")
    ├── rect.nim            #   Generic Rect[T] + intersect, contains, ...
    ├── rle.nim             #   Run-length encoding for the .gmm format
    └── webbrowser.nim      #   openUserManual(manualDir)
```

## Side-effect segregation

Every file's top-of-file comment names its side-effect class. The rough
buckets, from cleanest to dirtiest:

| Class | Where it lives |
|---|---|
| **Pure data / types** | `utils/*`, `common.nim`, `domain/*`, `ui/icons.nim`, `ui/theme.nim`, `fieldlimits.nim`, `cfghelper.nim`, `undomanager.nim`, `actions.nim`, `main/{appcontext, constants, shortcuts, keyboard}.nim` |
| **State mutation only** (touches AppContext, no I/O / draw / input) | `main/{view, status_msg, cursor, modes, versioncheck, actions_ui}.nim` |
| **File I/O** | `io/persistence.nim`, `main/{themeio, configio, mapio, logging}.nim`, `appevents.nim` |
| **OS / browser** | `utils/webbrowser.nim`, `platform/*` |
| **Drawing** (koi + nanovg) | `ui/{drawlevel, csdwindow, gfx}.nim`, `main/{rendering, dialogs}.nim` |
| **Input** (GLFW events) | `main/{events, init}.nim`, `cmdline.nim` |

A few specific observations:

- **`main/keyboard.nim` is pure logic** — it operates on `koi.Event` data
  values passed in by the caller, not live GLFW state. Unit-testable today.
- **`main/init.nim` mixes init and the per-frame window callbacks.** They
  share so much of the same dependency surface (splash window, theme load,
  render dispatch) that splitting them creates a cycle. Treat init.nim as
  "everything that lives at the app lifecycle level."
- **`dialogs.nim` and `rendering.nim` are still single big files (~2700
  and ~2100 lines).** Sub-splitting them into per-dialog and per-pane files
  is a planned follow-up — the 7 shared dialog templates implicitly capture
  `a` and `dlg` from caller scope, so a per-file split needs facade
  re-exports.

## Dependency direction

The module graph is a DAG. From cleanest (leaf, no internal imports) to
dirtiest (top, imports everything below):

```
Tier 0 — pure roots:
    utils/*, common, domain/*, ui/icons, ui/theme, fieldlimits, cfghelper,
    undomanager, actions, main/{appcontext, constants, shortcuts}, ui/gfx
        ↓
Tier 1 — state helpers (AppContext-aware, pure logic):
    main/{view, status_msg, cursor, modes, keyboard, logging, versioncheck}
        ↓
Tier 2 — I/O:
    io/persistence, main/{themeio, configio, mapio}, appevents
        ↓
Tier 3 — dialogs:
    main/dialogs
        ↓
Tier 4 — workflow:
    main/actions_ui
        ↓
Tier 5 — drawing:
    ui/{csdwindow, drawlevel}, main/rendering
        ↓
Tier 6 — input dispatch:
    main/events
        ↓
Tier 7 — lifecycle:
    main/init
        ↓
Tier 8: main.nim
```

A module can import from any module in a lower tier. Sibling modules in the
same tier don't import each other.

## Conventions

- **`# vim: et:ts=2:sw=2:fdm=marker`** at the bottom of every file.
- **`# {{{ Name` / `# }}}` fold markers** delineate logical sections inside
  each file. Vim's fold method picks them up automatically; other editors
  often have plugins.
- **`using a: var AppContext`** appears once at the top of every `main/*.nim`
  file. It lets procs take `a` without writing the type, the same way the
  original single-file `main.nim` did.
- **Every type field that's accessed from outside its module is marked `*`.**
  Most of `appcontext.nim` is starred — that's intentional; AppContext is a
  shared mutable god-context, not a hidden-state object.

## Tests

Unit tests live in `tests/` and use `std/unittest`. Run them with `nim test`
from the project root. The one exception is `src/utils/hocon.nim` — its
tests reference private types (`Token`, `tkString`) and stay inline as
`when isMainModule:`. The `test` task runs both.

## What was wrong with the old layout

`main.nim` was 11,130 lines and held essentially every piece of UI glue:
dialogs, rendering, event dispatch, keyboard shortcut definitions, theme
loading, file I/O, init/cleanup, the splash screen, AppContext itself. The
existing `# {{{` fold markers showed the author had already organized it
mentally into ~96 sections; the refactor just turned each cohesive group
of sections into a real Nim module.

The other 19 src/ files were flat. Splitting them into `domain/`, `ui/`,
`io/` and keeping `utils/` and `platform/` as-is gives a clear visual cue
about what layer each file belongs to.

<!-- vim: et:ts=2:sw=2:fdm=marker -->

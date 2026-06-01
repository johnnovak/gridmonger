# Gridmonger source tree

Gridmonger is a GUI map editor. The codebase is organized so that **where a
file lives tells you what kind of code it contains and which side effects it
performs**. This document is for orienting yourself — for what an individual
file owns, read the short comment block at the top of the file.

## Folder map

```
src/
├── main.nim                # Entry point (~140 lines: imports + main() loop)
│
├── main/                   # Everything that used to be in the giant main.nim
│   ├── appcontext.nim      #   AppContext + every companion state type +
│   │                       #   AppShortcut/QuickRefItem types
│   ├── constants.nim       #   File extensions, UI dimensions, floor groups
│   ├── keyboard.nim        #   Keyboard shortcut data + match/dispatch helpers
│   │                       #   + handleTabNavigation
│   ├── logging.nim         #   Log file rotation + init
│   ├── view.nim            #   Read-only view accessors (currLevel, viewRow, ...)
│   ├── cursor.nim          #   Cursor + view-scroll movement
│   ├── modes.nim           #   Pure UI-state mode transitions
│   ├── versioncheck.nim    #   AppContext reset for latest-version polling
│   ├── themeio.nim         #   Theme load/save/switch + scale-factor helpers
│   ├── configio.nim        #   App config + window-layout persistence (HOCON)
│   ├── mapio.nim           #   Map file (.gmm) load/save/autosave
│   ├── actions_ui.nim      #   UI-side wrappers around domain actions
│   ├── events.nim          #   Mouse + keyboard event dispatchers
│   ├── frame.nim           #   Top-level frame orchestrator (renderUI +
│   │                       #   renderDialogs)
│   ├── init.nim            #   App init/cleanup/splash + window callbacks
│   │
│   ├── panes/              #   Per-pane modules — each file owns *everything*
│   │   │                   #   about that pane (rendering + state mutators +
│   │   │                   #   sort/cache helpers + keyboard handler if
│   │   │                   #   pane-specific)
│   │   ├── levelview.nim      #     The central level view + level/region
│   │   │                      #     dropdowns + mode indicators + tooltip
│   │   ├── currentnotepane.nim   # Below the level view (current cell's note)
│   │   ├── noteslistpane.nim     # Left side (all notes, with filters)
│   │   ├── toolspane.nim         # Right side (special-wall + floor-color)
│   │   ├── statusbar.nim         # Bottom + ALL message setters
│   │   ├── quickref.nim          # `?` keyboard reference overlay
│   │   └── themepanel.nim        # Right-side theme editor
│   │
│   └── dialogs/            #   One file per dialog + shared infrastructure
│       ├── common.nim      #     The 7 shared field templates, dialog
│       │                   #     constants, layout helpers. Heavy re-exports
│       │                   #     so per-dialog files only need to add their
│       │                   #     own extras.
│       ├── about.nim
│       ├── preferences.nim
│       ├── save_discard_map.nim
│       ├── new_map.nim
│       ├── edit_map_props.nim
│       ├── new_level.nim
│       ├── edit_level_props.nim
│       ├── resize_level.nim
│       ├── delete_level.nim
│       ├── edit_note.nim
│       ├── edit_label.nim
│       ├── edit_region.nim
│       ├── save_discard_theme.nim
│       ├── overwrite_theme.nim
│       ├── copy_theme.nim
│       ├── rename_theme.nim
│       └── delete_theme.nim
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
│   ├── all.nim             #   Aggregator (re-exports all of domain/*)
│   ├── annotations.nim
│   ├── cellgrid.nim
│   ├── level.nim
│   ├── links.nim
│   ├── map.nim
│   ├── regions.nim
│   └── selection.nim
│
├── ui/                     # Visual primitives — take what they need as args
│   ├── all.nim             #   Aggregator (re-exports all of ui/*)
│   ├── csdwindow.nim       #     Custom client-side decorated window
│   ├── drawlevel.nim       #     Level rendering (nanovg)
│   ├── gfx.nim             #     Stateless image/pattern helpers
│   ├── icons.nim           #     Icon unicode constants
│   └── theme.nim           #     Theme types + HOCON theme parser
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
    ├── all.nim             #   Aggregator (re-exports all of utils/*)
    ├── converters.nim      #     Implicit int↔float converters
    ├── hocon.nim           #     HOCON parser
    ├── misc.nim            #     `alias` template, `clampMin`, ...
    ├── naturalsort.nim     #     Alphanumeric ("Level10" after "Level2")
    ├── rect.nim            #     Generic Rect[T] + intersect, contains, ...
    ├── rle.nim             #     Run-length encoding for the .gmm format
    └── webbrowser.nim      #     openUserManual(manualDir)
```

## Aggregators

`domain/all.nim`, `ui/all.nim`, and `utils/all.nim` each import + re-export
every other file in their folder. Consumers outside that folder can write
one `import domain/all` line instead of listing the 7 individual domain
modules. Cuts ~15 imports per consumer file.

Files **inside** a folder keep their sibling imports explicit (e.g.,
`domain/level.nim` says `import annotations` directly, not `import all`)
— an aggregator import from inside the folder would create a cycle.

Inside `main/`, sibling imports also stay explicit. There's no
`main/all` aggregator because:
1. Internal main/* modules would cycle through it.
2. The explicit import edges document the actual DAG.

The two notable bulk re-exporters that DO live inside main/:

- **`main/dialogs/common.nim`** — re-exports stdlib, koi, nanovg, common,
  appcontext, keyboard, statusbar, view, etc. so per-dialog files don't
  repeat 20+ imports each. They just `import main/dialogs/common` and add
  their specific extras (themeio, mapio, etc.).
- **`main/dialogs.nim`** — pure shim that re-exports all of
  `main/dialogs/*`. Consumers writing `import main/dialogs` get the full
  set of openXxxDialog + XxxDialog procs.

## Side-effect segregation

Every file's top-of-file comment names its side-effect class. The rough
buckets, from cleanest to dirtiest:

| Class | Where it lives |
|---|---|
| **Pure data / types** | `utils/*`, `common.nim`, `domain/*`, `ui/icons`, `ui/theme`, `fieldlimits.nim`, `cfghelper.nim`, `undomanager.nim`, `actions.nim`, `main/{appcontext, constants, keyboard}.nim` |
| **State mutation only** (touches AppContext, no I/O / draw / input) | `main/{view, cursor, modes, versioncheck, actions_ui}.nim` |
| **File I/O** | `io/persistence.nim`, `main/{themeio, configio, mapio, logging}.nim`, `appevents.nim` |
| **OS / browser** | `utils/webbrowser.nim`, `platform/*` |
| **Drawing** (koi + nanovg) | `ui/{drawlevel, csdwindow, gfx}.nim`, `main/panes/*.nim`, `main/dialogs/*.nim`, `main/frame.nim` |
| **Input** (GLFW events) | `main/events.nim`, `main/init.nim` (window callbacks), `cmdline.nim` |

A few specific observations:

- **`main/keyboard.nim` is pure logic** — it operates on `koi.Event` data
  values passed in by the caller, not live GLFW state. Unit-testable today.
- **`main/init.nim` mixes init and the per-frame window callbacks.** They
  share so much of the same dependency surface (splash window, theme load,
  render dispatch) that splitting them creates a cycle.
- **Per-pane principle**: each file under `main/panes/` owns *everything*
  about that pane — render proc, state mutators, sort/cache helpers, even
  keyboard handlers when they're pane-specific (e.g. `quickref.nim` owns
  `handleQuickRefKeyEvents`).
- **`panes/statusbar.nim`** is the textbook case for that principle. The
  message setters (`setStatusMessage` etc.) and the renderer
  (`renderStatusBar`) both touch `AppContext.ui.status`; splitting them
  by file was artificial. Co-located.

## Dependency direction

The module graph is a DAG. From cleanest (leaf, no internal imports) to
dirtiest (top, imports everything below):

```
Tier 0 — pure roots:
    utils/*, common, domain/*, ui/icons, ui/theme, fieldlimits, cfghelper,
    undomanager, actions, main/{appcontext, constants}, ui/gfx
        ↓
Tier 1 — state helpers (AppContext-aware, pure logic):
    main/{view, cursor, modes, keyboard, logging, versioncheck}
        ↓
Tier 2 — I/O:
    io/persistence, main/{themeio, configio, mapio}, appevents
        ↓
Tier 3 — panes/statusbar (depended on by many):
    main/panes/statusbar
        ↓
Tier 4 — actions_ui (depends on statusbar + I/O + dialogs):
    main/actions_ui  (NOTE: imports dialogs — see Tier 4.5 below)
        ↓
Tier 4.5 — dialogs:
    main/dialogs/common  →  main/dialogs/*  →  main/dialogs (shim)
        ↓
Tier 5 — other panes:
    main/panes/{levelview, currentnotepane, noteslistpane, toolspane,
                quickref, themepanel}
        ↓
Tier 6 — input dispatch:
    main/events
        ↓
Tier 7 — frame + lifecycle:
    main/frame, main/init
        ↓
Tier 8: main.nim
```

A module can import from any module in a lower tier. Sibling modules in
the same tier don't import each other.

## Conventions

- **`# vim: et:ts=2:sw=2:fdm=marker`** at the bottom of every file.
- **`# {{{ Name` / `# }}}` fold markers** delineate logical sections inside
  each file.
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
`when isMainModule:`. The `test` task in `config.nims` runs both.

## History

This source tree is the result of two refactors:

1. **The first split** broke up an 11,130-line `main.nim` into ~18 modules
   under `main/`, alongside light folder grouping of the other 19 source
   files into `domain/`, `ui/`, `io/`. (Plan archived in git history.)
2. **The second round** introduced the per-pane principle (status_msg got
   merged into statusbar, the rendering module got split per pane into
   `main/panes/`, quickref and themepanel got their own files), added the
   `domain/all` / `ui/all` / `utils/all` aggregator files to cut import
   noise, merged the `shortcuts.nim` type-only file into `appcontext.nim`,
   and split the 2700-line `dialogs.nim` into per-dialog files.

The original 11,130-line `main.nim` is now ~140 lines of imports + main
loop.

<!-- vim: et:ts=2:sw=2:fdm=marker -->

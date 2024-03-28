# Changelog

## v1.2.0 – 2024-04-25

### New features

- Multi-monitor support.
- Option to [nudge levels](https://gridmonger.johnnovak.net/manual/advanced-editing.html#nudge-level)
  and move or paste [selections](https://gridmonger.johnnovak.net/manual/advanced-editing.html#selections)
  with wraparound.
- Support for [diagonal movement](https://gridmonger.johnnovak.net/manual/moving-around.html#diagonal-movement)
  via the numeric keypad or the YUBN keys (à la Rogue).
- [Open-ended excavate](https://gridmonger.johnnovak.net/manual/basic-editing.html#open-ended-excavate)
  option to aid exploring tunnel style dungeons.
- Option to select whether the Left/Right cursor keys perform strafing or
  turning in [Walk Mode](https://gridmonger.johnnovak.net/manual/moving-around.html#walk-mode).
- Support for panning the level with the mouse (middle-click + drag, or
  Ctrl + left-click + drag). Works in *Paste Preview Mode* and *WASD Mode* too.
- The selection can now be moved with the mouse in *Paste Preview Mode*.
- The [user manual](https://gridmonger.johnnovak.net/manual/contents.html) is
  now searchable (works in the offline documentation too, but only page titles
  are displayed in the search results).
- You can now load map files by drag & dropping their icons onto the program
  window or taskbar icon.
- Option to get a notification when a new version is available.
- macOS: Support for opening map files from the Finder.

### Enhancements

- Erase and clear floor actions don't erase labels now.
- Clear floor actions don't erase annotations now.
- Setting the cursor position with the mouse has been improved; now the cursor
  follows the mouse pointer when you move it outside of the level's bounds.
- Turn off *Trail Mode* automatically in more scenarios that would result in
  confusing or unwanted behaviour.
- Restoring the window size and position on startup is now more robust.
- Idle perfomance has been improved; CPU and GPU utilisation is now close to
  zero if there is no user input.
- The user manual has been overhauled for improved wording and clarity.
- Improved status bar messages, dialogs, and more status icons.
- Minor improvements to some of the bundled themes.

### Fixes

- Fix crash when undoing the creation of the first level in an empty map.
- Fix crash when deleting the last remaining level of a map.
- Fix crash when nudging large levels zooomed in close to the maximum zoom
  factor.
- Fix nudging non-square levels; previously, the maximum vertical nudge amount
  was erroneously capped by the level's number of columns (instead of number
  of rows).
- Fix moving selections not moving links correctly (or at all).
- Fix moving selections leaving copies of the original labels if they were on
  empty cells.
- Fix evil move selection link corruption bug. Moving cells that contain
  links, then either cancelling the move operation or performing it and then
  undoing the move could generate extra "invisible" invalid links. You could
  continue using the program and saving the map would still succeed, but you
  could not load it back later.
- Canceling the "Save As" dialog invoked during the quit process no longer
  exits and discards the map without saving.
- If autosaving is enabled, the map no longer gets immediately auto-saved
  right after adding the first level to an empty map.
- The autosave timer now resets when the autosave preference is turned on.
- Autosaved untitled maps that have never been manually saved are now
  auto-numbered and are restored if the **Load last map** preference is enabled.
- The notes pane now fills the window horizontally when the tools pane is
  hidden.

---

## v1.1.0 – 2023-02-02

### New features

- Add Column and Statue floor types.

---

## v1.0.1 – 2022-12-29

### Fixes

- Fix bug where no operation can be performed on the selection in *Mark Mode*
  if only cells from the bottom row are selected.
- Fix a very obscure bug where the auto-saved map can get occasionally
  corrupted when creating a level with smaller dimensions than the current
  one.

---

## v1.0.0 – 2022-11-06

### New features

- Add preferences option to enable movement wraparound.
- Allow multiple source links for teleporters (Teon Banek).
- New Werdna theme (designed for the PC/CGA version of Wizardry 1-5).

### Fixes

- Fix Draw Wall Repeat modifier handling on Linux.
- Fix cursor jump when cursor is close to the level edges (Teon Banek).

### Contributors

- Teon "Th30n" Banek <<theongugl@gmail.com>>

---

## v0.9 – 2022-09-21

- First public release


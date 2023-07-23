# Changelog

## v1.2.0 – 2023-07-xx

### New features

- Add support for panning the level with the mouse (middle-click + drag, or
  Ctrl + left-click + drag). Works in Paste Preview Mode and WASD Mode too.

- The selection can now be moved with the mouse in Paste Preview Mode.

### Enhancements

- Better mouse handling when using the mouse to place the cursor and the
  mouse pointer is moved outside of the bounds of the level.

- Setting the cursor position with the mouse is improved; now the cursor
  follows the mouse pointer even if you move it outside of the level's
  bounds.

### Fixes

- Fix crash when undoing the creation of the very first level.

- Fix crash when deleting the last remaining level of a map.

- If auto-saving is enabled, the map no longer gets immediately auto-saved
  right after adding the first level to an empty map.

- The auto-save timer resets when the auto-save is enabled from a disabled
- state.


---

## v1.1.0 – 2023-02-02

### New features

- Add Column and Statue floor types.


---

## v1.0.1 – 2022-12-29

### Fixes

- Fix bug where no operation can be performed on the selection in "Mark mode"
  if only cells from the bottom row are selected.

- Fix a very obscure bug where the auto-saved map can get occasionally
  corrupted when creating a level with smaller dimensions than the current
  one.


---

## v1.0.0 – 2022-11-06

### New features

- Add preferences option to enable movement wrap-around.

- Allow multiple source links for teleporters (Teon Banek).

- New Werdna theme (designed for the PC/CGA version of Wizardry 1-5).

### Fixes

- Fix "Draw Wall Repeat" modifier handling on Linux.

- Fix cursor jump when cursor is close to the level edges (Teon Banek).

### Contributors

- Teon "Th30n" Banek <<theongugl@gmail.com>>


---

## v0.9 – 2022-09-21

- First public release


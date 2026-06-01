# dialogs
#
# Re-export shim. The actual dialog procs live in main/dialogs/<name>.nim
# files (mostly one per dialog; theme.nim holds all 5 theme dialogs which
# share a tightly-coupled workflow). Shared infrastructure is in
# main/dialogs/common. Consumers can `import main/dialogs` and get the full
# set of openXxxDialog + XxxDialog procs without naming each per-dialog
# module.

import ./dialogs/common
import ./dialogs/about
import ./dialogs/preferences
import ./dialogs/save_discard_map
import ./dialogs/new_map
import ./dialogs/edit_map_props
import ./dialogs/new_level
import ./dialogs/edit_level_props
import ./dialogs/resize_level
import ./dialogs/delete_level
import ./dialogs/edit_note
import ./dialogs/edit_label
import ./dialogs/edit_region
import ./dialogs/theme

export common, about, preferences,
       save_discard_map, new_map, edit_map_props,
       new_level, edit_level_props, resize_level, delete_level,
       edit_note, edit_label, edit_region,
       theme

# vim: et:ts=2:sw=2:fdm=marker

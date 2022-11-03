****************
Advanced editing
****************

Cell links
==========

A very handy advantage of Gridmonger over pencil-and-paper mapping is the
ability to establish links between cells. Links can be created between the
following cell types:

- pits and ceiling pits
- teleport sources and destinations
- upward and downward stairs
- entrance and exit doors

You can jump between linked cells by pressing the :kbd:`G` key, which is very
useful when navigating through complex, interlocking multi-level dungeons. The
included ``Eye of the Beholder I`` and ``The Dark Heart of Uukrul`` example
maps are great demonstrations of this.

To create a link, first move the cursor to the source cell and press
:kbd:`Shift+G` to enter *Set Link Destination Mode*. Now move the cursor to
the target cell, then press :kbd:`Enter` to create the link or :kbd:`Esc` to
cancel. All the common navigation shortcuts are available in this mode, so you
can change the current level, zoom in and out, etc.

The destination cell will be overwritten, but any existing note will be
preserved (and potentially converted to a **None** marker type). Once a link
has been created, you can see small triangles in the bottom-left corner of
the two linked cells.


.. raw:: html

    <div class="figure">
      <a href="_static/img/cell-links.png" class="glightbox">
        <img alt="Examples of linked cells" src="_static/img/cell-links.png"
        style="width: 35%">
      </a>
        <p class="caption">
          <span>Examples of linked cells</span>
        </p>
    </div>


To jump back and forth between two linked cells, place the cursor at either
end of the link, then press :kbd:`G`.

If you delete a cell that is part of a link, the other end will be unlinked,
but otherwise left intact. In fact, this is the easiest way to break a link.

The exact rules for creating links vary per linkable cell type:

Pits
    The link source must be a closed, open or hidden pit. The link destination
    is always set to a ceiling pit.

Teleports
    The link source can be either a teleport source or a teleport destination.
    The destination cell is automatically set to the other teleport type.

Stairs
    The link source can be either a downward or an upward stairs cell. The the
    direction of the stairs will be automatically adjusted based on the
    elevation of the involved levels.

Doors
    The link source can be either an entrance or an exit door.  The
    destination cell is automatically set to the other door type.


.. note::

    A cell cannot be both a link source and a destination, so you cannot
    create things like chain-linked teleport cells or multi-level staircases.
    Furthermore, links can only be created between exactly two cells. So, for
    instance, you cannot have two teleport sources that are linked to the same
    destination cell. Likewise, you cannot have a teleport source that is
    linked to multiple destinations (e.g. for teleports that would take the
    player to a randomly chosen location).

    All these constraints are enforced at link creation time: if either the
    source or the destination cell is already part of a link, those links will
    be severed before creating the new one.


.. rst-class:: style3

Selections
==========

The idea behind selections is simple: you select a number of cells first, then
perform some action on them.

All editing actions presented so far have to be invoked from *Edit Mode*,
which is the default operational mode of the program. To make a selection,
you need to enter *Select (Mark) Mode* by pressing :kbd:`M`. The cursor
will turn into a crosshair, and you will see the list of available actions for
manipulating the selection in the status bar.

To add a rectangular area to the selection, hold :kbd:`R` and use the movement
keys. For simplicity's sake, you can only use :ref:`moving-around:Normal
mode` movement keys when working with selections, regardless of the currently
active editing mode (:ref:`moving-around:WASD mode`, :ref:`moving-around:Walk
mode`, etc.) Selected cells are tinted pink (in most themes; the actual colour
is theme-dependent).  To subtract a rectangular area from the current
selection, hold :kbd:`S` and use the movement keys.

Similarly, you can "draw" the selection or "erase" from it by using the
:kbd:`D` and :kbd:`E` modifier keys with the movement keys, respectively.
:kbd:`A` selects the whole level (*Select All*), and :kbd:`U` clears the
selection (*Unselect All*).


.. tip::

  You can left-click with the mouse to set the cursor location in *Select
  Mode* too. This opens up some interesting possibilities, e.g. you can draw
  selections with the mouse when used in conjunction with the :kbd:`D` and
  :kbd:`E` modifiers.


.. raw:: html

    <div class="figure">
      <a href="_static/img/selections.png" class="glightbox">
        <img alt="Marking a non-contiguous area in Select Mode" src="_static/img/selections.png" style="width: 77%;">
      </a>
        <p class="caption">
          <span>Marking a non-contiguous area in Select Mode</span>
        </p>
    </div>


When you're happy with your selection, it's time to perform an action on it.
:kbd:`C` (or :kbd:`Y`) copies (yanks) the selected cells into the paste buffer
and returns to *Edit Mode*.

You can paste the contents of the buffer at the current cursor position by
pressing :kbd:`P`. It is important to note that links are *not* copied, but
you can paste the copied content as many times as you wish. This restriction
is necessary to maintain the integrity of the links.

If you press :kbd:`Shift+P`, you'll enter *Paste Preview Mode* where you can
position the selection interactively with the movement keys (usually shown in
a light-blue overlay, which is, again, theme-dependent), then perform the
paste action by pressing :kbd:`Enter`, or cancel it with :kbd:`Esc`. Note that
you can also switch the current level in *Paste Preview Mode*.


.. raw:: html

    <div class="figure">
      <a href="_static/img/paste-preview.png" class="glightbox">
        <img alt="Positioning the selection in Paste Preview Mode" src="_static/img/paste-preview.png" style="width: 77%;">
      </a>
        <p class="caption">
          <span>Positioning the selection in Paste Preview Mode</span>
        </p>
    </div>


.. tip::

  The contents of the paste buffer is preserved when opening another map file.
  Although you can only edit a single map at a given time, this enables you to
  copy-paste whole or partial levels between two maps.


Holding :kbd:`Ctrl` in *Select Mode* will reveal a list of further special
actions in the status bar:

Move :kbd:`Ctrl+M`
    The *link-preserving* alternative to the copy action: the selected cells
    will be cut first, then you will be automatically taken into *Paste
    Preview Mode* where you can reposition the selection. Note that the move
    action will leave the contents of the paste buffer intact (it uses a
    dedicated "move buffer" under the hood).

Erase :kbd:`Ctrl+E`
    Equivalent of using the *erase cell* action on the selected cells.

Fill :kbd:`Ctrl+F`
    Equivalent of using the *draw/clear floor* action on the selected cells.

Set colour :kbd:`Ctrl+C`
    Set the floor colour of the selected cells to the current colour.

Surround :kbd:`Ctrl+S`
    Surround the selected cells with solid walls (you can use this with the
    *select rectangle* action to draw rectangular rooms quickly).

Crop :kbd:`Ctrl+R`
    Crop the level to the bounding box of the selection.



Special level actions
=====================

There are a few special actions that operate on the whole level. These can be
invoked from *Edit Mode*.

Resize level
------------

The *resize level* action, invoked by :kbd:`Ctrl+E`, lets you to shrink or
expand the dimensions of the current level. You'll need to select an anchor
point for the action. It's probably easiest to illustrate the role of the
anchor point through a few examples:

.. rst-class:: multiline

- Making the level 2 columns and 3 rows larger using the top-left anchor point
  will add 2 extra empty columns at the right side of the level, and 3 extra
  empty rows at the bottom.

- Making the level 4 columns and 4 rows smaller using the centre anchor point
  will remove a 2-cell wide "stripe" from around the level.


.. rst-class:: style1 big

Nudge level
-----------

You can shift the contents of the level around without changing its dimensions
with the *nudge level* action.

Press :kbd:`Ctrl+E` to enter *Nudge Preview Mode*, then use the movement keys
to reposition the level's contents. Accept the changes by pressing
:kbd:`Enter`, or discard them with :kbd:`Esc`.


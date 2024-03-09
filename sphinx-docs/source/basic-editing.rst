*************
Basic editing
*************

Most cRPG maps tend to fall into one of two categories: *tunnel style maps*, and
the more compact *wall style maps* (for lack of better terms). There's also a
less common third *hybrid style* that combines elements from both.

.. raw:: html

    <div class="figure">
      <a href="_static/img/eob.png" class="glightbox">
        <img alt="Tunnel style — Eye of the Beholder I" src="_static/img/eob.png" style="width: 77%;">
      </a>
        <p class="caption">
          <span>
            Tunnel style — <a class="reference external" href="https://en.wikipedia.org/wiki/Eye_of_the_Beholder_(video_game)">Eye of the Beholder I</a></span>
        </p>
    </div>

    <div class="figure">
      <a href="_static/img/por.png" class="glightbox">
        <img alt="Wall style — Pool of Radiance" src="_static/img/por.png" style="width: 55%;">
      </a>
      <p class="caption">
        <span>
          Wall style — <a class="reference external" href="https://en.wikipedia.org/wiki/Pool_of_Radiance">Pool of Radiance</a>
        </span>
    </div>

    <div class="figure">
      <a href="_static/img/uukrul.png" class="glightbox">
        <img alt="Hybrid style — Dark Heart of Uukrul" src="_static/img/uukrul.png" style="width: 82%;">
      </a>
      <p class="caption">
        <span>
          Hybrid style — <a class="reference external" href="https://en.wikipedia.org/wiki/The_Dark_Heart_of_Uukrul">The Dark Heart of Uukrul</a>
        </span>
    </div>


Tunnel style maps are easiest to create with the *excavate* (*draw tunnel*)
tool. To use it, hold down the :kbd:`D` key and use the movement keys. The
name "excavate" is quite fitting, as all existing cell content will be
deleted. Junctions are automatically created on tunnel crossings, and
neighbouring cells are joined into larger areas. Of course, you can press
:kbd:`D` without moving the cursor to excavate only the current cell. 

The :kbd:`D` key acts as a *modifier key* when used together with the movement
keys (similarly to :kbd:`Shift` or :kbd:`Ctrl`). There are a few other tools
that work the same way:

* :kbd:`E` – Erase whole cell, including walls (we'll talk about walls shortly)
* :kbd:`F` – Draw/clear floor
* :kbd:`C` – Set floor colour

New cells are drawn with the current floor colour, which is indicated in the
tools pane on the right. You can toggle the visibility of the tools pane with
:kbd:`Alt+T`. To cycle through the available floor colours, press the :kbd:`,`
and :kbd:`.` keys. To "pick" the floor colour from the current cell, press
:kbd:`I`.

Gridmonger has a virtually unlimited undo history (only limited by your
computer's memory). You can undo most actions with :kbd:`U`, :kbd:`Ctrl+U`, or
:kbd:`Ctrl+Z` and redo them with :kbd:`Ctrl+R` or :kbd:`Ctrl+Y`. The only
action that cannot be undone is the creation of a new map which discards the
current map.


Floor types
===========

So far so good, but how do we create doors, pressure plates, pits, teleports,
and all sorts of other paraphernalia brave adventurers frequently run into in
well-designed dungeons?

In tunnel style dungeons these contraptions take up an entire cell, so they
are represented as different *floor types*. You can draw them with the number
keys :kbd:`1` to :kbd:`7`. But there are more than 20 floor types in total, so
how does that exactly work?

Each number key is assigned to up to four floor types. You can cycle forward
between all floor types assigned to a particular number key by pressing the
key multiple times repeatedly, and backward by pressing the key with the
:kbd:`Shift` modifier.

.. raw:: html

    <table class="floors">
      <thead>
        <tr>
          <th class="key">Key</th>
          <th class="icon">Floor</th>
          <th class="name">Name</th>
        </tr>
      </thead>

      <tbody>
        <tr>
          <td class="key" rowspan="3"><kbd>1</kbd></td>
          <td class="icon"><img src="_static/img/floor-open-door.png" alt="Open door"></td>
          <td class="name">Open door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-locked-door.png" alt="Locked door"></td>
          <td class="name">Locked door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-archway.png" alt="Archway"></td>
          <td class="name">Archway</td>
        </tr>
      </tbody>

      <tbody>
        <tr>
          <td class="key" rowspan="4"><kbd>2</kbd></td>
          <td class="icon"><img src="_static/img/floor-secret-door.png" alt="Secret door"></td>
          <td class="name">Secret door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-secret-door-block.png" alt="Secret door (block style)"></td>
          <td class="name">Secret door (block style)</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-one-way-door-1.png" alt="One-way door (N/E)"></td>
          <td class="name">One-way door (N/E)</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-one-way-door-2.png" alt="One-way door (S/W)"></td>
          <td class="name">One-way door (S/W)</td>
        </tr>
      </tbody>

      <tbody>
        <tr>
          <td class="key" rowspan="2"><kbd>3</kbd></td>
          <td class="icon"><img src="_static/img/floor-pressure-plate.png" alt="Pressure plate"></td>
          <td class="name">Pressure plate</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-hidden-pressure-plate.png" alt="Hidden pressure plate"></td>
          <td class="name">Hidden pressure plate</td>
        </tr>
      </tbody>

      <tbody>
        <tr>
          <td class="key" rowspan="4"><kbd>4</kbd></td>
          <td class="icon"><img src="_static/img/floor-closed-pit.png" alt="Closed pit"></td>
          <td class="name">Closed pit</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-open-pit.png" alt="Open pit"></td>
          <td class="name">Open pit</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-hidden-pit.png" alt="Hidden pit"></td>
          <td class="name">Hidden pit</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-ceiling-pit.png" alt="Ceiling pit"></td>
          <td class="name">Ceiling pit</td>
        </tr>
      </tbody>

      <tbody>
        <tr>
          <td class="key" rowspan="4"><kbd>5</kbd></td>
          <td class="icon"><img src="_static/img/floor-teleport-src.png" alt="Teleport source"></td>
          <td class="name">Teleport source</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-teleport-dest.png" alt="Teleport destination"></td>
          <td class="name">Teleport destination</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-spinner.png" alt="Spinner"></td>
          <td class="name">Spinner</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-invisible-barrier.png" alt="Invisible barrier"></td>
          <td class="name">Invisible barrier</td>
        </tr>
      </tbody>

      <tbody>
        <tr>
          <td class="key" rowspan="4"><kbd>6</kbd></td>
          <td class="icon"><img src="_static/img/floor-stairs-down.png" alt="Stairs down"></td>
          <td class="name">Stairs down</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-stairs-up.png" alt="Stairs up"></td>
          <td class="name">Stairs up</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-entrance-door.png" alt="Entrance door"></td>
          <td class="name">Entrance door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-exit-door.png" alt="Exit door"></td>
          <td class="name">Exit door</td>
        </tr>
      </tbody>

      <tbody>
        <tr>
          <td class="key"><kbd>7</kbd></td>
          <td class="icon"><img src="_static/img/floor-bridge.png" alt="Bridge"></td>
          <td class="name">Bridge</td>
        </tr>
      </tbody>

      <tbody>
        <tr>
          <td class="key" rowspan="2"><kbd>8</kbd></td>
          <td class="icon"><img src="_static/img/floor-column.png" alt="Column"></td>
          <td class="name">Column</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-statue.png" alt="Statue"></td>
          <td class="name">Statue</td>
        </tr>
      </tbody>

    </table>


Most door types can be oriented either horizontally or vertically. When
placing them in tunnels (as you normally would), they are automatically
oriented correctly. Should you need it, you can always change the floor
orientation manually with the :kbd:`O` key.

These two floor types are a bit special:

.. rst-class:: multiline

- There are two *one-way doors types*: one for the North or East direction,
  and another for South or West. Press the :kbd:`O` key to switch between
  North-South or East-West orientation, then :kbd:`2`/:kbd:`Shift+2` to flip
  the arrow direction.

- The *bridge type* has a small amount of "overhang" that extends into its two
  adjacent cells. You can draw long continuous bridges by placing multiple
  bridge cells next to each other.

These floor types should take care of most of your dungeoneering needs. The
goal was to keep it simple and not overcomplicate matters by allowing
user-defined custom types. In the rare case where you really need something
not covered by these, you can always just add a note to the cell using a
custom ID as you will learn in the :ref:`annotations:Annotations` chapter.


.. rst-class:: style4

Wall types
==========

Drawing walls works slightly differently. The program makes a distinction
between *regular walls* (the most common wall type) and so-called *special
walls*.

To draw regular walls, hold down the :kbd:`W` modifier key and press one of
the movement keys. This toggles the current cell's wall in the selected
direction according to the following rules:

- If no wall exists in that direction, a regular wall is created.
- If the existing wall is a regular wall, the wall is removed.
- If the existing wall is a special wall, it is turned into a regular wall.

Although this might sound a bit complicated, it's really simple and intuitive
in practice --- just give it a go and you'll see!

.. note::

  For simplicity's sake, you can only use :ref:`moving-around:Normal Mode`
  movement keys with the draw wall modifier, regardless of the currently
  active editing mode (:ref:`moving-around:WASD mode`,
  :ref:`moving-around:Walk mode`, etc.)

Special walls are used for drawing all the different door types you've seen
previously as wall types, plus to represent some gadgets such as levers,
statues, keyholes, etc.

Drawing special walls works similarly to the method described above --- hold
down the :kbd:`R` modified key and press one of the movement keys. This will
use the current special wall type, as indicated in the right-side tools pane.
To change the current special wall type, use the :kbd:`[` and :kbd:`]` keys.

.. raw:: html

    <table class="walls">
      <thead>
        <tr>
          <th class="icon">Special wall</th>
          <th class="name">Name</th>
        </tr>
      </thead>

      <tbody>
        <tr>
          <td class="icon"><img src="_static/img/wall-open-door.png" alt="open door"></td>
          <td class="name">Open door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-locked-door.png" alt="locked door"></td>
          <td class="name">Locked door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-archway.png" alt="archway"></td>
          <td class="name">Archway</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-secret-door.png" alt="secret door"></td>
          <td class="name">Secret door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-one-way-door.png" alt="one-way door"></td>
          <td class="name">One-way door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-illusory.png" alt="illusory wall"></td>
          <td class="name">Illusory wall</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-invisible.png" alt="invisible wall"></td>
          <td class="name">Invisible wall</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-lever.png" alt="lever"></td>
          <td class="name">Lever</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-niche.png" alt="niche"></td>
          <td class="name">Niche</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-statue.png" alt="statue"></td>
          <td class="name">Statue</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-keyhole.png" alt="keyhole"></td>
          <td class="name">Keyhole</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-writing.png" alt="writing"></td>
          <td class="name">Writing</td>
        </tr>
      </tbody>

    </table>

One-way doors are a bit special; their arrows always point towards the drawing
direction. If you want to flip the direction of the arrow, just go to the
"other side" of the door and draw it again in the opposite direction! The
lever, niche, statue, and writing special wall types are similarly
"directional".


Draw wall repeat
================

So far we've seen how to draw walls in a single cell, but what about drawing
long continuous walls with a minimal number of keystrokes? Of course, this
is Gridmonger, so there is a way to do just that!

After you have set or cleared a wall in a cell, you have the option to repeat
that action horizontally or vertically, depending on the orientation of the
wall you've just manipulated. So, if you've set or cleared the *north* or
*south* wall, you can repeat that action in the *horizontal direction*;
similarly, if you've manipulated the *east* or *west* wall, you can repeat
that action in the *vertical direction*.

To use this feature, first set or clear a wall in the current cell using the
:kbd:`W` modifier, then hold down :kbd:`Shift` without releasing :kbd:`W` to
enter *draw wall repeat mode*. Now you can use the movement keys to repeat the draw wall
action either horizontally or vertically, depending on the orientation of the
wall you've drawn first.

Although you won't need this often, you can use the repeat feature with
the :kbd:`S` draw special wall modifier too.

The usage of the repeat tool is probably best illustrated with an example.
Let's see how to draw a spiral with it!

.. raw:: html

    <div class="figure">
      <a href="_static/img/draw-wall-repeat.png" class="glightbox">
        <img alt="Drawing a spiral with the draw wall repeat tool" src="_static/img/draw-wall-repeat.png" style="width: 37%;">
      </a>
        <p class="caption">
          <span>Drawing a spiral with the draw wall repeat tool</span>
        </p>
    </div>


Move the cursor to ``1``, hold down :kbd:`W` and keep it held down until you
have reached ``6`` while carrying out the following (the arrow keys represent
any of the :ref:`moving-around:Normal Mode` movement keys). Pay attention to
the status bar messages after each keystroke!

1. Press :kbd:`←`, hold down :kbd:`Shift`, press :kbd:`↑` twice,
   release :kbd:`Shift`.

2. Press :kbd:`↑`, hold down :kbd:`Shift`, press :kbd:`→` twice,
   release :kbd:`Shift`.

3. Press :kbd:`→`, hold down :kbd:`Shift`, press :kbd:`↓` twice,
   release :kbd:`Shift`.

4. Press :kbd:`↓`, hold down :kbd:`Shift`, press :kbd:`←`,
   release :kbd:`Shift`.

5. Press :kbd:`←`, hold down :kbd:`Shift`, press :kbd:`↑`,
   release :kbd:`Shift`.

6. Press :kbd:`↑`, then press :kbd:`→`. You can release :kbd:`W` now, the
   spiral has been completed!


Now draw a few more spirals and similar shapes on your own! After a few
minutes of practice, using the repeat tool should become second nature to you.


.. rst-class:: style1

Trail Mode
==========

In *Trail Mode*, the cursor leaves a trail behind as you move it around. You
can then "draw in" the map over it (this is really only useful for
tunnel-style maps), or you can use it to track your movement over an already
mapped area. 

Use the :kbd:`T` key to toggle *Trail Mode*; you'll see two little footsteps
in the top-left corner when it's enabled. Because in this mode you're
modifying the map when moving the cursor, all cursor movements will become
undoable actions.

.. raw:: html

    <div class="figure">
      <a href="_static/img/trail.png" class="glightbox">
        <img alt="Trail Mode" src="_static/img/trail.png" style="width: 90%;">
      </a>
        <p class="caption">
          <span>Trail Mode</span>
        </p>
    </div>


Similarly to the *erase cell* tool, you can erase the trail one cell at a time
by holding :kbd:`X` and using the movement keys. You can only use this tool if
*Trail Mode* is turned off.

To delete the whole trail in the current level only, press :kbd:`Ctrl+Alt+X`.
To excavate the whole trail in the current level (overwriting existing cell
contents), press :kbd:`Ctrl+Alt+D`.

The trail data for all levels is saved into the map file.

.. note::

    *Trail Mode* is turned off automatically when performing an action that
    would yield confusing or unwanted results with it being on (e.g., creating
    or deleting levels, changing the current level, or working with
    :ref:`advanced-editing:Selections`).


.. rst-class:: style6 big

Editing in WASD Mode
====================

In :ref:`moving-around:WASD Mode`, the editing modifiers :kbd:`D`, :kbd:`W`
and :kbd:`E` are not available because they're used for movement. But this is
not a problem, as in this mode you're supposed to use *mouse modifiers*
instead for these actions.

For example, to draw tunnels, hold down the left mouse button and use the
WASD movement keys.

The following mouse modifiers are available:

* Left button -- draw tunnel
* Right button -- draw wall
* Right & left buttons -- draw special wall
* Middle button -- erase cell

The mouse cursor must be inside the level area when using the mouse modifiers.

To draw special walls, make sure to press then right mouse button first,
*then* the left button (otherwise you'd end up in draw tunnel mode).

Naturally, the :ref:`basic-editing:Draw wall repeat` tool is available in this
mode too.

As the mouse buttons act as editing modifiers in *WASD Mode*, you need to hold
:kbd:`Shift` to unlock the :ref:`moving-around:Mouse movement actions`:

- Hold :kbd:`Shift` and left-click somewhere inside the level to move the
  cursor there.
- Hold :kbd:`Shift+Ctrl` and the left button, or :kbd:`Shift` and the middle
  button and move the mouse to pan the level.


.. tip::

    Some games, such as the renowned `Eye of the Beholder series
    <https://en.wikipedia.org/wiki/Eye_of_the_Beholder_(video_game)>`_, don't
    support WASD-style navigation. Luckily, most emulators (e.g., `DosBox
    <https://www.dosbox.com/>`_ and `WinUAE <https://www.winuae.net/>`_)
    provide a way to remap the cursor keys to the WASD keys in these games.



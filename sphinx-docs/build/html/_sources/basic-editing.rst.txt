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

* :kbd:`E` – erase whole cell, including walls (we'll talk about walls shortly)
* :kbd:`F` – draw/clear floor
* :kbd:`C` – set floor colour

New cells are drawn with the current floor colour, which is indicated in the
tools pane on the right. You can toggle the visibility of the tools pane with
:kbd:`Alt+T`. To cycle through the available floor colours, press the :kbd:`,`
and :kbd:`.` keys. To "pick" the floor colour from the current cell, press
:kbd:`I`.

Gridmonger has a virtually unlimited undo history (only limited by your
computer's memory). You can undo most actions with :kbd:`Ctrl+Z` or :kbd:`U`,
and redo them with :kbd:`Ctrl+Y` or :kbd:`Ctrl+R`. The only action that cannot
be undone is the creation of a new map which discards the current map.


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
          <td class="icon"><img src="_static/img/floor-open-door.png" alt="open door"></td>
          <td class="name">open door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-locked-door.png" alt="locked door"></td>
          <td class="name">locked door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-archway.png" alt="archway"></td>
          <td class="name">archway</td>
        </tr>
      </tbody>

      <tbody>
        <tr>
          <td class="key" rowspan="4"><kbd>2</kbd></td>
          <td class="icon"><img src="_static/img/floor-secret-door.png" alt="secret door"></td>
          <td class="name">secret door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-secret-door-block.png" alt="secret door (block style)"></td>
          <td class="name">secret door (block style)</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-one-way-door-1.png" alt="one-way door (1)"></td>
          <td class="name">one-way door (N/E)</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-one-way-door-2.png" alt="one-way door (2)"></td>
          <td class="name">one-way door (S/W)</td>
        </tr>
      </tbody>

      <tbody>
        <tr>
          <td class="key" rowspan="2"><kbd>3</kbd></td>
          <td class="icon"><img src="_static/img/floor-pressure-plate.png" alt="pressure plate"></td>
          <td class="name">pressure plate</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-hidden-pressure-plate.png" alt="hidden pressure plate"></td>
          <td class="name">hidden pressure plate</td>
        </tr>
      </tbody>

      <tbody>
        <tr>
          <td class="key" rowspan="4"><kbd>4</kbd></td>
          <td class="icon"><img src="_static/img/floor-closed-pit.png" alt="closed pit"></td>
          <td class="name">closed pit</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-open-pit.png" alt="open pit"></td>
          <td class="name">open pit</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-hidden-pit.png" alt="hidden pit"></td>
          <td class="name">hidden pit</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-ceiling-pit.png" alt="ceiling pit"></td>
          <td class="name">ceiling pit</td>
        </tr>
      </tbody>

      <tbody>
        <tr>
          <td class="key" rowspan="4"><kbd>5</kbd></td>
          <td class="icon"><img src="_static/img/floor-teleport-src.png" alt="teleport source"></td>
          <td class="name">teleport source</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-teleport-dest.png" alt="teleport destination"></td>
          <td class="name">teleport destination</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-spinner.png" alt="spinner"></td>
          <td class="name">spinner</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-invisible-barrier.png" alt="invisible barrier"></td>
          <td class="name">invisible barrier</td>
        </tr>
      </tbody>

      <tbody>
        <tr>
          <td class="key" rowspan="4"><kbd>6</kbd></td>
          <td class="icon"><img src="_static/img/floor-stairs-down.png" alt="stairs down"></td>
          <td class="name">stairs down</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-stairs-up.png" alt="stairs up"></td>
          <td class="name">stairs up</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-entrance-door.png" alt="entrance door"></td>
          <td class="name">entrance door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/floor-exit-door.png" alt="exit door"></td>
          <td class="name">exit door</td>
        </tr>
      </tbody>

      <tbody>
        <tr>
          <td class="key"><kbd>7</kbd></td>
          <td class="icon"><img src="_static/img/floor-bridge.png" alt="bridge"></td>
          <td class="name">bridge</td>
        </tr>
      </tbody>

    </table>


Most door types can be oriented either horizontally or vertically. When
placing them in tunnels (as you normally would), they are automatically
oriented correctly. Should you need it, you can always change the floor
orientation manually with the :kbd:`O` key.

The *bridge* type is a bit special; it has a small amount of "overhang" into
its two adjacent cells. You can draw long continuous bridges by placing
multiple bridge floors next to each other.

These floor types should take care of most of your dungeoneering needs. The
goal was to keep it simple and not overcomplicate matters by allowing the
users to define their custom types. In the rare case where you really need
something not covered by these, you can always just add a note to the cell
using a custom ID, as you will learn in the :ref:`annotations:Annotations`
chapter.


.. rst-class:: style4

Wall types
==========

Drawing walls works slightly differently. The program makes a distinction
between *regular walls* (the most common wall type) and so-called *special
walls*.

To draw regular walls, hold down the :kbd:`W` modifier key and press one of
the movement keys. This toggles the current cell's wall in the selected
direction according to the following rules:

- if no wall exists in that direction, a regular wall is created
- if the existing wall is a regular wall, the wall is removed
- if the existing wall is a special wall, it is turned into a regular wall

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
          <td class="name">open door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-locked-door.png" alt="locked door"></td>
          <td class="name">locked door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-archway.png" alt="archway"></td>
          <td class="name">archway</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-secret-door.png" alt="secret door"></td>
          <td class="name">secret door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-one-way-door.png" alt="one-way door"></td>
          <td class="name">one-way door</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-illusory.png" alt="illusory wall"></td>
          <td class="name">illusory wall</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-invisible.png" alt="invisible wall"></td>
          <td class="name">invisible wall</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-lever.png" alt="lever"></td>
          <td class="name">lever</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-niche.png" alt="niche"></td>
          <td class="name">niche</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-statue.png" alt="statue"></td>
          <td class="name">statue</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-keyhole.png" alt="keyhole"></td>
          <td class="name">keyhole</td>
        </tr>
        <tr>
          <td class="icon"><img src="_static/img/wall-writing.png" alt="writing"></td>
          <td class="name">writing</td>
        </tr>
      </tbody>

    </table>

One-way doors are a bit special; their arrows are drawn towards the direction
you've used when drawing them. So if you want to flip the direction of the arrow,
just go to the "other side" of the door and draw it again!


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
enter *repeat mode*. Now you can use the movement keys to repeat the draw wall
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
        <img alt="Trail mode" src="_static/img/trail.png" style="width: 90%;">
      </a>
        <p class="caption">
          <span>Trail mode</span>
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
    would yield confusing or unwanted results with it being on (e.g. creating
    or deleting levels, changing the current level, entering *Select Mode*,
    etc.)


.. rst-class:: style6 big

Editing in WASD Mode
====================

In :ref:`moving-around:WASD Mode`, the editing modifiers :kbd:`D`, :kbd:`W`
and :kbd:`E` are not available because they're used for movement. But this is
not a problem, as in this mode you're supposed to use *mouse modifiers*
instead for these actions.

For example, to draw tunnels, hold down the left mouse button and use the
:kbd:`W`:kbd:`A`:kbd:`S`:kbd:`D` movement keys.

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

If you hold the :kbd:`Shift` key, you can move the cursor by left-clicking
somewhere inside the level like in *Normal Mode*.

.. tip::

    Some games, such as the renowned `Eye of the Beholder series
    <https://en.wikipedia.org/wiki/Eye_of_the_Beholder_(video_game)>`_,
    don't support WASD-style navigation. Luckily, most emulators (e.g. `DosBox
    <https://www.dosbox.com/>`_ and `WinUAE <https://www.winuae.net/>`_)
    provide a way to remap the cursor keys to the WASD keys in these games.



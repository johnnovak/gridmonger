******************
Map & level basics
******************

General concepts
================

What you usually refer to as a map or an area in a cRPG (typically a 16×16 or
32×32 cell grid) is called a *level* in Gridmonger. A set of levels is, in
turn, called a *map*. The program always operates on a single map: when you
start it for the first time, you are greeted with an empty map; when you load
or save your work, you're always loading or saving a map.

Let's load one of the example maps to illustrate these concepts! Start up
Gridmonger, press :kbd:`Ctrl+O` to bring up the open map dialog, then select
the file ``Eye of the Beholder I.gmm`` from the ``Example Maps`` folder in
your program directory (Gridmonger map files have the ``.gmm`` extension). Mac
users will need to download the `Example Maps
<https://gridmonger.johnnovak.net/files/gridmonger-example-maps.zip>`_
separately.

Click on the current level drop-down at the top of the window that currently
shows ``Undermountain – Upper Sewers (-1)``. The list of all levels that
comprise this map will appear:

* Undermountain -- Upper Sewers (-1)
* Undermountain -- Middle Sewers (-2)
* Undermountain -- Lower Sewers (-3)
* Undermountain -- Upper Level Dwarven Ruins (-4)
* ...

As you can see, the full name of a level consists of three components:

``Location name – Level name (Elevation)``

**Location name** may refer to a distinct geographical area, a dungeon, or a
city consisting of one or more levels. In this example, the whole game takes
place in the Undermountain dungeon deep beneath the city of Waterdeep.

**Level name** is the name of an individual level (or area) within the
location. It is optional because some locations may contain only a single
level, or multiple levels but with no unique characteristics. In either case,
it would make little sense to name the level.

**Elevation** is the vertical position of the level in relation to the ground.
An elevation of zero means ground level (displayed as ``G`` in the level
name). Negative numbers are underground (e.g. the levels of a mine), and
positive numbers are above the ground (e.g. the floors of a castle or a
tower). As this game takes place entirely in an underground dungeon, all
numbers are negative.

The benefit of this naming scheme is that the program can automatically
organise the levels for you: the level list is sorted by location name first,
then by elevation, and lastly by level name. Note that elevation is sorted in
descending order because that way the resulting list in the drop-down mirrors
the vertical position of the levels (and underground dungeons are just more
common in cRPGs).

The important thing to remember is that the *full name* of every level must be
unique within the map (the program enforces this).

Map properties
==============

Apart from their name, levels have a few other properties too. Some of them can
be inherited from the map, so let's examine the map properties first. Bring up
the **Edit Map Properties** dialog with the :kbd:`Ctrl+Alt+P` shortcut!

Let's start with the **General** tab. Unsurprisingly, every map must have a
**Title** --- this is what gets displayed in the title bar of the window. You
can also optionally specify the name of the **Game** and the **Author** of the
map. The local **Creation time** is also displayed as a non-editable property.

The **Coordinates** tab contains properties that govern how the cell
coordinates are displayed. **Origin** specifies the corner where counting the
grid coordinates should start from. There are two coordinate styles to choose
from: *number* and *letter*. You can set the style separately for columns and
rows with **Column style** and **Row style**, respectively. The letter style
works as follows: ``A`` corresponds to ``0``, ``B`` to ``1``, and so on, right
until ``Z`` (``25``), then it continues with ``AA``, ``AB``, ``AC``, etc. You
can specify the starting values for the coordinates in the **Column start**
and **Row start** fields. You need to enter the start values as numbers, even
for letter style coordinates, in which case the program helpfully displays the
corresponding letter coordinates next to the input fields. Negative start
values are allowed (``-1`` corresponds to ``-B`` when using the letter style).

Finally, the **Notes** tab contains a nice large text field to store all your
map related notes in. You can use :kbd:`Shift+Enter` to insert line breaks
when editing the note text.


Level properties
================

Now open the **Edit Level Properties** dialog with the :kbd:`Ctrl+P` shortcut.

The **General** tab contains the **Location name**, **Level name** and
**Elevation** properties discussed previously. The dimensions of the level are
also displayed (**Columns** and **Rows**), but you cannot edit those fields.

By default, levels use the same coordinate settings as the map. You can
customise them on an individual level basis by enabling **Override map
settings** in the **Coordinates** tab.

The **Regions** properties will be discussed later in the :doc:`regions`
chapter.

You can attach notes to individual levels as well under the **Notes** tab.


Managing maps &  levels
=======================

To add a new level, press :kbd:`Ctrl+N` to bring up the **New Level** dialog.
This is almost exactly the same as the **Edit Level Properties** dialog, the
only difference being that here you must specify the level's dimensions. The
maximum allowed size is 6,666×6,666 --- hopefully, you'll never ever come
across a level this big, but some kind of upper limit had to be introduced and
this is as good as any! Don't worry if you don't get the level size quite
right initially; you can always change it later with the resize and crop
actions, as you'll see.

To delete the current level, press :kbd:`Ctrl+D`. If you accidentally deleted
a level, no problem, you can always undo it by pressing :kbd:`U` or
:kbd:`Ctrl+Z`.

Similarly, you can create a new map with :kbd:`Ctrl+Alt+N`. Make sure to save
your current map first if you don't want to lose it, because deleting the
whole map is the one action that *cannot* be undone!


.. rst-class:: style1 big

Saving maps
===========

Whenever you save your map with :kbd:`Ctrl+S`, Gridmonger appends the ``.bak``
suffix to the name of your current map file, then creates a new file with the
normal map name. This is a safety measure --- if saving the map fails for
whatever reason, at least you have your last backup. Just remove the ``.bak``
suffix from the filename and load it as a regular map file.

You can also save the map under a new name with :kbd:`Ctrl+Shift+S`.

Gridmonger has an autosaving feature that is enabled by default; you will
learn more about this in the :ref:`preferences:preferences` section.


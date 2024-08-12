***********
Annotations
***********

One of the big benefits of creating your own maps --- even for games featuring
auto-maps --- is the ability to annotate them. There are two types of
annotations available: *notes* and *labels*.


Notes
=====

A *note* is a textual comment linked to a cell. Notes can optionally have a
marker, which is some symbol displayed in the cell. There are four marker
types to choose from:


.. raw:: html

    <div class="figure">
      <a href="_static/img/annotations-types.png" class="glightbox">
        <img alt="Examples of the four different marker types" src="_static/img/annotations-types.png" style="width: 67%;">
      </a>
        <p class="caption">
          <span>Examples of the four different marker types</span>
        </p>
    </div>


None
    No marker, only a little triangle in the top-right corner of the cell.

Number
    An automatically incrementing number. The background colour can be chosen
    from four predefined colours.

    Numbers are assigned in left-to-right, top-to-bottom order (normal English
    reading order). Numbering restarts from ``1`` in each level. Notes are
    renumbered automatically whenever a numbered note is added or deleted
    as a result of any action (including :ref:`advanced-editing:Special level
    actions` or actions that affect :ref:`advanced-editing:Selections`.)

ID
    An identifier of up to two characters in length, consisting of English
    letters and numbers.

Icon
    An icon chosen from a predefined set of 40 icons.


.. raw:: html

    <div class="figure">
      <a href="_static/img/annotations-icons.png" class="glightbox">
        <img alt="Annotation icon set" src="_static/img/annotations-icons.png" style="width: 65%;">
      </a>
        <p class="caption">
          <span>Annotation icon set</span>
        </p>
    </div>


To add a note, press :kbd:`N` or :kbd:`;` in a non-empty cell. A cell cannot
have more than one note; if you use the shortcut in a cell that already has a
note, you'll be editing it. To erase a note, press :kbd:`Shift+N` or
:kbd:`Shift+;`.

.. note::

    Only the :kbd:`;` and :kbd:`Shift+;` shortcuts are available with
    :ref:`YUBN keys <moving-around:Diagonal movement>` enabled.

You can use :kbd:`Shift+Enter` to insert line breaks into the note text.

If the cell's floor is non-empty (e.g., it contains a pressure plate or a
teleport), placing a note of type **Number**, **ID**, or **Icon** will clear
its content. If you want to preserve the cell's content, use the **None**
marker type, which will only display a little triangle in the top-right corner
of the cell while keeping its content intact.

Conversely, if you overwrite a note of type **Number**, **ID**, or **Icon**
with some cell content (e.g., a teleport), the note won't be deleted, but it
will be converted to the **None** marker type. As this type only displays the
little triangle in the top-right corner, the new cell content and the note can
coexist.

The note under the cursor is displayed in the *notes pane* below the level,
which can be toggled with :kbd:`Alt+N`. You can also hover over a cell with
the mouse pointer; if it has a note, it will be displayed in a tooltip.
This tooltip can also be toggled with :kbd:`Space` for the current cell.

.. tip::

    As creating and editing notes are frequently used actions, special care
    has been taken to make the note dialog fully keyboard operable.

    Hold down :kbd:`Ctrl` and use the horizontal movement keys to navigate
    between the tabs, or press :kbd:`Ctrl+1-4` to jump to one of the
    four tabs.

    To cycle between text fields, press :kbd:`Tab` and :kbd:`Shift+Tab`. You
    can use the movement keys to select the colour in the **Number** tab and
    the icon image in the **Icon** tab.


.. rst-class:: style8

Labels
======

A *label* is just some text overlaid on top of the level. Labels are attached
to a single cell; the text starts from this cell and potentially extends into
neighbouring cells. Creating a label overwrites the contents of the starting
cell, including any notes.

In contrast with notes, you can attach labels to empty cells as well. This is
useful when placing labels in empty areas.


.. raw:: html

    <div class="figure">
      <a href="_static/img/annotations-labels.png" class="glightbox">
        <img alt="Example use of labels" src="_static/img/annotations-labels.png">
      </a>
        <p class="caption">
          <span>Example use of labels &mdash; note that all but one label reside
          in empty areas</span>
        </p>
    </div>


Press :kbd:`Ctrl+T` to add a label starting from the current cell. You can
select the colour of the label from four predefined colours (you can change
the colour with the movement keys when you're not editing the table text).

Press :kbd:`Shift+Enter` to insert line breaks into the label text.

To edit a label, go to its starting cell (the top-left corner of the label
text) and press :kbd:`Ctrl+T`. To erase it, press :kbd:`Shift+T`.

.. note::

   The *excavate (draw tunnel)*, *erase cell*, and *draw/clear floor* tools
   leave labels intact. You need to use :kbd:`Shift+T` to delete labels.

.. tip::

   If you want to copy or move a label, make sure to include its starting cell
   in the :ref:`selection <advanced-editing:Selections>`.


.. rst-class:: style5 big


Notes list
==========

To find a note, you can hover over all the annotations with the mouse. But
that gets tiresome quickly, especially in large multi-level dungeons.

A much better way is to use the *notes list pane*, which can be toggled by
pressing :kbd:`Alt+L`.


.. raw:: html

    <div class="figure">
      <a href="_static/img/notes-list-pane.png" class="glightbox">
        <img alt="Notes list pane" src="_static/img/notes-list-pane.png" style="width: 100%;">
      </a>
        <p class="caption">
          <span>Notes list pane (on the left)</span>
        </p>
    </div>



By default, the notes list pane shows all notes in the current level. You can
change the filter criteria with the controls at the top of the pane. Let's
illustrate this with a concrete example:

.. rst-class:: multiline

1. Load the ``Eye of the Beholder I`` example map and go to the
   ``Undermountain – Lower Sewers (-3)`` level.
2. Open the *notes list pane* with :kbd:`Alt+L`---you'll see all notes in 
   the current level. Click on a note to move the cursor to it.
3. Enter ``gem`` in the **Search** field to only show notes that contain this
   word. Note the notes list is filtered dynamically as you type.
4. Now click on the **Map** button at the top of the pane to see notes
   containing ``gem`` in all levels of the map, not just the current one.
5. The results are grouped by levels; you'll see the names of four levels, all
   collapsed by default. Click on the little triangles to their left to
   expand them, or the big ``+`` button below the search field to expand all
   at once.
6. Toggle the **None** button off by clicking on it (below the **Map**
   button); now notes of the **None** marker type are filtered out.
7. Click on the **Icon** button while holding down the :kbd:`Ctrl` key to only
   show notes of the **Icon** marker type.
8. Click on the little trash can icon to the right of the **Search** text
   field to clear the text filter. Now you can see all icon type annotations
   in all levels. Use the mouse wheel to scroll through the list. A scroll bar
   will also appear if you move the mouse pointer close to the right edge of
   the pane.


.. raw:: html
   
    <section class="style1" style="margin-bottom: 2em;"></section>


Here's a description of the note filtering options in detail:

Scope & grouping
----------------

In the first row, you can select to see notes

- from all levels of the **Map**, grouped by level;
- only notes from the current **Level**;
- or notes from the current level, grouped by **Region**.

If the current level has no regions, the **Region** and **Level** options will
yield identical results.

To expand or collapse all level or region groups at once, press the ``+`` and
``-`` buttons in the bottom-right corner of the filtering options pane,
respectively. If a level or region is empty (either because it contains no
notes, or because all its notes have been filtered out), its group is not
shown in the results.

The little chain icon right to the **Region** button enables linking the
cursor and the notes list pane. When enabled, moving the cursor to a cell that
contains a note will cause the notes list pane to auto-scroll to the note and
highlight it. *Beware, this will only happen if the note under the cursor is
included by the filter criteria!*


Marker type filters
-------------------

In the second row, you can filter the notes by marker type: **None**,
**Number**, **ID**, and **Icon**. Click on a button to toggle a type, or
hold :kbd:`Ctrl` while clicking to only enable a single type. Press the ``A``
button on the right to enable all marker types.


Full-text search
----------------

You can filter notes by full-text search by entering words in the **Search**
text field. Searching is case insensitive. If you enter multiple words
separated by spaces, notes that contain *either* of the words (fully or
partially) will be included in the results. The notes list is updated in
real-time as you type.

For example, if you enter ``gold gem``, all notes that contain either ``gold`` or
``gem`` will be shown (e.g., "gemstone", "green gem", and "golden
necklace").

To quickly reset the full-text filter, click on the little trash can icon to
the right of it.


Ordering
--------

There are two ordering options: **Type** orders notes by
marker type first, then alphabetically by their text, and **Text** orders them
only by their text.

If **Map** or **Region** scope is selected, each level or region group is
ordered individually.

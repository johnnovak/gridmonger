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

    Numbers are assigned in left-to-right, top-to-bottom (normal English
    reading order). Numbering restarts from ``1`` in each level. Notes are
    renumbered automatically whenever a numbered note is added or deleted.

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


To create a note, press :kbd:`N` or :kbd:`;` in a non-empty cell. A cell
cannot have more than one note; if you use the shortcut in a cell that already
has a note, you'll be editing it. To erase a note, press :kbd:`Shift+N` or
:kbd:`Shift+;`.

.. note::

    Only the :kbd:`;` and :kbd:`Shift+;` shortcuts are available with
    :ref:`YUBN keys <moving-around:Diagonal movement>` enabled.

Press :kbd:`Shift+Enter` to insert line breaks into the note text.

If the cell's floor is non-empty (e.g., it contains a pressure plate or a
teleport), placing a note of type **Number**, **ID**, or **Icon** will clear
its content. If you want to preserve the cell's content, use the **None**
marker type, which will only display a little triangle in the top-right corner
of the cell while keeping its content intact.

Conversely, if you overwrite a note of type **Number**, **ID**, or **Icon**
with some cell content (e.g., a teleport), the note won't be deleted, but it
will be converted to the **None** marker type. This will only display the
little triangle in the top-right corner, so the new cell content and the note
can coexist.

The note under the cursor is displayed in the *notes pane* below the level,
which can be toggled with :kbd:`Alt+N`. You can also hover over a cell with
the mouse pointer; if it has a note, it will be displayed in a tooltip.
This tooltip can also be toggled with :kbd:`Space` for the current cell.

.. tip::

    As creating and editing notes are frequently used actions, special
    care has been taken to make the note dialog fully keyboard operable.

    Hold down :kbd:`Ctrl` and use the horizontal movement keys to navigate
    between the tabs, or press :kbd:`Ctrl+1-4` to jump to one of the
    four tabs.

    To cycle between text fields, use :kbd:`Tab` and :kbd:`Shift+Tab`. In the
    **Number** and **Icon** tabs, use the movement keys to select the colour or
    the icon image, respectively.

.. tip::

   Hovering over the annotations with the mouse is the quickest way to find a
   note by its text in a busy map.


.. rst-class:: style5 big

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
          <span>Example use of labels &mdash; note that all but one reside
          in empty areas</span>
        </p>
    </div>


Press :kbd:`Ctrl+T` to create a label starting from the current cell. You can
select the colour of the label from four predefined colours.

Press :kbd:`Shift+Enter` to insert line breaks into the label text.

To edit a label, go to its starting cell (the top-left corner of the label
text) and press :kbd:`Ctrl+T`. To erase it, press :kbd:`Shift+T`.

.. note::

   The *excavate (draw tunnel)*, *erase cell*, and *draw/clear floor* tools
   leave labels intact. You need to use :kbd:`Shift+T` to delete labels.

.. tip::

   If you want to copy or move a label, make sure to include its starting cell
   in the :ref:`selection <advanced-editing:Selections>`.

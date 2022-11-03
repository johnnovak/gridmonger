***********
Annotations
***********

One of the big benefits of creating your own maps --- even for games featuring
in-game auto-maps --- is the ability to annotate them. There are two types of
annotations available: *notes* and *labels*.


Notes
=====

A *note* is a textual comment linked to a cell. Notes can optionally have a
marker, which is some symbol that is displayed in the cell. There are four
marker types to choose from:


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
    No marker; only a little triangle is displayed in the top-right corner of
    the cell.

Number
    An automatically incrementing number. The background colour can be chosen
    from four predefined colours.

    Numbers are assigned in left-to-right, top-to-bottom order (normal English
    reading order). Numbering restarts from ``1`` in each level. Notes are
    renumbered automatically whenever a new numbered item is added, or an
    existing one is deleted.

ID
    An identifier of up to two characters in length consisting of English
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


To create a note, press the :kbd:`N` key in a non-empty cell. A cell cannot
have more than one note; if you press :kbd:`N` in a cell that already has one,
you'll be editing it. To erase a note, press :kbd:`Shift+N`.

Press :kbd:`Shift+Enter` to insert line breaks when editing the note text.

If the cell's floor is non-empty (e.g. it contains a pressure plate or a
teleport), placing a note of type **Number**, **ID** or **Icon** will clear
its content. If you want to preserve the cell's content, use the **None**
marker type, which will only display a little triangle in the top-right corner
of the cell while keeping its content intact.

Conversely, if you overwrite a note of type **Number**, **ID** or **Icon**
with some cell content (e.g. a teleport), the note won't be deleted, but it
will be converted to the **None** marker type, so the new cell content and the
note can coexist.

The note under the cursor is displayed in the *notes pane* below the level,
which can be toggled with :kbd:`Alt+N`. You can also hover over a cell with
the mouse pointer, and if it has a note, it will be displayed in a tooltip.
This tooltip can also be toggled with :kbd:`Space` for the cell under the
cursor.

.. tip::

    As creating and editing notes are very frequently used actions, special
    care has been taken to make the note dialog fully keyboard operable.

    Hold down :kbd:`Ctrl` and use the horizontal movement keys to navigate
    between the tabs, or press the number keys :kbd:`1` to :kbd:`4` to jump to
    a specific tab.

    To cycle between text fields, use :kbd:`Tab` and :kbd:`Shift+Tab`. In the
    **Number** and **Icon** tabs, use the movement keys to select the colour or
    the icon image, respectively.

.. tip::

   Hovering over the annotations with the mouse is the quickest way to find a
   note by its text in a busy map.


.. rst-class:: style5 big

Labels
======

A *label* is just some text overlaid on top of the level. Placing a label in a
cell overwrites its previous content, including notes (technically, a label is
just another annotation type). In contrast with notes, you can attach labels
to empty cells as well. This is useful when placing labels in empty areas
around the level, rather than on top of it.


.. raw:: html

    <div class="figure">
      <a href="_static/img/annotations-labels.png" class="glightbox">
        <img alt="Example use of labels" src="_static/img/annotations-labels.png">
      </a>
        <p class="caption">
          <span>Example use of labels &mdash; note that all but one reside
          in empty areas around the level</span>
        </p>
    </div>


To create a label starting from a cell, go to the cell and press
:kbd:`Ctrl+T`. You can select the colour of the label from four predefined
colours. 

To edit a label, go to the cell at the top-left corner of the label text, then
press :kbd:`Ctrl+T`. To erase it, press :kbd:`Shift+T`.

.. note::

   The *excavate (draw tunnel)* tool (:kbd:`D` modifier) does not erase
   labels, but the *erase cell* (:kbd:`E`) and *draw/clear floor* (:kbd:`F`)
   tools do.



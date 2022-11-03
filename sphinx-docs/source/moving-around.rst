*************
Moving around
*************

Gridmonger is a `modal editor
<https://en.wikipedia.org/wiki/Mode_(user_interface)>`_, meaning that a given
keystroke often performs entirely different actions in different *operational
modes* of the program.  There is no great mystery in this --- just think of
how the state of the :kbd:`NumLock` key affects how your numeric keypad
functions. Modes work in a similar fashion.

There are *four navigational modes*, and as you'll see, these different modes
have implications on other shortcuts as well. Then there are a few further
*special modes* for advanced editing; these will be discussed in the
:doc:`advanced-editing` chapter.


Common navigation keys
======================

The level-related navigational keys are the same in every mode.


You can zoom the view in and out with the :kbd:`=` and :kbd:`-` keys,
respectively. There are 20 zoom levels in total.

To change the current level, you can use the drop-down above the level, or
:kbd:`Ctrl+-`/:kbd:`Ctrl+=`, :kbd:`PgUp`/:kbd:`PgDn` or :kbd:`Kp-`/:kbd:`Kp+`
to go to the previous or next level.

.. note::

   When it comes to keyboard shortcuts, Gridmonger uses the `US keyboard
   layout <https://kbdlayout.info/KBDUS>`_, regardless of the keyboard layout
   and language settings of your operating system, or what the key labels on
   a non-US keyboard indicate. This is very similar to how most games handle
   the keyboard. For the more technically inclined, the program only cares
   about *positional scancodes*.


Normal Mode
===========

The most basic mode of operation is *Normal Mode*; this is what most people
will use 90% of the time. When you start Gridmonger for the first time, you
are in *Normal Mode*. This is indicated by a square shaped cursor.

.. raw:: html

    <div class="figure">
      <a href="_static/img/mode-normal.png" class="glightbox">
        <img alt="Normal mode (square cursor)" src="_static/img/mode-normal.png" style="width: 25%;">
      </a>
        <p class="caption">
          <span>Normal Mode (square cursor)</span>
        </p>
    </div>


One of the defining features of Gridmonger is its `Vim
<https://en.wikipedia.org/wiki/Vim_(text_editor)>`_-inspired keyboard
interface. This means that in addition to the standard cursor keys, you can
also use Vim-style `HJKL key
<https://en.wikipedia.org/wiki/Arrow_keys#HJKL_keys>`_ navigation to move
around. You might have already encountered this style of navigation in
some text-based games originally developed on UNIX systems, such as the
venerable `Rogue <https://en.wikipedia.org/wiki/Rogue_(video_game)>`_ and `NetHack
<https://en.wikipedia.org/wiki/NetHack>`_.

If this doesn't mean anything to you, don't worry! Just keep using the
standard cursor keys or the keypad for now. But I do recommend you to read the
:ref:`About Vim <about-vim>` side-note at the end; you might find it
interesting enough to explore this topic further.

The following table summarises all the movement keys you can use in *Normal
Mode*:

.. raw:: html

    <table class="shortcuts std-move-keys">
      <thead>
        <tr>
          <th>Arrow</th>
          <th>Keypad</th>
          <th>Vim</th>
          <th></th>
        </tr>
      </thead>

      <tbody class="no-padding">
        <tr>
          <td><kbd>&larr;</kbd></td>
          <td><kbd>kp 4</kbd></td>
          <td><kbd>H</kbd></td>
          <td>Left</td>
        </tr>
        <tr>
          <td><kbd>&rarr;</kbd></td>
          <td><kbd>kp 6</kbd></td>
          <td><kbd>L</kbd></td>
          <td>Right</td>
        </tr>
        <tr>
          <td><kbd>&uarr;</kbd></td>
          <td><kbd>kp 8</kbd></td>
          <td><kbd>K</kbd></td>
          <td>Up</td>
        </tr>
        <tr>
          <td><kbd>&darr;</kbd></td>
          <td><kbd>kp 2</kbd><kbd>kp 5</kbd></td>
          <td><kbd>J</kbd></td>
          <td>Down</td>
        </tr>
      </tbody>
    </table>


You can use the :kbd:`8`:kbd:`4`:kbd:`5`:kbd:`6` keys on they keypad for
right-handed `WASD style
<https://en.wikipedia.org/wiki/Arrow_keys#WASD_keys>`_ navigation.

.. note::

  *NumLock* must be off if you want to use the number keys on the numeric
  keypad for navigation.


To move in 5-cell jumps, hold down :kbd:`Ctrl` while using the movement keys.
Similarly, you can pan the level by holding down :kbd:`Shift`. This can be
combined with :kbd:`Ctrl` to pan in 5-cell increments.

Note how the current coordinates change in right corner of the status bar as
you're moving the cursor. You can toggle the display of cell
coordinates around the level with :kbd:`Alt+C`. If you wish to change how the
coordinates are displayed, you can do so in the :ref:`maps-and-levels:Map
Properties` or :ref:`maps-and-levels:Level Properties` dialogs.

Changing the cursor location can be done with the mouse as well: left-click on
a cell within the level and the cursor will jump to that location. You can
even click-drag to move the cursor continuously.


Walk Mode
=========

*Walk Mode* can be toggled with the :kbd:`\`` key (that's the `grave accent
<https://en.wikipedia.org/wiki/Grave_accent>`_ or backtick key located in the
top-left corner of the keyboard before the :kbd:`1` key). The cursor is
displayed as a triangle instead of a square in this mode. The triangle points
to the walking direction and represents your avatar; you can turn, strafe, and
move forward and backward, just like in a classic dungeon crawler.

.. raw:: html

    <div class="figure">
      <a href="_static/img/mode-normal.png" class="glightbox">
        <img alt="Walk mode (triangle cursor pointing to the walking direction)" src="_static/img/mode-walk.png" style="width: 25%;">
      </a>
        <p class="caption">
          <span>Walk Mode (triangle cursor pointing to the walking direction)</span>
        </p>
    </div>


The cursor keys perform different actions in this mode, and Vim-style HJKL
navigation is not available (it would be too confusing):


.. raw:: html

    <table class="shortcuts std-move-keys">
      <thead>
        <tr>
          <th>Arrow</th>
          <th>Keypad</th>
          <th></th>
        </tr>
      </thead>
      <tbody class="no-padding">
        <tr>
          <td><kbd>&larr;</kbd></td>
          <td><kbd>kp 4</kbd></td>
          <td>Strafe left</td>
        </tr>
        <tr>
          <td><kbd>&rarr;</kbd></td>
          <td><kbd>kp 6</kbd></td>
          <td>Strafe right</td>
        </tr>
        <tr>
          <td><kbd>&uarr;</kbd></td>
          <td><kbd>kp 8</kbd></td>
          <td>Forward</td>
        </tr>
        <tr>
          <td><kbd>&darr;</kbd></td>
          <td><kbd>kp 2</kbd><kbd>kp 5</kbd></td>
          <td>Backward</td>
        </tr>
        <tr>
          <td>&ndash;</td>
          <td><kbd>kp 7</kbd></td>
          <td>Turn left</td>
        </tr>
        <tr>
          <td>&ndash;</td>
          <td><kbd>kp 9</kbd></td>
          <td>Turn right</td>
        </tr>
      </tbody>
    </table>

Similarly to *Normal Mode*, you can use the :kbd:`Ctrl` and :kbd:`Shift`
modifiers to perform jumps or pan the level, respectively, and you can also
left-click on a cell to move the cursor there.


WASD Mode
=========

Certain cRPGs, typically dungeon crawlers with real-time combat, are best
played with your left hand on the `WASD keys
<https://en.wikipedia.org/wiki/Arrow_keys#WASD_keys>`_ for moving the party,
and your right hand on the mouse for combat. Gridmonger's *WASD Mode* was
designed with players in mind who prefer to do the bulk of their mapping
with the WASD keys and the mouse when playing such games.

*WASD Mode* can be toggled with the :kbd:`Tab` key. You will see an indicator
in the top-left corner of the window when *WASD Mode* is on.

.. raw:: html

    <div class="figure">
      <a href="_static/img/mode-wasd.png" class="glightbox">
        <img alt="WASD Mode (square cursor and WASD indicator)" src="_static/img/mode-wasd.png" style="width: 25%;">
      </a>
        <p class="caption">
          <span>WASD Mode (square cursor and WASD indicator)</span>
        </p>
    </div>


When it comes to navigation, this mode is the same as *Normal Mode*, with the
addition that you can also use the :kbd:`W`:kbd:`A`:kbd:`S`:kbd:`D` keys for
cursor movement. Editing, however, is a little different --- see
:ref:`basic-editing:Editing in WASD Mode` to learn more about editing with the
mouse in this mode.

.. note::

   In *WASD Mode*, you cannot use the :kbd:`Ctrl` movement modifier with the
   :kbd:`W`:kbd:`A`:kbd:`S`:kbd:`D` keys for 5-cell jumps because that would
   interfere with other shortcuts. You can, however, use the :kbd:`Shift`
   modifier with them, and both the :kbd:`Ctrl` and :kbd:`Shift` modifiers are
   available with the other movement keys.

   As we'll see in the :ref:`basic-editing:Editing in WASD Mode` section, the
   mouse buttons are used for editing actions in this mode, so you need to
   hold :kbd:`Shift` while left-clicking to move the cursor.


.. rst-class:: style2

WASD + Walk Mode
================

If you enable both *WASD Mode* and *Walk Mode* (yes, you can do that!), the
movement keys become a bit more interesting:

.. raw:: html

    <table class="shortcuts std-move-keys">
      <thead>
        <tr>
          <th>Arrow</th>
          <th>Keypad</th>
          <th>WASD</th>
          <th></th>
        </tr>
      </thead>
      <tbody class="no-padding">
        <tr>
          <td><kbd>&larr;</kbd></td>
          <td><kbd>kp 4</kbd></td>
          <td><kbd>A</kbd></td>
          <td>Strafe left</td>
        </tr>
        <tr>
          <td><kbd>&rarr;</kbd></td>
          <td><kbd>kp 6</kbd></td>
          <td><kbd>D</kbd></td>
          <td>Strafe right</td>
        </tr>
        <tr>
          <td><kbd>&uarr;</kbd></td>
          <td><kbd>kp 8</kbd></td>
          <td><kbd>W</kbd></td>
          <td>Forward</td>
        </tr>
        <tr>
          <td><kbd>&darr;</kbd></td>
          <td><kbd>kp 2</kbd><kbd>kp 5</kbd></td>
          <td><kbd>S</kbd></td>
          <td>Backward</td>
        </tr>
        <tr>
          <td>&ndash;</td>
          <td><kbd>kp 7</kbd></td>
          <td><kbd>Q</kbd></td>
          <td>Turn left</td>
        </tr>
        <tr>
          <td>&ndash;</td>
          <td><kbd>kp 9</kbd></td>
          <td><kbd>E</kbd></td>
          <td>Turn right</td>
        </tr>
      </tbody>
    </table>


Admittedly, this is the most complex mode, and while some people might find it
really useful, if it doesn't click with you, don't feel compelled to use it.
In fact, *yours truly* pretty much only use *Normal Mode*, even when playing
real-time dungeon crawlers with WASD controls...

.. raw:: html

    <div class="figure">
      <a href="_static/img/mode-wasd+walk.png" class="glightbox">
        <img alt="WASD + Walk Mode (triangle cursor and WASD indicator)" src="_static/img/mode-wasd+walk.png" style="width: 25%;">
      </a>
        <p class="caption">
          <span>WASD + Walk Mode (triangle cursor and WASD indicator)</span>
        </p>
    </div>


.. rst-class:: style3 big

Navigating dialogs
==================

Apart from the usual :kbd:`Enter` to accept and :kbd:`Esc` to cancel, there
are a number of other handy shortcuts available in dialogs to maximise
efficiency.

:kbd:`Tab` and :kbd:`Shift+Tab` cycle between text fields in forward and
reverse order, respectively.

To switch between tabs, hold :kbd:`Ctrl` and press the left or right
navigation key. To jump to the *N*\ th tab, press :kbd:`Ctrl`\ +\ *N*, where
*N* is a number key (from the top row of the keyboard).

In some dialogs, you need to select something from a list of options (e.g. an
icon or a colour). You can use the navigation keys to do that. (You will see
examples of this later.)

Finally, you can press :kbd:`Alt+D` to select the **Discard** option where
applicable.

.. tip::

   Hardcore Vim enthusiasts, such as *yours truly*, remap the quite useless
   :kbd:`CapsLock` key to :kbd:`Ctrl` with a tool like `SharpKeys
   <https://github.com/randyrants/sharpkeys>`_ on Windows for extra
   efficiency. The :kbd:`Ctrl+[` Vim alias for the :kbd:`Esc` key is supported
   by Gridmonger for these people (it's much more efficient to type than
   reaching out for :kbd:`Esc` with your left pinky!)


.. raw:: html

   <div class="section style3"></div>


.. _about-vim:

.. admonition:: About Vim
   :class: sidenote about-vim

   If you're not a programmer, you're probably wondering what the hell this
   Vim thing is about! In short, Vim is a programmer's text-editor for people
   who know how to touch type. One of its most iconic feature is to allow
   typists to move the cursor without lifting their hands from the `home row
   <https://en.wikipedia.org/wiki/Touch_typing#Home_row>`_  (the ``ASDF`` and
   ``JKL;`` keys), and perform most common editing tasks with one or
   two-letter commands, without ever straying too far from the home position.

   Ergonomics wise, editing a grid-based cRPG map is very similar to editing a
   text file. Having to move your hand back and forth between the cursor keys
   (or the mouse) and the rest of the keyboard thousands of times a day is a
   huge performance killer. No wonder that people who learn how to touch type
   and get a taste of Vim rarely go back to their "old ways"! As the saying
   goes, there are only two types of people in the world: those who love Vim,
   and the rest who haven't learned it yet!

   In my opinion, touch typing is an essential skill that anyone working on a
   computer several hours a day should master. If you haven't learned to touch
   type yet, I very much encourage you to do so, and then give Vim-style
   navigation a go. I almost guarantee that you will be very positively
   surprised!

   There's tons of free touch typing trainers online, or you can just go
   old-school and use the completely unattractive but 100% effective `GNU
   Typist <https://www.gnu.org/savannah-checkouts/gnu/gtypist/gtypist.html>`_
   like I did back in the day. I was able to re-train my erratic typing
   patterns ingrained over 10+ years of constant computer use in about two
   short weeks, so if I could do it, then anybody can.


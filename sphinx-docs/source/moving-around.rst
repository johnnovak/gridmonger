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
respectively. There are 50 zoom levels in total.

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

   To spell it out, if you're using a non-US keyboard, you'll need to find
   the *location* of the key on the `US keyboard layout
   <https://kbdlayout.info/KBDUS>`_ that manual asks you to press, then press
   the key *at the same location* on your keyboard, regardless of the key's
   label.


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
also use Vim-style `HJKL key navigation 
<https://en.wikipedia.org/wiki/Arrow_keys#HJKL_keys>`_ to move
around. You might have already encountered this navigation style in
some text-based games originally developed on UNIX systems, such as the
venerable `Rogue <https://en.wikipedia.org/wiki/Rogue_(video_game)>`_ and `NetHack
<https://en.wikipedia.org/wiki/NetHack>`_.

If this doesn't mean anything to you, don't worry! Just keep using the
standard cursor keys or the keypad for now. But I do recommend you to read the
:ref:`About Vim <about-vim>` side-note at the end; you might find it
interesting enough to explore this topic further.

The following table summarises the *standard movement keys* available in
*Normal Mode*:

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
          <td>Left (West)</td>
        </tr>
        <tr>
          <td><kbd>&rarr;</kbd></td>
          <td><kbd>kp 6</kbd></td>
          <td><kbd>L</kbd></td>
          <td>Right (East)</td>
        </tr>
        <tr>
          <td><kbd>&uarr;</kbd></td>
          <td><kbd>kp 8</kbd></td>
          <td><kbd>K</kbd></td>
          <td>Up (North)</td>
        </tr>
        <tr>
          <td><kbd>&darr;</kbd></td>
          <td><kbd>kp 2</kbd><kbd>kp 5</kbd></td>
          <td><kbd>J</kbd></td>
          <td>Down (South)</td>
        </tr>
      </tbody>
    </table>


To move in 5-cell jumps, hold down :kbd:`Ctrl` while using the movement keys.
Similarly, you can pan the level by holding down :kbd:`Shift`. This can be
combined with :kbd:`Ctrl` to pan in 5-cell increments.

.. admonition:: Note for macOS users

   The 5-cell jump modifier is always :kbd:`Ctrl` on macOS regadless of your
   keyboard :ref:`preferences:preferences` settings. This is because certain
   :kbd:`Cmd` plus movement key combinations would clash with system
   shortcuts.


Observe how the current coordinates change in the bottom right corner of the
window as you move the cursor. You can toggle the display of cell
coordinates around the level with :kbd:`Alt+C`. If you wish to change how the
coordinates are displayed, you can do so in the :ref:`maps-and-levels:Map
Properties` or :ref:`maps-and-levels:Level Properties` dialogs.

.. note::

  *NumLock* must be off if you want to use the keypad for navigation.

.. tip::

  You can use the :kbd:`8`:kbd:`4`:kbd:`5`:kbd:`6` keys on they keypad for
  right-handed `WASD style
  <https://en.wikipedia.org/wiki/Arrow_keys#WASD_keys>`_ navigation.


Movement wraparound
~~~~~~~~~~~~~~~~~~~

Some cunningly crafted dungeons feature maps that "wrap around" from one side
to the other --- you step off the edge of the map, and you'll find yourself
entering on the opposite side (e.g., the first level of `Wizardry: Proving
Grounds of the Mad Overlord
<https://en.wikipedia.org/wiki/Wizardry:_Proving_Grounds_of_the_Mad_Overlord>`_,
or the fourth spider-infested level of `Eye of the Beholder
<https://en.wikipedia.org/wiki/Eye_of_the_Beholder_(video_game)>`_).

By default, you cannot move past the edges of the level but you can enable
this behaviour by ticking the **Movement wraparound** checkbox in the
:ref:`preferences:Editing tab` of the :ref:`preferences:Preferences` dialog.
For consistency, this enables wraparound cursor movement in all editing modes
(you'll learn about these modes below and in later chapters).


Diagonal movement
~~~~~~~~~~~~~~~~~

You can use the keypad to move in the intercardinal directions too
(diagonally, in 45-degree angle):

.. raw:: html

    <table class="shortcuts std-move-keys" style="width: 67%">
      <thead>
        <tr>
          <th>Keypad</th>
          <th width="45%"></th>
        </tr>
      </thead>

      <tbody class="no-padding">
        <tr>
          <td><kbd>kp 7</kbd></td>
          <td>Up &amp; left (Northwest)</td>
        </tr>
        <tr>
          <td><kbd>kp 9</kbd></td>
          <td>Up &amp; right (Northeast)</td>
        </tr>
        <tr>
          <td><kbd>kp 1</kbd></td>
          <td>Down &amp; left (Southwest)</td>
        </tr>
        <tr>
          <td><kbd>kp 3</kbd></td>
          <td>Down &amp; right (Southeast)</td>
        </tr>
      </tbody>
    </table>



In addition to the numeric keypad, there is an option to move the cursor
diagonally with the YUBN keys. This might be familiar to some from the classic
game `Rogue <https://en.wikipedia.org/wiki/Rogue_(video_game)>`_:

.. raw:: html

    <table class="shortcuts std-move-keys">
      <thead>
        <tr>
          <th>Keypad</th>
          <th>Vim</th>
          <th width="45%"></th>
        </tr>
      </thead>

      <tbody>
        <tr>
          <td><kbd>kp 7</kbd></td>
          <td><kbd>Y</kbd></td>
          <td>Up &amp; left (Northwest)</td>
        </tr>
        <tr>
          <td><kbd>kp 9</kbd></td>
          <td><kbd>U</kbd></td>
          <td>Up &amp; right (Northeast)</td>
        </tr>
        <tr>
          <td><kbd>kp 1</kbd></td>
          <td><kbd>B</kbd></td>
          <td>Down &amp; left (Southwest)</td>
        </tr>
        <tr>
          <td><kbd>kp 3</kbd></td>
          <td><kbd>N</kbd></td>
          <td>Down &amp; right (Southeast)</td>
        </tr>
      </tbody>
    </table>

YUBN navigation is off by default as these keys clash with some other
shortcuts. You need to enable **YUBN diagonal movement** explicitly in the
:ref:`preferences:Editing tab` of the :ref:`preferences:Preferences` dialog if
you wish to use it. Actions whose shortcuts clash with the YUBN keys also have
alternative secondary shortcuts to ensure you can still access them with YUBN
mode enabled.

The :kbd:`Shift` modifier to pan the level is available with
the YUBN keys too.

The :kbd:`Ctrl` modifier for 5-cell jumps, however, only works with the
diagonal movement keys on the numeric keypad to prevent further shortcut
clashes.


Mouse movement actions
~~~~~~~~~~~~~~~~~~~~~~

Changing the cursor location can be done with the mouse as well: left-click on
a cell within the level and the cursor will jump to that location. You can
even click-drag to move the cursor continuously.

To pan the level with the mouse, hold down the middle button over the level
and move the mouse pointer. Alternatively, you can left-click and move the
pointer while holding down the :kbd:`Ctrl` key.


Walk Mode
=========

*Walk Mode* can be toggled with the :kbd:`\`` key (that's the `grave accent
<https://en.wikipedia.org/wiki/Grave_accent>`_ or backtick key located in the
top-left corner of the keyboard before the :kbd:`1` key). The cursor is
displayed as a triangle instead of a square in *Walk Mode*. The triangle
represents your avatar and points to the walking direction; you can turn,
strafe, and move forward and backward, just like in a classic dungeon crawler.

.. raw:: html

    <div class="figure">
      <a href="_static/img/mode-normal.png" class="glightbox">
        <img alt="Walk mode (triangle cursor pointing to the walking direction)" src="_static/img/mode-walk.png" style="width: 25%;">
      </a>
        <p class="caption">
          <span>Walk Mode (triangle cursor pointing to the walking direction)</span>
        </p>
    </div>


By default, the left and right cursor keys perform strafing in *Walk Mode*.
You can change this to turning instead with the **Walk mode Left/Right keys**
option in the :ref:`preferences:Editing tab` of the
:ref:`preferences:Preferences` dialog.

Depending on whether :kbd:`←` and :kbd:`→` perform strafing or
turning, you can still use the other action with the :kbd:`Alt` modifier:

.. raw:: html

    <table class="shortcuts std-move-keys">
      <thead>
        <tr>
          <th>Arrow</th>
          <th>Strafe mode</th>
          <th>Turn mode</th>
        </tr>
      </thead>
      <tbody class="no-padding">
        <tr>
          <td><kbd>&uarr;</kbd></td>
          <td>Forward</td>
          <td>Forward</td>
        </tr>
        <tr>
          <td><kbd>&darr;</kbd></td>
          <td>Backward</td>
          <td>Backward</td>
        </tr>
        <tr>
          <td><kbd>&larr;</kbd></td>
          <td>Strafe left</td>
          <td>Turn left</td>
        </tr>
        <tr>
          <td><kbd>Alt</kbd>+<kbd>&larr;</kbd></td>
          <td>Turn left</td>
          <td>Strafe left</td>
        </tr>
        <tr>
          <td><kbd>&rarr;</kbd></td>
          <td>Strafe right</td>
          <td>Turn right</td>
        </tr>
        <tr>
          <td><kbd>Alt</kbd>+<kbd>&rarr;</kbd></td>
          <td>Turn right</td>
          <td>Strafe right</td>
        </tr>
      </tbody>
    </table>

The strafe and turn actions are always available on the keypad without
the need for the :kbd:`Alt` modifier:

.. raw:: html

    <table class="shortcuts std-move-keys">
      <thead>
        <tr>
          <th>Keypad</th>
          <th></th>
        </tr>
      </thead>
      <tbody class="no-padding">
        <tr>
          <td><kbd>kp 4</kbd></td>
          <td>Strafe left</td>
        </tr>
        <tr>
          <td><kbd>kp 6</kbd></td>
          <td>Strafe right</td>
        </tr>
        <tr>
          <td><kbd>kp 8</kbd></td>
          <td>Forward</td>
        </tr>
        <tr>
          <td><kbd>kp 2</kbd><kbd>kp 5</kbd></td>
          <td>Backward</td>
        </tr>
        <tr>
          <td><kbd>kp 7</kbd></td>
          <td>Turn left</td>
        </tr>
        <tr>
          <td><kbd>kp 9</kbd></td>
          <td>Turn right</td>
        </tr>
      </tbody>
    </table>

Just like in *Normal Mode*, you can use the :kbd:`Ctrl` and :kbd:`Shift`
modifiers to perform jumps or pan the level, respectively, and the same
:ref:`moving-around:Mouse movement actions` are also available.

Diagonal movement is not available in *Walk Mode* as it's not compatible with
the concept, and the numeric keys are used for other purposes anyway.

You can't use Vim-style HJKL navigation for walking either as that would be
too confusing. Consider using the :ref:`moving-around:WASD + Walk Mode` option
instead.


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
addition that you can also use the WASD keys for cursor movement. All diagonal
movement keys are available in *WASD mode*. Editing, however, is a little
different --- as you'll learn in the :ref:`basic-editing:Editing in WASD Mode`
section, the mouse buttons are repurposed for editing in this mode, so you
need to hold the :kbd:`Shift` modifier to use the :ref:`moving-around:Mouse
movement actions`.



.. note::

   In *WASD Mode*, you cannot use the :kbd:`Ctrl` movement modifier with the
   WASD keys for 5-cell jumps because that would
   interfere with other shortcuts. You can, however, use the :kbd:`Shift`
   modifier with them, and both the :kbd:`Ctrl` and :kbd:`Shift` modifiers are
   available with the other movement keys.


.. rst-class:: style2

WASD + Walk Mode
================

If you enable both *WASD Mode* and *Walk Mode* (yes, you can do that!), the
movement keys become a bit more interesting:

.. raw:: html

    <table class="shortcuts std-move-keys">
      <thead>
        <tr>
          <th>Arrow<br>(Turn mode)</th>
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

Strafe mode, turn mode, and the  :kbd:`Alt` modifiers for the arrow keys work
exactly the same way as in :ref:`moving-around:Walk mode`; they have only been
omitted for brevity.

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

In some dialogs, you need to select something from a list of options (e.g., an
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

   You can achieve the same thing on macOS by customising the modifier keys in
   the System Settings, and Linux offers similar customisation options.

.. admonition:: Note for macOS users

   Because these :kbd:`Ctrl` based shortcuts exist to please Vim users for the
   reasons outlined above, they're are never remapped to :kbd:`Cmd` on macOS.



.. raw:: html

   <section class="style6"></section>


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


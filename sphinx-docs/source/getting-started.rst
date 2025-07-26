***************
Getting started
***************

Like most worthwhile things in life, Gridmonger is *not* instant
gratification.  To paraphrase the famous quote about Linux:

.. rst-class:: quote

*Gridmonger is definitely user-friendly, but it's perhaps a tad more
selective about its friends than your average desktop application.*

But, alas, worry not --- if you are a fan of old-school computer role-playing
games and you are able to set them up in emulators, you will get along with
Gridmonger just fine!

The user interface is optimised for power users and is therefore operable by
keyboard shortcuts almost exclusively. While you could get quite far going by
the list of :ref:`appendixes/keyboard-shortcuts:Keyboard shortcuts` alone, the
more complex features --- especially the reason behind them --- would not be
so trivial to figure out on your own.  I very much recommend reading through
this manual at least once to familiarise yourself with the complete list of
program features. And don't just read --- create a test map, or load one of
the included `Example maps
<https://gridmonger.johnnovak.net/files/gridmonger-example-maps.zip>`_, and
try the features for yourself as you progress through the chapters!

Having said all that, some people are just impatient or want to get a taste
of the thing before committing to learning it. For them, I have included a few
quick tips in the :ref:`getting-started:quickstart` section below.

Requirements
============

Gridmonger requires very little hard drive space, only around 6-8 megabytes.
Windows 7 & 10 and macOS Mojave or later (10.14+) are supported, although, in
all likelihood, it will work fine on Windows XP and much earlier macOS
versions.

The program uses OpenGL for all its rendering; it works similarly to a game
engine. Any graphics card released in the last 10 years should be sufficient,
including laptops with integrated graphics.

Installation
============

Windows
-------

To install Gridmonger on Windows, download either the Windows installer (for
standard installations) or the portable ZIP package from the `Downloads
<https://gridmonger.johnnovak.net/#Downloads>`_ page, then run the installer
or simply unpack the ZIP file's contents somewhere. First-time users are
encouraged to use the installer and accept the default options.

.. important::

   If you choose the portable ZIP version, make sure to unpack it into a
   folder that is writable by normal (non-administrator) users. So don't put
   it into ``Program Files`` or similar system folders, as that will most
   likely not work.

macOS
-----

Just grab the program from the `Downloads
<https://gridmonger.johnnovak.net/#Downloads>`_ page and move it into your
``Applications`` folder. This is an unsigned application, so the usual advice
for running such apps applies (you'll need to grant the necessary permissions,
etc.)

Linux
-----

No Linux builds are provided yet, but you can try to build the program
yourself by following the `build instructions
<https://github.com/johnnovak/gridmonger#build-instructions>`_. There might be
some graphical glitches when resizing and moving the application window under
certain window managers, but otherwise, the program should work fine.


.. rst-class:: style8

Note for macOS users
====================

The manual only lists the Windows and Linux keyboard shorcuts for brevity, but
Gridmonger uses macOS user interface conventions by default.

So when the manual tells you to press the :kbd:`Ctrl` + ``Key`` shortcut, use
:kbd:`Cmd` + ``Key`` instead.

Similarly, :kbd:`Ctrl+Alt` + ``Key`` becomes :kbd:`Cmd+Shift` + ``Key``, and
lastly, :kbd:`Alt` + ``Key`` becomes :kbd:`Opt` + ``Key``.

The program always displays the correct modifier key labels in the user
interface. You can also refer to the quick keyboard reference panel by
pressing :kbd:`Shift+/` which shows the actual shortcuts.

You can switch to :kbd:`Ctrl` & :kbd:`Alt` based shortcuts even on macOS in
the :ref:`Preferences <shortcut modifiers>` dialog.


.. rst-class:: style4 big

Quickstart
==========

For the impatient among you, here are a few notes to get you started.

.. important::

   Always keep an eye on the *status bar messages* at the bottom of the
   window, as they contain important context-dependent information about the
   tools you're trying to use.

.. tip::

   If the user interface text is too small for you, you can set a custom
   scaling factor in the :ref:`Preferences <interface scaling>` dialog.


**Help**

.. rst-class:: multiline

- Press :kbd:`Shift+/` to display the quick keyboard reference
- Press :kbd:`F1` to open this manual in your default browser


**Maps & levels**

.. rst-class:: multiline

- :kbd:`Ctrl+O` opens a map, :kbd:`Ctrl+S` saves the map
- :kbd:`Ctrl+Alt+N` creates a new map
- :kbd:`Ctrl+Alt+P` opens the map properties
- :kbd:`Ctrl+N` creates a new level
- :kbd:`Ctrl+P` opens the level properties
- :kbd:`Ctrl+D` deletes the current level
- Cycle through the levels of the map with :kbd:`Ctrl+-` and :kbd:`Ctrl+=`,
  or :kbd:`PgUp` and :kbd:`PgDn`


**Themes**

.. rst-class:: multiline

- Use :kbd:`Ctrl+PgUp` and :kbd:`Ctrl+PgDn` to cycle through the themes
  (or :kbd:`Ctrl+Fn+↑` and :kbd:`Ctrl+Fn+↓` on laptops).


**Editing**

.. rst-class:: multiline

- Use the arrow keys, the numeric keypad, or :kbd:`H`:kbd:`J`:kbd:`K`:kbd:`L`
  to move the cursor (these are the *movement keys*)
- Adjust the zoom level with :kbd:`-` and :kbd:`=`
- Undo with with :kbd:`U`, :kbd:`Ctrl+U`, or :kbd:`Ctrl+Z`
- Redo with :kbd:`Ctrl+R` or :kbd:`Ctrl+Y`
- Hold :kbd:`D` and use the *movement keys* to draw (excavate)
  tunnels
- Hold :kbd:`E` and use the *movement keys* to erase cells
- Hold :kbd:`W` and use the *movement keys* to draw/clear walls around a cell
- Hold :kbd:`R` and use the *movement keys* to draw/clear special walls; change
  the current special wall with :kbd:`[` and :kbd:`]`
- Use :kbd:`1`–:kbd:`8` to place various floor types; press a number key
  repeatedly to cycle through all floor types assigned to that key (hold
  :kbd:`Shift` to cycle backwards)
- Press :kbd:`N` or :kbd:`;` to add a note to a cell or to edit an existing
  note
- Press :kbd:`Shift+N` or :kbd:`Shift+;` to remove a note



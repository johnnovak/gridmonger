***************
Getting started
***************

Like most worthwhile things in life, Gridmonger is *not* instant
gratification.  To paraphrase the famous quote about Linux:

.. rst-class:: quote

*Gridmonger is definitely user-friendly, but it's perhaps a tad more
selective about its friends than your average desktop application.*

But, alas, worry not --- if you are a fan of old-school computer role-playing
games, and you are able to set them up in emulators, you will get along with
Gridmonger just fine!

The user interface is optimised for power users, and therefore is operable by
keyboard shortcuts almost exclusively. While you could get quite far going by
the list of :ref:`appendixes/keyboard-shortcuts:Keyboard shortcuts` alone, the
more complex features --- and especially the reason behind them --- would be
not so trivial to figure out on your own.  I very much recommend reading
through this manual at least once to familiarise yourself with the full list
of program features. And don't just read --- create a test map, or load one of
the included `Example maps <https://gridmonger.johnnovak.net/files/gridmonger-example-maps.zip>`_, and try the
features for yourself as you're progressing through the chapters!

Having said all that, some people are just impatient, or want to get a taste
of the thing before committing to learning it. For them, I have included a few
quick tips in the :ref:`getting-started:quickstart` section below.

Requirements
============

Gridmonger requires very little hard drive space, only around 6-8 megabytes.
Windows 7 & 10 and macOS Mojave or later (10.14+) are supported, although
in all likelihood it will work just fine on Windows XP and much earlier macOS
versions. Currently, only Intel binaries are provided for macOS.

The program uses OpenGL for all its rendering; it works very similarly to a
game engine. You'll need a graphics card that supports OpenGL 3.2 core
profile or later. In practice, this means that any graphics card released in
the last 10 years or so will do (including integrated ones).

Installation
============

Windows
-------

To install Gridmonger on Windows, download either the Windows installer (for
standard installations) or the ZIP file (for portable installations) from the
`Downloads <https://gridmonger.johnnovak.net/#Downloads>`_ page. Then run the
installer, or simply unpack the contents of the ZIP file somewhere. First-time
users are encouraged to use the installer and accept the default install
options.

The 64-bit version is strongly recommended as it's more performant and more
thoroughly tested; only use the 32-bit version if you're still running a
legacy 32-bit version of Windows.

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


.. rst-class:: style4 big

Quickstart
==========

For the impatient among you, here's a few notes to get you started.

.. important::

   Always have an eye on the *status bar messages* at the bottom of the
   window, as they contain important context-dependent information about the
   tools you're trying to use.


**Maps & levels**

.. rst-class:: multiline

- :kbd:`Ctrl+O` opens a map, :kbd:`Ctrl+S` saves the current map
- :kbd:`Ctrl+Alt+N` creates a new map; :kbd:`Ctrl+Alt+P` opens the map
  properties
- :kbd:`Ctrl+N` creates a new level; :kbd:`Ctrl+P` opens the level properties
- :kbd:`Ctrl+D` deletes the current level
- Cycle through levels with :kbd:`Ctrl+-`/:kbd:`Ctrl+=` or
  :kbd:`PgUp`/:kbd:`PgDn`


**Themes**

.. rst-class:: multiline

- Use :kbd:`Ctrl+PgUp`/:kbd:`Ctrl+PgDn` to cycle through the themes


**Editing**

.. rst-class:: multiline

- Use the arrow keys or the :kbd:`H`:kbd:`J`:kbd:`K`:kbd:`L` for movement
- Set the zoom level with :kbd:`-`/:kbd:`=`
- Undo with :kbd:`U` or :kbd:`Ctrl+Z`; redo with :kbd:`Ctrl+R` or :kbd:`Ctrl+Y`
- Hold :kbd:`D` and use the movement keys to draw (excavate)
  tunnels
- Hold :kbd:`E` and use the movement keys to erase cells
- Hold :kbd:`W` and use the movement keys to draw/clear walls in the current
  cell
- Hold :kbd:`R` and use the movement keys to draw/clear special walls; change
  the current special wall with :kbd:`[`/:kbd:`]`
- Use :kbd:`1`-:kbd:`7` to place various floor types; press a number key
  repeatedly to cycle through all floor types assigned to that key (hold
  :kbd:`Shift` to cycle backwards)
- Press :kbd:`N` to create or edit notes

**Help**

.. rst-class:: multiline

- Press :kbd:`Shift+/` to display the quick keyboard reference
- Press :kbd:`F1` to open the manual in your default browser



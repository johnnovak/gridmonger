.. rst-class:: style7 big

***********
Preferences
***********

Before continuing with editing, let's quickly have a look at the preferences
settings. Press :kbd:`Ctrl+Alt+U` to bring up the preferences dialog. 

Startup tab
===========

On the **Startup** tab you have the option to toggle the display of the splash
screen, and to have it auto-closed after a set number of seconds.

Another important setting is the **Load last map** option. This is enabled by
default, so you can continue from where you left off in your next Gridmonger
session.

General tab
===========

On the **General** tab you will find the autosave settings. By default, the
map gets automatically saved every two minutes. This is great in general, but
you need to exercise some caution in order not to accidentally lose your work
(e.g., if the autosave kicks in right after deleting some levels and you quit
the program, you won't get the save confirmation dialog as the changes have
been already saved...) Also, if you're going to experiment with the editing
functions on the included example maps, it's best to either turn autosave off,
or create backup copies of the example maps first.

Below the autosave settings, you have the option to **Enable vertical sync**.
The program does its drawing just like a game engine; it's locked to your
desktop refresh rate if vertical sync is on. Disabling it may increase the
responsiveness of the UI, but at the cost of potentially much higher CPU
consumption. Generally, you should leave it on.

Editing tab
===========

This tab contains options that affect the workings of the editing operations.

**Movement-wrap around** controls whether the cursor should appear on the
opposite side when moved past the edges of the level (see
:ref:`moving-around:Movement wrap-around`).

**YUBN diagonal movement** enables moving the cursor in the intercardinal
directions via the YUBN keys in addition to the numeric keypad (see
:ref:`moving-around:Diagonal movement`).

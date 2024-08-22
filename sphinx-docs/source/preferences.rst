.. rst-class:: style7 big

***********
Preferences
***********

Before continuing with editing, let's quickly have a look at the preferences
settings. Press :kbd:`Ctrl+Alt+U` to bring up the preferences dialog. 

macOS users can always use the standard :kbd:`Cmd+,` shortcut as well.


General tab
===========

The first setting in the **General** tab is **Load last map**. This
allows you to continue from where you left off when you next start Gridmonger.

The next few settings control the **Autosave** behaviour. By default, the map
gets automatically saved every two minutes. This is great in general, but you
need to exercise some caution in order not to accidentally lose your work
(e.g., if the autosave kicks in right after deleting some levels and you quit
the program, you won't get the save confirmation dialog as the changes have
been already saved...) Also, if you're going to experiment with the editing
functions on the included example maps, it's best to either turn autosave off,
or create backup copies of the example maps first.

.. important::

    If autosaves are enabled and the current map hasn't been manually saved
    yet, an autosave file ``Untitled 1.gmm`` will be created in the special
    ``Autosave`` folder located in your :ref:`appendixes/user-data-folder:User
    Data Folder`.

If **Check for updates** is enabled, Gridmonger displays a notification if a
more recent version is available on program start or when you open the about
dialog.


Editing tab
===========

The **Editing** tab contains settings that affect the editing operations.

**Movement wraparound** controls whether the cursor should appear on the
opposite side when moved past the edges of the level (see
:ref:`moving-around:Movement wraparound`).

**YUBN diagonal movement** enables the YUBN keys for
:ref:`moving-around:Diagonal movement` in :ref:`moving-around:Normal mode` and
:ref:`moving-around:WASD mode` only, in addition to the numeric keypad.

**Walk mode Left/Right keys** controls whether the left and right cursor keys
perform strafing or turning in :ref:`moving-around:Walk mode`. This is
especially useful on keyboards without a numeric keypad. This only controls
the behaviour of the regular cursor keys --- the cursor keys on the keypad are
unaffected by this setting.

.. _show link lines:

**Show link lines** controls the display of lines that indicate
:ref:`advanced-editing:Linked cells` in the current level:

.. rst-class:: multiline

- **Manual toggle** -- All link lines are shown when you hold down the
  :kbd:`'` key, and only then (apostrophe key, to the left of :kbd:`Enter`).

- **Current cell** -- Link lines are shown for the current cell, holding the
  :kbd:`'` key shows all link lines.

- **All** -- All link lines are shown all the time.

**Open-ended excavate** controls whether the *excavate (draw tunnel)* tool
should close the tunnels off with a wall in the excavation direction (see
:ref:`basic-editing:Open-ended excavate`).


Interface tab
=============

The **Interface** tab is the home of all user-interface related settings.

**Show splash image** controls whether the nice Gridmonger logo should be
displayed at startup, and the following two settings whether it should be
auto-closed after a set number of seconds.

Then you have the option to enable **Vertical sync**. The program does its
drawing just like a game engine; it's locked to your desktop's refresh rate if
vertical sync is on. Disabling it may increase the responsiveness of the UI,
but at the cost of potentially much higher CPU consumption. Generally, you
should leave this on.

.. _interface scaling:

**Interface scaling** lets you set the scaling (zooming) of the entire user
interface between 100% (no zoom) and 500% (5-fold zoom). Gridmonger takes your
operating system's DPI and scaling settings into account, so this scaling is
applied on top of that. The new scaling factor takes effect after closing the
preferences dialog with the **OK** button.

.. important::

    You can reset 100% scaling with the :kbd:`Ctrl+F11` shortcut (or
    :kbd:`Cmd+F11` on macOS, depending on your settings.) This is handy if
    you've accidentally set such a large scaling factor that you can no longer
    navigate the preferences dialog to reset it.

.. _shortcut modifiers:

**Shortcut modifiers** is a setting only available on macOS. By default,
Gridmonger uses macOS user interface conventions for most keyboard shortcuts,
so the :kbd:`Cmd` and :kbd:`Cmd+Shift` modifiers are used.

This user manual only lists the Windows and Linux keyboard shortcuts for
brevity, so by default, when you're asked to press the :kbd:`Ctrl` + ``Key``
shortcut, you should press :kbd:`Cmd` + ``Key`` instead.

Similarly, :kbd:`Ctrl+Alt` + ``Key`` becomes :kbd:`Cmd+Shift` + ``Key``, and
lastly, :kbd:`Alt` + ``Key`` becomes :kbd:`Opt` + ``Key``.

You can switch to :kbd:`Ctrl` & :kbd:`Alt` based shortcuts even on macOS by
selecting the **Ctrl, Ctrl+Alt** option in the **Shortcut modifier keys**
dropdown.

The below :kbd:`Cmd`-based system level shorcuts are so pervasive that they're
also available in **Ctrl, Ctrl+Alt** mode:

.. rst-class:: multiline

- :kbd:`Cmd+O` to open a map
- :kbd:`Cmd+S` and :kbd:`Cmd+Shift+S` to save the map
- :kbd:`Cmd+,` to open the preferences dialog
- :kbd:`Cmd+Q` to quit the program


.. tip::

    The program always displays the correct modifier key labels in the user
    interface. You can also refer to the quick keyboard reference panel by
    pressing :kbd:`Shift+/`, which shows the actual shortcuts.


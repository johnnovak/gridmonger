.. rst-class:: style7 big

***********
Preferences
***********

Before continuing with editing, let's quickly have a look at the preferences
settings. Press :kbd:`Ctrl+Alt+U` to bring up the preferences dialog. 

Startup tab
===========

On the **Startup**
tab you have the option to toggle the display of the splash screen, and to
have it auto-closed after a set number of seconds.

Another important setting is the **Load last map** option. This is enabled by
default, so you can continue from where you left off in your next Gridmonger
session.

General tab
===========

On the **General** tab you will find the autosave settings. By default, the
map gets automatically saved every two minutes. This is great in general, but
you need to exercise some caution in order not to accidentally lose your work
(e.g. by deleting some levels, after which autosave kicks in, then you
quit the program, and this won't display a warning at this point because the
changes have already been saved...) Also, if you're going to experiment with
the editing functions on the included example maps, it's best to either turn
autosave off, or create backup copies of the example maps first.

Some cunningly crafted dungeons feature maps that "wrap around" from one side
to the other --- you step off the edge of the map, and you'll find yourself
entering on the opposite side (e.g. the first level of `Wizardry: Proving Grounds of the Mad Overlord <https://en.wikipedia.org/wiki/Wizardry:_Proving_Grounds_of_the_Mad_Overlord>`_,
or the fourth spider-infested level of `Eye of the Beholder <https://en.wikipedia.org/wiki/Eye_of_the_Beholder_(video_game)>`_).
You can enable this behaviour by ticking the **Movement wrap-around**
checkbox. For consistency, this enables wrap-around cursor movement in all
modes.

Finally, you have the option to **Enable vertical sync**. The program does its
drawing just like a game engine; it's locked to your desktop refresh rate if
vertical sync is on. Disabling it may increase the responsiveness of the UI,
but at the cost of potentially much higher CPU consumption. Generally, you
should leave it on.

.. rst-class:: style4 big

**************
Window layouts
**************

A typical way to use Gridmonger on a single monitor is to run it side-by-side
with the game you're playing. By pressing the *snap to left* or *snap to
right* buttons in the title bar (the first two buttons in the top right
corner), you can snap the Gridmonger window to the left or right half of
the desktop, respectively.

    TODO better image showing the notes list pane & tools

.. raw:: html

    <div class="figure">
      <a href="_static/img/eob-full.png" class="glightbox">
        <img alt="Playing and mapping Eye of the Beholder I on a single screen" src="_static/img/eob-full.png">
      </a>
        <p class="caption">
          <span>Playing and mapping <a class="reference external" href="https://en.wikipedia.org/wiki/Eye_of_the_Beholder_(video_game)">Eye of the Beholder I</a> on a single screen</span>
        </p>
    </div>

That's all good and well, but when you display the notes list pane with
:kbd:`Alt+L`, the visible map area becomes too narrow.

*Window layouts* can help in such scenarios on single-monitor setups:

.. rst-class:: multiline

- Press the *snap to right* button---now the Gridmonger window occupies the
  right half of the screen.

- Press :kbd:`Shift+F5` to save the current window layout in the first layout
  slot. This will be your "default" layout when playing the game.

- Press :kbd:`Alt+L` to display the notes pane, then enlarge the window
  horizontally by dragging its left edge.

- Press :kbd:`Shift+F6` to save this "search note" layout in the second
  layout slot.

- Now you can quickly switch between the two layouts with the :kbd:`F5` and
  :kbd:`F6` keys.

The idea behind this is that you don't need to have the notes list pane open
all the time, only when you're trying to find a particular note. So then you
pause the game, switch to the "search note" layout, find the note, then switch
back to your "default" layout.

There are four window layout slots available. :kbd:`Shift+F5`–:kbd:`F8` save
the current window layout in slots 1–4, and :kbd:`F5`–:kbd:`F8` restore them.
Layouts are saved into the configuration file, so they are global (they're not
tied to the current map).

Layouts store the size and position of the window, and the state of the four
toggleable panes. To recap:

- :kbd:`Alt+N` — Toggle current note pane
- :kbd:`Alt+L` — Toggle notes list pane
- :kbd:`Alt+T` — Toggle tools pane
- :kbd:`Shift+Alt+T` — Toggle title bar




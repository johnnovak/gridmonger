.. rst-class:: style4 big

**************
Window layouts
**************

A typical way to use Gridmonger on a single monitor is to run it side-by-side
with the game you're playing. By pressing the *snap to left* or *snap to
right* buttons in the title bar (the first two buttons in the top right
corner), you can snap the Gridmonger window to the left or right half of
the desktop, respectively.

.. raw:: html

    <div class="figure">
      <a href="_static/img/eob-full.jpg" class="glightbox">
        <img alt="Playing and mapping Eye of the Beholder I on a single screen" src="_static/img/eob-full.jpg">
      </a>
        <p class="caption">
          <span>Playing and mapping <a class="reference external" href="https://en.wikipedia.org/wiki/Eye_of_the_Beholder_(video_game)">Eye of the Beholder I</a> on a single screen</span>
        </p>
    </div>

That's all good and well, but when you display the notes list pane with
:kbd:`Alt+L`, the visible map area becomes too narrow.

*Window layouts* can help in such scenarios on single-monitor setups:

.. rst-class:: multiline

- Press the *snap to right* button --- now the Gridmonger window occupies the
  right half of the screen.

- Press :kbd:`Shift+F5` to save the current window layout in the first layout
  slot. This will be your "default" layout when playing the game.

- Press :kbd:`Alt+L` to display the notes pane, then enlarge the window
  horizontally by dragging its left edge.

- Press :kbd:`Shift+F6` to save this "search note" layout in the second
  layout slot.

- Now you can quickly switch between the two layouts with the :kbd:`F5` and
  :kbd:`F6` keys.

The idea behind this is that you don't need to always have the notes list pane
open, only when you're searching for a particular note. So then you pause the
game, switch to the "search note" layout, find the note, then switch back to
your "default" layout and continue playing.

There are four window layout slots available. :kbd:`Shift+F5`–:kbd:`F8` save
the current window layout in slots 1–4, and :kbd:`F5`–:kbd:`F8` restore them.
Layouts are global, they're not tied to the current map (they are saved into
the configuration file, like your preferences).

Layouts store the size and position of the window, and the state of the
following user interface elements:

- Current note pane (toggled by :kbd:`Alt+N`)
- Notes list pane (toggled by :kbd:`Alt+L`)
- Tools pane (toggled by :kbd:`Alt+T`)
- Title bar (toggled by :kbd:`Shift+Alt+T`)

Any other setting is either stored in the preferences as a global setting
(e.g., should the splash screen be shown at startup, is diagonal YUBN
navigation is enabled, etc.), or is saved into the map file (e.g., map zoom
level, whether WASD-mode is enabled, etc.)


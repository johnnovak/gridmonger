.. rst-class:: style4 big

*******
Regions
*******

In some cRPGs, levels don't always represent the vertically stacked floors of
a dungeon complex, but rectangular areas (regions) of a large contiguous
world map. In such games, all regions have the same dimensions.

For example, in `New World Computing
<https://en.wikipedia.org/wiki/New_World_Computing>`_'s 1986 classic, `Might
and Magic Book One: The Secret of the Inner Sanctum
<https://en.wikipedia.org/wiki/Might_and_Magic_Book_One:_The_Secret_of_the_Inner_Sanctum>`_,
the world map is one large 80×64 grid subdivided into 20 regions, each with a
grid size of 16×16. The full world map is included in the ``Example Maps``
folder under the name ``Might and Magic I``.

.. raw:: html

    <div class="figure">
      <a href="_static/img/mm1-regions.png" class="glightbox">
        <img alt="Might and Magic I &mdash; Map of VARN (excerpt)" src="_static/img/mm1-regions.png">
      </a>
        <p class="caption">
          <span><a class="reference external" href="https://en.wikipedia.org/wiki/Might_and_Magic_Book_One:_The_Secret_of_the_Inner_Sanctum">Might and Magic I</a> &mdash; Map of VARN (excerpt)</span>
        </p>
    </div>


Another good example is the ``Pool of Radiance`` map, which contains a
partial map of the City of Phlan from the `SSI Gold Box
<https://en.wikipedia.org/wiki/Gold_Box>`_ game `Pool of Radiance
<https://en.wikipedia.org/wiki/Pool_of_Radiance>`_.

.. raw:: html

    <div class="figure">
      <a href="_static/img/por-regions.png" class="glightbox">
        <img alt="Pool of Radiance — Phlan (excerpt)" src="_static/img/por-regions.png">
      </a>
        <p class="caption">
          <span><a class="reference external" href="https://en.wikipedia.org/wiki/Pool_of_Radiance">Pool of Radiance</a> — Phlan (excerpt)</span>
        </p>
    </div>


As you can see in the above examples, region boundaries are indicated with
distinctly coloured thick lines.

It is very easy to create such a region-based map in Gridmonger: just create a
level big enough to hold all the regions, and tick the **Enable regions**
checkbox in the level creation dialog. You will then need to specify the
region dimensions (**Region columns** and **Region rows**), and whether you
want the coordinates to restart in every region or not (**Per-region
coordinates** checkbox). Naturally, with per-region coordinates enabled, the
individual regions will obey the coordinate settings of the level.

For region-enabled levels, a second drop-down is shown below the level name
drop-down at the top that indicates the current region the cursor is in. If
you select a different region in this drop-down, the cursor will jump to
middle of the selected region.

By default, regions are named ``Untitled Region N``, where *N* is a running
number. You can change a region's name in the **Edit Region Properties**
dialog by pressing :kbd:`Ctrl+Alt+R`, where you can optionally also enter some
notes about the region.

Of course, you can turn regions on or off for any existing level in the level
properties dialog, or adjust the regions' dimensions.

.. note::

  Normally, the dimensions of your region-enabled level are meant to be
  integer multiples of the region dimensions. This is, however, not enforced
  by the program; "partial" regions at the edges of the level are allowed and
  they're handled just fine. In such cases, the **Origin** property of the
  level determines the corner the region subdivision starts from.

  Although partial regions are handled correctly (in a mathematical sense),
  their usage is generally discouraged as one can get quite unintuitive
  results when performing certain actions on them (e.g. when changing the
  origin, or resizing the level, the region borders could "shift around" in
  unexpected (but always deterministic) ways).

  Being relaxed about such restrictions makes the program a lot simpler, and
  some more complicated level manipulations would not be possible with
  stricter enforcements in place (you'll recognise them when you need them).
  In short, using partial regions *temporarily* is fine in some situations,
  but when you're done with your level manipulations, just get rid of them and
  you'll be fine. *Don't tempt the devil!*

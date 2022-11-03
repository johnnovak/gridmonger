**************
Advanced usage
**************

Command line usage
------------------

If you start Gridmonger from the command line, you have the option to override
various window related settings or to use a different config file. This might
come in handy for power users who want to use a script to start an emulator
and Gridmonger side by side.

Please run ``gridmonger -h`` to see the full list of available options.

.. note::

  Options requiring a value need to be specified in ``option:VALUE`` format,
  e.g. to set the window size to 1200×800, you would use ``--width:1200
  --height:800`` (or the shorthand ``-W:1200 -H:800``).


Map file format
---------------

Gridmonger maps have the ``.gmm`` extension and are stored in the generic
`RIFF <https://en.wikipedia.org/wiki/Resource_Interchange_File_Format>`_
container format. One of the reasons for this choice was admittedly nostalgic;
I wanted to honor the outstanding `Interchange File Format (IFF)
<https://en.wikipedia.org/wiki/Interchange_File_Format>`_ invented by
Electronic Arts and Commodore for the `Amiga
<https://en.wikipedia.org/wiki/Amiga>`_ in 1985, the greatest personal
computer of all time. It's a great hierarchical container format, as evidenced
by its many different incarnations and derivatives (WAV, AVI, PNG,
JPEG, WebP, just to name a few).

The details of the map format are described in `fileformat.txt
<https://github.com/johnnovak/gridmonger/blob/master/extras/docs/fileformat.txt>`_
in the GitHub repository.


.. rst-class:: style7 big

Theme & configuration formats
-----------------------------

Themes and the configuration are stored in a very minimal subset of the `HOCON
configuration format <https://github.com/lightbend/config>`_. Currently, there
is no exact specification for this --- if you want to write these files by
hand or would like to manipulate them programmatically, just follow the syntax
and structure of the existing files and you'll be fine.


.. rst-class:: style6 big

****************
User data folder
****************

The *user data folder* stores data such as your program settings, user
themes, autosaves, and the log file.

The location of the user data folder is in a standard system location for
non-portable installations:

Windows
    ``C:\Users\<USERNAME>\AppData\Roaming\Gridmonger``

macOS
    ``/Users/<USERNAME>/Library/Application Support/Gridmonger``

For portable installations, it is inside the application folder where the
Gridmonger executable resides.

The user data folder contains a number of subfolders; these are created by
the program at startup if they don't exist:

``Autosaves``
    If autosaves are enabled and the current map hasn't been manually saved
    yet, the autosave file ``Untitled 1.gmm`` will go into this folder. If
    ``Untitled 1.gmm`` already exists, the name ``Untitled
    2.gmm`` will be chosen, and so on. In the rare event of a program crash,
    unsaved maps are automatically saved here too as ``<Map Name> Crash
    Autosave.gmm``.

``Config``
    Location of the ``gridmonger.cfg`` configuration file that contains the
    application's settings.

``Logs``
    The logs from the last run are written to the file ``gridmonger.log`` in
    this folder. Log files from the last three runs are also preserved as
    ``gridmonger.log.bak1``, ``gridmonger.log.bak2`` and
    ``gridmonger.log.bak3``.

``Manual``
    The HTML user manual you're reading now.

``User Themes``
    User themes are saved into this folder. This is where you should put
    themes shared by other users.

``User Themes/Images``
    Images used by the user themes go here.



.. tip::

   If the application folder contains a subfolder named ``Config``, Gridmonger
   will attempt to start in portable mode. Technically, you can convert a
   standard installation into a portable one by moving the contents of your
   user data folder into ``Config`` in the Gridmonger folder.

   You can also do the reverse and convert a portable installation into a
   standard one, but on Windows you're better off just using the standard
   installer. That will also set up default file associations for Gridmonger
   map files (``.gmm``) and provides a standard uninstaller script.


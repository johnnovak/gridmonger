.. rst-class:: style6 big

****************
User data folder
****************

The *user data folder* stores data such as your program settings, user
themes, auto saves, and the log file.

The location of the *user data folder* is
``C:\Users\<USERNAME>\AppData\Roaming\Gridmonger`` on Windows, and
``/Users/<USERNAME>/Library/Application Support/Gridmonger`` on macOS. For
portable installations, it is the application folder where the executable
is located.

The user data folder contains a number of subfolders (they will be created by
the program if they don't exist):

``Autosaves``
    If autosaves are enabled, and the current map hasn't been saved to a file
    yet, the autosave file ``Untitled.gmm`` will go into this folder. Also, in
    the rare event of a program crash, unsaved maps are automatically saved
    here too as ``Crash Autosave.gmm``.

``Config``
    The configuration file ``gridmonger.cfg`` that contains the application's
    settings resides here.

``Logs``
    The logs from the last run are written to the file ``gridmonger.log`` in
    this folder. Log files from the last three runs can be found under the
    names ``gridmonger.log.bak1``, ``gridmonger.log.bak2`` and
    ``gridmonger.log.bak3``.

``Manual``
    The included HTML user manual.

``User Themes``
    User themes are saved into this folder. This is where you should put
    themes shared by other users.

``User Themes/Images``
    Images used by the user themes go here.



.. tip::

   If the application folder contains a subfolder named ``Config``, Gridmonger
   will attempt to start in portable mode. Technically, you can convert a
   standard installation into a portable one by moving the contents of your
   user data folder into the application folder. You can also convert a
   portable installation into a standard one by doing the reverse, but in
   practice you're better off just using the standard installer, as that also
   sets up default file associations for Gridmonger map files (``.gmm``), and
   provides a standard uninstaller script.


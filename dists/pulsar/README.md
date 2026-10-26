UltraStar WorldParty with Pulsar
=================================================

Pulsar is a fork of the discontinued Atom editor. To use this editor do the following steps:

1. Install the Free Pascal Compiler on your system, https://www.freepascal.org. In Debian/Ubuntu you can do it using
   `sudo apt install fp-compiler-3.2.2`.
2. Install Pulsar on your system, https://pulsar-edit.dev
3. Install Pulsar extensions, Open Pulsar, go the menu to "File->Settings", click in the left tab on "Install"
   a. Install Build Package, search for "build", install this extension and its dependencies
   b. Install Pascal language support, search for "language-pascal", install this extension
4. If you are in Debian/Ubuntu, you must execute './install.sh' to get the dependencies, compile and add a shorcut to execute the game. On other systems you must do the same manually.
5. Copy, depending on your system, the .atom-build.json file to the root project path and restart Pulsar
6. Create the resource file, execute rccompile-fpc.bat from the ./res folder
7. Click on "Open Folder" to search for the root project path.


Now you can press:
- F9 to compile
- Ctrl+F9 to compile in debug mode
- F10 to compile and execute the game
- Ctrl+F10 to compile in debug mode and execute the game
- F11 to only execute without compile
- Ctrl+F11 to only execute in debug mode without compile

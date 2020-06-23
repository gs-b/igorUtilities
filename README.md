# igorUtilities
Useful functions for Wavemetrics Igor Pro

# Installation
These functions were last tested in Igor 8, and are unlikely to compile in Igor versions <= 6.
All procedures are contained in a WaveMetrics Igor Pro procedure (.ipf) files. The install options are standard for the program and briefly described here:
  * Quick installation: download anywhere on your computer and drag it into Igor
  * Permenant installation: download and save into the Igor Procedures folder (on my device, this is at Documents/WaveMetrics/Igor Pro 8 User Fies/Igor Procedures/)
  * Sustainable installation: clone this repository onto your device, then make a shortcut to the repository folder and place the shortcut in the Igor Procedures folder.
    * In case you are using more than one Igor git repository, I recommend cloning them all into the same directory and automatically including them all in Igor via a shortcut to the parent directory placed in the Igor Procedures folder.
  
 # Procedure file summaries
 ## Igor Utilities (`igorUtilities.ipf`): Useful functions. These functions are required for all of my Igor repositories. *This procedure file has no dependencies.*
* Highlights of some of the functions:
* list_operation_g(...): a function for batch command execution, easily used from the command line. 
* Fast display window copying between instances of Igor Pro (on the same computer). Use Ctrl+8 to put the graph on "clipboard" and Ctrl+9 to load the graph in another Igor Pro Window (There are also menu items under the Window menu)
* disp_getWinListForWv(...): get the list of all windows using a wave
* disp_killWinsWithWave(...): automatically kill windows that contain specific waves, with user checking optional

## ThorLabs filter wheel control (`thorSlowWheels.ipf`): A scalable GUI for controlling ThorLabs filter wheels, also offering automatic position history logging and notebook integration (with the notebook code below). *This procedure file requires `igorUtilities.ipf` and `notebook.ipf`, found in this repo, and VDT2.xop (see below)*
* Uses the VDT2.xop XOP that ships with Igor Pro. To make that useable, move or copy it and its help file VDT2.xop from the 'More Extensions\Data Acquisition' folder to the Igor Extensions folder (all within 'Program Files\WaveMetrics\Igor Pro 8 Folder\' on Windows), and then restart Igor.
* Highlights:
* Scale to an unlimited number of filter wheels and configurations
* Any delays occur in background tasks so that execution of other tasks in Igor isn't disrupted (e.g., data acquisition or notekeeping)
* Tested with FW102C Filter Wheels. Does not support 'fast change' filter wheel FW103H (e.g., FW103H)

## Timestamped, auto-saving notebooks: Functionalities for using Igor notebooks to take notes during experiments. *This procedure file requires `igorUtilities.ipf`, found in this repo. Use with `thorSlowWheels.ipf` for automatically adding filter wheel information to your notebook.*
* Highlights:
* Create a notebook with `notes_newNB(<your notebook name>)`, which immediately prompts you to set a location for notebook backups. Use the options under the Notebook menu for further control
* Type and format the notebook as you like (it's formattable but still readable in plain text) -- time stamps are entered for every new paragraph (enter key)
* Track Molecular Devices ABF file recordings as they occur and automatically note the current file.
* Track ThorLabs filter wheel positions and automatically note them as well.

## Auto save (`autosave.ipf`): Automatic backups of your Igor Pro instance, with a GUI to allow the user to cancel backups.  **This procedure file has no dependencies.**
* (Note that a built-in autosave function is expected for the next full release of Igor, Igor 9)

## Layout organizer (`layouts.ipf`): Quickly organize your Igor Pro display windows by rapidly adding windows to layout pages. Quickly put the focus on the windows in the current layout page (by bring these windows to the fore and optionally hiding others). **This procedure file requires `igorUtilities.ipf`, found in this repo.**
* To use, make a layout (run `NewLayout` or other built-in tool; run `DisplayHelptopic "Page Layouts"` if unfamiliar) then use the `Append to Layout` option in the Windows menu to add one or more windows to the layout.
* CTRL+1 hotkey (and Layout Menu 'Window Control' options) will bring the windows that have been added to a page back to the fore. CTRL+SHIFT+1 will also hide all other windows. I have found this extremely useful when dealing with more than a handful of windows in Igor (so, almost all the time).




  

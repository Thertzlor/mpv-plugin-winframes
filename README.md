mpv-plugin-winframes
======================

mpv plugin for setting display output parameters, e.g. the refresh rate,
automatically to the best suitable value for playing the current file.

This is a Windows version of the plugin [mpv-plugin-xrandr](https://gitlab.com/lvml/mpv-plugin-xrandr/) by Lutz Vieweg and utilizes the tool [ChangeScreenResolution.exe](https://www.tools.taubenkorb.at/change-screen-resolution/) as a stand-in for xrandr. It retains full compatibility with all its features and options.

Rationale / Use Case:
=====================

Video replay looks choppy if the display refresh rate is not an even
multiple of the frame rate the video is encoded at.

Many displays support different refresh rates, and for some of them,
namely TVs, choosing the correct refresh rate is also important for the
quality of computing interpolated frames for "smoother motion".

Setting the display to the best suitable refresh rate manually
for each video you play is annoying, so this plugin aims at
automatizing this task.

## Why winframes?
While there are [multiple](https://github.com/CogentRedTester/mpv-changerefresh) nircmd based mpv [scripts](https://github.com/kevinlekiller/mpv_scripts/tree/master/autospeedwin) for changing the refresh rate on windows, they are far less flexible than the xrandr plugin due to the limitations of nircmd, which can only set but not read display information, requiring the user to provide a list of valid refresh rates which becomes problematic when using multiple displays with different capabilties.

ChangeScreenResolution on the other hand has (almost) all capabilties of xrandr allowing this plugin to retain the automatic detection of the optimal refresh rate.

Prerequisites / Installation
============================

In order to use winframes.lua, you only need to have mpv installed, as well as the [ChangeScreenResolution.exe](https://www.tools.taubenkorb.at/change-screen-resolution/) utility which in turn *might* requite the [Redistributable Packages for Visual Studio 2013](https://www.microsoft.com/en-us/download/details.aspx?id=40784).  
You can then either put the executable on your PATH, or in a directory of your choosing, in which case you need to provide the location with the `winframes-exec-path` option:

 mpv --script /path/to/winframes.lua --script-opts=winframes-exec-path="D:/utils/ChangeScreenResolution.exe"  ...

Usage:
======

 mpv --script /path/to/winframes.lua

(Or copy winframes.lua to ~/.config/mpv/scripts/ for permanent default usage.)

Shortcuts :
========
The script adds the shortcut **Ctrl+f** to toggle refresh rate adjustment on and off.  
This is mostly useful in conjunction with the --wait-for-fullscreen option.

Options:
========

Normally, you won't need to specify any options besides `winframes-exec-path`.

 mpv --script-opts=winframes-blacklist=25 ...

All options can also be permanently defined in a winframes.conf file in the script-opts directory.

## Optional blacklisting refresh rates:

You can set the script option "winframes-blacklist" to a certain refresh rate
or to a comma separated list of refresh rates that you don't want to be used at all.
This can be done to address compatibility issues - e.g., when you know that your
display can use 25 Hz, but if your computer tries to use that rate, your TV stays black,
you can use

 mpv --script-opts=winframes-blacklist=25 ...

or if both 25 and 24 Hz are unusable, you could specify:

 mpv --script-opts=winframes-blacklist=[24,25]

## Optional switching to a preferred output mode

In rare cases, e.g. when using a display that supports more different refresh
rates for an output mode you do not usually use, you might want to have mpv
switch to some preferred output mode during playback.

To do this, use "--script-opts=winframes-output-mode", e.g., if
you want to change to the "1920x1080" mode during playback, use:

 mpv --script-opts=winframes-output-mode=1920x1080 ...

## Restricting refresh rate change to fullscreen

Normally the script will adjust the refresh rate the moment a video starts playing.  
With the "winframes-wait-for-fullscreen" option the adjustment will only take place once the player enters fullscreen mode. 

 mpv --script-opts=winframes-wait-for-fullscreen=yes ...

### Reverting changes on exiting full screen
Once the refresh rate is changed, it is kept until the player exits.  
The "winframes-restore-outside-fullscreen" option changes this behavior also revert when the player exits fullscreen mode.

 mpv --script-opts=winframes-wait-for-fullscreen=yes,winframes-restore-outside-fullscreen=yes ...

If the "winframes-wait-for-fullscreen" option is not enabled, this option has no effect.

## Old screen change handling
In the original xrandr plugin, changing the active display would only adjust the refresh rate if the framerate of the video also changed. This behavior is altered in this version, so that switching the player to another monitor will *always* check if that monitor's refresh rate also needs to be adjusted.

If you prefer to retain 100% of the old screen handling logic you can restore it like this:

mpv --script-opts=winframes-old-monitor-handling=yes ...


DISCLAIMER
==========

This software is provided as-is, without any warranties.

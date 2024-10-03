Transmission Remote GUI.
Copyright (c) 2008-2019 by Yury Sidorov and Transmission Remote GUI working group.

Transmission Remote GUI is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

Transmission Remote GUI is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

In addition, as a special exception, OpenVPN Technologies, Inc. gives
permission to link the code of this program with the OpenSSL Library (or with
modified versions of OpenSSL that use the same license as OpenSSL), and
distribute linked combinations including the two. You must obey the GNU General
Public License in all respects for all of the code used other than OpenSSL. If
you modify this file, you may extend this exception to your version of the
file, but you are not obligated to do so. If you do not wish to do so, delete
this exception statement from your version.
*********************************************************************************

Transmission Remote GUI is feature rich cross platform front-end to remotely control Transmission daemon via its RPC protocol. It is faster and has more functionality than builtin Transmission web interface.

Transmission Remote GUI is developed using Lazarus RAD and Free Pascal compiler.

Features:
 * Native application for Windows, Linux and MacOS X
 * uTorrent-like interface
 * Select files to download
 * Choose files priority
 * View details about connected peers
 * Full information about each torrent
 * Per torrent options

Project home:
https://github.com/transmission-remote-gui/transgui

INSTALLATION

The installers are listed on the GitHub Releases page:
https://github.com/transmission-remote-gui/transgui/releases/latest

Different platform installation instructions:

LINUX:

Easy way (recommended).

There are precompiled program's binaries for i386 and x86_64 Linux architectures.
- Download a .zip archive for your architecture.
- Unzip it to your home dir.
- Create a desktop or menu shortcut to the transgui executable.
  * (If needed, change the transgui file permissions to executable).
- Run the program using the created shortcut.

Harder way.

Build the program by yourself.
- Make sure you have working Lazarus and Free Pascal compiler installed.
  * Free Pascal Compiler 2.6.2 and Lazarus 1.6 is used to develop Transmission Remote GUI. You may use different versions of FPC and Lazarus at your own risk.
- Download the sources archive and extract it to some folder or perform svn checkout.
- Open terminal/command line prompt and cd to the sources folder;
- Execute "make" command to build the application;
- Execute "make zipdist" command to create a release .zip archive in the "Release" sub-folder.

WINDOWS:

Portable zip tarball (recommended).
- Zip tarball release is much more small than the installer one, which can save you some bandwidth, disk space and time, just simply download and extract the zip tarball to wherever you want, directly execute "transgui.exe" or add shortcut for it.
- Please note that, the first time you use this program, you may need to install some additional dependencies (if you need SSL/TLS enabled), including:
  - Visual C++ Redistributable Package
    - https://www.microsoft.com/download/details.aspx?id=40784
    - https://download.microsoft.com/download/0/5/6/056dcda9-d667-4e27-8001-8a0c6971d6b1/vcredist_x86.exe
  - OpenSSL libs
    - https://wiki.openssl.org/index.php/Binaries
    - https://slproweb.com/products/Win32OpenSSL.html

Installer.
- This installer has additional installation wizard and includes static OpenSSL libraries in every releases, the size would be much bigger than the zip tarball, but you don't need to take care of the OpenSSL dependencies.
  1. Directly download the installer.
  2. Run the installer and follow the steps to install it on your system.

Using Chocolatey.
- Run "choco install transgui" to install the latest version of Transmission Remote GUI.

MACOS:

Without a package manager.
  1. Download the app image from release page.
  2. Open the image file to mount the image.
  3. Directly run the application or drag the app icon to your disk / Application folder.

Using Homebrew.
- You need to have Homebrew installed. Execute this command to install Transmission Remote Gui: "brew install --cask transmission-remote-gui"

COMMAND LINE PARAMETERS

You can specify path to a .torrent file or a magnet link as a command line parameter. The program will add the specified torrent.

-hidden : Start the program hidden. Only the program's tray icon will be visible.
--home=<home_dir> : Specifies a home directory for the program. All program's settings are stored in the home directory. You can run multiple instances of the program by specifying different home directories.

PORTABLE MODE

If the program finds the transgui.ini file in the same folder as the binary file, then it will store all configuration and data files in the program's folder, instead of the folder in a user profile.

FIXED SHORTCUTS

Alt + 1 : All Torrents
Alt + 2 : Downloading
Alt + 3 : Completed
Alt + 4 : Active
Alt + 5 : Inactive
Alt + 6 : Stopped
Alt + 7 : Error
Alt + 8 : Waiting
Alt + S : Searchbox (filter torrents by keywords) - Esc cancel filter and clean the box.
Alt + G : Info Pane - General Tab
Alt + K : Info Pane - Trackers Tab
Alt + P : Info Pane - Peers Tab
Alt + F : Info Pane - Files Tab


ADVANCED PARAMETERS

There are some parameters in the transgui.ini file, that can not be modified via the GUI.
More info on: https://github.com/transmission-remote-gui/transgui/issues/924  (File Manager & Shortcuts)
, https://github.com/transmission-remote-gui/transgui/issues/1020  (User Defined Menu -Windows Only-)
and https://github.com/transmission-remote-gui/transgui/issues/1070  (.torrent Auto Opening)

[Interface]
; Maximum number of elements in the folder history list
MaxFoldersHistory=10

[Interface]
;In Linux/MacOs Only if "Open Container Folder" give you error
FileOpenDoc=0

[Interface]
;Alternate File Manager (Windows Only)
FileManagerDefault={Full path to your File Manager .exe}
FileManagerDefaultParam={Alternate parameters, could be left blank}

[Interface]
;System Wide Shortcut key (Windows Only)
GlobalHotkey={Virtual Key Code} full list here http://docwiki.embarcadero.com/RADStudio/Seattle/en/Virtual_Key_Codes (Plus VK_A...VK_Z and VK_0..VK_9)
GlobalHotkeyMod={Modifier Key} [MOD_SHIFT , MOD_CONTROL , MOD_ALT , MOD_WIN alone or combined with + sign]

[Interface]
WatchLocalFolder= {LOCAL Folder to watch for torrent files}
WatchDestinationFolder= {REMOTE destination where the data would be saved if missing or empty last destination folder is used}
WatchInterval=1 {Time period in MINUTES between folder scans for torrents, may be fractional values 0,50 = 30 seconds}


[Shortcuts]
;Modify all the shortcuts of the GUI here

[Usermenu]
Caption1={Caption in the menu}
ExeName1={Full path to the program .exe you want to add to menu}
Params1="%s" {Usually "%s" but some programs may require additional parameters}
Caption2={same for item 2}
ExeName2={same for item 2}
Params2={same for item 2}

[StatusBarPanels]
;Customize the width of the statusbar panels to fit your language
;0 is the left most panel and 7 is the right most panel.
0=327
1=152
2=152
3=130
4=130
5=130
6=130
7=130

[MainForm]
BigToolBarHeight=48 {Height of the Big Icon Toolbar if missing default is 64}

[MainForm]
FromNow=1 {1=Shows the dates relatives to now , 0=Absolute Dates MM/DD/YY HH:MM:SS}
*********************************************************************************
Big Icons

Farm-Fresh Fatcow Web Hosting
http://www.fatcow.com/
License Creative Commons (Attribution 3.0 United States)
https://creativecommons.org/licenses/by/3.0/us/legalcode

Visual Farm
http://icons8.com/
License Creative Commons Attribution-No Derivative Works 3.0 Unported
https://creativecommons.org/licenses/by-nd/3.0/legalcode

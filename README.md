# BA2 Content Scanner v1.0

**Select. Scan. Find!**

## What does it do?

BA2 Content Scanner helps you find files stored inside Fallout 4 BA2 archives without opening or extracting them. If you know a full or partial filename, the scanner tells you which BA2 archive contains it.

For example, if you have my Immersive Diamond City Gate mod installed, search for `DCGateMoveSiren` to find that `.wav` sound file. You can search for any file that can be packed into a BA2. Uppercase and lowercase search letters make no difference.

The scanner is **read-only**. It will not extract, change, repair or repack your BA2 archives.

## Before you start

- Exit Fallout 4 before running.
- Windows 10/11 only.
- No extra programs or Windows components are needed.
- You do **NOT** need to install this tool through your mod manager.
- You do **NOT** need administrator privileges for normal scans.

## Installation and starting

1. Download the tool from its [Nexus Mods page](https://www.nexusmods.com/fallout4/mods/111343) when published, then extract the ZIP into any folder you choose.
2. Keep all three **release-package** files together in that folder.
3. Double-click **`BA2_Content_Scanner.bat`** to start the scanner.
4. In the PowerShell window, type the number of your preferred scan option, then press **Enter**.

## Main menu options

**[1] Scan Fallout 4 game folder**  
Finds your Fallout 4 Data folder automatically where possible. Its full location is shown before you search. If it cannot be found, you can browse to the folder yourself or return to the menu.

**[2] Scan mod manager folder**  
Looks for common Vortex, Mod Organizer 2 or Nexus Mod Manager folders. If none is found, you can browse to your mod manager folder. The selected location is always shown before searching.

**[3] Scan custom folder**  
Opens a Windows folder picker. Choose any folder containing BA2 archives, including one on a different drive.

**[4] Scan individual BA2 archive**  
Opens a Windows file picker that shows BA2 archives. Choose the particular `.ba2` file you want to search.

**[5] Scan entire computer (SLOW)**  
Warns you that searching whole drives can take a long time. You can include all or choose particular accessible local drives. Network drives are not included. Inaccessible folders are skipped quietly, but BA2 archives that fail to scan still produce warnings.

**[0] Exit PowerShell window.**

## Searching for a file

1. After choosing a location, look at the confirmed folder, drive or BA2 archive displayed in the window.
2. At **Search filename**, type the full filename or just a part of it, then press **Enter**.
3. Watch the progress indicator. It shows how many BA2 archives have been scanned, including the name of the one being checked.
4. Once the scan finishes, read the summary and the matching filenames. The matching BA2 archive and its internal file path are displayed.

After each scan you can immediately type a different filename to search the **SAME** location. The screen is cleared for each new search.

To return to the main menu, leave **Search filename** blank and press **Enter**.

In option **[4]**, type **`:NEW` (including the colon)** at the search prompt to open the Windows file picker and select another BA2 archive.

The scanner remembers your chosen locations while its window remains open. Closing the scanner ends that session's folder memory.

## Understanding the results

- **Archives discovered:** Number of BA2 archives found in your location.
- **Successfully scanned:** Archives whose filename lists could be read.
- **Failed / unsupported:** BA2 archives whose filename lists could not be read; these are listed with the reason where possible.
- **Files listed in BA2s:** Total filenames checked **INSIDE** the archives. This does **NOT** mean those files have been extracted or tested.
- **Matching filenames:** Number of filenames matching your search.

If no filenames match, that does not mean the scan failed: it means there was no match in the successfully scanned archive filename lists. The console displays up to **100 matches**; the TXT report includes **all matches**, even when there are more than 100.

## TXT scan reports

A `.txt` report is automatically created after **EVERY completed scan**, whether matches are found or not.

Normally, reports are placed in a folder named **`Reports`**, right beside **`BA2_Content_Scanner.bat`**. The scanner creates this folder if it does not already exist.

Example:

```text
BA2 Content Scanner/
    BA2_Content_Scanner.bat
    BA2_Content_Scanner.ps1
    README.txt
    Reports/
        BA2_Content_Scan_20261017_1.txt
        BA2_Content_Scan_20261017_2.txt
```

Reports are numbered in order each day (`_1`, `_2`, `_3`, etc.), starting from `_1` again on the next date. Previous reports are not overwritten. The full report location appears in the PowerShell window after a scan.

If Windows does not allow reports in that folder, the scanner will try Documents, then the Windows temporary folder instead. The report path displayed on-screen tells you exactly where it was saved.

## When something does not work

- **Fallout 4 or the mod manager was not detected:** Use the Windows folder picker to select its folder yourself.
- **No matching filenames:** Try a shorter part of the filename and check the chosen location.
- **BA2 scan warning:** The named archive could not be read. The TXT report includes details; other BA2 archives will still be scanned.
- **Full-drive scan takes a long time:** This is normal with large drives. For a faster search, select a specific folder or individual BA2 instead.
- **Cannot find the report:** Look for **`TXT REPORT:`** near the bottom of the PowerShell window.

## Important limitations

The scanner searches file names and folder paths listed inside BA2 archives. It does not search the data inside files, for example references inside Papyrus scripts.

A readable archive filename table does not prove that every archived file is undamaged. A folder that cannot be accessed during a full-drive scan may contain files the scanner cannot examine.

## Source code and build instructions

The complete v1.0 scanner consists of these two plain-text files:

- [`BA2_Content_Scanner.bat`](BA2_Content_Scanner.bat) — the Windows launcher.
- [`BA2_Content_Scanner.ps1`](BA2_Content_Scanner.ps1) — the PowerShell scanning utility.

**No compiled executable or build step is needed.** Keep the BAT and PS1 together. The BAT launcher starts Windows PowerShell with process-scoped `-ExecutionPolicy Bypass`, which does not permanently change the Windows execution policy. Review scripts before running them.

## Licence

**Personal use only. All rights reserved.** Source code is available for inspection, but this is a restrictive **source-available**, not an open-source, licence. See [LICENSE.txt](LICENSE.txt) for details and redistribution restrictions. Your own scan reports are not restricted by the licence.

## Nexus Mods

[BA2 Content Scanner for Fallout 4](https://www.nexusmods.com/fallout4/mods/111343) — **Nexus publication pending**.

Author: **broken9bot**

# BA2 Content Scanner v1.0 - Windows console interface.
# Windows PowerShell 5.1; standard Windows 10/11; no added components.
# READ ONLY for all scanned BA2 archives. No extraction or decompression.
param(
    [string]$ScanPath = '',
    [string]$ArchivePath = '',
    [string]$SearchTerm = ''
)

$ErrorActionPreference = 'Stop'
$script:ProgramVersion = '1.0'
$script:SessionFolders = @{ Game = $null; Manager = $null; Custom = $null; Archive = $null }
$script:LastScanPreview = New-Object 'System.Collections.Generic.List[object]'
$script:LastScanReport = $null
$script:PreviewLimit = 2000
$script:ConsoleBufferManaged = $false
$script:ConsoleMatchLimit = 100
$script:Utf8 = [System.Text.UTF8Encoding]::new($false)

function Show-Title {
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host '  BA2 CONTENT SCANNER' -ForegroundColor Cyan
    Write-Host ('  Fallout 4 archive filename search | v{0}' -f $script:ProgramVersion)
    Write-Host '============================================================' -ForegroundColor DarkCyan
    Write-Host 'Read only | BA2 archives only | No extraction or modifications' -ForegroundColor DarkGray
    Write-Host ''
}

function Get-SteamGamePath {
    # Detect the Fallout 4 Data folder without assuming C: or one Steam library.
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 377160',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 377160'
    )
    foreach ($key in $registryPaths) {
        try {
            $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            if ($item.InstallLocation) {
                [void]$candidates.Add((Join-Path $item.InstallLocation 'Data'))
            }
        }
        catch { }
    }

    $steamRoots = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            if ($item.SteamPath) { [void]$steamRoots.Add([string]$item.SteamPath) }
            if ($item.InstallPath) { [void]$steamRoots.Add([string]$item.InstallPath) }
        }
        catch { }
    }
    if (${env:ProgramFiles(x86)}) {
        [void]$steamRoots.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam'))
    }
    foreach ($steamRoot in ($steamRoots | Select-Object -Unique)) {
        if (-not $steamRoot) { continue }
        $libraries = New-Object 'System.Collections.Generic.List[string]'
        [void]$libraries.Add($steamRoot)
        $vdf = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf -PathType Leaf) {
            try {
                $vdfText = [System.IO.File]::ReadAllText($vdf)
                foreach ($match in [regex]::Matches($vdfText, '"path"\s+"([^"]+)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
                    [void]$libraries.Add($match.Groups[1].Value.Replace('\\', '\'))
                }
            }
            catch { }
        }
        foreach ($library in ($libraries | Select-Object -Unique)) {
            [void]$candidates.Add((Join-Path $library 'steamapps\common\Fallout 4\Data'))
        }
    }
    foreach ($path in ($candidates | Select-Object -Unique)) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Container)) {
            return (Get-Item -LiteralPath $path).FullName
        }
    }
    return $null
}

function Add-FolderCandidate {
    param($Items, [string]$Path, [string]$Manager)
    if (-not $Path) { return }
    try {
        if (Test-Path -LiteralPath $Path -PathType Container) {
            $full = (Get-Item -LiteralPath $Path -ErrorAction Stop).FullName
            foreach ($existing in $Items) {
                if ($existing.Path -ieq $full) { return }
            }
            [void]$Items.Add([pscustomobject]@{ Path = $full; Manager = $Manager })
        }
    } catch { }
}

function Get-ModManagerPaths {
    # Vortex defaults are documented by Nexus; its staging location may be custom.
    # MO2 supports global and portable installations. We do not read Vortex's database.
    $found = New-Object 'System.Collections.Generic.List[object]'
    if ($env:APPDATA) {
        Add-FolderCandidate -Items $found -Path (Join-Path $env:APPDATA 'Vortex\fallout4\mods') -Manager 'Vortex default'
    }
    if ($env:ProgramData) {
        Add-FolderCandidate -Items $found -Path (Join-Path $env:ProgramData 'Vortex\fallout4\mods') -Manager 'Vortex shared mode'
    }
    if ($env:LOCALAPPDATA) {
        Add-FolderCandidate -Items $found -Path (Join-Path $env:LOCALAPPDATA 'Vortex\fallout4\mods') -Manager 'Vortex alternate'
        $mo2Root = Join-Path $env:LOCALAPPDATA 'ModOrganizer'
        if (Test-Path -LiteralPath $mo2Root -PathType Container) {
            foreach ($instance in @(Get-ChildItem -LiteralPath $mo2Root -Directory -ErrorAction SilentlyContinue)) {
                if ($instance.Name -match 'fallout\s*4|fallout4') {
                    Add-MO2Instance -Items $found -InstancePath $instance.FullName
                }
            }
        }
    }
    if ($env:USERPROFILE) {
        Add-FolderCandidate -Items $found -Path (Join-Path $env:USERPROFILE 'Vortex Mods\fallout4') -Manager 'Vortex alternate'
        Add-FolderCandidate -Items $found -Path (Join-Path $env:USERPROFILE 'Nexus Mod Manager\Fallout4\Mods') -Manager 'Nexus Mod Manager'
    }
    # Limited checks on drive roots for common user-selected staging locations.
    # No full-disk searches or indexing; only known path patterns are tested.
    try {
        foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
            if (-not $drive.IsReady -or $drive.DriveType -ne [System.IO.DriveType]::Fixed) { continue }
            foreach ($relative in @('Vortex Mods\fallout4', 'Vortex\fallout4\mods',
                                   'Vortex Mods\Fallout 4', 'Mod Organizer 2\mods',
                                   'Games\Nexus Mod Manager\Fallout4\Mods')) {
                $manager = if ($relative -like 'Mod Organizer*') { 'MO2 possible portable' }
                           elseif ($relative -like 'Games*') { 'Nexus Mod Manager' }
                           else { 'Vortex possible custom staging' }
                Add-FolderCandidate -Items $found -Path (Join-Path $drive.RootDirectory.FullName $relative) -Manager $manager
            }
        }
    } catch { }
    return @($found.ToArray())
}

function Add-MO2Instance {
    param($Items, [string]$InstancePath)
    $base = $InstancePath
    $mods = 'mods'
    $ini = Join-Path $InstancePath 'ModOrganizer.ini'
    if (Test-Path -LiteralPath $ini -PathType Leaf) {
        try {
            foreach ($line in [System.IO.File]::ReadLines($ini)) {
                if ($line -match '^\s*base_directory\s*=\s*(.*?)\s*$') {
                    $candidate = $matches[1].Trim('"')
                    if ($candidate) { $base = [Environment]::ExpandEnvironmentVariables($candidate.Replace('/', '\')) }
                }
                if ($line -match '^\s*mod_directory\s*=\s*(.*?)\s*$') {
                    $candidate = $matches[1].Trim('"')
                    if ($candidate) { $mods = [Environment]::ExpandEnvironmentVariables($candidate.Replace('/', '\')) }
                }
            }
        } catch { }
    }
    $mods = $mods.Replace('%BASE_DIR%', $base).Replace('%base_dir%', $base)
    if (-not [System.IO.Path]::IsPathRooted($mods)) { $mods = Join-Path $base $mods }
    Add-FolderCandidate -Items $Items -Path $mods -Manager 'Mod Organizer 2'
}

function Browse-Folder {
    param([string]$InitialPath)
    # FolderBrowserDialog uses the .NET Framework included with Windows 10/11.
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Select the folder containing BA2 archives'
        $dialog.ShowNewFolderButton = $false
        $dialog.RootFolder = [System.Environment+SpecialFolder]::MyComputer
        if ($InitialPath -and (Test-Path -LiteralPath $InitialPath -PathType Container)) {
            $dialog.SelectedPath = $InitialPath
        }
        try {
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                return $dialog.SelectedPath
            }
        } finally { $dialog.Dispose() }
    }
    catch {
        Write-Host ('Windows folder browser unavailable: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
        $typed = Read-Host 'Folder path (blank = main menu)'
        if ($typed -and $typed.Trim()) { return $typed.Trim().Trim('"') }
    }
    return $null
}

function Choose-Folder {
    param([ValidateSet('Game','Manager','Custom')][string]$Mode)
    # Saved paths are session-only. Returning to the main menu does not erase them.
    $prior = $script:SessionFolders[$Mode]
    $resolved = $null
    $label = switch ($Mode) {
        'Game'    { 'FALLOUT 4 GAME DATA FOLDER' }
        'Manager' { 'MOD MANAGER FOLDER' }
        'Custom'  { 'CUSTOM FOLDER' }
    }
    Write-Host ''
    Write-Host $label -ForegroundColor Cyan

    if ($Mode -eq 'Game' -or $Mode -eq 'Manager') {
        # If we already found this location in this session, reuse it automatically.
        if ($prior -and (Test-Path -LiteralPath $prior -PathType Container)) {
            $resolved = (Get-Item -LiteralPath $prior -ErrorAction Stop).FullName
        }
        elseif ($Mode -eq 'Game') {
            $resolved = Get-SteamGamePath
        }
        else {
            $detected = @(Get-ModManagerPaths)
            if ($detected.Count -gt 0) { $resolved = [string]$detected[0].Path }
        }
        if ($resolved) {
            $script:SessionFolders[$Mode] = $resolved
            Write-Host 'Folder found and selected automatically:' -ForegroundColor Green
        }
        else {
            Write-Host 'No folder was found automatically.' -ForegroundColor Yellow
            Write-Host '  [B] Select a folder in the Windows folder browser'
            Write-Host '  [ENTER] Back to the main menu'
            while ($true) {
                $answer = Read-Host 'Your choice'
                if ($null -eq $answer -or -not $answer.Trim()) { return $null }
                if ($answer.Trim() -ieq 'B') { break }
                Write-Host 'Press B to browse or ENTER to go back.' -ForegroundColor Yellow
            }
        }
    }

    if (-not $resolved) {
        $initial = if ($prior -and (Test-Path -LiteralPath $prior -PathType Container)) {
            $prior
        } else { [Environment]::GetFolderPath('Desktop') }
        # Custom folder opens the picker immediately, while the two automatic modes
        # open it only when no previously known/detected path is available.
        $selected = Browse-Folder -InitialPath $initial
        if (-not $selected) { return $null }
        if (-not (Test-Path -LiteralPath $selected -PathType Container)) {
            Write-Host 'The selected folder is unavailable. Returning to the main menu.' -ForegroundColor Yellow
            Read-Host 'Press ENTER to continue' | Out-Null
            return $null
        }
        $resolved = (Get-Item -LiteralPath $selected -ErrorAction Stop).FullName
        $script:SessionFolders[$Mode] = $resolved
        Write-Host 'Folder selected:' -ForegroundColor Green
    }
    Write-Host ('  {0}' -f $resolved) -ForegroundColor White
    Write-Host ''
    return $resolved
}

function Initialize-ConsoleBuffer {
    # Default classic conhost scrollback is often 9,001 lines, leaving a tiny scrollbar.
    # Start smaller and expand as output grows. This does not change global Windows settings.
    try {
        if (-not [Console]::IsOutputRedirected) {
            $height = [Math]::Max([Console]::WindowHeight + 70, 180)
            $height = [Math]::Max($height, [Console]::CursorTop + [Console]::WindowHeight + 10)
            [Console]::BufferHeight = [Math]::Min($height, [Console]::LargestWindowHeight * 40)
            $script:ConsoleBufferManaged = $true
        }
    } catch { $script:ConsoleBufferManaged = $false }
}

function Update-ConsoleBuffer {
    if (-not $script:ConsoleBufferManaged) { return }
    try {
        if (([Console]::BufferHeight - [Console]::CursorTop) -lt 55 -and [Console]::BufferHeight -lt 6000) {
            [Console]::BufferHeight = [Math]::Min(6000, [Console]::BufferHeight + 150)
        }
    } catch { $script:ConsoleBufferManaged = $false }
}

function Show-ResultPages {
    if ($script:LastScanPreview.Count -eq 0) {
        Write-Host 'No filename matches available for page viewing.' -ForegroundColor Yellow
        return
    }
    $page = 0
    $pageSize = 12
    $pages = [int][Math]::Ceiling($script:LastScanPreview.Count / [double]$pageSize)
    while ($true) {
        Write-Host ''
        Write-Host ('RESULTS VIEWER - Page {0} of {1}' -f ($page + 1), $pages) -ForegroundColor Cyan
        Write-Host ('Report: {0}' -f $script:LastScanReport) -ForegroundColor DarkGray
        $from = $page * $pageSize
        $to = [Math]::Min($from + $pageSize, $script:LastScanPreview.Count)
        for ($i = $from; $i -lt $to; $i++) {
            $item = $script:LastScanPreview[$i]
            Write-Host ('  {0}. {1}' -f ($i + 1), $item.Entry) -ForegroundColor Green
            Write-Host ('     BA2: {0}' -f $item.Archive)
        }
        if ($script:LastScanPreview.Count -ge $script:PreviewLimit) {
            Write-Host ('Viewer shows first {0} matches; TXT report contains ALL matches.' -f $script:PreviewLimit) -ForegroundColor Yellow
        }
        Write-Host 'PageDown/N = next, PageUp/P = previous, Q/Esc = exit viewer.' -ForegroundColor Cyan
        Update-ConsoleBuffer
        try {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::Escape -or $key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') { return }
            if ($key.Key -eq [ConsoleKey]::PageDown -or $key.KeyChar -eq 'n' -or $key.KeyChar -eq 'N') {
                if ($page -lt ($pages - 1)) { $page++ }
                continue
            }
            if ($key.Key -eq [ConsoleKey]::PageUp -or $key.KeyChar -eq 'p' -or $key.KeyChar -eq 'P') {
                if ($page -gt 0) { $page-- }
                continue
            }
            if ($key.Key -eq [ConsoleKey]::Home) { $page = 0; continue }
            if ($key.Key -eq [ConsoleKey]::End) { $page = $pages - 1; continue }
        } catch {
            $answer = (Read-Host 'N/P/Q').Trim().ToUpperInvariant()
            if ($answer -eq 'Q') { return }
            if ($answer -eq 'N' -and $page -lt ($pages - 1)) { $page++ }
            if ($answer -eq 'P' -and $page -gt 0) { $page-- }
        }
    }
}

function Choose-BA2Archive {
    # Always show the Windows file picker first. Remember the previous BA2 folder
    # for this running PowerShell process only; nothing is written to settings.
    $initial = [Environment]::GetFolderPath('Desktop')
    if ($script:SessionFolders.Archive) {
        $previousDirectory = [System.IO.Path]::GetDirectoryName($script:SessionFolders.Archive)
        if ($previousDirectory -and (Test-Path -LiteralPath $previousDirectory -PathType Container)) {
            $initial = $previousDirectory
        }
    }
    Write-Host ''
    Write-Host 'Opening BA2 archive picker...' -ForegroundColor Cyan
    $selection = $null
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'BA2 Content Scanner - Select a BA2 archive'
        $dialog.Filter = 'Fallout 4 BA2 archives (*.ba2)|*.ba2'
        $dialog.FilterIndex = 1
        $dialog.CheckFileExists = $true
        $dialog.CheckPathExists = $true
        $dialog.Multiselect = $false
        $dialog.RestoreDirectory = $true
        $dialog.InitialDirectory = $initial
        try {
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $selection = $dialog.FileName
            }
        }
        finally { $dialog.Dispose() }
        if (-not $selection) {
            Write-Host 'No archive selected.' -ForegroundColor Yellow
            return $null
        }
    }
    catch {
        Write-Host ('Windows BA2 file picker unavailable: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
        Write-Host 'Enter a BA2 file path manually (or Q to cancel).' -ForegroundColor Yellow
        $selection = Read-Host 'BA2 path'
        if ($null -eq $selection) { return $null }
        $selection = $selection.Trim().Trim('"')
        if (-not $selection -or $selection -ieq 'Q') { return $null }
    }
    try {
        if (-not $selection.EndsWith('.ba2', [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host 'Only .ba2 archive files can be selected.' -ForegroundColor Yellow
            return $null
        }
        if (-not (Test-Path -LiteralPath $selection -PathType Leaf)) {
            Write-Host 'Selected BA2 could not be found or accessed.' -ForegroundColor Yellow
            return $null
        }
        $confirmed = (Get-Item -LiteralPath $selection -ErrorAction Stop).FullName
        $script:SessionFolders.Archive = $confirmed
        Write-Host ''
        Write-Host 'CONFIRMED BA2 ARCHIVE:' -ForegroundColor Green
        Write-Host ('  {0}' -f $confirmed)
        Write-Host 'Last archive folder remembered for this PowerShell session.' -ForegroundColor DarkGray
        return $confirmed
    }
    catch {
        Write-Host ('Could not access BA2: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
        return $null
    }
}

function Get-LocalDrives {
    # Do not include network shares, mapped network volumes, optical drives,
    # or unready drives. USB drives are commonly Fixed or Removable.
    $drives = New-Object 'System.Collections.Generic.List[object]'
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        try {
            if (-not $drive.IsReady) { continue }
            if ($drive.DriveType -ne [System.IO.DriveType]::Fixed -and
                $drive.DriveType -ne [System.IO.DriveType]::Removable) { continue }
            [void]$drives.Add([pscustomobject]@{
                Path = $drive.RootDirectory.FullName
                Label = $drive.VolumeLabel
                DriveType = $drive.DriveType.ToString()
            })
        }
        catch { }
    }
    return @($drives.ToArray() | Sort-Object Path -Unique)
}

function Choose-ComputerDrives {
    Write-Host ''
    Write-Host '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' -ForegroundColor Yellow
    Write-Host '  WARNING - FULL COMPUTER SCAN (SLOW)' -ForegroundColor Yellow
    Write-Host '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' -ForegroundColor Yellow
    Write-Host 'This searches every accessible folder on the selected local drives'
    Write-Host 'for BA2 archives, and may take a considerable amount of time.'
    Write-Host 'Inaccessible and protected folders will be skipped silently.'
    Write-Host 'Network drives are excluded. Connected USB drives are included.'
    Write-Host 'The discovery phase can be slow before archive scanning starts.'
    Write-Host ''
    $available = @(Get-LocalDrives)
    if ($available.Count -eq 0) {
        Write-Host 'No ready local drives detected.' -ForegroundColor Yellow
        return
    }
    Write-Host 'Available local drives:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $available.Count; $i++) {
        $drive = $available[$i]
        Write-Host ('  [{0}] {1}  {2} ({3})' -f ($i+1), $drive.Path, $drive.Label, $drive.DriveType)
    }
    while ($true) {
        Write-Host 'ENTER/A = all; 1,3 = selected drives; Q = cancel.' -ForegroundColor Cyan
        $pick = Read-Host 'Drive selection'
        if ($null -eq $pick -or $pick.Trim() -ieq 'Q') { return }
        $pick = $pick.Trim()
        $selected = New-Object 'System.Collections.Generic.List[string]'
        if (-not $pick -or $pick -ieq 'A') {
            foreach ($drive in $available) { [void]$selected.Add($drive.Path) }
        }
        elseif ($pick -match '^\s*\d+(\s*,\s*\d+)*\s*$') {
            foreach ($part in @($pick.Split(','))) {
                $index = [int]$part.Trim()
                if ($index -lt 1 -or $index -gt $available.Count) {
                    $selected.Clear()
                    break
                }
                if (-not $selected.Contains($available[$index - 1].Path)) {
                    [void]$selected.Add($available[$index - 1].Path)
                }
            }
        }
        if ($selected.Count -eq 0) {
            Write-Host 'Invalid drive selection. Please try again.' -ForegroundColor Yellow
            continue
        }
        Write-Host ''
        Write-Host ('SELECTED DRIVES: {0}' -f ($selected -join ', ')) -ForegroundColor Cyan
        return $selected.ToArray()
    }
}

function Find-BA2Archives {
    param([string[]]$Roots, $FolderWarnings, [switch]$QuietFolderAccess)
    # Iterative traversal avoids recursion depth limits and follows no reparse
    # directory (junction/symlink/mount point), preventing cycles and duplicates.
    $found = New-Object 'System.Collections.Generic.List[string]'
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    foreach ($root in $Roots) {
        if (-not [string]::IsNullOrWhiteSpace($root)) { $pending.Push($root) }
    }
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $folderCount = [long]0
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        while ($pending.Count -gt 0) {
            $folder = $pending.Pop()
            if (-not $visited.Add($folder.TrimEnd('\'))) { continue }
            $folderCount++
            # Discovery cannot show a final percentage before archive counting.
            if ($folderCount -eq 1 -or ($folderCount % 100) -eq 0) {
                Write-Progress -Id 2 -Activity 'Discovering BA2 archives (this may be slow)' `
                    -Status ('Folders checked: {0} | BA2 found: {1}' -f $folderCount, $found.Count) `
                    -CurrentOperation $folder
            }
            if (($folderCount % 1000) -eq 0 -and $stopwatch.Elapsed.TotalSeconds -ge 5) {
                Write-Host ('Discovery: {0} folders checked; {1} BA2 archives found...' -f $folderCount, $found.Count) -ForegroundColor DarkCyan
                $stopwatch.Restart()
                Update-ConsoleBuffer
            }
            try {
                foreach ($path in [System.IO.Directory]::EnumerateFiles($folder, '*.ba2', [System.IO.SearchOption]::TopDirectoryOnly)) {
                    if ([System.IO.Path]::GetExtension($path).Equals('.ba2', [System.StringComparison]::OrdinalIgnoreCase)) {
                        [void]$found.Add($path)
                    }
                }
            }
            catch {
                if (-not $QuietFolderAccess) {
                    [void]$FolderWarnings.Add(('BA2 listing: {0} - {1}' -f $folder, $_.Exception.Message))
                }
            }
            try {
                foreach ($subfolder in [System.IO.Directory]::EnumerateDirectories($folder)) {
                    try {
                        $attributes = [System.IO.File]::GetAttributes($subfolder)
                        if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                        [void]$pending.Push($subfolder)
                    }
                    catch {
                        if (-not $QuietFolderAccess) {
                            [void]$FolderWarnings.Add(('Folder access: {0} - {1}' -f $subfolder, $_.Exception.Message))
                        }
                    }
                }
            }
            catch {
                if (-not $QuietFolderAccess) {
                    [void]$FolderWarnings.Add(('Folder listing: {0} - {1}' -f $folder, $_.Exception.Message))
                }
            }
        }
    }
    finally {
        Write-Progress -Id 2 -Activity 'Discovering BA2 archives' -Completed
    }
    Write-Host ('Discovery finished: {0} folders checked.' -f $folderCount) -ForegroundColor DarkCyan
    return @($found.ToArray() | Sort-Object -Unique)
}

function Choose-SearchTerm {
    param([switch]$AllowNewArchive, [switch]$SlowDriveScan)
    Write-Host ''
    Write-Host 'Search for a filename or part of a filename.' -ForegroundColor Cyan
    Write-Host 'Matches are not case-sensitive.' -ForegroundColor DarkGray
    if ($SlowDriveScan) {
        Write-Host 'NOTE: A new scan of the selected drives can be SLOW.' -ForegroundColor Yellow
    }
    if ($AllowNewArchive) {
        Write-Host 'Choose another BA2: type :NEW (include the colon).' -ForegroundColor Yellow
        Write-Host 'Blank ENTER = main menu.' -ForegroundColor DarkGray
    } else {
        Write-Host 'Blank ENTER = main menu.' -ForegroundColor DarkGray
    }
    $term = Read-Host 'Search filename'
    if ($null -eq $term) { return $null }
    $term = $term.Trim()
    if (-not $term) { return $null }
    return $term
}

function Read-BA2NameTable {
    param([string]$ArchivePath, [string]$Needle)
    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($ArchivePath, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = [System.IO.BinaryReader]::new($stream, [System.Text.Encoding]::UTF8)
        if ($stream.Length -lt 24) { throw 'BA2 header shorter than 24 bytes' }
        if ([System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -ne 'BTDX') {
            throw 'invalid BA2 signature (expected BTDX)'
        }
        $version = $reader.ReadUInt32()
        $type = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
        $count = $reader.ReadUInt32()
        $namesOffset = $reader.ReadUInt64()
        if ($version -notin @(1, 2, 3, 7, 8)) { throw ('unsupported BA2 version: {0}' -f $version) }
        if ($type -notin @('GNRL', 'DX10')) { throw ('unsupported BA2 type: {0}' -f $type) }
        if ($count -gt 1000000) { throw ('implausible filename count: {0}' -f $count) }
        $headerLength = 24
        if ($version -eq 2) { $headerLength = 32 }
        if ($version -eq 3) { $headerLength = 36 }
        if ($stream.Length -lt $headerLength) { throw 'BA2 extended header truncated' }
        $minimumRecordBytes = 24
        if ($type -eq 'GNRL') { $minimumRecordBytes = 36 }
        $minimumOffset = [uint64]$headerLength + ([uint64]$count * [uint64]$minimumRecordBytes)
        if ($namesOffset -lt $minimumOffset -or $namesOffset -gt [uint64]$stream.Length) {
            throw ('name table offset {0} is outside expected file bounds (size {1})' -f $namesOffset, $stream.Length)
        }
        if (([uint64]$stream.Length - $namesOffset) -lt ([uint64]$count * 3)) {
            throw 'name table too short for the advertised filename count'
        }
        $stream.Position = [long]$namesOffset
        $matches = New-Object 'System.Collections.Generic.List[string]'
        $normalizedNeedle = $Needle.Replace('/', '\')
        for ($i = 0; $i -lt $count; $i++) {
            if (($stream.Length - $stream.Position) -lt 2) {
                throw ('name table truncated at entry {0} of {1}' -f ($i + 1), $count)
            }
            $length = [int]$reader.ReadUInt16()
            if ($length -lt 1 -or $length -gt 4096) {
                throw ('invalid filename byte length {0} at entry {1}' -f $length, ($i + 1))
            }
            if (($stream.Length - $stream.Position) -lt $length) {
                throw ('filename extends beyond file at entry {0}' -f ($i + 1))
            }
            $name = [System.Text.Encoding]::UTF8.GetString($reader.ReadBytes($length)).TrimEnd([char]0)
            if (-not $name -or $name.IndexOf([char]0) -ge 0) {
                throw ('empty or invalid filename at entry {0}' -f ($i + 1))
            }
            if ($name.Replace('/', '\').IndexOf($normalizedNeedle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                [void]$matches.Add($name)
            }
        }
        return [pscustomobject]@{
            Success = $true; Count = [int]$count; Matches = $matches;
            Version = $version; Type = $type; Error = ''
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false; Count = 0; Matches = $null;
            Version = $null; Type = $null; Error = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }
}

function Start-Report {
    # yyyyMMdd_1, yyyyMMdd_2, ... ; reset on next local calendar day.
    # FileMode.CreateNew guarantees no overwrite even with concurrent scanner windows.
    $date = Get-Date -Format 'yyyyMMdd'
    $destinations = New-Object 'System.Collections.Generic.List[string]'
    [void]$destinations.Add((Join-Path $PSScriptRoot 'Reports'))
    $documents = [Environment]::GetFolderPath('MyDocuments')
    if ($documents) { [void]$destinations.Add((Join-Path $documents 'BA2 Content Scanner Reports')) }
    if ($env:TEMP) { [void]$destinations.Add((Join-Path $env:TEMP 'BA2 Content Scanner Reports')) }
    foreach ($directory in $destinations) {
        if (-not $directory) { continue }
        try {
            if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
                [void][System.IO.Directory]::CreateDirectory($directory)
            }
            for ($number = 1; $number -le 999999; $number++) {
                $path = Join-Path $directory ('BA2_Content_Scan_{0}_{1}.txt' -f $date, $number)
                if ([System.IO.File]::Exists($path)) { continue }
                try {
                    $file = [System.IO.FileStream]::new($path, [System.IO.FileMode]::CreateNew,
                        [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
                    try {
                        $writer = [System.IO.StreamWriter]::new($file, $script:Utf8)
                        return [pscustomobject]@{ Path = $path; Writer = $writer }
                    } catch { $file.Dispose(); throw }
                }
                catch [System.IO.IOException] {
                    if ([System.IO.File]::Exists($path)) { continue }
                    throw
                }
            }
        } catch { }
    }
    throw 'Cannot create a TXT report in Reports, Documents, or TEMP. Check folder permissions.'
}

function Run-Scan {
    param([string]$Root = '', [string]$Needle,
          [string]$ArchiveFile = '', [string[]]$Drives = @())
    $scanKind = 'Folder'
    $target = $Root
    if ($ArchiveFile) { $scanKind = 'Single BA2'; $target = $ArchiveFile }
    elseif ($Drives.Count -gt 0) { $scanKind = 'Local drives'; $target = ($Drives -join ', ') }
    Write-Host ('Scan target : {0}' -f $target)
    Write-Host ('Search term : {0}' -f $Needle)
    Write-Host 'Searching BA2 filenames only; no archives will be modified.' -ForegroundColor DarkGray
    Write-Host ''
    $started = Get-Date
    $script:LastScanPreview.Clear()
    $script:LastScanReport = $null
    $report = $null
    $warningItems = New-Object 'System.Collections.Generic.List[object]'
    $folderWarnings = New-Object 'System.Collections.Generic.List[string]'
    $discovered = 0
    $successful = 0
    $failed = 0
    $filenames = [long]0
    $matchCount = [long]0
    $matchingArchives = 0
    $consoleMatches = 0
    $consoleLimitNotified = $false
    try {
        $report = Start-Report
        $writer = $report.Writer
        $script:LastScanReport = $report.Path
        $writer.WriteLine('BA2 CONTENT SCANNER - REPORT')
        $writer.WriteLine(('Version        : {0}' -f $script:ProgramVersion))
        $writer.WriteLine(('Started        : {0}' -f $started.ToString('yyyy-MM-dd HH:mm:ss')))
        $writer.WriteLine(('Scan mode      : {0}' -f $scanKind))
        $writer.WriteLine(('Scan target    : {0}' -f $target))
        $writer.WriteLine(('Search term    : {0}' -f $Needle))
        $writer.WriteLine('Scope          : BA2 internal filenames/paths only (case-insensitive partial search)')
        $writer.WriteLine('Safety         : Read-only BA2 access; no extraction or modification')
        $writer.WriteLine('Duplicates     : Each discovered BA2 copy is scanned independently')
        $writer.WriteLine('')
        $writer.WriteLine('=== MATCHES ===')

        $archives = @()
        if ($ArchiveFile) {
            # One archive; do not enumerate directories. Also used by QA.
            $archives = @($ArchiveFile)
        }
        else {
            $roots = if ($Drives.Count -gt 0) { @($Drives) } else { @($Root) }
            Write-Host 'Discovering BA2 archives... (folders checked shown below)' -ForegroundColor Cyan
            if ($Drives.Count -gt 0) {
                $archives = @(Find-BA2Archives -Roots $roots -FolderWarnings $folderWarnings -QuietFolderAccess)
            }
            else {
                $archives = @(Find-BA2Archives -Roots $roots -FolderWarnings $folderWarnings)
            }
        }
        $discovered = $archives.Count
        if ($discovered -eq 0) {
            Write-Host 'No BA2 archives were found in the selected location.' -ForegroundColor Yellow
        }
        Write-Host ('Found {0} BA2 archive(s).' -f $discovered) -ForegroundColor Cyan
        Write-Host ''

        for ($index = 0; $index -lt $discovered; $index++) {
            Update-ConsoleBuffer
            $archivePath = [string]$archives[$index]
            $percent = [int][Math]::Floor((100.0 * $index) / $discovered)
            Write-Progress -Id 1 -Activity 'BA2 archives scanned' `
                -Status ('{0} / {1} completed' -f $index, $discovered) `
                -CurrentOperation ([System.IO.Path]::GetFileName($archivePath)) -PercentComplete $percent
            $result = Read-BA2NameTable -ArchivePath $archivePath -Needle $Needle
            if (-not $result.Success) {
                $failed++
                [void]$warningItems.Add([pscustomobject]@{ Archive = $archivePath; Reason = $result.Error })
                continue
            }
            $successful++
            $filenames += [long]$result.Count
            if ($result.Matches.Count -gt 0) { $matchingArchives++ }
            foreach ($name in $result.Matches) {
                $matchCount++
                if ($script:LastScanPreview.Count -lt $script:PreviewLimit) {
                    [void]$script:LastScanPreview.Add([pscustomobject]@{ Archive = $archivePath; Entry = $name })
                }
                $writer.WriteLine(('Archive : {0}' -f $archivePath))
                $writer.WriteLine(('Entry   : {0}' -f $name))
                $writer.WriteLine('')
                Update-ConsoleBuffer
                # Keep console match output until after the SCAN COMPLETE summary.
                # All matches are still written to the TXT report immediately.
            }
        }
        Write-Progress -Id 1 -Activity 'BA2 archives scanned' -Completed
        $finished = Get-Date
        $duration = [Math]::Round(($finished - $started).TotalSeconds, 1)
        $writer.WriteLine('=== SCAN SUMMARY ===')
        $writer.WriteLine(('Completed              : {0}' -f $finished.ToString('yyyy-MM-dd HH:mm:ss')))
        $writer.WriteLine(('Elapsed seconds        : {0}' -f $duration))
        $writer.WriteLine(('BA2 archives discovered: {0}' -f $discovered))
        $writer.WriteLine(('Successfully scanned   : {0}' -f $successful))
        $writer.WriteLine(('Failed / unsupported   : {0}' -f $failed))
        $writer.WriteLine(('Files listed inside BA2s: {0}' -f $filenames))
        $writer.WriteLine(('Archives with matches  : {0}' -f $matchingArchives))
        $writer.WriteLine(('Matching filenames     : {0}' -f $matchCount))
        if ($Drives.Count -eq 0) {
            $writer.WriteLine(('Folder access warnings : {0}' -f $folderWarnings.Count))
        }
        $writer.WriteLine('')
        $writer.WriteLine('=== ARCHIVE SCAN WARNINGS / FAILURES ===')
        if ($warningItems.Count -eq 0) { $writer.WriteLine('None.') }
        else {
            foreach ($item in $warningItems) {
                $writer.WriteLine(('Archive : {0}' -f $item.Archive))
                $writer.WriteLine(('Reason  : {0}' -f $item.Reason))
                $writer.WriteLine('')
            }
        }
        $writer.WriteLine('')
        if ($Drives.Count -eq 0) {
            $writer.WriteLine('=== FOLDER ACCESS WARNINGS ===')
            if ($folderWarnings.Count -eq 0) { $writer.WriteLine('None.') }
            else { foreach ($warning in $folderWarnings) { $writer.WriteLine($warning); $writer.WriteLine('') } }
            $writer.WriteLine('')
        }
        $writer.WriteLine('=== IMPORTANT LIMITATIONS ===')
        $writer.WriteLine('This tool searches BA2 internal filenames, not file contents or PEX references.')
        $writer.WriteLine('A valid filename table does not prove the archive payload is undamaged.')
        $writer.WriteLine('Zero matches only means the requested text was not found in successfully scanned filename tables.')
        $writer.WriteLine('A failed archive or inaccessible folder may contain additional matches.')
        $writer.WriteLine('Directory junctions and symbolic-link folders are not followed to avoid loops and duplicate scanning.')
        $writer.Flush()

        Write-Host ''
        Write-Host '==================== SCAN COMPLETE ====================' -ForegroundColor Cyan
        Write-Host ('  Scan target         : {0}' -f $target)
        Write-Host ('  Archives discovered : {0}' -f $discovered)
        Write-Host ('  Successfully scanned: {0}' -f $successful)
        Write-Host ('  Failed / unsupported: {0}' -f $failed)
        Write-Host ('  Files listed in BA2s: {0}' -f $filenames)
        Write-Host ('  Matching filenames  : {0}' -f $matchCount)
        if ($Drives.Count -eq 0) {
            Write-Host ('  Folder warnings     : {0}' -f $folderWarnings.Count)
        }
        Write-Host ('  Elapsed             : {0} seconds' -f $duration)
        Write-Host '=======================================================' -ForegroundColor Cyan
        # Present results below the scan summary instead of during scanning.
        foreach ($item in $script:LastScanPreview) {
            Update-ConsoleBuffer
            if ($consoleMatches -lt $script:ConsoleMatchLimit) {
                Write-Host ''
                Write-Host 'MATCH FOUND' -ForegroundColor Green
                Write-Host ('  Archive : {0}' -f $item.Archive)
                Write-Host ('  Entry   : {0}' -f $item.Entry)
                $consoleMatches++
            }
            elseif (-not $consoleLimitNotified) {
                Write-Host ''
                Write-Host ('More than {0} matches; further matches are saved to the TXT report.' -f $script:ConsoleMatchLimit) -ForegroundColor Yellow
                $consoleLimitNotified = $true
                break
            }
        }
        if ($matchCount -eq 0) {
            Write-Host 'No matching filenames found in successfully scanned BA2 archives.' -ForegroundColor Yellow
        }
        Write-Host ''
        if ($failed -eq 0 -and $folderWarnings.Count -eq 0) {
            if ($discovered -gt 0) {
                Write-Host 'All discovered BA2 filename tables scanned successfully. No scan warnings.' -ForegroundColor Green
            } else {
                Write-Host 'No BA2 archives to scan in this location.' -ForegroundColor Yellow
            }
        }
        else {
            if ($Drives.Count -gt 0) {
                Write-Host ('WARNING: {0} BA2 archive(s) could not be scanned.' -f $failed) -ForegroundColor Yellow
            } else {
                Write-Host ('WARNING: {0} BA2 archive(s) could not be scanned; {1} folder warning(s).' -f $failed, $folderWarnings.Count) -ForegroundColor Yellow
            }
            foreach ($item in $warningItems) {
                Write-Host ('  Archive: {0}' -f $item.Archive) -ForegroundColor Yellow
                Write-Host ('  Reason : {0}' -f $item.Reason) -ForegroundColor Yellow
                Update-ConsoleBuffer
            }
            $showLimit = [Math]::Min($folderWarnings.Count, 30)
            for ($wi = 0; $wi -lt $showLimit; $wi++) {
                Write-Host ('  Folder warning: {0}' -f $folderWarnings[$wi]) -ForegroundColor Yellow
                Update-ConsoleBuffer
            }
            if ($folderWarnings.Count -gt $showLimit) {
                Write-Host ('  ... {0} additional folder warnings in TXT report.' -f ($folderWarnings.Count - $showLimit)) -ForegroundColor Yellow
            }
            Write-Host 'These failures may mean some matching filenames were missed.' -ForegroundColor Yellow
        }
        Write-Host ''
        Write-Host ('TXT REPORT: {0}' -f $report.Path) -ForegroundColor Green
        Update-ConsoleBuffer
        if ($failed -gt 0 -or $folderWarnings.Count -gt 0) { return 2 }
        return 0
    }
    catch {
        Write-Progress -Id 1 -Activity 'BA2 archives scanned' -Completed
        Write-Progress -Id 2 -Activity 'Discovering BA2 archives' -Completed
        Write-Host ('SCAN ERROR: {0}' -f $_.Exception.Message) -ForegroundColor Red
        if ($null -ne $report) {
            try { $report.Writer.WriteLine(('SCAN INTERRUPTED: {0}' -f $_.Exception.Message)) } catch { }
            Write-Host ('Partial report: {0}' -f $report.Path) -ForegroundColor Yellow
        }
        return 1
    }
    finally {
        if ($null -ne $report) { $report.Writer.Dispose() }
    }
}

Initialize-ConsoleBuffer

# Preserve v0.2 -ScanPath/-SearchTerm mode; add testable single-BA2 -ArchivePath.
if ($ScanPath -or $ArchivePath -or $SearchTerm) {
    Show-Title
    if (-not $SearchTerm -or ($ScanPath -and $ArchivePath) -or (-not $ScanPath -and -not $ArchivePath)) {
        Write-Host 'For non-interactive mode supply -SearchTerm with EITHER -ScanPath or -ArchivePath.' -ForegroundColor Red
        exit 1
    }
    if ($ScanPath) {
        if (-not (Test-Path -LiteralPath $ScanPath -PathType Container)) {
            Write-Host ('Scan directory does not exist: {0}' -f $ScanPath) -ForegroundColor Red
            exit 1
        }
        exit (Run-Scan -Root (Get-Item -LiteralPath $ScanPath).FullName -Needle $SearchTerm)
    }
    if (-not $ArchivePath.EndsWith('.ba2', [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        Write-Host ('Not a valid accessible .ba2 file: {0}' -f $ArchivePath) -ForegroundColor Red
        exit 1
    }
    exit (Run-Scan -ArchiveFile (Get-Item -LiteralPath $ArchivePath).FullName -Needle $SearchTerm)
}

while ($true) {
    # Clear old search output on EVERY return to the main menu, but leave
    # the session-only target memory untouched.
    Clear-Host
    Initialize-ConsoleBuffer
    Show-Title
    Write-Host '==================== MAIN MENU ====================' -ForegroundColor Cyan
    Write-Host '  [1] Scan Fallout 4 game folder'
    Write-Host '  [2] Scan mod manager folder (Vortex / MO2 / NMM)'
    Write-Host '  [3] Scan custom folder'
    Write-Host '  [4] Scan individual BA2 archive'
    Write-Host '  [5] Scan entire computer (SLOW)'
    Write-Host '  [0] Exit'
    Write-Host ''
    $choice = (Read-Host 'Choose scan location').Trim()
    $mode = switch ($choice) {
        '1' { 'Game' }
        '2' { 'Manager' }
        '3' { 'Custom' }
        '4' { 'Archive' }
        '5' { 'Computer' }
        '0' { exit 0 }
        default { '' }
    }
    if (-not $mode) { continue }

    Clear-Host
    Initialize-ConsoleBuffer
    Show-Title
    $chosenPath = $null
    $chosenDrives = @()
    if ($mode -eq 'Archive') {
        $chosenPath = Choose-BA2Archive
    }
    elseif ($mode -eq 'Computer') {
        $chosenDrives = @(Choose-ComputerDrives)
        if ($chosenDrives.Count -eq 0) { continue }
    }
    else {
        $chosenPath = Choose-Folder -Mode $mode
    }
    if ($mode -ne 'Computer' -and -not $chosenPath) { continue }

    # One repeated search prompt; no extra post-scan action menu. A blank
    # search returns to the main menu, where the folder memory still exists.
    while ($true) {
        $activeTarget = if ($mode -eq 'Computer') { $chosenDrives -join ', ' } else { $chosenPath }
        Write-Host ('CURRENT {0} TARGET:' -f $mode.ToUpperInvariant()) -ForegroundColor Cyan
        Write-Host ('  {0}' -f $activeTarget)
        $needle = Choose-SearchTerm -AllowNewArchive:($mode -eq 'Archive') -SlowDriveScan:($mode -eq 'Computer')
        if (-not $needle) { break }

        if ($mode -eq 'Archive' -and $needle -ieq ':NEW') {
            Clear-Host
            Initialize-ConsoleBuffer
            Show-Title
            $nextPath = Choose-BA2Archive
            if ($nextPath) { $chosenPath = $nextPath }
            continue
        }

        # The NEXT scan starts with a clean screen; previous matches and
        # summaries remain available in that scan's numbered TXT report.
        Clear-Host
        Initialize-ConsoleBuffer
        Show-Title
        if ($mode -eq 'Archive') {
            [void](Run-Scan -ArchiveFile $chosenPath -Needle $needle)
        }
        elseif ($mode -eq 'Computer') {
            [void](Run-Scan -Drives $chosenDrives -Needle $needle)
        }
        else {
            [void](Run-Scan -Root $chosenPath -Needle $needle)
        }
        Write-Host ''
        Write-Host 'You can search again in the SAME location.' -ForegroundColor Cyan
        Write-Host 'Leave the next filename blank and press ENTER for the main menu.' -ForegroundColor DarkGray
        Write-Host 'Your complete results and warnings are saved in the TXT report.' -ForegroundColor DarkGray
        Write-Host ''
    }
}

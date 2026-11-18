# Kill Streak :: resident sound player
#
# started hidden by sfx_launch.vbs (or directly, for testing):
#   powershell -NoProfile -ExecutionPolicy Bypass -File mods\killstreak\tools\sfx_server.ps1 -BaseDir <mod dir>
#
# it tails tmp\queue.txt - the mod appends one file name per line for every sound it
# wants to play - and plays it with System.Media.SoundPlayer (asynchronous, files are
# preloaded so playback starts within a few milliseconds).
#
# the helper shuts itself down as soon as the game process is gone, so it never
# survives a session.

param(
    [string]$BaseDir = ""
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($BaseDir)) {
    $BaseDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}

$tmpDir  = Join-Path $BaseDir "tmp"
$sfxDir  = Join-Path $BaseDir "sfx"
$queue   = Join-Path $tmpDir "queue.txt"
$logFile = Join-Path $tmpDir "sfx.log"
$pidFile = Join-Path $tmpDir "server.pid"
# a heartbeat the mod reads before it tries to start a helper: as long as the stamp
# is fresh the mod must NOT launch anything (starting a process from inside the game
# opens a console window and throws the player back to the desktop)
$beatFile = Join-Path $tmpDir "server.heartbeat"
# the mod writes the requested kill sound volume here as a whole percent ("85").
# an integer on purpose: "0.85" would be read as 85 in a comma decimal locale
$volFile = Join-Path $tmpDir "volume.txt"
$game    = "payday_win32_release"

if (-not (Test-Path -LiteralPath $tmpDir)) {
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
}

# keep the log small
try {
    if ((Test-Path -LiteralPath $logFile) -and ((Get-Item -LiteralPath $logFile).Length -gt 262144)) {
        Remove-Item -LiteralPath $logFile -Force
    }
} catch { }

function Log([string]$msg) {
    try {
        $line = "[" + (Get-Date -Format "HH:mm:ss.fff") + "] " + $msg
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    } catch { }
}

# > volume ---------------------------------------------------------------------
# SoundPlayer has no volume property and setting the device mixer would change the
# volume of every other program, so the PCM data is scaled before it is handed to
# the player. this keeps the same low latency path (everything still goes through
# a preloaded SoundPlayer) and the volume is per mod.
$script:volume  = 1.0
$script:scaleOk = $false

$scaleCode = @'
using System;
using System.IO;

namespace KillStreak {
    public static class Wav {
        public static byte[] Scale(string path, double vol) {
            byte[] b = File.ReadAllBytes(path);
            if (vol >= 0.999) { return b; }
            byte[] outBytes = (byte[])b.Clone();
            if (vol < 0.0) { vol = 0.0; }

            int i = 12;                                  // skip "RIFF" + size + "WAVE"
            while (i + 8 <= outBytes.Length) {
                int size = BitConverter.ToInt32(outBytes, i + 4);
                bool isData = outBytes[i] == (byte)'d' && outBytes[i + 1] == (byte)'a'
                           && outBytes[i + 2] == (byte)'t' && outBytes[i + 3] == (byte)'a';
                if (isData) {
                    long start = i + 8;
                    long end = start + size;
                    if (end > outBytes.Length) { end = outBytes.Length; }
                    for (long p = start; p + 1 < end; p += 2) {
                        short s = (short)(outBytes[p] | (outBytes[p + 1] << 8));
                        int v = (int)Math.Round(s * vol);
                        if (v > 32767) { v = 32767; }
                        if (v < -32768) { v = -32768; }
                        outBytes[p] = (byte)(v & 0xFF);
                        outBytes[p + 1] = (byte)((v >> 8) & 0xFF);
                    }
                    return outBytes;
                }
                if (size < 0) { break; }
                i += 8 + size + (size & 1);              // chunks are word aligned
            }
            return outBytes;
        }
    }
}
'@

function Ensure-Scale {
    if ($script:scaleOk) { return $true }
    try {
        Add-Type -TypeDefinition $scaleCode -Language CSharp -ErrorAction Stop | Out-Null
        $script:scaleOk = $true
        Log "volume scaling ready"
    } catch {
        Log ("volume scaling is unavailable, playing at full volume: " + $_)
        $script:scaleOk = $false
    }
    return $script:scaleOk
}

# reads tmp/volume.txt, returns $null when the file says nothing usable
function Read-Volume {
    try {
        if (-not (Test-Path -LiteralPath $volFile)) { return $null }
        $txt = (Get-Content -LiteralPath $volFile -TotalCount 1)
        if ($null -eq $txt) { return $null }
        $txt = ([string]$txt).Trim()
        if ($txt -eq "") { return $null }
        $iv = 0
        if (-not [int]::TryParse($txt, [ref]$iv)) { return $null }
        if ($iv -lt 0) { $iv = 0 }
        if ($iv -gt 100) { $iv = 100 }
        return ($iv / 100.0)
    } catch {
        return $null
    }
}

# only one instance: a stale helper from a previous session would double every sound
if (Test-Path -LiteralPath $pidFile) {
    try {
        $old = [int](Get-Content -LiteralPath $pidFile -TotalCount 1)
        $proc = Get-Process -Id $old -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -eq "powershell") {
            Log "another server is already running (pid $old), exiting"
            exit
        }
    } catch { }
}
Set-Content -LiteralPath $pidFile -Value $PID -Encoding ASCII

function Beat() {
    try {
        Set-Content -LiteralPath $beatFile -Encoding ASCII `
            -Value ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    } catch { }
}

Beat
Log "server started (pid $PID), base dir: $BaseDir"

$pools = @{}
$idx = @{}

# compile the scaler up front: doing it on the first kill would stall that sound
[void](Ensure-Scale)
$v0 = Read-Volume
if ($null -ne $v0) { $script:volume = $v0 }
Log ("volume: " + $script:volume)

# .wav goes through SoundPlayer (tiny latency, several instances for overlap),
# anything else (mp3 / wma / ...) goes through the WPF media pipeline, which can
# decode more formats but needs a moment to open the file the first time
$mediaPools = @{}
$mediaIdx = @{}
$wpfReady = $false

function Ensure-Wpf() {
    if ($script:wpfReady) { return $true }
    try {
        Add-Type -AssemblyName PresentationCore | Out-Null
        $script:wpfReady = $true
    } catch {
        Log ("wpf media is not available: " + $_)
        $script:wpfReady = $false
    }
    return $script:wpfReady
}

# only one voice line at a time: a kill chain produces a line every few hundred ms
# and three half spoken lines on top of each other is just noise. the newest line
# wins and cuts the previous one, the way an announcer would.
$script:active = New-Object System.Collections.ArrayList

function Stop-Active() {
    foreach ($p in $script:active) {
        try { $p.Stop() } catch { }
    }
    $script:active.Clear()
}

function Play-Media([string]$path, [string]$name) {
    if (-not (Ensure-Wpf)) { return }

    if (-not $mediaPools.ContainsKey($path)) {
        $list = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt 3; $i++) {
            try {
                $mp = New-Object System.Windows.Media.MediaPlayer
                $mp.Volume = $script:volume
                $mp.Open([uri]$path)
                [void]$list.Add($mp)
            } catch {
                Log ("could not open " + $path + ": " + $_)
            }
        }
        if ($list.Count -eq 0) { return }
        $mediaPools[$path] = $list
        $mediaIdx[$path] = 0
    }

    $i = $mediaIdx[$path]
    $mediaIdx[$path] = ($i + 1) % $mediaPools[$path].Count
    try {
        Stop-Active
        $mp = $mediaPools[$path][$i]
        $mp.Position = [TimeSpan]::Zero
        $mp.Play()
        [void]$script:active.Add($mp)
        Log ("played: " + $name)
    } catch {
        Log ("play failed for " + $path + ": " + $_)
    }
}

function Play-Sound([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    if ($script:volume -le 0.0) { return }         # muted, save the work

    # the mod writes "men1/Headshot.wav", windows is happier with backslashes
    $name = $name.Replace('/', '\')

    $path = Join-Path $sfxDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        Log "missing sound file: $path"
        return
    }

    if ([System.IO.Path]::GetExtension($name).ToLower() -ne ".wav") {
        Play-Media $path $name
        return
    }

    if (-not $pools.ContainsKey($path)) {
        # the volume is baked into the PCM when the pool is built, so a volume change
        # throws the whole pool away (see the main loop) instead of rescaling here
        $bytes = $null
        if ($script:scaleOk -and $script:volume -lt 0.999) {
            try {
                $bytes = [KillStreak.Wav]::Scale($path, $script:volume)
            } catch {
                Log ("could not scale " + $path + ": " + $_)
                $bytes = $null
            }
        }

        $list = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt 4; $i++) {
            $sp = New-Object System.Media.SoundPlayer
            if ($null -ne $bytes) {
                # one stream per player, but they all share the same scaled buffer
                $ms = New-Object System.IO.MemoryStream -ArgumentList (, $bytes)
                $sp.Stream = $ms
            } else {
                $sp.SoundLocation = $path
            }
            try {
                $sp.Load()
                # Load() leaves the stream at its end; rewind so a later Play() on this
                # pooled instance still starts from the first sample
                if ($null -ne $bytes) { $ms.Position = 0 }
            } catch {
                Log ("could not load " + $path + ": " + $_)
            }
            [void]$list.Add($sp)
        }
        $pools[$path] = $list
        $idx[$path] = 0
    }

    $i = $idx[$path]
    $idx[$path] = ($i + 1) % 4
    try {
        Stop-Active
        $pools[$path][$i].Play()
        [void]$script:active.Add($pools[$path][$i])
        Log ("played: " + $name)
    } catch {
        Log ("play failed for " + $path + ": " + $_)
    }
}

# start at the beginning: the mod truncates the queue right before it starts this
# helper, so everything in there belongs to the current session
$pos = 0

$checks = 0
$volChecks = 0

while ($true) {
    # the mod writes tmp/volume.txt when the player moves the volume slider. the
    # preloaded wav pools carry the volume they were scaled with, so they have to go.
    $volChecks = $volChecks + 1
    if ($volChecks -ge 12) {                       # ~100 ms
        $volChecks = 0
        $want = Read-Volume
        if (($null -ne $want) -and ([Math]::Abs($want - $script:volume) -gt 0.004)) {
            $script:volume = $want
            $pools.Clear()
            $idx.Clear()
            foreach ($key in @($mediaPools.Keys)) {
                foreach ($mp in $mediaPools[$key]) {
                    try { $mp.Volume = $script:volume } catch { }
                }
            }
            Log ("volume set to " + $script:volume)
        }
    }

    try {
        if (Test-Path -LiteralPath $queue) {
            $len = (Get-Item -LiteralPath $queue).Length
            if ($len -lt $pos) {
                # the mod truncated the file (new session)
                $pos = 0
            }
            if ($len -gt $pos) {
                $fs = [System.IO.File]::Open($queue, [System.IO.FileMode]::Open,
                                             [System.IO.FileAccess]::Read,
                                             [System.IO.FileShare]::ReadWrite)
                try {
                    [void]$fs.Seek($pos, [System.IO.SeekOrigin]::Begin)
                    $sr = New-Object System.IO.StreamReader($fs)
                    $text = $sr.ReadToEnd()
                    $pos = $fs.Position
                    $sr.Close()
                } finally {
                    $fs.Close()
                }

                foreach ($line in ($text -split "`r?`n")) {
                    $l = $line.Trim()
                    if ($l -eq "") { continue }
                    if ($l -eq "__stop") { Log "stop requested"; exit }
                    Play-Sound $l
                }
            }
        }
    } catch {
        Log ("queue read failed: " + $_)
    }

    # check every ~2 s whether the game is still running
    $checks = $checks + 1
    if ($checks -ge 200) {
        $checks = 0
        Beat
        if (-not (Get-Process -Name $game -ErrorAction SilentlyContinue)) {
            Start-Sleep -Milliseconds 1500
            if (-not (Get-Process -Name $game -ErrorAction SilentlyContinue)) {
                Log "game exited, stopping"
                break
            }
        }
    }

    Start-Sleep -Milliseconds 8
}

try { Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue } catch { }
try { Remove-Item -LiteralPath $beatFile -Force -ErrorAction SilentlyContinue } catch { }

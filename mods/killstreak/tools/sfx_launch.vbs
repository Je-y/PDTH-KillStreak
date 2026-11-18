' Kill Streak :: hidden launcher for tools/sfx_server.ps1
' started from the mod with:  wscript //nologo tools/sfx_launch.vbs
' window style 0 = hidden, false = do not wait, so the game never blocks on it.

Option Explicit

Dim fso, sh, base, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")

base = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))

cmd = "powershell.exe -NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden" _
    & " -File """ & base & "\tools\sfx_server.ps1"" -BaseDir """ & base & """"

sh.Run cmd, 0, False

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$fx = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $fx 'csc.exe'
$references = @('System.dll','System.Core.dll','System.Management.dll','System.Xaml.dll','System.Web.Extensions.dll',
    'WPF\WindowsBase.dll','WPF\PresentationCore.dll','WPF\PresentationFramework.dll',
    'WPF\UIAutomationTypes.dll','WPF\UIAutomationProvider.dll')
foreach ($file in @('csc.exe') + $references) {
    if (-not (Test-Path -LiteralPath (Join-Path $fx $file))) { throw "Отсутствует компонент .NET Framework: $file" }
}
$manifest = Join-Path $PSScriptRoot 'WinPulse.manifest'
[xml]$xml = Get-Content -LiteralPath $manifest -Encoding UTF8 -Raw
if ($xml.SelectSingleNode("//*[local-name()='requestedExecutionLevel']").level -ne 'asInvoker') {
    throw 'Окно должно запускаться под текущим пользователем.'
}
$temp = [IO.Directory]::CreateDirectory((Join-Path $PSScriptRoot ([guid]::NewGuid().ToString('N'))))
try {
    # The same pulse mark as the title bar, embedded as a native application icon.
    Add-Type -AssemblyName System.Drawing
    $icon = Join-Path $temp.FullName 'pulse.ico'
    $bitmap = [Drawing.Bitmap]::new(64,64)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $pen = [Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml('#CEA4FF'),5)
    $png = [IO.MemoryStream]::new()
    try {
        $graphics.SmoothingMode = 'AntiAlias'
        $graphics.Clear([Drawing.ColorTranslator]::FromHtml('#2D203D'))
        $pen.LineJoin = 'Round'
        $points = [Drawing.Point[]]@([Drawing.Point]::new(4,32),[Drawing.Point]::new(17,32),
            [Drawing.Point]::new(24,14),[Drawing.Point]::new(34,52),[Drawing.Point]::new(42,24),
            [Drawing.Point]::new(48,32),[Drawing.Point]::new(60,32))
        $graphics.DrawLines($pen,$points)
        $bitmap.Save($png,[Drawing.Imaging.ImageFormat]::Png)
        $writer = [IO.BinaryWriter]::new([IO.File]::Create($icon))
        try {
            $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]1)
            $writer.Write([byte[]](64,64,0,0)); $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$png.Length); $writer.Write([uint32]22); $writer.Write($png.ToArray())
        } finally { $writer.Dispose() }
    } finally { $png.Dispose(); $pen.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
    $exe = Join-Path $temp.FullName 'WinPulse.exe'
    $flags = @('/nologo','/target:winexe','/platform:x64','/optimize+','/warnaserror+','/codepage:65001',
        "/out:$exe","/win32manifest:$manifest","/win32icon:$icon","/resource:$PSScriptRoot\Shell.xaml,Shell.xaml")
    foreach ($name in $references) { $flags += '/reference:' + (Join-Path $fx $name) }
    $sources = @('WinPulse.cs','SessionView.cs','WorkspacePages.cs','Visuals.cs') | ForEach-Object { Join-Path $PSScriptRoot $_ }
    & $csc @flags @sources
    if ($LASTEXITCODE -ne 0) { throw "Ошибка компилятора $LASTEXITCODE" }
    Copy-Item -LiteralPath $exe -Destination (Join-Path $root 'WinPulse.exe') -Force
} finally {
    foreach ($file in $temp.GetFiles()) { $file.Delete() }
    $temp.Delete()
}
# END OF FILE | Всего твиков в файле: 0

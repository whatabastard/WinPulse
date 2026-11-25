#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Startup','Background')][string]$View,
    [string]$OpenPackage
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
if ($View -eq 'Startup') {
    if ($OpenPackage) { throw 'OpenPackage requires Background' }
    $library = Join-Path (Split-Path $PSScriptRoot) 'lib'
    $temp = [IO.Directory]::CreateDirectory((Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))))
    $summary = Join-Path $temp.FullName 'summary.txt'
    $output = Join-Path $temp.FullName 'startup.json'
    $previous = $env:WP_LIB
    try {
        $env:WP_LIB = $library
        & (Join-Path $library 'wp.ps1') get-autorun $summary $output
        if ($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($output)) { throw 'Не удалось прочитать автозагрузку' }
        [IO.File]::ReadAllText($output)
    } finally {
        $env:WP_LIB = $previous
        foreach ($file in $summary,$output) { if ([IO.File]::Exists($file)) { [IO.File]::Delete($file) } }
        $temp.Delete()
    }
    return
}
$build = [int](Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' CurrentBuildNumber)
$packages = @(Get-AppxPackage | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage } | Sort-Object PackageFamilyName -Unique)
$items = @(foreach ($package in $packages) {
    $family = $package.PackageFamilyName
    $uri = if ($build -ge 22000) { 'ms-settings:appsfeatures-app?' + [uri]::EscapeDataString($family) } else { 'ms-settings:privacy-backgroundapps' }
    [ordered]@{name=$package.Name; packageFamilyName=$family; settingsUri=$uri}
})
if ($OpenPackage) {
    $chosen = @($items | Where-Object { $_.packageFamilyName -eq $OpenPackage })
    if ($chosen.Count -ne 1) { throw 'Пакет отсутствует у текущего пользователя' }
    Start-Process -FilePath $chosen[0].settingsUri
    return
}
[ordered]@{schemaVersion=1; windowsBuild=$build; items=$items; fallbackUri='ms-settings:appsfeatures'} | ConvertTo-Json -Depth 5
# END OF FILE | Всего твиков в файле: 0

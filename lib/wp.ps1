#Requires -Version 5.1
# ============================================================
#  WinPulse 7.1 "Rebuild"  |  lib\wp.ps1  |  ЧАСТЬ 1/6
#  PowerShell-движок. Единственная точка входа из batch:
#    powershell -NoProfile -ExecutionPolicy Bypass -File wp.ps1 <verb> <args>
#
#  Кодировка ЭТОГО файла: UTF-8 С BOM, CRLF.
#  Без BOM PowerShell 5.1 читает файл как ANSI и ломает кириллицу.
#
#  Контракт:
#    результат всегда KEY=VALUE в файл (Arg1), UTF-8 без BOM
#    ключи только A-Z0-9_, из значений вырезаны  !  ^  %  "  `
#    exit 0 = успех, 2 = частично (get-*), 1 = провал (do-* или нет файла)
#    get-* только чтение, do-* изменение
#
#  Вызов напрямую запрещён: без WP_LIB в окружении exit 9009.
#  Это защита от применения твиков мимо журнала и точки восстановления.
# ============================================================
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Verb = 'get-engine',
    [Parameter(Position = 1)][string]$Arg1 = '',
    [Parameter(Position = 2)][string]$Arg2 = '',
    [Parameter(Position = 3)][string]$Arg3 = '',
    [Parameter(Position = 4)][string]$Arg4 = '',
    [Parameter(Position = 5)][string]$Arg5 = ''
)

if (-not $env:WP_LIB) { exit 9009 }

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:KV = New-Object 'System.Collections.Generic.List[string]'
$script:Failures = New-Object 'System.Collections.Generic.List[string]'
$script:Partial = $false
$script:IsMutating = $false
$script:SysDrive = $env:SystemDrive
if ([string]::IsNullOrEmpty($script:SysDrive)) { $script:SysDrive = 'C:' }

# ------------------------------------------------------------
#  Инфраструктура вывода
# ------------------------------------------------------------
function Clean-Val {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    $s = [string]$Value
    $s = $s -replace '[\x00-\x1F]', ''
    $s = $s -replace '[!^%"`]', ''
    return $s.Trim()
}

function Add-KV {
    param([string]$Key, [object]$Value)
    $k = $Key.ToUpperInvariant() -replace '[^A-Z0-9_]', ''
    if ([string]::IsNullOrEmpty($k)) { return }
    $script:KV.Add("$k=$(Clean-Val $Value)") | Out-Null
}

function Write-KV {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return }
    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $enc = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllLines($Path, $script:KV, $enc)
    }
    catch { exit 1 }
}

# ВАЖНО: & $Code выполняется в ДОЧЕРнем scope. Присваивание
# внутри создаёт локальную копию. Аккумуляторы, которые читаются
# снаружи, обязаны быть $script: или мутацией объекта (List.Add).
function Invoke-Step {
    param([string]$Name, [scriptblock]$Code)
    try { & $Code }
    catch {
        $script:Partial = $true
        $msg = [string]$_.Exception.Message
        $msg = ($msg -replace '[!^%"`|;:\r\n\t]', ' ') -replace '\s+', ' '
        $msg = $msg.Trim()
        if ($msg.Length -gt 110) { $msg = $msg.Substring(0, 110) }
        $script:Failures.Add(('{0} [{1}]' -f $Name, $msg)) | Out-Null
    }
}

# ------------------------------------------------------------
#  Типы носителей. MSFT_PhysicalDisk.BusType и STORAGE_BUS_TYPE
#  совпадают: 8=RAID, 9=iSCSI, 10=SAS. В 6.x было перепутано.
#
#  MediaType приходит как enum, как UInt16 или как строка "HDD" -
#  зависит от версии Storage-модуля. Прямой [int] на строке
#  бросает InvalidCastException и роняет весь шаг. Поэтому
#  сначала приводим к строке, потом мапим имя, потом число.
# ------------------------------------------------------------
function Get-MediaName {
    param([object]$Media, [object]$Bus)
    $sm = ([string]$Media).Trim().ToUpper()
    $m = -1
    switch ($sm) {
        'HDD'         { $m = 3 }
        'SSD'         { $m = 4 }
        'SCM'         { $m = 5 }
        'UNSPECIFIED' { $m = 0 }
    }
    if ($m -lt 0) {
        $r = 0
        if ([int]::TryParse($sm, [ref]$r)) { $m = $r }
    }
    if ($m -eq 3) { return 'HDD' }
    if ($m -eq 4 -or $m -eq 5) { return 'SSD' }
    if ((Get-BusName $Bus) -eq 'NVMe') { return 'SSD' }
    return 'Unknown'
}

function Get-BusName {
    param([object]$Bus)
    $sb = ([string]$Bus).Trim().ToUpper()
    switch ($sb) {
        'NVME'              { return 'NVMe' }
        'SATA'              { return 'SATA' }
        'SAS'               { return 'SAS' }
        'ISCSI'             { return 'iSCSI' }
        'RAID'              { return 'RAID' }
        'USB'               { return 'USB' }
        'ATA'               { return 'ATA' }
        'SPACES'            { return 'Spaces' }
        'SCSI'              { return 'SCSI' }
        'VIRTUAL'           { return 'Virtual' }
        'FILEBACKEDVIRTUAL' { return 'Virtual' }
    }
    $r = 0
    if ([int]::TryParse($sb, [ref]$r)) {
        switch ($r) {
            17 { return 'NVMe' }
            11 { return 'SATA' }
            10 { return 'SAS' }
            9  { return 'iSCSI' }
            8  { return 'RAID' }
            7  { return 'USB' }
            3  { return 'ATA' }
            16 { return 'Spaces' }
            1  { return 'SCSI' }
            14 { return 'Virtual' }
            15 { return 'Virtual' }
        }
    }
    return 'Other'
}

# ------------------------------------------------------------
#  Единый парсер поколения CPU. Используется и get-detect,
#  и get-detect-api, чтобы порог жил в одном месте.
# ------------------------------------------------------------
function Get-CpuClass {
    param([string]$Name, [string]$Vendor, [int]$Cores, [int]$Threads)
    $gen = 0; $series = 0; $bucket = 'unknown'; $hybrid = 0
    if ($Vendor -eq 'Intel') {
        if ($Name -match 'i[3579][-\s]*(\d{4,5})') {
            $m = $Matches[1]
            if ($m.Length -eq 5) { $gen = [int]$m.Substring(0, 2) }
            elseif ($m -match '^10\d\d$') { $gen = 10 }
            else { $gen = [int]$m.Substring(0, 1) }
        }
        elseif ($Name -match 'Ultra\s+[579]\s+\d{3}') { $gen = 14 }
        elseif ($Name -match '\bN\d{3}\b') { $gen = 12 }
        $series = $gen
        if ($gen -ge 12) { $bucket = 'intel_new' }
        elseif ($gen -ge 1) { $bucket = 'intel_old' }
        if ($gen -ge 12) {
            if ($Threads -gt $Cores -and $Threads -lt (2 * $Cores)) { $hybrid = 1 }
            elseif ($Name -match 'Ultra') { $hybrid = 1 }
        }
    }
    elseif ($Vendor -eq 'AMD') {
        if ($Name -match 'Ryzen\s+(?:Threadripper\s+)?(?:[3579]\s+)?(?:PRO\s+)?(\d{4})') {
            $m = $Matches[1]
            $series = [int]$m.Substring(0, 1) * 1000
            # 3200G и 3400G - это Zen+ (Picasso), а не Zen2
            if ($m -match '^(3200|3400)$') { $bucket = 'zen_old' }
            elseif ($series -ge 3000) { $bucket = 'zen_new' }
            else { $bucket = 'zen_old' }
        }
        elseif ($Name -match 'Ryzen\s+AI') { $series = 9000; $bucket = 'zen_new' }
    }
    return @{ Gen = $gen; Series = $series; Bucket = $bucket; Hybrid = $hybrid }
}

# ------------------------------------------------------------
#  Привилегии процесса. Нужны для веток под TrustedInstaller.
#  Pack=1 обязателен: без него C# выровняет long на 8 и
#  структура TOKEN_PRIVILEGES уедет на 8 байт.
# ------------------------------------------------------------
if (-not ('WinPulse.Native' -as [type])) {
    Add-Type -Namespace WinPulse -Name Native -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct TOKEN_PRIVILEGES {
    public int PrivilegeCount;
    public long Luid;
    public int Attributes;
}
[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool OpenProcessToken(IntPtr ProcessHandle, int DesiredAccess, out IntPtr TokenHandle);
[DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);
[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges,
    ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);
'@
}

function Enable-WpPrivilege {
    param([string[]]$Names)
    $tok = [IntPtr]::Zero
    $h = [System.Diagnostics.Process]::GetCurrentProcess().Handle
    if (-not [WinPulse.Native]::OpenProcessToken($h, 0x28, [ref]$tok)) { return $false }
    $all = $true
    foreach ($n in $Names) {
        $luid = [long]0
        if (-not [WinPulse.Native]::LookupPrivilegeValue($null, $n, [ref]$luid)) { $all = $false; continue }
        $tp = New-Object 'WinPulse.Native+TOKEN_PRIVILEGES'
        $tp.PrivilegeCount = 1
        $tp.Luid = $luid
        $tp.Attributes = 2
        $null = [WinPulse.Native]::AdjustTokenPrivileges($tok, $false, [ref]$tp, 0, [IntPtr]::Zero, [IntPtr]::Zero)
        # AdjustTokenPrivileges возвращает true даже при ERROR_NOT_ALL_ASSIGNED
        if ([System.Runtime.InteropServices.Marshal]::GetLastWin32Error() -ne 0) { $all = $false }
    }
    return $all
}

# ------------------------------------------------------------
#  Реестр: разбор пути и конвертация данных
# ------------------------------------------------------------
function Split-WpRegPath {
    param([string]$Path)
    $p = ($Path -replace '/', '\').TrimEnd('\')
    $i = $p.IndexOf('\')
    if ($i -lt 1) { throw "bad registry path: $Path" }
    $root = $p.Substring(0, $i).ToUpperInvariant()
    $hive = switch ($root) {
        'HKLM'               { [Microsoft.Win32.RegistryHive]::LocalMachine }
        'HKEY_LOCAL_MACHINE' { [Microsoft.Win32.RegistryHive]::LocalMachine }
        'HKU'                { [Microsoft.Win32.RegistryHive]::Users }
        'HKEY_USERS'         { [Microsoft.Win32.RegistryHive]::Users }
        'HKCU'               { [Microsoft.Win32.RegistryHive]::CurrentUser }
        'HKEY_CURRENT_USER'  { [Microsoft.Win32.RegistryHive]::CurrentUser }
        'HKCR'               { [Microsoft.Win32.RegistryHive]::ClassesRoot }
        default              { throw "unsupported hive: $root" }
    }
    return @{ Hive = $hive; Sub = $p.Substring($i + 1) }
}

function Convert-WpRegData {
    param([string]$Type, [string]$Data)
    switch ($Type.ToUpperInvariant()) {
        'REG_DWORD' {
            # 4294967295 не влезает в int32: приводим через байты, не кастом
            if ($Data -match '^0[xX]') { $u = [Convert]::ToUInt32($Data.Substring(2), 16) }
            else { $u = [uint32]$Data }
            return @{ Kind = [Microsoft.Win32.RegistryValueKind]::DWord
                      Value = [BitConverter]::ToInt32([BitConverter]::GetBytes($u), 0) }
        }
        'REG_QWORD' {
            if ($Data -match '^0[xX]') { $u = [Convert]::ToUInt64($Data.Substring(2), 16) }
            else { $u = [uint64]$Data }
            return @{ Kind = [Microsoft.Win32.RegistryValueKind]::QWord
                      Value = [BitConverter]::ToInt64([BitConverter]::GetBytes($u), 0) }
        }
        'REG_BINARY' {
            $hex = $Data -replace '[^0-9a-fA-F]', ''
            if ($hex.Length % 2 -ne 0) { throw 'REG_BINARY: odd hex length' }
            $b = New-Object byte[] ($hex.Length / 2)
            for ($i = 0; $i -lt $b.Length; $i++) {
                $b[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
            }
            return @{ Kind = [Microsoft.Win32.RegistryValueKind]::Binary; Value = $b }
        }
        'REG_MULTI_SZ' {
            return @{ Kind = [Microsoft.Win32.RegistryValueKind]::MultiString
                      Value = [string[]]($Data -split '\\0') }
        }
        'REG_EXPAND_SZ' {
            return @{ Kind = [Microsoft.Win32.RegistryValueKind]::ExpandString; Value = $Data }
        }
        default {
            return @{ Kind = [Microsoft.Win32.RegistryValueKind]::String; Value = $Data }
        }
    }
}

function Format-WpRegReadback {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [byte[]]) { return (($Value | ForEach-Object { $_.ToString('x2') }) -join '') }
    if ($Value -is [string[]]) { return ($Value -join '\0') }
    return [string]$Value
}

# ------------------------------------------------------------
#  API-канал детекта. Ни одного обращения к WMI, CIM,
#  службе Storage или модулям PS. Только kernel32 и реестр.
#  Работает при убитом репозитории WMI и отключённом StorSvc.
# ------------------------------------------------------------
if (-not ('WinPulse.Api' -as [type])) {
    Add-Type -IgnoreWarnings -Namespace WinPulse -Name Api -UsingNamespace System.Runtime.InteropServices -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct MEMORYSTATUSEX {
    public uint dwLength;
    public uint dwMemoryLoad;
    public ulong ullTotalPhys;
    public ulong ullAvailPhys;
    public ulong ullTotalPageFile;
    public ulong ullAvailPageFile;
    public ulong ullTotalVirtual;
    public ulong ullAvailVirtual;
    public ulong ullAvailExtendedVirtual;
}
[StructLayout(LayoutKind.Sequential)]
public struct SYSTEM_POWER_STATUS {
    public byte ACLineStatus;
    public byte BatteryFlag;
    public byte BatteryLifePercent;
    public byte SystemStatusFlag;
    public uint BatteryLifeTime;
    public uint BatteryFullLifeTime;
}
[DllImport("kernel32.dll", SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);
[DllImport("kernel32.dll", SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS lpSystemPowerStatus);
[DllImport("kernel32.dll", SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool GetLogicalProcessorInformation(IntPtr Buffer, ref uint ReturnedLength);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern uint GetSystemFirmwareTable(uint FirmwareTableProviderSignature,
    uint FirmwareTableID, IntPtr pFirmwareTableBuffer, uint BufferSize);
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode,
    IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);
[DllImport("kernel32.dll", SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool CloseHandle(IntPtr hObject);
[DllImport("kernel32.dll", SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool DeviceIoControl(IntPtr hDevice, uint dwIoControlCode,
    IntPtr lpInBuffer, uint nInBufferSize, IntPtr lpOutBuffer, uint nOutBufferSize,
    out uint lpBytesReturned, IntPtr lpOverlapped);
'@
}

# DesiredAccess=0 достаточно: оба IOCTL объявлены FILE_ANY_ACCESS.
# Это снимает зависимость от прав на запись в устройство.
function Open-WpDevice {
    param([string]$Path)
    $h = [WinPulse.Api]::CreateFileW($Path, 0, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h -eq [IntPtr](-1)) { return [IntPtr]::Zero }
    return $h
}

function Invoke-WpIoctl {
    param([IntPtr]$Handle, [uint32]$Code, [byte[]]$In, [int]$OutSize)
    $inPtr = [IntPtr]::Zero
    $outPtr = [IntPtr]::Zero
    try {
        $inLen = 0
        if ($In -and $In.Length -gt 0) {
            $inLen = $In.Length
            $inPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($inLen)
            [System.Runtime.InteropServices.Marshal]::Copy($In, 0, $inPtr, $inLen)
        }
        $outPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($OutSize)
        for ($i = 0; $i -lt $OutSize; $i++) {
            [System.Runtime.InteropServices.Marshal]::WriteByte($outPtr, $i, 0)
        }
        $ret = [uint32]0
        $ok = [WinPulse.Api]::DeviceIoControl($Handle, $Code, $inPtr, [uint32]$inLen,
              $outPtr, [uint32]$OutSize, [ref]$ret, [IntPtr]::Zero)
        if (-not $ok) { return $null }
        $out = New-Object byte[] $OutSize
        [System.Runtime.InteropServices.Marshal]::Copy($outPtr, $out, 0, $OutSize)
        return $out
    }
    finally {
        if ($inPtr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($inPtr) }
        if ($outPtr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($outPtr) }
    }
}

# Один handle, два запроса. SeekPenalty=0 -> SSD, =1 -> HDD.
# Это метод SMART-утилит, служба Storage для него не нужна.
function Get-WpDiskInfo {
    param([int]$DiskNumber)
    $h = Open-WpDevice ("\\.\PhysicalDrive" + $DiskNumber)
    if ($h -eq [IntPtr]::Zero) { return $null }
    try {
        $res = @{ Seek = $null; Bus = $null; Name = '' }
        $any = $false

        $q1 = New-Object byte[] 12
        [BitConverter]::GetBytes([uint32]7).CopyTo($q1, 0)
        [BitConverter]::GetBytes([uint32]0).CopyTo($q1, 4)
        $r1 = Invoke-WpIoctl -Handle $h -Code 0x2D1400 -In $q1 -OutSize 12
        if ($r1) { $res.Seek = [int]$r1[8]; $any = $true }

        $q2 = New-Object byte[] 12
        [BitConverter]::GetBytes([uint32]0).CopyTo($q2, 0)
        [BitConverter]::GetBytes([uint32]0).CopyTo($q2, 4)
        $r2 = Invoke-WpIoctl -Handle $h -Code 0x2D1400 -In $q2 -OutSize 1024
        if ($r2) {
            $res.Bus = [int][BitConverter]::ToUInt32($r2, 28)
            $off = [int][BitConverter]::ToUInt32($r2, 16)
            if ($off -gt 0 -and $off -lt $r2.Length) {
                $sb = New-Object System.Text.StringBuilder
                for ($i = $off; $i -lt $r2.Length; $i++) {
                    if ($r2[$i] -eq 0) { break }
                    [void]$sb.Append([char]$r2[$i])
                }
                $res.Name = $sb.ToString().Trim()
            }
            $any = $true
        }
        if (-not $any) { return $null }
        return $res
    }
    finally { [void][WinPulse.Api]::CloseHandle($h) }
}

# IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS вместо Get-Partition -> Get-Disk
function Get-WpVolumeDisk {
    param([string]$Drive)
    $h = Open-WpDevice ("\\.\" + $Drive)
    if ($h -eq [IntPtr]::Zero) { return $null }
    try {
        $r = Invoke-WpIoctl -Handle $h -Code 0x560000 -In $null -OutSize 64
        if (-not $r) { return $null }
        return @{
            Count = [int][BitConverter]::ToUInt32($r, 0)
            Disk  = [int][BitConverter]::ToUInt32($r, 8)
        }
    }
    finally { [void][WinPulse.Api]::CloseHandle($h) }
}

# Топология CPU без WMI. Union не маршалим, читаем по смещениям.
# Смешанные SMT и non-SMT ядра = гибрид (P-cores + E-cores).
function Get-WpCpuTopology {
    $len = [uint32]0
    [void][WinPulse.Api]::GetLogicalProcessorInformation([IntPtr]::Zero, [ref]$len)
    if ($len -eq 0) { return $null }
    $buf = [System.Runtime.InteropServices.Marshal]::AllocHGlobal([int]$len)
    try {
        if (-not [WinPulse.Api]::GetLogicalProcessorInformation($buf, [ref]$len)) { return $null }
        $ptrSize = [IntPtr]::Size
        if ($ptrSize -eq 8) { $stride = 32 } else { $stride = 24 }
        $relOff = $ptrSize
        $flagOff = $ptrSize + 4
        $maxBit = $ptrSize * 8
        $cores = 0; $threads = 0; $smt = 0
        $count = [int][math]::Floor($len / $stride)
        for ($i = 0; $i -lt $count; $i++) {
            $base = $i * $stride
            $rel = [System.Runtime.InteropServices.Marshal]::ReadInt32($buf, $base + $relOff)
            if ($rel -ne 0) { continue }
            if ($ptrSize -eq 8) {
                $mask = [System.Runtime.InteropServices.Marshal]::ReadIntPtr($buf, $base).ToInt64()
            }
            else {
                $mask = [int64][uint32][System.Runtime.InteropServices.Marshal]::ReadInt32($buf, $base)
            }
            $bits = 0
            for ($b = 0; $b -lt $maxBit; $b++) {
                if (([int64]1 -shl $b) -band $mask) { $bits++ }
            }
            $cores++
            $threads += $bits
            $flags = [System.Runtime.InteropServices.Marshal]::ReadByte($buf, $base + $flagOff)
            if (($flags -band 1) -eq 1) { $smt++ }
        }
        $hybrid = 0
        if ($smt -gt 0 -and $smt -lt $cores) { $hybrid = 1 }
        return @{ Cores = $cores; Threads = $threads; Hybrid = $hybrid; SmtCores = $smt }
    }
    finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buf) }
}

# SMBIOS Type 3: тип корпуса без WMI. Отличает ноутбук от
# десктопа с ИБП даже в деградированном режиме.
function Get-WpSmbiosChassis {
    $sig = 0x52534D42
    $need = [WinPulse.Api]::GetSystemFirmwareTable($sig, 0, [IntPtr]::Zero, 0)
    if ($need -eq 0) { return $null }
    $buf = [System.Runtime.InteropServices.Marshal]::AllocHGlobal([int]$need)
    try {
        $got = [WinPulse.Api]::GetSystemFirmwareTable($sig, 0, $buf, $need)
        if ($got -eq 0) { return $null }
        $total = [int]$got
        $pos = 8
        $chassis = -1
        while ($pos -lt ($total - 4)) {
            $t = [System.Runtime.InteropServices.Marshal]::ReadByte($buf, $pos)
            $l = [System.Runtime.InteropServices.Marshal]::ReadByte($buf, $pos + 1)
            if ($l -lt 4) { break }
            if ($t -eq 3 -and $l -ge 6) {
                $chassis = [int]([System.Runtime.InteropServices.Marshal]::ReadByte($buf, $pos + 5) -band 0x7F)
            }
            if ($t -eq 127) { break }
            $s = $pos + $l
            while ($s -lt ($total - 1)) {
                if ([System.Runtime.InteropServices.Marshal]::ReadByte($buf, $s) -eq 0 -and
                    [System.Runtime.InteropServices.Marshal]::ReadByte($buf, $s + 1) -eq 0) { $s += 2; break }
                $s++
            }
            if ($s -le $pos) { break }
            $pos = $s
        }
        return $chassis
    }
    finally { [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buf) }
}

# [ЧАСТЬ 1/6 ЗАВЕРШЕНА - ДАЛЕЕ ИДЁТ ДИСПЕТЧЕР VERB]

# ============================================================
#  ДИСПЕТЧЕР VERB
#  Части 3-6 добавляют остальные ветки перед 'default'.
# ============================================================
function Write-RollbackRecord {
    param([string]$Line)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Line + [Environment]::NewLine)
    $stream = [IO.File]::Open($env:JOURNAL, 'Open', 'Write', 'Read')
    try {
        $offset = $stream.Seek(0, 'End')
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } catch {
            $stream.SetLength($offset)
            throw
        }
    } finally { $stream.Dispose() }
}

switch ($Verb.ToLowerInvariant()) {
    'session-key' {
        # The journal records KEY only for keys created by this session.
        if ($env:WP_DRYRUN -eq '1') { exit 1 }
        try {
            $path = Split-WpRegPath $env:WP_KEY_PATH
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($path.Hive, 'Default')
            $key = $base.OpenSubKey($path.Sub)
            if ($Arg1 -eq 'create') {
                if ($null -ne $key) { exit 11 }
                Write-RollbackRecord "KEY|$env:WP_KEY_PATH|ABSENT"
                $key = $base.CreateSubKey($path.Sub)
                if ($null -eq $key) { throw 'Could not create key' }
            } elseif ($Arg1 -eq 'undo') {
                if ($null -eq $key) { exit 10 }
                if ($key.SubKeyCount -or $key.ValueCount) { exit 11 }
                $key.Close()
                $base.DeleteSubKey($path.Sub, $false)
            } else { throw 'Unknown key operation' }
            exit 0
        } catch {
            [Console]::Error.WriteLine($_.Exception.Message)
            exit 1
        } finally {
            if ($key) { $key.Dispose() }
            if ($base) { $base.Dispose() }
        }
    }
    'snapshot-task' {
        try {
            $taskPath = $env:_TP
            if ([string]::IsNullOrWhiteSpace($taskPath) -or $taskPath -match '[!^|\x00-\x1f]') {
                throw 'Invalid task path for rollback journal'
            }
            $split = $taskPath.LastIndexOf('\')
            $folder = if ($split -gt 0) { $taskPath.Substring(0, $split) } else { '\' }
            $name = $taskPath.Substring($split + 1)
            $scheduler = New-Object -ComObject Schedule.Service
            $scheduler.Connect()
            try {
                $task = $scheduler.GetFolder($folder).GetTask($name)
            } catch {
                $cause = $_.Exception.GetBaseException()
                if ($cause.HResult -in -2147024894, -2147024893) { exit 10 }
                throw
            }
            if (-not $task.Enabled) { exit 11 }
            Write-RollbackRecord "TASK|$taskPath|ENABLED"
            exit 12
        } catch {
            [Console]::Error.WriteLine($_.Exception.Message)
            exit 1
        }
    }
    'snapshot-reg' {
        # 10 = ABSENT, 11 = SAME, 12 = DIFF. Other codes stop the caller.
        try {
            $path = Split-WpRegPath $env:_SK
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($path.Hive, 'Default')
            $key = $base.OpenSubKey($path.Sub)
            $record = 'ABSENT'
            $result = 10
            if ($key -and $key.GetValueNames() -contains $env:_SV) {
                $kind = $key.GetValueKind($env:_SV)
                $value = $key.GetValue($env:_SV, $null, 'DoNotExpandEnvironmentNames')
                if ($null -eq $value) { throw 'Registry value disappeared during snapshot' }
                $type = switch ($kind) {
                    'DWord'        { 'REG_DWORD' }
                    'QWord'        { 'REG_QWORD' }
                    'Binary'       { 'REG_BINARY' }
                    'String'       { 'REG_SZ' }
                    'ExpandString' { 'REG_EXPAND_SZ' }
                    'MultiString'  { 'REG_MULTI_SZ' }
                    default        { throw "Unsupported registry type: $kind" }
                }
                $data = switch ($kind) {
                    'DWord' { '0x{0:x}' -f $value }
                    'QWord' { '0x{0:x}' -f $value }
                    'Binary' { [BitConverter]::ToString($value).Replace('-', '') }
                    'MultiString' {
                        if (@($value | Where-Object { $_ -match '\\0' -or $_ -eq '' }).Count) {
                            throw 'Multi-string cannot be encoded in rollback journal'
                        }
                        $value -join '\0'
                    }
                    default { [string]$value }
                }
                if ($data -match '[!\^\|\x00-\x1f]') {
                    throw 'Value cannot be replayed losslessly by batch'
                }
                $record = "$type|$data"
                $result = 12
                if ($env:_ST -eq $type) {
                    $target = Convert-WpRegData $type $env:_SD
                    if ($kind -eq 'Binary') {
                        if ($data -eq [BitConverter]::ToString($target.Value).Replace('-', '')) { $result = 11 }
                    } elseif ($kind -ne 'MultiString' -and $value -ceq $target.Value) {
                        $result = 11
                    }
                }
            }
            if ($result -eq 11 -and $Arg1 -in 'REG_SET', 'REGACL') { exit 11 }
            $recordType = if ($Arg1 -eq 'REGACL') { 'REGACL' } else { 'REG' }
            $line = "$recordType|$env:_SK|$env:_SV|$record"
            if ($line.Length -gt 7900) { throw 'Record exceeds batch replay limit' }
            Write-RollbackRecord $line
        } catch {
            [Console]::Error.WriteLine($_.Exception.Message)
            exit 1
        } finally {
            if ($key) { $key.Dispose() }
            if ($base) { $base.Dispose() }
        }
        exit $result
    }
    'rotate-sessions' {
        if ($env:WP_DRYRUN -eq '1') { exit 0 }
        try {
            if ($env:_KEEP -notmatch '^[1-9][0-9]?$') { throw 'Invalid retention limit' }
            $root = Get-Item -LiteralPath (Join-Path $env:WP_ROOT 'Backups')
            if ($root.FullName -ne $env:WP_BACKUPS -or $root.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Unexpected backup directory'
            }
            $sessions = @(foreach ($dir in $root.GetDirectories()) {
                if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($dir.Name -notmatch '^(\d{8}_\d{6}|r\d{2,10})$') { continue }
                $marker = Join-Path $dir.FullName 'session.txt'
                if (-not [IO.File]::Exists($marker) -or -not [IO.File]::Exists((Join-Path $dir.FullName 'journal.txt'))) { continue }
                if ($dir.GetDirectories().Count -or @($dir.GetFiles() | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { continue }
                $header = @(Get-Content -LiteralPath $marker -TotalCount 2)
                if ($header.Count -eq 2 -and $header[0] -like 'WinPulse *' -and $header[1] -eq "Session: $($dir.Name)") { $dir }
            })
            $excess = $sessions.Count - [int]$env:_KEEP
            if ($excess -gt 0) {
                foreach ($dir in ($sessions | Where-Object Name -ne $env:STAMP | Sort-Object CreationTimeUtc, Name | Select-Object -First $excess)) {
                    if ($dir.Parent.FullName -ne $root.FullName) { throw 'Unexpected session path' }
                    $dir.Delete($true)
                    [IO.File]::AppendAllText($env:SESSION_LOG, "[ROTATE] removed session $($dir.Name)" + [Environment]::NewLine)
                }
            }
        } catch {
            [Console]::Error.WriteLine($_.Exception.Message)
            exit 1
        }
        exit 0
    }
    'get-frametime' {
        Invoke-Step 'frametime' {
            $csv = [string]$Arg2
            Add-KV 'FT_OK' 0
            if ([string]::IsNullOrWhiteSpace($csv)) { Add-KV 'FT_ERR' 'no path'; return }
            if (-not (Test-Path -LiteralPath $csv)) { Add-KV 'FT_ERR' 'no file'; return }
            $rows = @()
            try { $rows = @(Import-Csv -LiteralPath $csv -ErrorAction Stop) } catch { Add-KV 'FT_ERR' 'csv parse'; return }
            if ($rows.Count -lt 10) { Add-KV 'FT_ERR' 'too few frames'; return }
            $col = $null
            foreach ($c in @('MsBetweenPresents', 'msBetweenPresents', 'MsBetweenDisplayChange', 'msBetweenDisplayChange')) {
                if ($rows[0].PSObject.Properties.Name -contains $c) { $col = $c; break }
            }
            if (-not $col) { Add-KV 'FT_ERR' 'unknown schema'; Add-KV 'FT_COLS' (($rows[0].PSObject.Properties.Name -join ' ') -replace '[|!^%"`]', ' '); return }
            Add-KV 'FT_COL' $col
            $vals = New-Object 'System.Collections.Generic.List[double]'
            $ci = [System.Globalization.CultureInfo]::InvariantCulture
            $ns = [System.Globalization.NumberStyles]::Float
            foreach ($r in $rows) {
                $d = 0.0
                $s = [string]$r.$col
                if ([double]::TryParse($s, $ns, $ci, [ref]$d)) {
                    if ($d -gt 0 -and $d -lt 1000) { $vals.Add($d) }
                }
            }
            if ($vals.Count -lt 10) { Add-KV 'FT_ERR' 'no valid frametimes'; return }
            $arr = $vals.ToArray()
            $n = $arr.Length
            $sum = 0.0
            foreach ($v in $arr) { $sum += $v }
            $avg = $sum / $n
            $sq = 0.0
            foreach ($v in $arr) { $sq += ($v - $avg) * ($v - $avg) }
            $sd = [math]::Sqrt($sq / $n)
            $sorted = $arr.Clone()
            [array]::Sort($sorted)
            [array]::Reverse($sorted)
            $k1 = [math]::Max(1, [int][math]::Ceiling($n * 0.01))
            $k01 = [math]::Max(1, [int][math]::Ceiling($n * 0.001))
            $s1 = 0.0
            for ($i = 0; $i -lt $k1; $i++) { $s1 += $sorted[$i] }
            $s01 = 0.0
            for ($i = 0; $i -lt $k01; $i++) { $s01 += $sorted[$i] }
            $low1 = 1000.0 / ($s1 / $k1)
            $low01 = 1000.0 / ($s01 / $k01)
            Add-KV 'FT_OK' 1
            if ($env:WP_DESKTOP_TOKEN) {
                # Each plotted point is the longest frame in a consecutive bin.
                $width = [int][math]::Ceiling($n / 120.0)
                $peaks = for ($start = 0; $start -lt $n; $start += $width) {
                    $end = [math]::Min($start + $width, $n)
                    $peak = 0.0
                    for ($i = $start; $i -lt $end; $i++) {
                        $peak = [math]::Max($peak, $arr[$i])
                    }
                    $peak.ToString('0.###', $ci)
                }
                Add-KV 'FT_SERIES' ($peaks -join ',')
            }
            Add-KV 'FT_FRAMES' $n
            Add-KV 'FT_AVG_MS' ([math]::Round($avg, 3))
            Add-KV 'FT_AVG_FPS' ([int][math]::Round(1000.0 / $avg))
            Add-KV 'FT_LOW1_FPS' ([int][math]::Round($low1))
            Add-KV 'FT_LOW01_FPS' ([int][math]::Round($low01))
            Add-KV 'FT_STDDEV_MS' ([math]::Round($sd, 3))
            Add-KV 'FT_WORST_MS' ([math]::Round($sorted[0], 3))
        }
    }
    'get-nic' {
        Invoke-Step 'nic' {
            $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
            $keys = @(
                @('*InterruptModeration', 'InterruptModeration'),
                @('*EEE', 'EEE'),
                @('*AdvancedEEE', 'AdvancedEEE'),
                @('*GreenEthernet', 'EnableGreenEthernet', 'GreenEthernet'),
                @('*GigabitLite', 'GigaLite', 'GigabitLite'),
                @('*PowerDownPll', 'PowerDownPll'),
                @('*SelectiveSuspend', 'SelectiveSuspend', 'PowerSavingMode'),
                @('*PMARPOffload'),
                @('*PMNSOffload'),
                @('*RscIPv4'),
                @('*RscIPv6'),
                @('ASPM'),
                @('CLKREQ'),
                @('*RSS')
            )
            $guids = @{}
            try {
                foreach ($a in @(Get-NetAdapter -Physical -ErrorAction Stop)) {
                    if ([string]$a.MediaType -ne '802.3') { continue }
                    $g = ([string]$a.InterfaceGuid).Trim('{}').ToLowerInvariant()
                    if ($g) { $guids[$g] = [string]$a.Name }
                }
            }
            catch { }
            Add-KV 'NIC_ETH_PHYS' $guids.Count
            $n = 0
            $subs = @()
            Add-KV 'NIC_BASE_EXISTS' $(if (Test-Path -LiteralPath $base) { 1 } else { 0 })
            try { $subs = @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue) } catch { $subs = @() }
            if ($subs.Count -eq 0) {
                try { $subs = @(Get-ChildItem -Path $base -ErrorAction SilentlyContinue) } catch { $subs = @() }
            }
            Add-KV 'NIC_SUBKEYS' $subs.Count
            foreach ($s in $subs) {
                $idx = [string]$s.PSChildName
                if ($idx -notmatch '^\d{4}$') { continue }
                $p = $null
                try { $p = Get-ItemProperty -LiteralPath $s.PSPath -ErrorAction Stop } catch { $p = $null }
                if ($null -eq $p) {
                    try { $p = Get-ItemProperty -Path $s.PSPath -ErrorAction Stop } catch { continue }
                }
                $desc = [string]$p.DriverDesc
                if ([string]::IsNullOrWhiteSpace($desc)) { continue }
                $n++
                $cfg = ([string]$p.NetCfgInstanceId).Trim('{}').ToLowerInvariant()
                $elig = 0
                $aname = ''
                if ($cfg -and $guids.ContainsKey($cfg)) { $elig = 1; $aname = $guids[$cfg] }
                if ($desc -match '(?i)virtual|vmware|virtualbox|hyper-v|tap-|loopback|wan miniport|bluetooth|wireless|wi-fi|wifi|802\.11|vpn|tunnel') { $elig = 0 }
                $clean = $desc -replace '[|!^%"`]', ' '
                $clean = ($clean -replace '\s+', ' ').Trim()
                if ($clean.Length -gt 46) { $clean = $clean.Substring(0, 46) }
                Add-KV ("NIC_{0}_IDX" -f $n) $idx
                Add-KV ("NIC_{0}_NAME" -f $n) $clean
                Add-KV ("NIC_{0}_ALIAS" -f $n) ($aname -replace '[|!^%"`]', ' ')
                Add-KV ("NIC_{0}_ELIG" -f $n) $elig
                for ($i = 0; $i -lt $keys.Count; $i++) {
                    $has = 0; $found = ''
                    foreach ($cand in @($keys[$i])) {
                        if ($p.PSObject.Properties.Name -contains $cand) { $has = 1; $found = $cand; break }
                    }
                    Add-KV ("NIC_{0}_K{1}" -f $n, ($i + 1)) $has
                    Add-KV ("NIC_{0}_N{1}" -f $n, ($i + 1)) $found
                    $cur = ''
                    if ($has -eq 1) { $cur = ([string]$p.$found) -replace '[|!^%"`]', ' ' }
                    Add-KV ("NIC_{0}_V{1}" -f $n, ($i + 1)) $cur
                }
            }
            Add-KV 'NIC_COUNT' $n
        }
    }
    'do-provisioned' {
        $script:IsMutating = $true
        $tier = $Arg2.ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($tier)) { $tier = 'core' }
        $core = @(
            'Microsoft.549981C3F5F10', 'Microsoft.BingNews', 'Microsoft.BingWeather',
            'Microsoft.BingSearch', 'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub',
            'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MixedReality.Portal',
            'Microsoft.SkypeApp', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo',
            'Microsoft.Clipchamp', 'Microsoft.WindowsFeedbackHub',
            'MicrosoftCorporationII.MicrosoftFamily', 'Microsoft.Windows.DevHome',
            'MicrosoftTeams', 'MSTeams'
        )
        $extra = @(
            'Microsoft.WindowsCamera', 'Microsoft.WindowsAlarms',
            'Microsoft.WindowsSoundRecorder', 'microsoft.windowscommunicationsapps',
            'Microsoft.People', 'Microsoft.YourPhone', 'Microsoft.WindowsMaps',
            'MicrosoftCorporationII.QuickAssist', 'Microsoft.GetHelp',
            'Microsoft.Todos', 'Microsoft.Office.OneNote',
            'Microsoft.OutlookForWindows', 'Microsoft.PowerAutomateDesktop'
        )
        $protect = @(
            'Microsoft.VCLibs', 'Microsoft.NET.Native', 'Microsoft.UI.Xaml',
            'Microsoft.WindowsAppRuntime', 'Microsoft.Services.Store.Engagement',
            'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller',
            'Microsoft.WindowsStore', 'Microsoft.SecHealthUI', 'Microsoft.AAD.BrokerPlugin',
            'Microsoft.AccountsControl', 'Microsoft.CredDialogHost', 'Microsoft.LockApp',
            'Microsoft.Windows.StartMenuExperienceHost', 'Microsoft.Windows.ShellExperienceHost',
            'Microsoft.Windows.CloudExperienceHost', 'Microsoft.Windows.OOBENetwork',
            'Microsoft.Windows.AppRep.ChxApp', 'Microsoft.XboxGameCallableUI',
            'Microsoft.BioEnrollment', 'Microsoft.MicrosoftEdge', 'Microsoft.Edge',
            'MicrosoftWindows.Client', 'Windows.CBSPreview', 'Windows.PrintDialog',
            'Microsoft.AsyncTextService', 'Microsoft.Win32WebViewHost',
            'Microsoft.Windows.PeopleExperienceHost', 'Microsoft.Windows.PinningConfirmationDialog',
            'Microsoft.Windows.XGpuEjectDialog', 'Microsoft.ECApp'
        )
        $list = $core
        if ($tier -eq 'extra') { $list = $extra }
        Add-KV 'PV_TIER' $tier
        Add-KV 'PV_IRREVERSIBLE' 1
        $all = @()
        try { $all = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) } catch { $all = @() }
        $i = 0; $listed = 0; $totR = 0; $totF = 0
        foreach ($fam in $list) {
            $i++
            $f = 0; $r = 0; $fl = 0; $sk = 0
            $isProt = $false
            foreach ($p in $protect) { if ($fam -like ($p + '*')) { $isProt = $true } }
            if ($isProt) { $sk = 1 }
            else {
                foreach ($pkg in $all) {
                    if ([string]$pkg.DisplayName -ne $fam) { continue }
                    $f++
                    $full = [string]$pkg.PackageName
                    if ([string]::IsNullOrWhiteSpace($full)) { $sk++; continue }
                    try {
                        Remove-AppxProvisionedPackage -Online -PackageName $full -ErrorAction Stop | Out-Null
                        $r++; $totR++; $listed++
                        Add-KV ("PV_PKG{0}_NAME" -f $listed) $full
                    }
                    catch { $fl++; $totF++ }
                }
            }
            Add-KV ("PV_P{0}_FAMILY" -f $i) $fam
            Add-KV ("PV_P{0}_FOUND" -f $i) $f
            Add-KV ("PV_P{0}_REMOVED" -f $i) $r
            Add-KV ("PV_P{0}_FAILED" -f $i) $fl
            Add-KV ("PV_P{0}_SKIPPED" -f $i) $sk
            Add-KV ("PV_P{0}_PROTECTED" -f $i) $(if ($isProt) { 1 } else { 0 })
        }
        Add-KV 'PV_FAMILIES' $i
        Add-KV 'PV_LISTED' $listed
        Add-KV 'PV_REMOVED' $totR
        Add-KV 'PV_FAILED' $totF
    }
	    'get-features' {
        Invoke-Step 'features' {
            $devs = $null
            try { $devs = @(Get-PnpDevice -PresentOnly -ErrorAction Stop) } catch { $devs = $null }
            $map = @{
                'FT_BT'         = 'Bluetooth'
                'FT_SMARTCARD'  = 'SmartCardReader'
                'FT_BIOMETRIC'  = 'Biometric'
                'FT_NFC'        = 'Proximity'
                'FT_MODEM'      = 'Modem'
                'FT_SENSOR'     = 'Sensor'
            }
            foreach ($k in $map.Keys) {
                if ($null -eq $devs) { Add-KV $k -1; continue }
                $cls = $map[$k]
                $n = 0
                foreach ($d in $devs) {
                    if ([string]$d.Class -ne $cls) { continue }
                    if ([string]$d.Status -eq 'Unknown') { continue }
                    $n++
                }
                Add-KV $k $n
            }
            $dom = -1
            try {
                $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
                if ($cs.PartOfDomain) { $dom = 1 } else { $dom = 0 }
            }
            catch { $dom = -1 }
            Add-KV 'FT_DOMAIN' $dom
            $rdp = -1
            try {
                $v = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction Stop).fDenyTSConnections
                if ([int]$v -eq 0) { $rdp = 1 } else { $rdp = 0 }
            }
            catch { $rdp = -1 }
            Add-KV 'FT_RDP' $rdp
            $hello = -1
            try {
                $p = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\FaceLogon'
                if (Test-Path $p) { $hello = 1 } else { $hello = 0 }
            }
            catch { $hello = -1 }
			            $lap = -1
            try {
                $bat = @(Get-CimInstance Win32_Battery -ErrorAction Stop).Count
                $portable = @(8, 9, 10, 11, 12, 14, 18, 21)
                $isPort = $false
                try {
                    foreach ($e in @(Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop)) {
                        foreach ($c in @($e.ChassisTypes)) {
                            if ($portable -contains [int]$c) { $isPort = $true }
                        }
                    }
                }
                catch { }
                if ($bat -gt 0 -or $isPort) { $lap = 1 } else { $lap = 0 }
            }
            catch { $lap = -1 }
            Add-KV 'FT_LAPTOP' $lap
            Add-KV 'FT_HELLO' $hello
        }
    }
	    'get-autorun' {
        Invoke-Step 'autorun' {
            $items = [Collections.Generic.List[object]]::new()
            $readErrors = [Collections.Generic.List[string]]::new()
            function Add-StartupItem($source, $key, $name, $command, $signature, $state) {
                if (-not $Arg2) { return }
                $items.Add([ordered]@{source=$source; location=$key; name=$name; command=$command; signature=$signature; state=$state})
            }
            function ArExe([string]$c) {
                if ([string]::IsNullOrWhiteSpace($c)) { return $null }
                $t = [Environment]::ExpandEnvironmentVariables($c.Trim()) -replace '^\\\?\?\\', ''
                if ($t -match '^"([^"]+)"') { return $Matches[1] }
                if ($t -match '^([A-Za-z]:\\.+?\.(exe|dll|bat|cmd|ps1|vbs|js))(?=\s|,|$)') { return $Matches[1] }
                if ($t -match '^([A-Za-z]:\\.+?)(?=\s+[-/]|\s*$)') { return $Matches[1] }
                if ($t -match '^[A-Za-z]:\\') { return $t }
                return $null
            }
            function ArEditable([string]$identity, [string]$legacy) {
                if (-not $identity -or $identity -cne (Clean-Val $legacy) -or $identity -match '[\x00-\x1f&|<>!%"^()]') { return 0 }
                return 1
            }
            function ArClean([string]$s, [int]$max) {
                if ($null -eq $s) { return '' }
                $t = $s -replace '[|!"]', ' '
                $t = $t -replace '\s+', ' '
                $t = $t.Trim()
                if ($t.Length -gt $max) { $t = $t.Substring(0, $max) }
                return $t
            }
            $regSrc = @(
                @('HKCU_RUN', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'),
                @('HKCU_RUNONCE', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'),
                @('HKLM_RUN', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'),
                @('HKLM_RUNONCE', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'),
                @('HKLM_WOW_RUN', 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run')
            )
            $dirSrc = @(
                @('STARTUP_USER', (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup')),
                @('STARTUP_COMMON', (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'))
            )
            $n = 0; $unsign = 0; $missing = 0; $total = 0
            foreach ($s in $regSrc) {
                $k = $s[0]; $path = $s[1]; $cnt = 0; $dis = 0
                if (Test-Path $path) {
                    $props = $null
                    try { $props = Get-ItemProperty -LiteralPath $path -ErrorAction Stop } catch { $readErrors.Add($path) }
                    if ($props) {
                        foreach ($pr in $props.PSObject.Properties) {
                            if ($pr.Name -in 'PSPath','PSParentPath','PSChildName','PSDrive','PSProvider','PSComputerName','PSShowComputerName','RunspaceId') { continue }
                            $cnt++; $total++
                            $exe = ArExe ([string]$pr.Value)
                            $st = 'NoPath'; $ex = 0
                            if ($exe) {
                                if (Test-Path -LiteralPath $exe) {
                                    $ex = 1
                                    $sg = $null
                                    try { $sg = Get-AuthenticodeSignature -LiteralPath $exe -ErrorAction Stop } catch { }
                                    if ($sg) { $st = [string]$sg.Status } else { $st = 'Unknown' }
                                }
                                else { $st = 'Missing'; $missing++ }
                            }
                            if ($ex -eq 1 -and $st -ne 'Valid') { $unsign++ }
                            Add-StartupItem $k $path $pr.Name ([string]$pr.Value) $st 'registered'
                            if ($n -lt 40) {
                                $n++
                                Add-KV ("AR_E{0}_NAME" -f $n) (ArClean $pr.Name 40)
                                Add-KV ("AR_E{0}_EDITABLE" -f $n) (ArEditable $pr.Name (ArClean $pr.Name 40))
                                Add-KV ("AR_E{0}_SRC" -f $n) $k
                                Add-KV ("AR_E{0}_CMD" -f $n) (ArClean ([string]$pr.Value) 110)
                                Add-KV ("AR_E{0}_SIGN" -f $n) $st
                            }
                        }
                    }
                    $dp = Join-Path $path 'AutorunsDisabled'
                    if (Test-Path $dp) {
                        try {
                            $dpr = Get-ItemProperty -LiteralPath $dp -ErrorAction Stop
                            $dis = @($dpr.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }).Count
                        }
                        catch { $dis = 0 }
                    }
                }
                Add-KV ("AR_{0}_COUNT" -f $k) $cnt
                Add-KV ("AR_{0}_DISABLED" -f $k) $dis
            }
            $sh = $null
            try { $sh = New-Object -ComObject WScript.Shell } catch { }
            foreach ($s in $dirSrc) {
                $k = $s[0]; $path = $s[1]; $cnt = 0
                if (Test-Path $path) {
                    $files = @(Get-ChildItem -LiteralPath $path -Filter *.lnk -File -Force -ErrorAction SilentlyContinue)
                    $cnt = $files.Count; $total += $cnt
                    foreach ($f in $files) {
                        $tgt = ''
                        if ($sh) { try { $tgt = $sh.CreateShortcut($f.FullName).TargetPath } catch { } }
                        $st = 'NoPath'; $ex = 0
                        if ($tgt -and (Test-Path -LiteralPath $tgt)) {
                            $ex = 1
                            $sg = $null
                            try { $sg = Get-AuthenticodeSignature -LiteralPath $tgt -ErrorAction Stop } catch { }
                            if ($sg) { $st = [string]$sg.Status } else { $st = 'Unknown' }
                        }
                        elseif ($tgt) { $st = 'Missing'; $missing++ }
                        if ($ex -eq 1 -and $st -ne 'Valid') { $unsign++ }
                        Add-StartupItem $k $f.FullName $f.BaseName $tgt $st 'registered'
                        if ($n -lt 40) {
                            $n++
                            Add-KV ("AR_E{0}_NAME" -f $n) (ArClean $f.BaseName 40)
                                Add-KV ("AR_E{0}_EDITABLE" -f $n) (ArEditable $f.BaseName (ArClean $f.BaseName 40))
                            Add-KV ("AR_E{0}_SRC" -f $n) $k
                            Add-KV ("AR_E{0}_CMD" -f $n) (ArClean $tgt 110)
                            Add-KV ("AR_E{0}_SIGN" -f $n) $st
                        }
                    }
                }
                Add-KV ("AR_{0}_COUNT" -f $k) $cnt
                Add-KV ("AR_{0}_DISABLED" -f $k) 0
            }
            $tc = 0
            try {
                $all = @(Get-ScheduledTask -ErrorAction Stop)
                foreach ($t in $all) {
                    if ($t.TaskPath -like '\Microsoft\Windows\*') { continue }
                    $hit = $false
                    foreach ($tr in $t.Triggers) {
                        $cn = ''
                        try { $cn = [string]$tr.CimClass.CimClassName } catch { }
                        if ($cn -match 'LogonTrigger|BootTrigger') { $hit = $true }
                    }
                    if (-not $hit) { continue }
                    $tc++; $total++
                    Add-StartupItem 'TASKS_LOGON' ($t.TaskPath + $t.TaskName) $t.TaskName ([string]$t.Actions[0].Execute) $null ([string]$t.State)
                    if ($n -lt 40) {
                        $n++
                        Add-KV ("AR_E{0}_NAME" -f $n) (ArClean $t.TaskName 40)
                        Add-KV ("AR_E{0}_SRC" -f $n) 'TASKS_LOGON'
                        Add-KV ("AR_E{0}_CMD" -f $n) (ArClean ([string]$t.Actions[0].Execute) 110)
                        Add-KV ("AR_E{0}_ARGS" -f $n) (ArClean ([string]$t.Actions[0].Arguments) 110)
                        Add-KV ("AR_E{0}_SIGN" -f $n) ('Task:' + [string]$t.State)
                        Add-KV ("AR_E{0}_PATH" -f $n) ($t.TaskPath + $t.TaskName)
                                Add-KV ("AR_E{0}_EDITABLE" -f $n) (ArEditable ($t.TaskPath + $t.TaskName) ($t.TaskPath + $t.TaskName))
                    }
                }
            }
            catch { $tc = 0; $readErrors.Add('TASKS_LOGON') }
            Add-KV 'AR_TASKS_LOGON_COUNT' $tc
            Add-KV 'AR_TASKS_LOGON_DISABLED' 0
            Add-KV 'AR_SHOWN' $n
            Add-KV 'AR_TOTAL' $total
            Add-KV 'AR_UNSIGN' $unsign
            Add-KV 'AR_MISSING' $missing
            if ($Arg2) {
                $view = [ordered]@{schemaVersion=1; items=$items.ToArray(); readErrors=$readErrors.ToArray()}
                [IO.File]::WriteAllText($Arg2, (ConvertTo-Json $view -Depth 5), [Text.UTF8Encoding]::new($false))
                return
            }
            $vShell = ''; $vInit = ''; $vApp = ''
            $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
            try { $vShell = [string](Get-ItemProperty -LiteralPath $wl -Name Shell -EA Stop).Shell } catch { }
            try { $vInit = [string](Get-ItemProperty -LiteralPath $wl -Name Userinit -EA Stop).Userinit } catch { }
            try { $vApp = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -Name AppInit_DLLs -EA Stop).AppInit_DLLs } catch { }
            $vIf = 0; $vIfBlock = 0; $vIfSus = 0
            $ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
            if (Test-Path $ifeo) {
                foreach ($sk in @(Get-ChildItem -LiteralPath $ifeo -EA SilentlyContinue)) {
                    $dv = $null
                    try { $dv = (Get-ItemProperty -LiteralPath $sk.PSPath -Name Debugger -EA Stop).Debugger } catch { }
                    if (-not $dv) { continue }
                    $vIf++
                    $bn = ''
                    try { $bn = [IO.Path]::GetFileName(([Environment]::ExpandEnvironmentVariables([string]$dv).Trim('"'))) } catch { }
                    if ($bn -match '^(taskkill|systray|rundll32|cmd|ntsd|vsjitdebugger)\.exe$') { $vIfBlock++ } else { $vIfSus++ }
                    if ($vIf -le 12) {
                        Add-KV ("AR_IFEO{0}_NAME" -f $vIf) (ArClean $sk.PSChildName 40)
                        Add-KV ("AR_IFEO{0}_DBG" -f $vIf) (ArClean ([string]$dv) 110)
                    }
                }
            }
            $bad = 0
            if ($vShell -and $vShell.Trim() -ne 'explorer.exe') { $bad++ }
            if ($vInit -and $vInit.Trim().TrimEnd(',') -notmatch 'userinit\.exe$') { $bad++ }
            if ($vApp.Trim()) { $bad++ }
            if ($vIfSus -gt 0) { $bad++ }
            Add-KV 'AR_VEC_SHELL' (ArClean $vShell 110)
            Add-KV 'AR_VEC_USERINIT' (ArClean $vInit 110)
            Add-KV 'AR_VEC_APPINIT' (ArClean $vApp 110)
            Add-KV 'AR_VEC_IFEO' $vIf
            Add-KV 'AR_IFEO_BLOCK' $vIfBlock
            Add-KV 'AR_IFEO_SUSPECT' $vIfSus
            $script:ArWl = @(
                'RobloxPlayerBeta', 'AMDInstallLauncher', 'ModifyLinkUpdate',
                'AMD Install Manager - Check For Updates',
                'AdobeAAMUpdater', 'AdobeGCInvoker', 'Adobe ARM',
                'SunJavaUpdateSched', 'JavaUpdateScheduler',
                'CCleaner Monitoring', 'QuickTime Task', 'iTunesHelper',
                'SpotifyWebHelper', 'Dropbox Update',
                'MicrosoftEdgeAutoLaunch', 'Opera scheduled Autoupdate'
            )
            function ArHit([string]$nm) {
                if ([string]::IsNullOrWhiteSpace($nm)) { return $false }
                if ($nm -match '(?i)securityhealth|windowsdefender|msascui|blocktelemetry|processlasso|standbylist|windhawk') { return $false }
                if ($nm -match '[|!^%"`]') { return $false }
                foreach ($w in $script:ArWl) { if ($nm -like ($w + '*')) { return $true } }
                return $false
            }
            function ArSigned([string]$exe) {
                if (-not $exe) { return $true }
                if (-not (Test-Path -LiteralPath $exe)) { return $true }
                $sg = $null
                try { $sg = Get-AuthenticodeSignature -LiteralPath $exe -ErrorAction Stop } catch { }
                if ($sg -and [string]$sg.Status -eq 'Valid') { return $true }
                return $false
            }
            foreach ($s in $regSrc) {
                $k = $s[0]; $path = $s[1]; $c = 0
                if (Test-Path $path) {
                    $props = $null
                    try { $props = Get-ItemProperty -LiteralPath $path -ErrorAction Stop } catch { $readErrors.Add($path) }
                    if ($props) {
                        foreach ($pr in $props.PSObject.Properties) {
                            if ($pr.Name -in 'PSPath','PSParentPath','PSChildName','PSDrive','PSProvider','PSComputerName','PSShowComputerName','RunspaceId') { continue }
                            if (-not (ArHit $pr.Name)) { continue }
                            if (-not (ArSigned (ArExe ([string]$pr.Value)))) { continue }
                            $c++
                            if ($c -le 12) { Add-KV ("AR_C{0}_{1}" -f $k, $c) $pr.Name }
                        }
                    }
                }
                Add-KV ("AR_C{0}_COUNT" -f $k) $c
            }
            foreach ($s in $dirSrc) {
                $k = $s[0]; $path = $s[1]; $c = 0
                if (Test-Path $path) {
                    foreach ($f in @(Get-ChildItem -LiteralPath $path -Filter *.lnk -File -Force -EA SilentlyContinue)) {
                        if (-not (ArHit $f.BaseName)) { continue }
                        $tgt = ''
                        if ($sh) { try { $tgt = $sh.CreateShortcut($f.FullName).TargetPath } catch { } }
                        if (-not (ArSigned $tgt)) { continue }
                        $c++
                        if ($c -le 12) { Add-KV ("AR_C{0}_{1}" -f $k, $c) $f.BaseName }
                    }
                }
                Add-KV ("AR_C{0}_COUNT" -f $k) $c
            }
            $c = 0
            try {
                foreach ($tt in @(Get-ScheduledTask -ErrorAction Stop)) {
                    if ($tt.TaskPath -like '\Microsoft\Windows\*') { continue }
                    if (-not (ArHit $tt.TaskName)) { continue }
                    $hit = $false
                    foreach ($tr in $tt.Triggers) {
                        $cn = ''
                        try { $cn = [string]$tr.CimClass.CimClassName } catch { }
                        if ($cn -match 'LogonTrigger|BootTrigger') { $hit = $true }
                    }
                    if (-not $hit) { continue }
                    if ([string]$tt.State -eq 'Disabled') { continue }
                    $c++
                    if ($c -le 12) { Add-KV ("AR_CTASKS_LOGON_{0}" -f $c) ($tt.TaskPath + $tt.TaskName) }
                }
            }
            catch { $c = 0 }
            Add-KV 'AR_CTASKS_LOGON_COUNT' $c
            Add-KV 'AR_VECTORS' $bad
        }
    }
	    'get-smart' {
        Invoke-Step 'smart' {
            $pds = @(Get-PhysicalDisk -ErrorAction Stop)
            $n = 0
            foreach ($d in $pds) {
                $n++
                $p = "SM_$n"
                Add-KV ("{0}_NAME" -f $p)   ([string]$d.FriendlyName)
                Add-KV ("{0}_SERIAL" -f $p) ([string]$d.SerialNumber)
                Add-KV ("{0}_MEDIA" -f $p)  (Get-MediaName $d.MediaType $d.BusType)
                Add-KV ("{0}_BUS" -f $p)    (Get-BusName $d.BusType)
                Add-KV ("{0}_SIZE_GB" -f $p) ([int][math]::Round([double]$d.Size / 1GB))
                Add-KV ("{0}_HEALTH" -f $p) ([string]$d.HealthStatus)
                Add-KV ("{0}_FW" -f $p)     ([string]$d.FirmwareVersion)
                $rc = $null
                try { $rc = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
                $keys = @('TEMP','WEAR','POH','RERR','WERR','RUNC','WUNC','CYC')
                if ($null -eq $rc) {
                    Add-KV ("{0}_SMART" -f $p) 'Unavailable'
                    foreach ($k in $keys) { Add-KV ("{0}_{1}" -f $p, $k) -1 }
                }
                else {
                    Add-KV ("{0}_SMART" -f $p) 'OK'
                    $vals = @{
                        'TEMP' = $rc.Temperature
                        'WEAR' = $rc.Wear
                        'POH'  = $rc.PowerOnHours
                        'RERR' = $rc.ReadErrorsTotal
                        'WERR' = $rc.WriteErrorsTotal
                        'RUNC' = $rc.ReadErrorsUncorrected
                        'WUNC' = $rc.WriteErrorsUncorrected
                        'CYC'  = $rc.StartStopCycleCount
                    }
                    foreach ($k in $keys) {
                        $iv = [int64]0
                        $sv = [string]$vals[$k]
                        if ([int64]::TryParse($sv, [ref]$iv)) {
                            Add-KV ("{0}_{1}" -f $p, $k) $iv
                        } else {
                            Add-KV ("{0}_{1}" -f $p, $k) -1
                        }
                    }
                }
            }
            Add-KV 'SM_COUNT' $n
        }
    }

    # --------------------------------------------------------
    #  get-engine <file> - проверка движка для selftest
    # --------------------------------------------------------
    'get-engine' {
        Add-KV 'ENGINE_OK' 1
        Add-KV 'PS_VERSION' $PSVersionTable.PSVersion.ToString()
        Add-KV 'PS_EDITION' $PSVersionTable.PSEdition
        Add-KV 'PS_CLR' $PSVersionTable.CLRVersion.ToString()
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
        Add-KV 'PS_ADMIN' ([int]$pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
        Add-KV 'CURRENT_SID' $id.User.Value
        Add-KV 'PS_SYSDRIVE' $script:SysDrive
    }

    # --------------------------------------------------------
    #  get-detect <file> - канал 1, WMI/CIM плюс реестр
    # --------------------------------------------------------
    'get-detect' {

        # --- ОС. ProductName на Win11 врёт, семейство только по build ---
        Invoke-Step 'os' {
            $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
            $build = 0
            if ($cv.CurrentBuildNumber) { $build = [int]$cv.CurrentBuildNumber }
            elseif ($cv.CurrentBuild) { $build = [int]$cv.CurrentBuild }
            $ubr = 0
            if ($cv.UBR) { $ubr = [int]$cv.UBR }
            $product = [string]$cv.ProductName
            $display = [string]$cv.DisplayVersion
            if ([string]::IsNullOrWhiteSpace($display)) { $display = [string]$cv.ReleaseId }
            if ([string]::IsNullOrWhiteSpace($display)) {
                $known = @{ 19045 = '22H2'; 22621 = '22H2'; 22631 = '23H2'; 26100 = '24H2' }
                if ($known.ContainsKey($build)) { $display = $known[$build] } else { $display = 'N/A' }
            }
            $edMap = @{
                'Professional' = 'Pro'; 'ProfessionalN' = 'Pro N'
                'ProfessionalEducation' = 'Pro Education'
                'ProfessionalWorkstation' = 'Pro Workstation'
                'Core' = 'Home'; 'CoreN' = 'Home N'
                'CoreSingleLanguage' = 'Home SL'; 'CoreCountrySpecific' = 'Home China'
                'Enterprise' = 'Enterprise'; 'EnterpriseN' = 'Enterprise N'
                'Education' = 'Education'; 'EducationN' = 'Education N'
                'IoTEnterprise' = 'IoT Enterprise'
            }
            $ed = [string]$cv.EditionID
            if ($edMap.ContainsKey($ed)) { $edition = $edMap[$ed] }
            else { $edition = ($product -replace '^Windows\s+(10|11)\s+', '') }
            if ([string]::IsNullOrWhiteSpace($edition)) { $edition = 'Unknown' }

            $family = 'Windows'
            if ($build -ge 22000) { $family = 'Windows 11' }
            elseif ($build -ge 10240) { $family = 'Windows 10' }
            $supported = 0
            if ($build -ge 19045) { $supported = 1 }

            Add-KV 'WIN_PRODUCT' $product
            Add-KV 'WIN_FAMILY' $family
            Add-KV 'WIN_EDITION' $edition
            Add-KV 'WIN_DISPLAY' $display
            Add-KV 'WIN_BUILD' $build
            Add-KV 'WIN_UBR' $ubr
            Add-KV 'WIN_SUPPORTED' $supported
            Add-KV 'SYS_DRIVE' $script:SysDrive
        }

        Invoke-Step 'hotfix' {
            $hf = Get-HotFix -ErrorAction Stop |
                  Where-Object { $_.InstalledOn } |
                  Sort-Object InstalledOn -Descending |
                  Select-Object -First 1
            if ($hf) { Add-KV 'LAST_UPDATE' $hf.InstalledOn.ToString('yyyy-MM-dd') }
            else { Add-KV 'LAST_UPDATE' 'Unknown' }
        }

        # --- CPU. Поколение через общий Get-CpuClass, не inline ---
        Invoke-Step 'cpu' {
            $cpus = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
            $name = [string]$cpus[0].Name
            $cores = [int](($cpus | Measure-Object NumberOfCores -Sum).Sum)
            $threads = [int](($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum)
            $vendor = 'Unknown'
            if ($name -match 'Intel' -or $cpus[0].Manufacturer -match 'Intel') { $vendor = 'Intel' }
            elseif ($name -match 'AMD' -or $cpus[0].Manufacturer -match 'AMD') { $vendor = 'AMD' }

            $cls = Get-CpuClass -Name $name -Vendor $vendor -Cores $cores -Threads $threads

            Add-KV 'CPU_NAME' $name
            Add-KV 'CPU_VENDOR' $vendor
            Add-KV 'CPU_CORES' $cores
            Add-KV 'CPU_THREADS' $threads
            Add-KV 'CPU_SERIES' ([int]$cls.Series)
            Add-KV 'CPU_GENERATION' ([string]$cls.Bucket)
            Add-KV 'CPU_HYBRID' ([int]$cls.Hybrid)
        }

        Invoke-Step 'ram' {
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            $bytes = [double]$cs.TotalPhysicalMemory
            Add-KV 'RAM_MB' ([int][math]::Round($bytes / 1MB))
            Add-KV 'RAM_GB' ([int][math]::Round($bytes / 1GB))
            $speed = 0
            $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
            if ($mods.Count -gt 0) {
                if ($mods[0].ConfiguredClockSpeed) { $speed = [int]$mods[0].ConfiguredClockSpeed }
                elseif ($mods[0].Speed) { $speed = [int]$mods[0].Speed }
            }
            Add-KV 'RAM_SPEED' $speed
            Add-KV 'RAM_SLOTS' $mods.Count
        }

        # --- GPU. HWID = PNPDeviceID без префикса PCI\ ---
        Invoke-Step 'gpu' {
            $all = @(Get-CimInstance Win32_VideoController -ErrorAction Stop |
                     Where-Object { $_.PNPDeviceID -like 'PCI\*' })
            Add-KV 'GPU_COUNT' $all.Count
            if ($all.Count -eq 0) {
                Add-KV 'GPU_NAME' 'Unknown GPU'
                Add-KV 'GPU_VENDOR' 'Unknown'
                Add-KV 'GPU_INSTANCE' ''
                Add-KV 'GPU_HWID' ''
                Add-KV 'GPU_CLASSKEY' ''
                return
            }
            $real = @($all | Where-Object { [string]$_.Name -notmatch 'Basic Display' })
            if ($real.Count -eq 0) { $real = $all }
            $g = $real | Sort-Object { [double]$_.AdapterRAM } -Descending | Select-Object -First 1
            $id = [string]$g.PNPDeviceID
            $hwid = $id -replace '^PCI\\', ''
            $vendor = 'Unknown'
            if ($id -match 'VEN_10DE') { $vendor = 'NVIDIA' }
            elseif ($id -match 'VEN_1002' -or $id -match 'VEN_1022') { $vendor = 'AMD' }
            elseif ($id -match 'VEN_8086') { $vendor = 'Intel' }
            $ddate = 'Unknown'
            if ($g.DriverDate) { $ddate = ([datetime]$g.DriverDate).ToString('yyyy-MM-dd') }

            $classKey = ''
            try {
                $drv = (Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_Driver' -ErrorAction Stop).Data
                if ($drv) { $classKey = "HKLM\SYSTEM\CurrentControlSet\Control\Class\$drv" }
            }
            catch { $script:Failures.Add('gpu_classkey') | Out-Null }

            Add-KV 'GPU_NAME' ([string]$g.Name)
            Add-KV 'GPU_VENDOR' $vendor
            Add-KV 'GPU_DRIVER' ([string]$g.DriverVersion)
            Add-KV 'GPU_DRIVER_DATE' $ddate
            Add-KV 'GPU_INSTANCE' $id
            Add-KV 'GPU_HWID' $hwid
            Add-KV 'GPU_CLASSKEY' $classKey
        }

        # --- Загрузочный диск. IsBoot у PhysicalDisk НЕТ, идём от раздела ---
        Invoke-Step 'bootdisk' {
            $letter = $script:SysDrive.TrimEnd(':')
            $bname = 'Unknown'; $btype = 'Unknown'; $bbus = 'Unknown'
            $part = Get-Partition -DriveLetter $letter -ErrorAction Stop
            $disk = Get-Disk -Number $part.DiskNumber -ErrorAction Stop
            $phys = $null
            try { $phys = $disk | Get-PhysicalDisk -ErrorAction Stop | Select-Object -First 1 } catch { }
            if (-not $phys) {
                $phys = Get-PhysicalDisk -ErrorAction Stop |
                        Where-Object { $_.SerialNumber -and $_.SerialNumber -eq $disk.SerialNumber } |
                        Select-Object -First 1
            }
            if (-not $phys) {
                $phys = Get-PhysicalDisk -ErrorAction Stop |
                        Where-Object { [string]$_.DeviceId -eq [string]$disk.Number } |
                        Select-Object -First 1
            }
            if ($phys) {
                $bname = [string]$phys.FriendlyName
                $btype = Get-MediaName $phys.MediaType $phys.BusType
                $bbus = Get-BusName $phys.BusType
            }
            else {
                $bname = [string]$disk.FriendlyName
                if ([string]$disk.BusType -eq 'NVMe') { $btype = 'SSD'; $bbus = 'NVMe' }
            }
            Add-KV 'BOOT_DISK_NAME' $bname
            Add-KV 'BOOT_DISK_TYPE' $btype
            Add-KV 'BOOT_DISK_BUS' $bbus
        }

        Invoke-Step 'alldisks' {
            $pd = @(Get-PhysicalDisk -ErrorAction Stop)
            $hdd = 0; $unk = 0; $parts = @()
            foreach ($d in $pd) {
                $t = Get-MediaName $d.MediaType $d.BusType
                $b = Get-BusName $d.BusType
                if ($t -eq 'HDD') { $hdd++ }
                if ($t -eq 'Unknown') { $unk++ }
                $parts += ("{0} [{1}/{2}]" -f [string]$d.FriendlyName, $t, $b)
            }
            $allssd = 0
            if ($pd.Count -gt 0 -and $hdd -eq 0 -and $unk -eq 0) { $allssd = 1 }
            Add-KV 'DISK_COUNT' $pd.Count
            Add-KV 'HDD_COUNT' $hdd
            Add-KV 'DISK_UNKNOWN' $unk
            Add-KV 'ALL_SSD' $allssd
            Add-KV 'ALL_DISKS' ($parts -join '; ')
        }

        Invoke-Step 'freespace' {
            $ld = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($script:SysDrive)'" -ErrorAction Stop
            if ($ld -and $ld.FreeSpace) {
                Add-KV 'FREE_SPACE_GB' ([int][math]::Floor([double]$ld.FreeSpace / 1GB))
                Add-KV 'FREE_SPACE_KNOWN' 1
            }
            else {
                Add-KV 'FREE_SPACE_GB' 0
                Add-KV 'FREE_SPACE_KNOWN' 0
            }
        }

        Invoke-Step 'firmware' {
            $fw = [string]$env:firmware_type
            if ([string]::IsNullOrWhiteSpace($fw)) {
                if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State') { $fw = 'UEFI' }
                else { $fw = 'Unknown' }
            }
            Add-KV 'BOOT_MODE' $fw
            $sb = 'Unknown'
            try { if (Confirm-SecureBootUEFI -ErrorAction Stop) { $sb = 'Enabled' } else { $sb = 'Disabled' } }
            catch { $sb = 'Unsupported' }
            Add-KV 'SECURE_BOOT' $sb
        }

        Invoke-Step 'bitlocker' {
            $st = 'NotSupported'
            try {
                $v = Get-BitLockerVolume -MountPoint $script:SysDrive -ErrorAction Stop
                if ([string]$v.ProtectionStatus -eq 'On') { $st = 'Enabled' } else { $st = 'Disabled' }
            }
            catch { $st = 'NotSupported' }
            Add-KV 'BITLOCKER_STATUS' $st
        }

        Invoke-Step 'vbs' {
            $vbs = 'Unknown'; $hvci = 'Unknown'
            try {
                $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
                switch ([int]$dg.VirtualizationBasedSecurityStatus) {
                    0 { $vbs = 'Disabled' }
                    1 { $vbs = 'EnabledNotRunning' }
                    2 { $vbs = 'Running' }
                    default { $vbs = 'Unknown' }
                }
                $svc = @($dg.SecurityServicesRunning)
                if ($svc -contains 2) { $hvci = 'Running' } else { $hvci = 'Off' }
            }
            catch {
                $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
                $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
                if ($p -and $p.Enabled -eq 1) { $hvci = 'Enabled' } else { $hvci = 'Off' }
            }
            Add-KV 'VBS_STATUS' $vbs
            Add-KV 'HVCI_STATUS' $hvci
        }

        Invoke-Step 'defender' {
            $rt = 'Unknown'; $tp = 'Unknown'
            try {
                $s = Get-MpComputerStatus -ErrorAction Stop
                $rt = [int][bool]$s.RealTimeProtectionEnabled
                $tp = [int][bool]$s.IsTamperProtected
            }
            catch { }
            Add-KV 'DEFENDER_RT' $rt
            Add-KV 'DEFENDER_TAMPER' $tp
            $av = 'none'
            try {
                $prods = @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop |
                           Where-Object { $_.displayName -notmatch 'Defender' } |
                           Select-Object -ExpandProperty displayName)
                if ($prods.Count -gt 0) { $av = ($prods -join '; ') }
            }
            catch { }
            Add-KV 'AV_THIRD' $av
        }

        Invoke-Step 'restore' {
            $cnt = 0; $en = 0
            $sr = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -ErrorAction SilentlyContinue
            $disabled = $false
            if ($sr -and $sr.DisableSR -eq 1) { $disabled = $true }
            try {
                $rp = @(Get-ComputerRestorePoint -ErrorAction Stop)
                $cnt = $rp.Count
                if (-not $disabled) { $en = 1 }
            }
            catch { $cnt = 0; $en = 0 }
            Add-KV 'RESTORE_COUNT' $cnt
            Add-KV 'RESTORE_ENABLED' $en
        }

        Invoke-Step 'platform' {
            $chassis = 'Desktop'; $laptop = 0
            $map = @{ 3='Desktop';4='Desktop';5='Desktop';6='Desktop';7='Desktop';
                      8='Laptop';9='Laptop';10='Laptop';11='Laptop';12='Laptop';
                      14='Laptop';18='Laptop';21='Laptop';31='Laptop';32='Laptop';
                      17='Server';23='Server' }
            $enc = @(Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop)
            if ($enc.Count -gt 0) {
                $types = @($enc[0].ChassisTypes)
                if ($types.Count -gt 0) {
                    $t = [int]$types[0]
                    if ($map.ContainsKey($t)) { $chassis = $map[$t] }
                    if ($chassis -eq 'Laptop') { $laptop = 1 }
                }
            }
            $bat = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
            if ($bat.Count -gt 0) { $laptop = 1 }
            $onbat = 0
            try {
                $bs = @(Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryStatus -ErrorAction Stop)
                if ($bs.Count -gt 0 -and -not $bs[0].PowerOnline) { $onbat = 1 }
            }
            catch { }
            Add-KV 'CHASSIS' $chassis
            Add-KV 'IS_LAPTOP' $laptop
            Add-KV 'ON_BATTERY' $onbat
        }

        # --- Кто реально сидит за консолью, для WP_HKCU ---
        Invoke-Step 'user' {
            Add-KV 'CURRENT_SID' ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
            $csid = ''; $cuser = 'Unknown'
            $procs = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop)
            if ($procs.Count -gt 0) {
                $p = $procs | Sort-Object SessionId | Select-Object -First 1
                $o = Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid -ErrorAction Stop
                $csid = [string]$o.Sid
                $ow = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction SilentlyContinue
                if ($ow -and $ow.User) { $cuser = ("{0}\{1}" -f $ow.Domain, $ow.User) }
            }
            Add-KV 'CONSOLE_SID' $csid
            Add-KV 'CONSOLE_USER' $cuser
        }
    }

    # --------------------------------------------------------
    #  get-interfaces <file> - GUID активных адаптеров для Nagle
    #  Аккумулятор $script: : += внутри Invoke-Step создал бы
    #  локальную копию и наружу пришла бы пустота.
    # --------------------------------------------------------
    'get-interfaces' {
        $script:IfList = New-Object 'System.Collections.Generic.List[object]'
        Invoke-Step 'netadapter' {
            $ad = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
            foreach ($a in $ad) {
                $script:IfList.Add([pscustomobject]@{
                    Guid = [string]$a.InterfaceGuid
                    Name = [string]$a.Name
                })
            }
        }
        if ($script:IfList.Count -eq 0) {
            Invoke-Step 'interfaces_fallback' {
                $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
                foreach ($k in (Get-ChildItem -LiteralPath $base -ErrorAction Stop)) {
                    $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                    if (-not $p) { continue }
                    $ip = @($p.IPAddress) | Where-Object { $_ -and $_ -ne '0.0.0.0' }
                    $dhcp = [string]$p.DhcpIPAddress
                    if ($ip.Count -gt 0 -or ($dhcp -and $dhcp -ne '0.0.0.0')) {
                        $script:IfList.Add([pscustomobject]@{
                            Guid = [string]$k.PSChildName
                            Name = 'registry'
                        })
                    }
                }
            }
        }
        Add-KV 'IF_COUNT' $script:IfList.Count
        $i = 0
        foreach ($g in $script:IfList) {
            $i++
            Add-KV "IF_${i}_GUID" $g.Guid
            Add-KV "IF_${i}_NAME" $g.Name
        }
    }

    # --------------------------------------------------------
    #  get-gpuclass <file> - реальные экземпляры адаптеров.
    #  ULPS пишется только AMD, HDCP только NVIDIA.
    #  Слепой 0000 мог оказаться iGPU или другим адаптером.
    # --------------------------------------------------------
    'get-gpuclass' {
        $script:GcList = New-Object 'System.Collections.Generic.List[object]'
        Invoke-Step 'gpuclass' {
            $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
            foreach ($k in (Get-ChildItem -LiteralPath $base -ErrorAction Stop)) {
                if ($k.PSChildName -notmatch '^\d{4}$') { continue }
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                if (-not $p) { continue }
                $desc = [string]$p.DriverDesc
                if ([string]::IsNullOrWhiteSpace($desc)) { continue }
                $ven = 'Unknown'
                $matchId = [string]$p.MatchingDeviceId
                $prov = [string]$p.ProviderName
                if ($matchId -match 'VEN_10DE' -or $prov -match 'NVIDIA') { $ven = 'NVIDIA' }
                elseif ($matchId -match 'VEN_1002' -or $prov -match 'AMD|ATI') { $ven = 'AMD' }
                elseif ($matchId -match 'VEN_8086' -or $prov -match 'Intel') { $ven = 'Intel' }
                $script:GcList.Add([pscustomobject]@{
                    Index  = [string]$k.PSChildName
                    Vendor = $ven
                    Desc   = $desc
                    Key    = "$base\$($k.PSChildName)"
                })
            }
        }
        Add-KV 'GC_COUNT' $script:GcList.Count
        $i = 0
        foreach ($g in $script:GcList) {
            $i++
            Add-KV "GC_${i}_INDEX" $g.Index
            Add-KV "GC_${i}_VENDOR" $g.Vendor
            Add-KV "GC_${i}_DESC" $g.Desc
            Add-KV "GC_${i}_KEY" $g.Key
        }
    }

# [ЧАСТЬ 2/6 ЗАВЕРШЕНА - SWITCH ОСТАЁТСЯ ОТКРЫТЫМ]

    # --------------------------------------------------------
    #  get-detect-api <file> - канал 2, БЕЗ WMI
    #  Только kernel32 P/Invoke, System.IO и реестр.
    #  Работает при убитом репозитории WMI и отключённом StorSvc.
    #  Ключи те же, что у get-detect, плюс *_SOURCE.
    # --------------------------------------------------------
    'get-detect-api' {
        Add-KV 'DETECT_API_OK' 1

        Invoke-Step 'api_os' {
            $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
            $b = 0
            if ($cv.CurrentBuildNumber) { $b = [int]$cv.CurrentBuildNumber }
            elseif ($cv.CurrentBuild) { $b = [int]$cv.CurrentBuild }
            $u = 0
            if ($cv.UBR) { $u = [int]$cv.UBR }
            $fam = 'Windows'
            if ($b -ge 22000) { $fam = 'Windows 11' }
            elseif ($b -ge 10240) { $fam = 'Windows 10' }
            $sup = 0
            if ($b -ge 19045) { $sup = 1 }
            $dv = [string]$cv.DisplayVersion
            if ([string]::IsNullOrWhiteSpace($dv)) { $dv = [string]$cv.ReleaseId }
            if ([string]::IsNullOrWhiteSpace($dv)) { $dv = 'N/A' }
            $edMap = @{
                'Professional' = 'Pro'; 'ProfessionalN' = 'Pro N'
                'Core' = 'Home'; 'CoreN' = 'Home N'; 'CoreSingleLanguage' = 'Home SL'
                'Enterprise' = 'Enterprise'; 'Education' = 'Education'
            }
            $ed = [string]$cv.EditionID
            if ($edMap.ContainsKey($ed)) { $edition = $edMap[$ed] } else { $edition = $ed }
            Add-KV 'WIN_PRODUCT' ([string]$cv.ProductName)
            Add-KV 'WIN_EDITION' $edition
            Add-KV 'WIN_FAMILY' $fam
            Add-KV 'WIN_DISPLAY' $dv
            Add-KV 'WIN_BUILD' $b
            Add-KV 'WIN_UBR' $u
            Add-KV 'WIN_SUPPORTED' $sup
            Add-KV 'OS_SOURCE' 'registry'
            Add-KV 'SYS_DRIVE' $script:SysDrive
            if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State') {
                Add-KV 'BOOT_MODE' 'UEFI'
            }
            $sb = 'Unknown'
            try { if (Confirm-SecureBootUEFI -ErrorAction Stop) { $sb = 'Enabled' } else { $sb = 'Disabled' } }
            catch { $sb = 'Unsupported' }
            Add-KV 'SECURE_BOOT' $sb
        }

        Invoke-Step 'api_ram' {
            $m = New-Object 'WinPulse.Api+MEMORYSTATUSEX'
            $m.dwLength = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf($m)
            if (-not [WinPulse.Api]::GlobalMemoryStatusEx([ref]$m)) { throw 'GlobalMemoryStatusEx failed' }
            Add-KV 'RAM_MB' ([int][math]::Round($m.ullTotalPhys / 1MB))
            Add-KV 'RAM_GB' ([int][math]::Round($m.ullTotalPhys / 1GB))
            Add-KV 'RAM_FREE_MB' ([int][math]::Round($m.ullAvailPhys / 1MB))
            Add-KV 'RAM_SOURCE' 'api'
        }

        Invoke-Step 'api_free' {
            $di = New-Object System.IO.DriveInfo($script:SysDrive)
            if (-not $di.IsReady) { throw 'system drive not ready' }
            Add-KV 'FREE_SPACE_GB' ([int][math]::Floor($di.AvailableFreeSpace / 1GB))
            Add-KV 'FREE_SPACE_KNOWN' 1
            Add-KV 'FREE_SPACE_SOURCE' 'api'
        }

        Invoke-Step 'api_power' {
            $sps = New-Object 'WinPulse.Api+SYSTEM_POWER_STATUS'
            if (-not [WinPulse.Api]::GetSystemPowerStatus([ref]$sps)) { throw 'GetSystemPowerStatus failed' }
            $bat = 0
            if ($sps.BatteryFlag -ne 128 -and $sps.BatteryFlag -ne 255) { $bat = 1 }
            $onbat = 0
            if ($sps.ACLineStatus -eq 0) { $onbat = 1 }
            Add-KV 'BATTERY_PRESENT' $bat
            Add-KV 'ON_BATTERY' $onbat
            Add-KV 'AC_STATUS' ([int]$sps.ACLineStatus)
            Add-KV 'POWER_SOURCE' 'api'
        }

        Invoke-Step 'api_chassis' {
            $c = Get-WpSmbiosChassis
            if ($null -eq $c -or $c -lt 0) { throw 'SMBIOS chassis type unavailable' }
            $map = @{ 3='Desktop';4='Desktop';5='Desktop';6='Desktop';7='Desktop';
                      8='Laptop';9='Laptop';10='Laptop';11='Laptop';12='Laptop';
                      14='Laptop';18='Laptop';21='Laptop';31='Laptop';32='Laptop';
                      17='Server';23='Server' }
            $nm = 'Other'
            if ($map.ContainsKey($c)) { $nm = $map[$c] }
            Add-KV 'CHASSIS' $nm
            Add-KV 'CHASSIS_CODE' $c
            Add-KV 'CHASSIS_SOURCE' 'smbios'
        }

        Invoke-Step 'api_cpu' {
            $p = Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction Stop
            $nm = [string]$p.ProcessorNameString
            $vid = [string]$p.VendorIdentifier
            $ven = 'Unknown'
            if ($vid -match 'Intel' -or $nm -match 'Intel') { $ven = 'Intel' }
            elseif ($vid -match 'AMD' -or $nm -match 'AMD') { $ven = 'AMD' }
            $cores = 0; $threads = 0; $hyb = 0
            $topo = Get-WpCpuTopology
            if ($topo) {
                $cores = [int]$topo.Cores
                $threads = [int]$topo.Threads
                $hyb = [int]$topo.Hybrid
                Add-KV 'CPU_SMT_CORES' ([int]$topo.SmtCores)
                Add-KV 'CPU_TOPO_SOURCE' 'api'
            }
            if ($threads -le 0) {
                $n = @(Get-ChildItem -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor' -ErrorAction SilentlyContinue).Count
                if ($n -gt 0) { $threads = $n }
                elseif ($env:NUMBER_OF_PROCESSORS) { $threads = [int]$env:NUMBER_OF_PROCESSORS }
                Add-KV 'CPU_TOPO_SOURCE' 'registry'
            }
            $cls = Get-CpuClass -Name $nm -Vendor $ven -Cores $cores -Threads $threads
            # Топология по смешанным SMT-ядрам точнее эвристики по имени
            if ($hyb -eq 1) { $cls.Hybrid = 1 }
            Add-KV 'CPU_NAME' $nm
            Add-KV 'CPU_VENDOR' $ven
            Add-KV 'CPU_CORES' $cores
            Add-KV 'CPU_THREADS' $threads
            Add-KV 'CPU_SERIES' ([int]$cls.Series)
            Add-KV 'CPU_GENERATION' ([string]$cls.Bucket)
            Add-KV 'CPU_HYBRID' ([int]$cls.Hybrid)
            Add-KV 'CPU_SOURCE' 'registry+api'
        }

        Invoke-Step 'api_disks' {
            $vol = Get-WpVolumeDisk $script:SysDrive
            $bootNum = -1; $spanned = 0
            if ($vol) {
                $bootNum = [int]$vol.Disk
                if ([int]$vol.Count -gt 1) { $spanned = 1 }
            }
            Add-KV 'BOOT_DISK_NUMBER' $bootNum
            Add-KV 'BOOT_DISK_SPANNED' $spanned

            $limit = 16
            $ec = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\disk\Enum' -ErrorAction SilentlyContinue
            if ($ec -and $ec.Count) { $limit = [int]$ec.Count }
            if ($limit -lt 1) { $limit = 1 }
            if ($limit -gt 32) { $limit = 32 }

            $total = 0; $hdd = 0; $unk = 0
            $parts = @()
            $bType = 'Unknown'; $bName = 'Unknown'; $bBus = 'Unknown'
            for ($d = 0; $d -lt $limit; $d++) {
                $info = Get-WpDiskInfo $d
                if (-not $info) { continue }
                $total++
                $t = 'Unknown'
                if ($null -ne $info.Seek) {
                    if ([int]$info.Seek -eq 0) { $t = 'SSD' } else { $t = 'HDD' }
                }
                $busName = 'Other'
                if ($null -ne $info.Bus) {
                    $busName = Get-BusName $info.Bus
                    if ($t -eq 'Unknown' -and [int]$info.Bus -eq 17) { $t = 'SSD' }
                }
                if ($t -eq 'HDD') { $hdd++ }
                if ($t -eq 'Unknown') { $unk++ }
                $dn = [string]$info.Name
                if ([string]::IsNullOrWhiteSpace($dn)) { $dn = "PhysicalDrive$d" }
                $parts += ("{0} [{1}/{2}]" -f $dn, $t, $busName)
                if ($d -eq $bootNum) {
                    $bName = $dn
                    $bBus = $busName
                    # Том размазан по дискам: тип не приписываем первому попавшемуся
                    if ($spanned -eq 1) { $bType = 'Unknown' } else { $bType = $t }
                }
            }
            $allssd = 0
            if ($total -gt 0 -and $hdd -eq 0 -and $unk -eq 0) { $allssd = 1 }
            Add-KV 'DISK_COUNT' $total
            Add-KV 'HDD_COUNT' $hdd
            Add-KV 'DISK_UNKNOWN' $unk
            Add-KV 'ALL_SSD' $allssd
            Add-KV 'ALL_DISKS' ($parts -join '; ')
            Add-KV 'BOOT_DISK_TYPE' $bType
            Add-KV 'BOOT_DISK_NAME' $bName
            Add-KV 'BOOT_DISK_BUS' $bBus
            Add-KV 'DISK_SOURCE' 'api'
        }

        Invoke-Step 'api_gpu' {
            $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
            $cands = @()
            foreach ($k in (Get-ChildItem -LiteralPath $base -ErrorAction Stop)) {
                if ($k.PSChildName -notmatch '^\d{4}$') { continue }
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                if (-not $p) { continue }
                $desc = [string]$p.DriverDesc
                if ([string]::IsNullOrWhiteSpace($desc)) { continue }
                $mid = [string]$p.MatchingDeviceId
                $prov = [string]$p.ProviderName
                $ven = 'Unknown'
                if ($mid -match 'VEN_10DE' -or $prov -match 'NVIDIA') { $ven = 'NVIDIA' }
                elseif ($mid -match 'VEN_1002' -or $prov -match 'AMD|ATI') { $ven = 'AMD' }
                elseif ($mid -match 'VEN_8086' -or $prov -match 'Intel') { $ven = 'Intel' }
                $rank = 1
                if ($ven -eq 'NVIDIA' -or $ven -eq 'AMD') { $rank = 3 }
                elseif ($ven -eq 'Intel') { $rank = 2 }
                if ($desc -match 'Basic Display') { $rank = 0 }
                $cands += [pscustomobject]@{
                    Index = [string]$k.PSChildName; Desc = $desc; Vendor = $ven
                    Match = $mid; Rank = $rank
                    Drv = [string]$p.DriverVersion; DrvDate = [string]$p.DriverDate
                    Key = "$base\$($k.PSChildName)"
                }
            }
            Add-KV 'GPU_COUNT' $cands.Count
            Add-KV 'GPU_SOURCE' 'registry'
            if ($cands.Count -eq 0) {
                Add-KV 'GPU_NAME' 'Unknown GPU'
                Add-KV 'GPU_VENDOR' 'Unknown'
                Add-KV 'GPU_INSTANCE' ''
                Add-KV 'GPU_HWID' ''
                return
            }
            $g = $cands | Sort-Object Rank -Descending | Select-Object -First 1
            Add-KV 'GPU_NAME' $g.Desc
            Add-KV 'GPU_VENDOR' $g.Vendor
            Add-KV 'GPU_DRIVER' $g.Drv
            Add-KV 'GPU_DRIVER_DATE' $g.DrvDate
            Add-KV 'GPU_CLASSKEY' $g.Key

            # MatchingDeviceId - это и есть ключ устройства в Enum\PCI.
            # Значение Driver связывает его с классом, а не угаданный 0000.
            $hwid = ''; $inst = ''
            try {
                if ($g.Match -like 'PCI\*') {
                    $devPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($g.Match)"
                    $want = "{4d36e968-e325-11ce-bfc1-08002be10318}\$($g.Index)"
                    foreach ($ik in (Get-ChildItem -LiteralPath $devPath -ErrorAction Stop)) {
                        $ip = Get-ItemProperty -LiteralPath $ik.PSPath -ErrorAction SilentlyContinue
                        if ($ip -and [string]$ip.Driver -ieq $want) {
                            $inst = "$($g.Match)\$($ik.PSChildName)"
                            break
                        }
                        if (-not $inst) { $inst = "$($g.Match)\$($ik.PSChildName)" }
                    }
                }
            }
            catch { $script:Failures.Add('gpu_instance') | Out-Null }
            if ($inst) { $hwid = $inst -replace '^PCI\\', '' }
            Add-KV 'GPU_INSTANCE' $inst
            Add-KV 'GPU_HWID' $hwid
        }

        $lap = 0
        foreach ($line in $script:KV) {
            if ($line -eq 'CHASSIS=Laptop') { $lap = 1 }
            if ($line -eq 'BATTERY_PRESENT=1') { $lap = 1 }
        }
        Add-KV 'IS_LAPTOP' $lap
    }

    # --------------------------------------------------------
    #  get-security <file> - гейт MAXIMUM и экран безопасности.
    #  Риски отдаются КОДАМИ, русский текст рисует batch.
    # --------------------------------------------------------
    'get-security' {
        $script:Risks = New-Object 'System.Collections.Generic.List[string]'
        $script:SecRt = 'Unknown'
        $script:SecThird = 'none'
        $script:SecFwOff = 0

        Invoke-Step 'sec_defender' {
            $rt = 'Unknown'; $tp = 'Unknown'; $svc = 'Unknown'; $sig = -1
            try {
                $s = Get-MpComputerStatus -ErrorAction Stop
                $rt = [int][bool]$s.RealTimeProtectionEnabled
                $tp = [int][bool]$s.IsTamperProtected
                $svc = [int][bool]$s.AMServiceEnabled
                $sig = [int]$s.AntivirusSignatureAge
            }
            catch { }
            $script:SecRt = $rt
            Add-KV 'SEC_DEFENDER_RT' $rt
            Add-KV 'SEC_TAMPER' $tp
            Add-KV 'SEC_DEF_SERVICE' $svc
            Add-KV 'SEC_DEF_SIG_AGE' $sig
            if ($sig -ge 0 -and $sig -gt 7) { $script:Risks.Add('DEF_SIG_OLD') | Out-Null }
        }

        Invoke-Step 'sec_av' {
            $avSourceOk = $false
            $names = @()
            try {
                $names = @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop |
                           Where-Object { $_.displayName -notmatch 'Defender' } |
                           Select-Object -ExpandProperty displayName)
                $avSourceOk = $true
            }
            catch { }
            Add-KV 'SEC_AV_SOURCE_OK' ([int]$avSourceOk)
            if ($names.Count -gt 0) { $script:SecThird = ($names -join '; ') }
            Add-KV 'SEC_AV_THIRD' $script:SecThird
        }

        Invoke-Step 'sec_vbs' {
            $vbs = 'Unknown'; $hvci = 'Unknown'; $cg = 'Unknown'
            try {
                $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
                switch ([int]$dg.VirtualizationBasedSecurityStatus) {
                    0 { $vbs = 'Disabled' }
                    1 { $vbs = 'EnabledNotRunning' }
                    2 { $vbs = 'Running' }
                    default { $vbs = 'Unknown' }
                }
                $run = @($dg.SecurityServicesRunning)
                if ($run -contains 2) { $hvci = 'Running' } else { $hvci = 'Off' }
                if ($run -contains 1) { $cg = 'Running' } else { $cg = 'Off' }
            }
            catch {
                $p = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -ErrorAction SilentlyContinue
                if ($p -and $p.Enabled -eq 1) { $hvci = 'Enabled' } else { $hvci = 'Off' }
            }
            Add-KV 'SEC_VBS' $vbs
            Add-KV 'SEC_HVCI' $hvci
            Add-KV 'SEC_CREDENTIAL_GUARD' $cg
        }

        Invoke-Step 'sec_firmware' {
            $sb = 'Unknown'
            try { if (Confirm-SecureBootUEFI -ErrorAction Stop) { $sb = 'Enabled' } else { $sb = 'Disabled' } }
            catch { $sb = 'Unsupported' }
            Add-KV 'SEC_SECUREBOOT' $sb
            if ($sb -eq 'Disabled') { $script:Risks.Add('SECUREBOOT_OFF') | Out-Null }
            $bl = 'NotSupported'
            try {
                $v = Get-BitLockerVolume -MountPoint $script:SysDrive -ErrorAction Stop
                if ([string]$v.ProtectionStatus -eq 'On') { $bl = 'Enabled' } else { $bl = 'Disabled' }
            }
            catch { $bl = 'NotSupported' }
            Add-KV 'SEC_BITLOCKER' $bl
            if ($bl -eq 'Enabled') { $script:Risks.Add('BITLOCKER_ON') | Out-Null }
        }

        Invoke-Step 'sec_firewall' {
            foreach ($f in @(Get-NetFirewallProfile -ErrorAction Stop)) {
                $on = [int][bool]$f.Enabled
                Add-KV ('SEC_FW_' + $f.Name.ToUpperInvariant()) $on
                if ($on -eq 0) { $script:SecFwOff = 1 }
            }
        }

        Invoke-Step 'sec_uac' {
            $lua = -1; $prompt = -1
            $p = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction Stop
            if ($null -ne $p.EnableLUA) { $lua = [int]$p.EnableLUA }
            if ($null -ne $p.ConsentPromptBehaviorAdmin) { $prompt = [int]$p.ConsentPromptBehaviorAdmin }
            Add-KV 'SEC_UAC' $lua
            Add-KV 'SEC_UAC_PROMPT' $prompt
            if ($lua -eq 0) { $script:Risks.Add('UAC_OFF') | Out-Null }
        }

        Invoke-Step 'sec_gpu_driver' {
            $age = -1; $dd = 'Unknown'
            $g = Get-CimInstance Win32_VideoController -ErrorAction Stop |
                 Where-Object { $_.PNPDeviceID -like 'PCI\*' } |
                 Sort-Object { [double]$_.AdapterRAM } -Descending |
                 Select-Object -First 1
            if ($g -and $g.DriverDate) {
                $dt = [datetime]$g.DriverDate
                $dd = $dt.ToString('yyyy-MM-dd')
                $age = [int](New-TimeSpan -Start $dt -End (Get-Date)).TotalDays
            }
            Add-KV 'SEC_GPU_DRIVER_DATE' $dd
            Add-KV 'SEC_GPU_DRIVER_AGE_DAYS' $age
            if ($age -gt 365) { $script:Risks.Add('GPU_DRIVER_OLD') | Out-Null }
        }

        Invoke-Step 'sec_restore' {
            $cnt = 0; $en = 1
            $sr = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -ErrorAction SilentlyContinue
            if ($sr -and $sr.DisableSR -eq 1) { $en = 0; $script:Risks.Add('SR_DISABLED') | Out-Null }
            try { $cnt = @(Get-ComputerRestorePoint -ErrorAction Stop).Count } catch { $cnt = 0 }
            Add-KV 'SEC_RP_COUNT' $cnt
            Add-KV 'SEC_RP_ENABLED' $en
            if ($cnt -eq 0) { $script:Risks.Add('NO_RP') | Out-Null }
        }

        Invoke-Step 'sec_build' {
            $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
            $b = 0
            if ($cv.CurrentBuildNumber) { $b = [int]$cv.CurrentBuildNumber }
            elseif ($cv.CurrentBuild) { $b = [int]$cv.CurrentBuild }
            $sup = 0
            if ($b -ge 19045) { $sup = 1 }
            Add-KV 'SEC_WIN_BUILD' $b
            Add-KV 'SEC_WIN_SUPPORTED' $sup
            if ($sup -eq 0) { $script:Risks.Add('UNSUPPORTED_BUILD') | Out-Null }
        }

        Invoke-Step 'sec_power' {
            $lap = 0; $onbat = 0
            if (@(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue).Count -gt 0) { $lap = 1 }
            try {
                $bs = @(Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryStatus -ErrorAction Stop)
                if ($bs.Count -gt 0 -and -not $bs[0].PowerOnline) { $onbat = 1 }
            }
            catch { }
            Add-KV 'SEC_IS_LAPTOP' $lap
            Add-KV 'SEC_ON_BATTERY' $onbat
            if ($onbat -eq 1) { $script:Risks.Add('ON_BATTERY') | Out-Null }
        }

        $active = 0
        if ($script:SecRt -eq 1) { $active = 1 }
        if ($script:SecThird -ne 'none') { $active = 1 }
        Add-KV 'SEC_AV_ACTIVE' $active
        if ($active -eq 0) { $script:Risks.Add('NO_AV') | Out-Null }
        if ($script:SecFwOff -eq 1) { $script:Risks.Add('FW_OFF') | Out-Null }

        Add-KV 'SEC_RISK_COUNT' $script:Risks.Count
        $ri = 0
        foreach ($r in $script:Risks) {
            $ri++
            Add-KV ('SEC_RISK_' + $ri) $r
        }
    }

# [ЧАСТЬ 3/6 ЗАВЕРШЕНА - SWITCH ОСТАЁТСЯ ОТКРЫТЫМ]

    # --------------------------------------------------------
    #  get-tasks <file> <tasklistfile>
    #  Пути задач приходят из batch: определения твиков живут там.
    #  Get-ScheduledTask, а не парсинг локализованного schtasks.
    # --------------------------------------------------------
    'get-tasks' {
        $script:StI = 0
        Invoke-Step 'tasks_state' {
            if ([string]::IsNullOrWhiteSpace($Arg2)) { throw 'no task list file' }
            if (-not (Test-Path -LiteralPath $Arg2)) { throw 'task list file missing' }
            foreach ($line in (Get-Content -LiteralPath $Arg2 -ErrorAction Stop)) {
                $p = $line.Trim()
                if ([string]::IsNullOrWhiteSpace($p)) { continue }
                $script:StI++
                Add-KV ('ST_TASK_' + $script:StI + '_PATH') $p
                $tp = Split-Path $p -Parent
                $tn = Split-Path $p -Leaf
                # Get-ScheduledTask требует TaskPath с хвостовым слэшем
                if (-not $tp.EndsWith('\')) { $tp = $tp + '\' }
                try {
                    $t = Get-ScheduledTask -TaskPath $tp -TaskName $tn -ErrorAction Stop
                    Add-KV ('ST_TASK_' + $script:StI + '_STATE') ([string]$t.State)
                }
                catch {
                    Add-KV ('ST_TASK_' + $script:StI + '_STATE') 'Absent'
                }
            }
        }
        Add-KV 'ST_TASK_COUNT' $script:StI
    }

    # --------------------------------------------------------
    #  get-boottime <file>
    #  Event 100 = длительность загрузки, 101/102/103 = виновники.
    #  Поля берутся из XML по ИМЕНИ: порядок Data меняется между
    #  сборками, а wevtutil /f:text на русской винде даст кириллицу.
    # --------------------------------------------------------
    'get-boottime' {
        $logName = 'Microsoft-Windows-Diagnostics-Performance/Operational'

        Invoke-Step 'boot_logstate' {
            $li = Get-WinEvent -ListLog $logName -ErrorAction Stop
            Add-KV 'BT_LOG_ENABLED' ([int][bool]$li.IsEnabled)
            Add-KV 'BT_LOG_RECORDS' $li.RecordCount
        }

        $script:BtI = 0
        Invoke-Step 'boot_events' {
            $ev = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Id = 100 } -MaxEvents 10 -ErrorAction Stop)
            foreach ($e in $ev) {
                $script:BtI++
                $d = @{}
                $x = [xml]$e.ToXml()
                foreach ($n in $x.Event.EventData.Data) { $d[[string]$n.Name] = [string]$n.'#text' }
                Add-KV ('BT_' + $script:BtI + '_TIME') $e.TimeCreated.ToString('yyyy-MM-dd HH:mm')
                $total = $d['BootTime']
                if (-not $total) { $total = $d['BootDuration'] }
                Add-KV ('BT_' + $script:BtI + '_TOTAL') $total
                Add-KV ('BT_' + $script:BtI + '_MAIN') $d['MainPathBootTime']
                Add-KV ('BT_' + $script:BtI + '_POST') $d['BootPostBootTime']
                Add-KV ('BT_' + $script:BtI + '_DEGR') $d['BootDegradationDelta']
                if (-not $total -and -not $d['MainPathBootTime']) {
                    Add-KV ('BT_' + $script:BtI + '_NOTE') 'no timing fields in this event'
                }
            }
        }
        Add-KV 'BT_COUNT' $script:BtI

        $script:BaI = 0
        Invoke-Step 'boot_degradation' {
            $ev = @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Id = 101, 102, 103 } -MaxEvents 25 -ErrorAction Stop)
            foreach ($e in $ev) {
                $script:BaI++
                $d = @{}
                $x = [xml]$e.ToXml()
                foreach ($n in $x.Event.EventData.Data) { $d[[string]$n.Name] = [string]$n.'#text' }
                $nm = $d['Name']
                if ([string]::IsNullOrWhiteSpace($nm)) { $nm = $d['FriendlyName'] }
                if ([string]::IsNullOrWhiteSpace($nm)) { $nm = 'unknown' }
                Add-KV ('BA_' + $script:BaI + '_ID') $e.Id
                Add-KV ('BA_' + $script:BaI + '_TIME') $e.TimeCreated.ToString('yyyy-MM-dd HH:mm')
                Add-KV ('BA_' + $script:BaI + '_NAME') $nm
                Add-KV ('BA_' + $script:BaI + '_TOTAL') $d['TotalTime']
                Add-KV ('BA_' + $script:BaI + '_DEGR') $d['DegradationTime']
            }
        }
        Add-KV 'BA_COUNT' $script:BaI
    }

    # --------------------------------------------------------
    #  get-benchmark <file> <workdir> <quick|full>
    #  Все метрики ЦЕЛЫЕ: дробные в PS уезжают в культуру ОС
    #  (1234,5) и set /a в batch на таком молча ломается.
    #  Честные ярлыки: диск write=write-through, read=cached.
    # --------------------------------------------------------
    'get-benchmark' {
        $work = $Arg2
        if ([string]::IsNullOrWhiteSpace($work)) { $work = Join-Path $env:TEMP 'WinPulseBench' }
        $profileName = $Arg3
        if ([string]::IsNullOrWhiteSpace($profileName)) { $profileName = 'quick' }
        $script:BenchStMs = 0
        Add-KV 'BENCH_ENGINE' 'wp.ps1 7.0'
        Add-KV 'BENCH_PROFILE' $profileName
        Add-KV 'BENCH_STAMP' ([datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))
        Add-KV 'BENCH_WORKDIR' $work
        $total = [System.Diagnostics.Stopwatch]::StartNew()

        # --- CPU, один поток. Индекс относительный, не Cinebench ---
        Invoke-Step 'bench_cpu_st' {
            $iter = 1500000
            if ($profileName -eq 'full') { $iter = 3000000 }
            $acc = [double]0
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            for ($i = 1; $i -le $iter; $i++) { $acc += [math]::Sqrt($i) }
            $sw.Stop()
            $script:BenchStMs = [int]$sw.ElapsedMilliseconds
            $sec = [math]::Max($sw.Elapsed.TotalSeconds, 0.001)
            Add-KV 'BENCH_CPU_ST_MS' $script:BenchStMs
            Add-KV 'BENCH_CPU_ST_ITER' $iter
            Add-KV 'BENCH_CPU_ST_SCORE' ([int][math]::Round($iter / $sec / 1000))
            Add-KV 'BENCH_CPU_CHECKSUM' ([int][math]::Round($acc))
        }

        # --- CPU, все потоки. Runspace pool, а НЕ Parallel.For:
        #     ScriptBlock на чужом потоке без Runspace в PS 5.1 падает ---
        Invoke-Step 'bench_cpu_mt' {
            $threads = [int]$env:NUMBER_OF_PROCESSORS
            if ($threads -lt 1) { $threads = 1 }
            if ($threads -gt 16) { $threads = 16 }
            $iter = 1500000
            if ($profileName -eq 'full') { $iter = 3000000 }
            $code = {
                param([int]$N)
                $s = [System.Diagnostics.Stopwatch]::StartNew()
                $a = [double]0
                for ($i = 1; $i -le $N; $i++) { $a += [math]::Sqrt($i) }
                $s.Stop()
                return $s.ElapsedMilliseconds
            }
            $pool = [runspacefactory]::CreateRunspacePool(1, $threads)
            $pool.Open()
            $items = New-Object 'System.Collections.Generic.List[object]'
            try {
                for ($t = 0; $t -lt $threads; $t++) {
                    $ps = [powershell]::Create()
                    $ps.RunspacePool = $pool
                    $null = $ps.AddScript($code).AddArgument($iter)
                    $items.Add([pscustomobject]@{ PS = $ps; H = $ps.BeginInvoke() })
                }
                # Берём максимум внутренних замеров, а не wall time:
                # создание пула не должно попадать в результат CPU
                $max = 0
                foreach ($it in $items) {
                    $res = $it.PS.EndInvoke($it.H)
                    $v = 0
                    if ($res -and $res.Count -gt 0) { $v = [int]$res[0] }
                    if ($v -gt $max) { $max = $v }
                    $it.PS.Dispose()
                }
                Add-KV 'BENCH_CPU_MT_MS' $max
                Add-KV 'BENCH_CPU_MT_THREADS' $threads
                Add-KV 'BENCH_CPU_MT_ITER' ($iter * $threads)
                if ($max -gt 0 -and $script:BenchStMs -gt 0) {
                    Add-KV 'BENCH_CPU_MT_SPEEDUP_PCT' ([int][math]::Round(100 * $script:BenchStMs * $threads / $max))
                }
            }
            finally { $pool.Close(); $pool.Dispose() }
        }

        # --- RAM. Буферы выделены ДО замера, в цикле только копирование.
        #     В 6.x клонировался массив в каждой итерации: мерили аллокации ---
        Invoke-Step 'bench_ram' {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $freeMb = [int]([double]$os.FreePhysicalMemory / 1024)
            $blockMb = 64
            if ($freeMb -lt 1024) { $blockMb = 16 }
            if ($freeMb -lt 256) { $blockMb = 4 }
            $bytes = $blockMb * 1MB
            $loops = 16
            if ($profileName -eq 'full') { $loops = 32 }
            $src = New-Object 'byte[]' $bytes
            $dst = New-Object 'byte[]' $bytes
            for ($i = 0; $i -lt $bytes; $i += 4096) { $src[$i] = 1 }
            [System.Buffer]::BlockCopy($src, 0, $dst, 0, $bytes)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            for ($i = 0; $i -lt $loops; $i++) { [System.Buffer]::BlockCopy($src, 0, $dst, 0, $bytes) }
            $sw.Stop()
            $sec = [math]::Max($sw.Elapsed.TotalSeconds, 0.001)
            Add-KV 'BENCH_RAM_BLOCK_MB' $blockMb
            Add-KV 'BENCH_RAM_LOOPS' $loops
            Add-KV 'BENCH_RAM_MS' ([int]$sw.ElapsedMilliseconds)
            Add-KV 'BENCH_RAM_COPY_MBS' ([int][math]::Round(($blockMb * $loops) / $sec))
            Add-KV 'BENCH_RAM_FREE_MB' $freeMb
            $src = $null; $dst = $null
        }

        # --- Диск. Реальный файл, WriteThrough на запись,
        #     чтение помечено cached и не притворяется CrystalDiskMark ---
        Invoke-Step 'bench_disk' {
            if (-not (Test-Path -LiteralPath $work)) {
                New-Item -ItemType Directory -Path $work -Force | Out-Null
            }
            $qual = Split-Path -Qualifier $work
            $freeGb = 999
            if ($qual) {
                $di = New-Object System.IO.DriveInfo($qual)
                $freeGb = [int][math]::Floor($di.AvailableFreeSpace / 1GB)
            }
            $blockMb = 64
            if ($profileName -eq 'full') { $blockMb = 256 }
            if ($freeGb -lt 4) { $blockMb = 32 }
            if ($freeGb -lt 1) { throw 'not enough free space for disk test' }
            $bytes = $blockMb * 1MB
            $chunk = 1MB
            $buf = New-Object 'byte[]' $bytes
            for ($i = 0; $i -lt $bytes; $i += 4096) { $buf[$i] = 7 }
            $path = Join-Path $work ('bench_' + [guid]::NewGuid().ToString('N') + '.tmp')
            try {
                $swW = [System.Diagnostics.Stopwatch]::StartNew()
                $fsW = New-Object System.IO.FileStream -ArgumentList $path,
                    ([System.IO.FileMode]::Create), ([System.IO.FileAccess]::Write),
                    ([System.IO.FileShare]::None), $chunk, ([System.IO.FileOptions]::WriteThrough)
                try {
                    $off = 0
                    while ($off -lt $bytes) { $fsW.Write($buf, $off, $chunk); $off += $chunk }
                    $fsW.Flush($true)
                }
                finally { $fsW.Dispose() }
                $swW.Stop()
                $secW = [math]::Max($swW.Elapsed.TotalSeconds, 0.001)
                Add-KV 'BENCH_DISK_BLOCK_MB' $blockMb
                Add-KV 'BENCH_DISK_WRITE_MS' ([int]$swW.ElapsedMilliseconds)
                Add-KV 'BENCH_DISK_WRITE_MBS' ([int][math]::Round($blockMb / $secW))
                Add-KV 'BENCH_DISK_WRITE_MODE' 'writethrough'

                $swR = [System.Diagnostics.Stopwatch]::StartNew()
                $fsR = New-Object System.IO.FileStream -ArgumentList $path,
                    ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read),
                    ([System.IO.FileShare]::None), $chunk, ([System.IO.FileOptions]::SequentialScan)
                $readTotal = 0
                try {
                    while (($n = $fsR.Read($buf, 0, $chunk)) -gt 0) { $readTotal += $n }
                }
                finally { $fsR.Dispose() }
                $swR.Stop()
                $secR = [math]::Max($swR.Elapsed.TotalSeconds, 0.001)
                Add-KV 'BENCH_DISK_READ_MS' ([int]$swR.ElapsedMilliseconds)
                Add-KV 'BENCH_DISK_READ_CACHED_MBS' ([int][math]::Round(($readTotal / 1MB) / $secR))
                Add-KV 'BENCH_DISK_READ_MODE' 'cached'
            }
            finally {
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
                }
                $buf = $null
            }
        }

        # --- Сеть. Test-Connection + StatusCode, а не findstr "Average":
        #     на русской винде ping печатает "Среднее", и парсинг пустел ---
        Invoke-Step 'bench_net' {
            $ok = 0
            Add-KV 'BENCH_NET_TARGET' '1.1.1.1'
            try {
                $p = @(Test-Connection -ComputerName '1.1.1.1' -Count 4 -ErrorAction Stop)
                $times = @($p | Where-Object { $_.StatusCode -eq 0 } | ForEach-Object { [int]$_.ResponseTime })
                if ($times.Count -gt 0) {
                    Add-KV 'BENCH_NET_MIN_MS' ([int](($times | Measure-Object -Minimum).Minimum))
                    Add-KV 'BENCH_NET_AVG_MS' ([int][math]::Round((($times | Measure-Object -Average).Average)))
                    Add-KV 'BENCH_NET_MAX_MS' ([int](($times | Measure-Object -Maximum).Maximum))
                    Add-KV 'BENCH_NET_SAMPLES' $times.Count
                    $ok = 1
                }
            }
            catch { }
            Add-KV 'BENCH_NET_OK' $ok
        }

        Invoke-Step 'bench_dns' {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $null = Resolve-DnsName -Name 'example.com' -Type A -DnsOnly -ErrorAction Stop
            $sw.Stop()
            Add-KV 'BENCH_DNS_MS' ([int]$sw.ElapsedMilliseconds)
        }

        $total.Stop()
        Add-KV 'BENCH_DURATION_S' ([int][math]::Round($total.Elapsed.TotalSeconds))
    }

# [ЧАСТЬ 4/6 ЗАВЕРШЕНА - SWITCH ОСТАЁТСЯ ОТКРЫТЫМ]

    # --------------------------------------------------------
    #  get-mmagent <file> - снимок для журнала отката
    # --------------------------------------------------------
    'get-mmagent' {
        $script:MmOk = 0
        Invoke-Step 'mmagent_read' {
            $m = Get-MMAgent -ErrorAction Stop
            Add-KV 'MM_MEMORYCOMPRESSION' ([int][bool]$m.MemoryCompression)
            Add-KV 'MM_PAGECOMBINING' ([int][bool]$m.PageCombining)
            Add-KV 'MM_APPLAUNCHPREFETCHING' ([int][bool]$m.ApplicationLaunchPrefetching)
            Add-KV 'MM_APPLICATIONPRELAUNCH' ([int][bool]$m.ApplicationPreLaunch)
            Add-KV 'MM_OPERATIONAPI' ([int][bool]$m.OperationAPI)
            Add-KV 'MM_MAXOPERATIONAPIFILES' ([int]$m.MaxOperationAPIFiles)
            $script:MmOk = 1
        }
        Add-KV 'MM_AVAILABLE' $script:MmOk
    }

    # --------------------------------------------------------
    #  do-mmagent <file> <feature> <1|0>
    #  1 = включить функцию, 0 = выключить.
    #  MemoryTrim отвергается: такого параметра у MMAgent НЕТ,
    #  в 6.x команда падала, а лог рисовал [OK].
    # --------------------------------------------------------
    'do-mmagent' {
        $script:IsMutating = $true
        $feature = $Arg2.ToLowerInvariant()
        $state = $Arg3
        Add-KV 'MM_FEATURE' $feature
        Add-KV 'MM_REQUESTED' $state
        Add-KV 'MM_APPLIED' 0
        Add-KV 'MM_BEFORE' -1
        Add-KV 'MM_ACTUAL' -1
        Add-KV 'MM_NEED_REBOOT' 0
        Add-KV 'MM_REBOOT_HINT' 0
        Add-KV 'MM_ERROR' ''

        $map = @{
            'memorycompression'    = 'MemoryCompression'
            'pagecombining'        = 'PageCombining'
            'applaunchprefetching' = 'ApplicationLaunchPrefetching'
            'applicationprelaunch' = 'ApplicationPreLaunch'
            'operationapi'         = 'OperationAPI'
        }
        if ($feature -eq 'memorytrim') {
            Add-KV 'MM_ERROR' 'MemoryTrim is not a valid MMAgent parameter'
            $script:Partial = $true
            break
        }
        if (-not $map.ContainsKey($feature)) {
            Add-KV 'MM_ERROR' ('unknown feature: ' + $feature)
            $script:Partial = $true
            break
        }
        if ($state -ne '0' -and $state -ne '1') {
            Add-KV 'MM_ERROR' 'state must be 0 or 1'
            $script:Partial = $true
            break
        }
        $param = $map[$feature]
        try {
            $before = Get-MMAgent -ErrorAction Stop
            Add-KV 'MM_BEFORE' ([int][bool]$before.$param)

            $splat = @{ $param = $true }
            if ($state -eq '1') { Enable-MMAgent @splat -ErrorAction Stop }
            else { Disable-MMAgent @splat -ErrorAction Stop }

            # Успех = фактическое состояние совпало, а не "команда не упала"
            $after = Get-MMAgent -ErrorAction Stop
            $actual = [int][bool]$after.$param
            Add-KV 'MM_ACTUAL' $actual
            if ($actual -eq [int]$state) { Add-KV 'MM_APPLIED' 1 }
            else {
                Add-KV 'MM_APPLIED' 0
                Add-KV 'MM_NEED_REBOOT' 1
            }
            if ($feature -eq 'memorycompression' -or $feature -eq 'pagecombining') {
                Add-KV 'MM_REBOOT_HINT' 1
            }
        }
        catch {
            Add-KV 'MM_ERROR' $_.Exception.Message
            $script:Partial = $true
        }
    }

    # --------------------------------------------------------
    #  get-defender <file>
    #  Исключения поэлементно: batch снимает их в журнал до правок
    #  и возвращает ровно то, что было, а не "включить всё обратно".
    # --------------------------------------------------------
    'get-defender' {
        $script:DefOk = 0
        Invoke-Step 'def_preference' {
            $p = Get-MpPreference -ErrorAction Stop
            $script:DefOk = 1
            $cap = 60

            $paths = @($p.ExclusionPath | Where-Object { $_ })
            Add-KV 'DEF_EXCL_PATH_COUNT' $paths.Count
            $i = 0
            foreach ($v in $paths) {
                if ($i -ge $cap) { break }
                $i++
                Add-KV ('DEF_EXCL_PATH_' + $i) $v
            }
            if ($paths.Count -gt $cap) { Add-KV 'DEF_EXCL_PATH_TRUNCATED' 1 }
            else { Add-KV 'DEF_EXCL_PATH_TRUNCATED' 0 }

            $procs = @($p.ExclusionProcess | Where-Object { $_ })
            Add-KV 'DEF_EXCL_PROC_COUNT' $procs.Count
            $i = 0
            foreach ($v in $procs) {
                if ($i -ge $cap) { break }
                $i++
                Add-KV ('DEF_EXCL_PROC_' + $i) $v
            }
            if ($procs.Count -gt $cap) { Add-KV 'DEF_EXCL_PROC_TRUNCATED' 1 }
            else { Add-KV 'DEF_EXCL_PROC_TRUNCATED' 0 }

            $exts = @($p.ExclusionExtension | Where-Object { $_ })
            Add-KV 'DEF_EXCL_EXT_COUNT' $exts.Count
            $i = 0
            foreach ($v in $exts) {
                if ($i -ge $cap) { break }
                $i++
                Add-KV ('DEF_EXCL_EXT_' + $i) $v
            }

            Add-KV 'DEF_RT_DISABLED' ([int][bool]$p.DisableRealtimeMonitoring)
            Add-KV 'DEF_SCRIPT_DISABLED' ([int][bool]$p.DisableScriptScanning)
            Add-KV 'DEF_BEHAVIOR_DISABLED' ([int][bool]$p.DisableBehaviorMonitoring)
            Add-KV 'DEF_IOAV_DISABLED' ([int][bool]$p.DisableIOAVProtection)
            Add-KV 'DEF_CLOUD_DISABLED' ([int][bool]$p.DisableBlockAtFirstSeen)
            Add-KV 'DEF_PUA' ([int]$p.PUAProtection)
            Add-KV 'DEF_MAPS' ([int]$p.MAPSReporting)
            Add-KV 'DEF_SAMPLES' ([int]$p.SubmitSamplesConsent)
            Add-KV 'DEF_SCAN_CPU' ([int]$p.ScanAvgCPULoadFactor)
        }
        Add-KV 'DEF_AVAILABLE' $script:DefOk

        Invoke-Step 'def_status' {
            $s = Get-MpComputerStatus -ErrorAction Stop
            Add-KV 'DEF_RT_ENABLED' ([int][bool]$s.RealTimeProtectionEnabled)
            Add-KV 'DEF_TAMPER' ([int][bool]$s.IsTamperProtected)
            Add-KV 'DEF_SERVICE' ([int][bool]$s.AMServiceEnabled)
            Add-KV 'DEF_AV_ENABLED' ([int][bool]$s.AntivirusEnabled)
            Add-KV 'DEF_BEHAVIOR_ENABLED' ([int][bool]$s.BehaviorMonitorEnabled)
            Add-KV 'DEF_IOAV_ENABLED' ([int][bool]$s.IoavProtectionEnabled)
            Add-KV 'DEF_NIS_ENABLED' ([int][bool]$s.NISEnabled)
            Add-KV 'DEF_SIG_AGE' ([int]$s.AntivirusSignatureAge)
            Add-KV 'DEF_QUICKSCAN_AGE' ([int]$s.QuickScanAge)
            Add-KV 'DEF_FULLSCAN_AGE' ([int]$s.FullScanAge)
        }
    }

    # --------------------------------------------------------
    #  do-defender <file> <action> <value>
    #  addexclpath | removeexclpath | addexclproc | removeexclproc
    #  rt | script    value 1 = защита ВКЛ, 0 = защита ВЫКЛ
    #  Tamper Protection молча откатывает изменения - называем
    #  причину вслух, а не рисуем зелёную галочку.
    # --------------------------------------------------------
    'do-defender' {
        $script:IsMutating = $true
        $action = $Arg2.ToLowerInvariant()
        $val = $Arg3
        Add-KV 'DEF_ACTION' $action
        Add-KV 'DEF_VALUE' $val
        Add-KV 'DEF_APPLIED' 0
        Add-KV 'DEF_BEFORE' ''
        Add-KV 'DEF_ACTUAL' -1
        Add-KV 'DEF_TAMPER' 'Unknown'
        Add-KV 'DEF_TAMPER_BLOCKED' 0
        Add-KV 'DEF_ERROR' ''

        $pref = $null
        try { $pref = Get-MpPreference -ErrorAction Stop }
        catch {
            Add-KV 'DEF_AVAILABLE' 0
            Add-KV 'DEF_ERROR' ('Defender preference API unavailable: ' + $_.Exception.Message)
            $script:Partial = $true
            break
        }
        Add-KV 'DEF_AVAILABLE' 1
        try {
            $st = Get-MpComputerStatus -ErrorAction Stop
            Add-KV 'DEF_TAMPER' ([int][bool]$st.IsTamperProtected)
        }
        catch { }

        try {
            switch ($action) {
                'addexclpath' {
                    # Defender дописывает хвостовой слэш: сравниваем без него
                    $norm = $val.TrimEnd('\')
                    $had = @($pref.ExclusionPath | Where-Object { $_ -and ([string]$_).TrimEnd('\') -ieq $norm })
                    if ($had.Count -gt 0) { Add-KV 'DEF_BEFORE' 'PRESENT' } else { Add-KV 'DEF_BEFORE' 'ABSENT' }
                    if ($had.Count -eq 0) { Add-MpPreference -ExclusionPath $val -ErrorAction Stop }
                    $now = @(Get-MpPreference -ErrorAction Stop).ExclusionPath
                    $ok = @($now | Where-Object { $_ -and ([string]$_).TrimEnd('\') -ieq $norm })
                    if ($ok.Count -gt 0) { Add-KV 'DEF_APPLIED' 1 }
                }
                'removeexclpath' {
                    $norm = $val.TrimEnd('\')
                    $had = @($pref.ExclusionPath | Where-Object { $_ -and ([string]$_).TrimEnd('\') -ieq $norm })
                    if ($had.Count -gt 0) { Add-KV 'DEF_BEFORE' 'PRESENT' } else { Add-KV 'DEF_BEFORE' 'ABSENT' }
                    if ($had.Count -gt 0) { Remove-MpPreference -ExclusionPath $val -ErrorAction Stop }
                    $now = @(Get-MpPreference -ErrorAction Stop).ExclusionPath
                    $ok = @($now | Where-Object { $_ -and ([string]$_).TrimEnd('\') -ieq $norm })
                    if ($ok.Count -eq 0) { Add-KV 'DEF_APPLIED' 1 }
                }
                'addexclproc' {
                    $had = @($pref.ExclusionProcess | Where-Object { $_ -and ([string]$_) -ieq $val })
                    if ($had.Count -gt 0) { Add-KV 'DEF_BEFORE' 'PRESENT' } else { Add-KV 'DEF_BEFORE' 'ABSENT' }
                    if ($had.Count -eq 0) { Add-MpPreference -ExclusionProcess $val -ErrorAction Stop }
                    $now = @(Get-MpPreference -ErrorAction Stop).ExclusionProcess
                    $ok = @($now | Where-Object { $_ -and ([string]$_) -ieq $val })
                    if ($ok.Count -gt 0) { Add-KV 'DEF_APPLIED' 1 }
                }
                'removeexclproc' {
                    $had = @($pref.ExclusionProcess | Where-Object { $_ -and ([string]$_) -ieq $val })
                    if ($had.Count -gt 0) { Add-KV 'DEF_BEFORE' 'PRESENT' } else { Add-KV 'DEF_BEFORE' 'ABSENT' }
                    if ($had.Count -gt 0) { Remove-MpPreference -ExclusionProcess $val -ErrorAction Stop }
                    $now = @(Get-MpPreference -ErrorAction Stop).ExclusionProcess
                    $ok = @($now | Where-Object { $_ -and ([string]$_) -ieq $val })
                    if ($ok.Count -eq 0) { Add-KV 'DEF_APPLIED' 1 }
                }
                'rt' {
                    if ($val -ne '0' -and $val -ne '1') { throw 'rt value must be 0 or 1' }
                    $want = [int]$val
                    Add-KV 'DEF_BEFORE' ([int][bool]$pref.DisableRealtimeMonitoring)
                    $disable = $false
                    if ($want -eq 0) { $disable = $true }
                    Set-MpPreference -DisableRealtimeMonitoring $disable -ErrorAction Stop
                    $actual = 0
                    try {
                        $s2 = Get-MpComputerStatus -ErrorAction Stop
                        $actual = [int][bool]$s2.RealTimeProtectionEnabled
                        Add-KV 'DEF_TAMPER' ([int][bool]$s2.IsTamperProtected)
                    }
                    catch { }
                    Add-KV 'DEF_ACTUAL' $actual
                    if ($actual -eq $want) { Add-KV 'DEF_APPLIED' 1 }
                }
                'script' {
                    if ($val -ne '0' -and $val -ne '1') { throw 'script value must be 0 or 1' }
                    $want = [int]$val
                    Add-KV 'DEF_BEFORE' ([int][bool]$pref.DisableScriptScanning)
                    $disable = $false
                    if ($want -eq 0) { $disable = $true }
                    Set-MpPreference -DisableScriptScanning $disable -ErrorAction Stop
                    $p2 = Get-MpPreference -ErrorAction Stop
                    $actual = 1 - [int][bool]$p2.DisableScriptScanning
                    Add-KV 'DEF_ACTUAL' $actual
                    if ($actual -eq $want) { Add-KV 'DEF_APPLIED' 1 }
                }
                default { throw ('unknown action: ' + $action) }
            }
        }
        catch {
            Add-KV 'DEF_ERROR' $_.Exception.Message
            $script:Partial = $true
        }

        $applied = $false
        $tamper = $false
        foreach ($line in $script:KV) {
            if ($line -eq 'DEF_APPLIED=1') { $applied = $true }
            if ($line -eq 'DEF_TAMPER=1') { $tamper = $true }
        }
        if (-not $applied) {
            if ($tamper) {
                Add-KV 'DEF_TAMPER_BLOCKED' 1
                Add-KV 'DEF_ERROR' 'blocked by Tamper Protection - disable it manually in Windows Security'
            }
            $script:Partial = $true
        }
    }

# [ЧАСТЬ 5/6 ЗАВЕРШЕНА - SWITCH ОСТАЁТСЯ ОТКРЫТЫМ]

    # --------------------------------------------------------
    #  get-restorepoints <file>
    #  Выбор точки не автоматизируем: rstrui делает это сам.
    # --------------------------------------------------------
    'get-restorepoints' {
        $script:RpN = 0
        Invoke-Step 'restorepoints' {
            $rp = @(Get-ComputerRestorePoint -ErrorAction Stop) | Sort-Object SequenceNumber -Descending
            foreach ($r in $rp) {
                $script:RpN++
                $dt = [string]$r.CreationTime
                try {
                    $dt = [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$r.CreationTime).ToString('yyyy-MM-dd HH:mm:ss')
                }
                catch { }
                Add-KV ('RP_' + $script:RpN + '_SEQ') $r.SequenceNumber
                Add-KV ('RP_' + $script:RpN + '_DATE') $dt
                Add-KV ('RP_' + $script:RpN + '_DESC') $r.Description
                Add-KV ('RP_' + $script:RpN + '_TYPE') $r.RestorePointType
            }
        }
        Add-KV 'RP_COUNT' $script:RpN
        $sr = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -ErrorAction SilentlyContinue
        if ($sr -and $sr.DisableSR -eq 1) { Add-KV 'RP_SR_DISABLED' 1 } else { Add-KV 'RP_SR_DISABLED' 0 }
    }

    # --------------------------------------------------------
    #  do-restorepoint <file> <description>
    #  Службы и SystemRestorePointCreationFrequency НЕ меняет:
    #  это делает batch через обёртки, чтобы попало в журнал.
    #  Успех = точка с нашим описанием реально найдена,
    #  а не "Checkpoint-Computer не бросил исключение".
    # --------------------------------------------------------
    'do-restorepoint' {
        $script:IsMutating = $true
        $desc = $Arg2
        if ([string]::IsNullOrWhiteSpace($desc)) {
            $desc = 'WinPulse ' + [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
        }
        Add-KV 'RP_DESC' $desc
        Add-KV 'RP_CREATED' 0
        Add-KV 'RP_SEQ' ''
        Add-KV 'RP_REASON' ''
        Add-KV 'RP_NEEDS_VSS' 0
        Add-KV 'RP_BLOCKED_POLICY' 0

        $pol = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' -ErrorAction SilentlyContinue
        if ($pol -and ($pol.DisableSR -eq 1 -or $pol.DisableConfig -eq 1)) {
            Add-KV 'RP_BLOCKED_POLICY' 1
            Add-KV 'RP_REASON' 'System Restore is disabled by group policy'
            $script:Partial = $true
            break
        }

        foreach ($svc in @('VSS', 'swprv')) {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s) {
                Add-KV ('RP_SVC_' + $svc.ToUpperInvariant()) ([string]$s.StartType)
                if ([string]$s.StartType -eq 'Disabled') { Add-KV 'RP_NEEDS_VSS' 1 }
            }
            else { Add-KV ('RP_SVC_' + $svc.ToUpperInvariant()) 'Absent' }
        }

        $before = 0
        try { $before = @(Get-ComputerRestorePoint -ErrorAction Stop).Count } catch { $before = 0 }
        Add-KV 'RP_COUNT_BEFORE' $before

        try {
            Enable-ComputerRestore -Drive ($script:SysDrive + '\') -ErrorAction Stop
            Add-KV 'RP_DRIVE_ENABLED' 1
        }
        catch {
            Add-KV 'RP_DRIVE_ENABLED' 0
            Add-KV 'RP_ENABLE_ERROR' $_.Exception.Message
        }

        $cpErr = ''
        try {
            Checkpoint-Computer -Description $desc -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        }
        catch { $cpErr = $_.Exception.Message }
        Add-KV 'RP_CHECKPOINT_ERROR' $cpErr

        $after = 0; $seq = ''; $found = $false
        try {
            $rp = @(Get-ComputerRestorePoint -ErrorAction Stop)
            $after = $rp.Count
            $mine = $rp | Where-Object { $_.Description -eq $desc } | Select-Object -Last 1
            if ($mine) { $found = $true; $seq = [string]$mine.SequenceNumber }
        }
        catch { }
        Add-KV 'RP_COUNT_AFTER' $after
        Add-KV 'RP_SEQ' $seq

        if ($found) {
            Add-KV 'RP_CREATED' 1
        }
        else {
            if ([string]::IsNullOrWhiteSpace($cpErr)) {
                $cpErr = 'checkpoint reported no error but no matching restore point exists'
            }
            Add-KV 'RP_REASON' $cpErr
            $script:Partial = $true
        }
    }

    # --------------------------------------------------------
    #  do-regacl <file> <key> <value> <type> <data>
    #  Ветки под TrustedInstaller: Enum\PCI (MSI),
    #  WindowsRuntime\ActivatableClassId (GameBar).
    #  type=DELETE удаляет значение: нужно для отката созданного.
    #  Владелец и ACE возвращаются в finally при ЛЮБОМ исходе.
    # --------------------------------------------------------
    'do-regacl' {
        $script:IsMutating = $true
        $rKey = $Arg2; $rVal = $Arg3; $rType = $Arg4; $rData = $Arg5
        Add-KV 'REGACL_KEY' $rKey
        Add-KV 'REGACL_VALUE' $rVal
        Add-KV 'REGACL_WRITTEN' 0
        Add-KV 'REGACL_DELETED' 0
        Add-KV 'REGACL_OWNER_BEFORE' ''
        Add-KV 'REGACL_OWNER_RESTORED' 0
        Add-KV 'REGACL_ACL_RESTORED' 0
        Add-KV 'REGACL_CREATED_KEYS' 0
        Add-KV 'REGACL_READBACK' ''

        $base = $null; $anchorKey = $null; $writeKey = $null
        $oldOwner = $null; $rule = $null; $anchor = $null
        try {
            if ([string]::IsNullOrWhiteSpace($rKey)) { throw 'empty key' }
            $privOk = Enable-WpPrivilege @('SeTakeOwnershipPrivilege', 'SeRestorePrivilege', 'SeBackupPrivilege')
            Add-KV 'REGACL_PRIVILEGES' ([int]$privOk)

            $conv = Convert-WpRegData -Type $rType -Data $rData
            $parts = Split-WpRegPath -Path $rKey
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($parts.Hive, [Microsoft.Win32.RegistryView]::Registry64)

            # Ближайший существующий предок плюс список отсутствующих подключей
            $missing = New-Object 'System.Collections.Generic.List[string]'
            $probe = $parts.Sub
            while ($true) {
                $k = $base.OpenSubKey($probe)
                if ($null -ne $k) { $k.Close(); break }
                $idx = $probe.LastIndexOf('\')
                if ($idx -lt 1) { throw "no existing ancestor for $($parts.Sub)" }
                $missing.Insert(0, $probe.Substring($idx + 1))
                $probe = $probe.Substring(0, $idx)
            }
            $anchor = $probe
            Add-KV 'REGACL_ANCHOR' $anchor
            Add-KV 'REGACL_CREATED_KEYS' $missing.Count

            $need = [System.Security.AccessControl.RegistryRights]::TakeOwnership -bor `
                    [System.Security.AccessControl.RegistryRights]::ChangePermissions
            $anchorKey = $base.OpenSubKey($anchor, $need)
            if ($null -eq $anchorKey) { throw "cannot open anchor with TakeOwnership: $anchor" }

            $acl = $anchorKey.GetAccessControl()
            $oldOwner = $acl.Owner
            Add-KV 'REGACL_OWNER_BEFORE' $oldOwner
            $adminSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
            $acl.SetOwner($adminSid)
            $anchorKey.SetAccessControl($acl)

            $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                $adminSid,
                [System.Security.AccessControl.RegistryRights]::FullControl,
                ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor `
                 [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
                [System.Security.AccessControl.PropagationFlags]::None,
                [System.Security.AccessControl.AccessControlType]::Allow)
            $acl2 = $anchorKey.GetAccessControl()
            $acl2.AddAccessRule($rule)
            $anchorKey.SetAccessControl($acl2)
            $anchorKey.Close(); $anchorKey = $null

            $writeKey = $base.OpenSubKey($anchor, $true)
            if ($null -eq $writeKey) { throw "anchor not writable after ACL change: $anchor" }
            foreach ($seg in $missing) {
                $next = $writeKey.CreateSubKey($seg)
                $writeKey.Close()
                $writeKey = $next
            }
            if ($rType.ToUpperInvariant() -eq 'DELETE') {
                $writeKey.DeleteValue($rVal, $false)
                $rb = ''
                Add-KV 'REGACL_DELETED' 1
            }
            else {
                $writeKey.SetValue($rVal, $conv.Value, $conv.Kind)
                $rb = Format-WpRegReadback ($writeKey.GetValue($rVal, $null))
            }
            $writeKey.Close(); $writeKey = $null
            Add-KV 'REGACL_READBACK' $rb
            Add-KV 'REGACL_WRITTEN' 1
        }
        catch {
            Add-KV 'REGACL_ERROR' $_.Exception.Message
            $script:Partial = $true
        }
        finally {
            if ($null -ne $writeKey) { $writeKey.Close() }
            if ($null -ne $anchor -and $null -ne $base) {
                try {
                    $need2 = [System.Security.AccessControl.RegistryRights]::TakeOwnership -bor `
                             [System.Security.AccessControl.RegistryRights]::ChangePermissions
                    $anchorKey = $base.OpenSubKey($anchor, $need2)
                    if ($null -ne $anchorKey) {
                        if ($null -ne $rule) {
                            $acl3 = $anchorKey.GetAccessControl()
                            $null = $acl3.RemoveAccessRule($rule)
                            $anchorKey.SetAccessControl($acl3)
                            Add-KV 'REGACL_ACL_RESTORED' 1
                        }
                        if ($oldOwner) {
                            $acl4 = $anchorKey.GetAccessControl()
                            $acl4.SetOwner((New-Object System.Security.Principal.NTAccount($oldOwner)))
                            $anchorKey.SetAccessControl($acl4)
                            Add-KV 'REGACL_OWNER_RESTORED' 1
                        }
                        $anchorKey.Close()
                    }
                }
                catch { Add-KV 'REGACL_RESTORE_ERROR' $_.Exception.Message }
            }
            if ($null -ne $base) { $base.Close() }
        }
    }

    # --------------------------------------------------------
    #  do-appx <file> <selective|full> <target SID>
    #  selective = 6 паттернов, full = 13 (включая Widgets).
    #  Удаляем ТОЛЬКО для целевого пользователя, provisioned
    #  не трогаем: поэтому переустановка реальна.
    #  Результат по каждому паттерну: batch считает 6 или 13
    #  операций, а не одну кашу.
    # --------------------------------------------------------
    'do-appx' {
        $script:IsMutating = $true
        $mode = $Arg2.ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($mode)) { $mode = 'selective' }
        $sid = $Arg3
        $patterns = @('*CandyCrush*', '*TikTok*', '*Facebook*', '*Twitter*', '*Disney*', '*BubbleWitch*')
        if ($mode -eq 'full') {
            $patterns += @('*Spotify*', '*BingWeather*', '*BingNews*', '*BingSports*',
                           '*BingFinance*', '*Microsoft.BingSearch*', '*Windows.Client.WebExperience*')
        }
        Add-KV 'APPX_MODE' $mode
        Add-KV 'APPX_TARGET_SID' $sid
        Add-KV 'APPX_PATTERNS' $patterns.Count
        Add-KV 'APPX_IRREVERSIBLE' 1
        if ($mode -eq 'full') { Add-KV 'APPX_RISK_SEARCH' 1 } else { Add-KV 'APPX_RISK_SEARCH' 0 }

        $found = 0; $removed = 0; $failed = 0; $skipped = 0; $listed = 0
        $cap = 40
        $lastErr = ''
        $pi = 0
        foreach ($p in $patterns) {
            $pi++
            $pFound = 0; $pRemoved = 0; $pFailed = 0; $pSkipped = 0
            $pkgs = @()
            try { $pkgs = @(Get-AppxPackage -AllUsers -Name $p -ErrorAction Stop) }
            catch {
                try { $pkgs = @(Get-AppxPackage -Name $p -ErrorAction Stop) }
                catch { $pkgs = @() }
            }
            foreach ($k in $pkgs) {
                $found++; $pFound++
                $full = [string]$k.PackageFullName
                if ([string]::IsNullOrWhiteSpace($full)) { $skipped++; $pSkipped++; continue }

                # Установлен ли для этого SID: проверяем состояние,
                # а не парсим локализованный текст ошибки удаления
                if ($sid -and $k.PackageUserInformation) {
                    $ui = @($k.PackageUserInformation | Where-Object { [string]$_.UserSecurityIdentifier -eq $sid })
                    if ($ui.Count -eq 0) { $skipped++; $pSkipped++; continue }
                    if ([string]$ui[0].InstallState -ne 'Installed') { $skipped++; $pSkipped++; continue }
                }

                try {
                    if ($sid) { Remove-AppxPackage -Package $full -User $sid -ErrorAction Stop }
                    else { Remove-AppxPackage -Package $full -ErrorAction Stop }
                    $removed++; $pRemoved++
                    if ($listed -lt $cap) {
                        $listed++
                        Add-KV ('APPX_PKG_' + $listed + '_NAME') $full
                        Add-KV ('APPX_PKG_' + $listed + '_FAMILY') ([string]$k.PackageFamilyName)
                        Add-KV ('APPX_PKG_' + $listed + '_LOC') ([string]$k.InstallLocation)
                    }
                }
                catch {
                    $failed++; $pFailed++
                    $lastErr = [string]$_.Exception.Message
                }
            }
            Add-KV ('APPX_P' + $pi + '_PATTERN') $p
            Add-KV ('APPX_P' + $pi + '_FOUND') $pFound
            Add-KV ('APPX_P' + $pi + '_REMOVED') $pRemoved
            Add-KV ('APPX_P' + $pi + '_FAILED') $pFailed
            Add-KV ('APPX_P' + $pi + '_SKIPPED') $pSkipped
        }
        Add-KV 'APPX_FOUND' $found
        Add-KV 'APPX_REMOVED' $removed
        Add-KV 'APPX_FAILED' $failed
        Add-KV 'APPX_SKIPPED' $skipped
        Add-KV 'APPX_LISTED' $listed
        if ($removed -gt $cap) { Add-KV 'APPX_LIST_TRUNCATED' 1 } else { Add-KV 'APPX_LIST_TRUNCATED' 0 }
        Add-KV 'APPX_LAST_ERROR' $lastErr
        Add-KV 'APPX_REINSTALL_HINT' 'Add-AppxPackage -Register {InstallLocation}\AppxManifest.xml -DisableDevelopmentMode'
        if ($failed -gt 0) { $script:Partial = $true }
    }

    # --------------------------------------------------------
    default {
        Add-KV 'ENGINE_ERROR' 'unknown verb'
        Add-KV 'ENGINE_VERB' $Verb
        if ($Arg1) { Write-KV $Arg1 }
        exit 9009
    }
}

# ============================================================
#  ФИНАЛИЗАЦИЯ: файл результата и код возврата
#  get-* при частичном провале -> 2, do-* -> 1.
#  Batch различает: 2 = работаем с остатком, 1 = мутация не удалась.
# ============================================================
if ($script:Failures.Count -gt 0) {
    Add-KV 'PS_FAILURES' ($script:Failures -join ';')
}
else { Add-KV 'PS_FAILURES' '' }

if ($Verb -like 'do-*') { $script:IsMutating = $true }
if ($Arg1) { Write-KV $Arg1 }

if ($script:Partial) {
    if ($script:IsMutating) { exit 1 }
    exit 2
}
exit 0

# END OF FILE | Всего твиков в файле: 0
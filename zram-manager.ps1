# zram-manager for Windows
# Windows has no native zRAM or vm.swappiness. This script manages
# Memory Compression and the Windows page file instead.

[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$Auto,
    [switch]$EnableCompression,
    [switch]$DisableCompression,
    [switch]$PageFileAutomatic,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SizeString([UInt64]$Bytes) {
    if ($Bytes -ge 1TB) { return ('{0:N1} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

function Get-MemoryCompressionState {
    try {
        $agent = Get-MMAgent
        return [bool]$agent.MemoryCompression
    } catch {
        return $null
    }
}

function Show-Status {
    $os = Get-CimInstance Win32_OperatingSystem
    $computer = Get-CimInstance Win32_ComputerSystem
    $pageFiles = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
    $total = [UInt64]$computer.TotalPhysicalMemory
    $free = [UInt64]$os.FreePhysicalMemory * 1KB
    $used = $total - $free
    $percent = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 0) } else { 0 }
    $compression = Get-MemoryCompressionState

    Write-Host ''
    Write-Host '=== ZRAM MANAGER - WINDOWS ===' -ForegroundColor Cyan
    Write-Host 'Windows equivalent: Memory Compression + page file'
    Write-Host ''
    Write-Host ('RAM       {0} used / {1} total ({2}%)' -f (Get-SizeString $used), (Get-SizeString $total), $percent)
    Write-Host ('Available {0}' -f (Get-SizeString $free))
    Write-Host ('Memory Compression: {0}' -f $(if ($null -eq $compression) { 'unavailable' } elseif ($compression) { 'enabled' } else { 'disabled' }))
    Write-Host ('Automatic page file: {0}' -f $computer.AutomaticManagedPagefile)
    if ($pageFiles.Count -gt 0) {
        Write-Host 'Page files:'
        foreach ($pageFile in $pageFiles) {
            Write-Host ('  {0}: {1} used / {2} allocated' -f $pageFile.Name, (Get-SizeString ([UInt64]$pageFile.CurrentUsage * 1MB)), (Get-SizeString ([UInt64]$pageFile.AllocatedBaseSize * 1MB)))
        }
    } else {
        Write-Host 'Page files: none detected' -ForegroundColor Yellow
    }
    Write-Host ''
}

function Set-MemoryCompression([bool]$Enabled) {
    if ($Enabled) {
        Enable-MMAgent -MemoryCompression
        Write-Host '[OK] Windows Memory Compression enabled.' -ForegroundColor Green
    } else {
        Disable-MMAgent -MemoryCompression
        Write-Host '[OK] Windows Memory Compression disabled.' -ForegroundColor Green
    }
}

function Set-AutomaticPageFile {
    $computer = Get-CimInstance Win32_ComputerSystem
    if (-not $computer.AutomaticManagedPagefile) {
        Set-CimInstance -InputObject $computer -Property @{ AutomaticManagedPagefile = $true } | Out-Null
    }
    Write-Host '[OK] Windows automatic page-file management enabled.' -ForegroundColor Green
    Write-Host 'A restart may be required before every page-file change takes effect.' -ForegroundColor Yellow
}

function Show-Help {
    @'
Usage: .\zram-manager.ps1 [option]

  -Status                 Show RAM, Memory Compression, and page-file status
  -Auto                   Enable Memory Compression and automatic page-file sizing
  -EnableCompression      Enable Windows Memory Compression
  -DisableCompression     Disable Windows Memory Compression
  -PageFileAutomatic      Enable automatic Windows page-file management
  -Help                   Show this help

Windows does not provide zRAM, vm.swappiness, or Linux compression algorithms.
Use this script as the Windows equivalent, or run the Bash version in WSL for Linux zRAM.
'@
}

if ($Help) {
    Show-Help
    exit 0
}

if (-not (Test-Administrator)) {
    Write-Error 'Please run PowerShell as Administrator.'
    exit 1
}

if ($Auto) {
    Set-MemoryCompression $true
    Set-AutomaticPageFile
    Show-Status
    exit 0
}

if ($EnableCompression) {
    Set-MemoryCompression $true
    exit 0
}

if ($DisableCompression) {
    Set-MemoryCompression $false
    exit 0
}

if ($PageFileAutomatic) {
    Set-AutomaticPageFile
    exit 0
}

Show-Status

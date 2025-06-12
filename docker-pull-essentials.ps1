#Requires -Version 7.0
<#
.SYNOPSIS
    PowerShell wrapper for docker-pull-essentials.sh
    
.DESCRIPTION
    This script provides a PowerShell interface to run the docker-pull-essentials.sh
    bash script on Windows with WSL2 or when PowerShell is the preferred shell.
    
.PARAMETER DryRun
    Show what would be pulled without actually pulling
    
.PARAMETER Parallel
    Number of parallel pulls (default: 4)
    
.PARAMETER Retry
    Number of retry attempts per image (default: 2)
    
.PARAMETER Timeout
    Timeout for each pull in seconds (default: 300)
    
.PARAMETER SkipAI
    Skip AI/ML model pulls
    
.PARAMETER SkipWindows
    Skip Windows-specific images
    
.PARAMETER LogFile
    Log output to file (default: docker-pull.log)
    
.PARAMETER UseWSL
    Force execution in WSL2 (auto-detected by default)
    
.EXAMPLE
    .\docker-pull-essentials.ps1
    Pulls all images with default settings
    
.EXAMPLE
    .\docker-pull-essentials.ps1 -DryRun
    Shows what would be pulled without actually pulling
    
.EXAMPLE
    .\docker-pull-essentials.ps1 -Parallel 8 -SkipAI
    Uses 8 parallel workers and skips AI/ML models
    
.NOTES
    Version: 1.1.0
    Author: Generated for Ubuntu Dev Environment
    Last Updated: 2025-06-11
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [int]$Parallel = 4,
    [int]$Retry = 2,
    [int]$Timeout = 300,
    [switch]$SkipAI,
    [switch]$SkipWindows,
    [string]$LogFile = "docker-pull.log",
    [switch]$UseWSL,
    [switch]$Help
)

# Script metadata
$script:ScriptName = $MyInvocation.MyCommand.Name
$script:ScriptVersion = "1.1.0"
$script:LogPrefix = "[$ScriptName]"

# Logging functions
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp $script:LogPrefix $Level`: $Message"
    
    switch ($Level) {
        "ERROR" { Write-Error $logMessage }
        "WARN"  { Write-Warning $logMessage }
        "DEBUG" { if ($VerbosePreference -eq "Continue") { Write-Verbose $logMessage } }
        default { Write-Host $logMessage }
    }
    
    # Also write to log file
    Add-Content -Path $LogFile -Value $logMessage -ErrorAction SilentlyContinue
}

function Show-Help {
    Get-Help $MyInvocation.MyCommand.Path -Full
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..."
    
    # Check if Docker is available
    try {
        $dockerVersion = docker --version 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Docker command failed"
        }
        Write-Log "Docker found: $dockerVersion"
    }
    catch {
        Write-Log "Docker is not installed or not accessible" -Level "ERROR"
        Write-Log "Please install Docker Desktop or ensure Docker is in your PATH" -Level "ERROR"
        exit 2
    }
    
    # Check Docker daemon
    try {
        docker info >$null 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Docker daemon not accessible"
        }
        Write-Log "Docker daemon is running"
    }
    catch {
        Write-Log "Docker daemon is not running or not accessible" -Level "ERROR"
        Write-Log "Please start Docker Desktop or Docker service" -Level "ERROR"
        exit 2
    }
    
    # Detect environment
    $script:IsWSL = $false
    if ($env:WSL_DISTRO_NAME -or (Get-Command wsl -ErrorAction SilentlyContinue)) {
        $script:IsWSL = $true
        Write-Log "WSL environment detected"
    }
    else {
        Write-Log "Native Windows environment detected"
    }
}

function ConvertTo-BashArgs {
    $bashArgs = @()
    
    if ($DryRun) { $bashArgs += "--dry-run" }
    if ($SkipAI) { $bashArgs += "--skip-ai" }
    if ($SkipWindows) { $bashArgs += "--skip-windows" }
    
    $bashArgs += "--parallel", $Parallel
    $bashArgs += "--retry", $Retry
    $bashArgs += "--timeout", $Timeout
    $bashArgs += "--log-file", $LogFile
    
    return $bashArgs
}

function Invoke-BashScript {
    param([string[]]$Arguments)
    
    $bashScript = "docker-pull-essentials.sh"
    $bashScriptPath = Join-Path $PSScriptRoot $bashScript
    
    # Check if bash script exists
    if (-not (Test-Path $bashScriptPath)) {
        Write-Log "Bash script not found: $bashScriptPath" -Level "ERROR"
        Write-Log "Please ensure docker-pull-essentials.sh is in the same directory" -Level "ERROR"
        exit 1
    }
    
    # Convert to Unix line endings if needed
    $content = Get-Content $bashScriptPath -Raw
    if ($content -match "`r`n") {
        Write-Log "Converting line endings to Unix format..."
        $content = $content -replace "`r`n", "`n"
        Set-Content $bashScriptPath -Value $content -NoNewline
    }
    
    # Make script executable in WSL
    if ($script:IsWSL -or $UseWSL) {
        Write-Log "Executing via WSL..."
        $wslPath = $bashScriptPath -replace '\\', '/' -replace '^([A-Za-z]):', '/mnt/$1'
        $wslArgs = $Arguments -join ' '
        $command = "wsl bash `"$wslPath`" $wslArgs"
    }
    else {
        # Try to run with bash on Windows (Git Bash, MSYS2, etc.)
        if (Get-Command bash -ErrorAction SilentlyContinue) {
            Write-Log "Executing with bash..."
            $bashArgs = @($bashScriptPath) + $Arguments
            $command = "bash"
            $commandArgs = $bashArgs
        }
        else {
            Write-Log "Bash not found. Please install Git Bash, MSYS2, or use WSL2" -Level "ERROR"
            exit 127
        }
    }
    
    try {
        if ($script:IsWSL -or $UseWSL) {
            Invoke-Expression $command
        }
        else {
            & $command @commandArgs
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Script execution failed with exit code: $LASTEXITCODE" -Level "ERROR"
            exit $LASTEXITCODE
        }
    }
    catch {
        Write-Log "Failed to execute bash script: $_" -Level "ERROR"
        exit 1
    }
}

function Main {
    if ($Help) {
        Show-Help
        return
    }
    
    Write-Log "Starting Docker pull script (v$script:ScriptVersion)"
    Write-Log "PowerShell version: $($PSVersionTable.PSVersion)"
    
    # Run prerequisites check
    Test-Prerequisites
    
    # Convert PowerShell parameters to bash arguments
    $bashArgs = ConvertTo-BashArgs
    
    Write-Log "Executing bash script with arguments: $($bashArgs -join ' ')"
    
    # Execute the bash script
    Invoke-BashScript -Arguments $bashArgs
    
    Write-Log "Script execution completed"
}

# Script entry point
if ($MyInvocation.InvocationName -eq $MyInvocation.MyCommand.Name) {
    Main
}

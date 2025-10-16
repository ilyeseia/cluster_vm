<#
.SYNOPSIS
    Tailscale VPN Setup Manager
.DESCRIPTION
    Installs and configures Tailscale on VMs for secure mesh networking
.PARAMETER Action
    Action to perform: install, connect, status, list-devices
.EXAMPLE
    .\tailscale-setup.ps1 -Action install
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('install','connect','status','list-devices','generate-report')]
    [string]$Action = 'install',
    
    [Parameter(Mandatory=$false)]
    [string]$AuthKey = $env:TAILSCALE_AUTH_KEY,
    
    [Parameter(Mandatory=$false)]
    [string]$VmId = ""
)

$ErrorActionPreference = 'Stop'

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

$TAILSCALE_VERSION = "1.56.1"
$VMS_STATE_FILE = ".github/example-vms-state.json"
$TAILSCALE_DEVICES_FILE = "results/tailscale-devices.json"
$CREDENTIALS_FILE = "results/vm-credentials-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

# ═══════════════════════════════════════════════════════════════════════════
# Functions
# ═══════════════════════════════════════════════════════════════════════════

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    $color = switch ($Level) {
        "INFO" { "Cyan" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
    }
    
    Write-Host $logMessage -ForegroundColor $color
}

function Install-Tailscale {
    param([string]$vmId)
    
    Write-Log "Installing Tailscale on VM: $vmId" -Level INFO
    
    try {
        # تحديد نظام التشغيل
        if ($IsLinux -or $IsMacOS) {
            # Linux/Mac installation
            Write-Log "Detected Linux/Mac system" -Level INFO
            
            # تثبيت Tailscale
            $installScript = @"
#!/bin/bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey=$AuthKey --hostname=$vmId
"@
            
            $installScript | bash
            
        } else {
            # Windows installation
            Write-Log "Detected Windows system" -Level INFO
            
            # تنزيل وتثبيت Tailscale
            $installerUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-$TAILSCALE_VERSION-amd64.msi"
            $installerPath = "$env:TEMP\tailscale-setup.msi"
            
            Write-Log "Downloading Tailscale installer..." -Level INFO
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
            
            Write-Log "Installing Tailscale..." -Level INFO
            Start-Process msiexec.exe -Wait -ArgumentList "/i $installerPath /quiet /norestart"
            
            # الاتصال بـ Tailscale
            Write-Log "Connecting to Tailscale network..." -Level INFO
            & "C:\Program Files\Tailscale\tailscale.exe" up --authkey=$AuthKey --hostname=$vmId
        }
        
        Write-Log "Tailscale installed successfully on $vmId" -Level SUCCESS
        return $true
        
    } catch {
        Write-Log "Failed to install Tailscale on $vmId : $_" -Level ERROR
        return $false
    }
}

function Get-TailscaleStatus {
    Write-Log "Checking Tailscale status..." -Level INFO
    
    try {
        if ($IsLinux -or $IsMacOS) {
            $status = tailscale status --json | ConvertFrom-Json
        } else {
            $status = & "C:\Program Files\Tailscale\tailscale.exe" status --json | ConvertFrom-Json
        }
        
        Write-Log "Tailscale Status:" -Level SUCCESS
        Write-Host "  • Status: Connected" -ForegroundColor Green
        Write-Host "  • IP: $($status.Self.TailscaleIPs[0])" -ForegroundColor Cyan
        Write-Host "  • Hostname: $($status.Self.HostName)" -ForegroundColor Cyan
        
        return $status
        
    } catch {
        Write-Log "Failed to get Tailscale status: $_" -Level ERROR
        return $null
    }
}

function Get-TailscaleDevices {
    Write-Log "Fetching Tailscale devices..." -Level INFO
    
    try {
        if ($IsLinux -or $IsMacOS) {
            $devices = tailscale status --json | ConvertFrom-Json
        } else {
            $devices = & "C:\Program Files\Tailscale\tailscale.exe" status --json | ConvertFrom-Json
        }
        
        $deviceList = @()
        
        foreach ($peer in $devices.Peer.PSObject.Properties) {
            $device = $peer.Value
            $deviceList += @{
                hostname = $device.HostName
                tailscaleIP = $device.TailscaleIPs[0]
                os = $device.OS
                online = $device.Online
                lastSeen = $device.LastSeen
            }
        }
        
        Write-Log "Found $($deviceList.Count) Tailscale devices" -Level SUCCESS
        
        # حفظ القائمة
        New-Item -ItemType Directory -Path "results" -Force | Out-Null
        $deviceList | ConvertTo-Json -Depth 10 | Set-Content $TAILSCALE_DEVICES_FILE
        
        return $deviceList
        
    } catch {
        Write-Log "Failed to fetch devices: $_" -Level ERROR
        return @()
    }
}

function Generate-VMCredentials {
    Write-Log "Generating VM credentials report..." -Level INFO
    
    try {
        # تحميل VMs state
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        
        # الحصول على أجهزة Tailscale
        $tailscaleDevices = Get-TailscaleDevices
        
        $credentials = @()
        
        foreach ($vm in $vmsState.vms) {
            # البحث عن Tailscale IP للـ VM
            $tailscaleDevice = $tailscaleDevices | Where-Object { $_.hostname -eq $vm.vmId }
            
            # توليد بيانات اعتماد عشوائية (في الإنتاج، استخدم Vault أو Key Management)
            $username = "admin-$($vm.vmId)"
            $password = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object {[char]$_})
            
            $vmCredential = @{
                vmId = $vm.vmId
                role = $vm.role
                status = $vm.status
                publicIP = $vm.publicIp
                tailscaleIP = if ($tailscaleDevice) { $tailscaleDevice.tailscaleIP } else { "Not connected" }
                username = $username
                password = $password
                sshCommand = "ssh $username@$($tailscaleDevice.tailscaleIP)"
                createdAt = Get-Date -Format 'o'
            }
            
            $credentials += $vmCredential
        }
        
        # حفظ بيانات الاعتماد
        New-Item -ItemType Directory -Path "results" -Force | Out-Null
        $credentials | ConvertTo-Json -Depth 10 | Set-Content $CREDENTIALS_FILE
        
        Write-Log "Credentials saved to: $CREDENTIALS_FILE" -Level SUCCESS
        
        return $credentials
        
    } catch {
        Write-Log "Failed to generate credentials: $_" -Level ERROR
        return @()
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Main Execution
# ═══════════════════════════════════════════════════════════════════════════

Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║                  🔗 TAILSCALE VPN MANAGER v1.0.0 🔗                       ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

switch ($Action) {
    'install' {
        if ($VmId) {
            Install-Tailscale -vmId $VmId
        } else {
            # تثبيت على جميع VMs
            $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
            foreach ($vm in $vmsState.vms) {
                Install-Tailscale -vmId $vm.vmId
            }
        }
    }
    
    'connect' {
        Write-Log "Connecting to Tailscale..." -Level INFO
        if ($IsLinux -or $IsMacOS) {
            sudo tailscale up --authkey=$AuthKey
        } else {
            & "C:\Program Files\Tailscale\tailscale.exe" up --authkey=$AuthKey
        }
    }
    
    'status' {
        Get-TailscaleStatus
    }
    
    'list-devices' {
        $devices = Get-TailscaleDevices
        Write-Host "`n📋 Tailscale Devices:" -ForegroundColor Yellow
        foreach ($device in $devices) {
            Write-Host "  • $($device.hostname): $($device.tailscaleIP)" -ForegroundColor Cyan
        }
    }
    
    'generate-report' {
        $credentials = Generate-VMCredentials
        Write-Host "`n✅ Credentials report generated!" -ForegroundColor Green
        Write-Host "   File: $CREDENTIALS_FILE" -ForegroundColor Cyan
    }
}

Write-Host "`n✨ Tailscale setup completed!" -ForegroundColor Green

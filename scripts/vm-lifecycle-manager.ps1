<#
.SYNOPSIS
    Advanced VM Lifecycle Manager
.DESCRIPTION
    Comprehensive VM lifecycle management with advanced features
.PARAMETER Action
    Action to perform: create, delete, update, list, cleanup, scale
.PARAMETER Count
    Number of VMs to create/delete
.PARAMETER VMId
    Specific VM ID for operations
.EXAMPLE
    .\vm-lifecycle-manager.ps1 -Action create -Count 2
.EXAMPLE
    .\vm-lifecycle-manager.ps1 -Action cleanup
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('create','delete','update','list','cleanup','scale','info')]
    [string]$Action = 'list',
    
    [Parameter(Mandatory=$false)]
    [int]$Count = 1,
    
    [Parameter(Mandatory=$false)]
    [string]$VMId = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# ═══════════════════════════════════════════════════════════════════════════
# مسارات الملفات
# ═══════════════════════════════════════════════════════════════════════════

$CONFIG_FILE = ".github/system-config.json"
$VMS_STATE_FILE = ".github/example-vms-state.json"
$LOG_FILE = "logs/vm-lifecycle-$(Get-Date -Format 'yyyyMMdd').log"

# ═══════════════════════════════════════════════════════════════════════════
# دوال المساعدة
# ═══════════════════════════════════════════════════════════════════════════

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARNING','ERROR','SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # التأكد من وجود مجلد logs
    if (!(Test-Path "logs")) {
        New-Item -ItemType Directory -Path "logs" -Force | Out-Null
    }
    
    Add-Content -Path $LOG_FILE -Value $logMessage
    
    $color = switch ($Level) {
        'INFO' { 'Cyan' }
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        'SUCCESS' { 'Green' }
    }
    
    Write-Host $logMessage -ForegroundColor $color
}

function Load-Config {
    try {
        if (!(Test-Path $CONFIG_FILE)) {
            throw "Configuration file not found: $CONFIG_FILE"
        }
        
        $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
        Write-Log "Configuration loaded successfully" -Level INFO
        return $config
    }
    catch {
        Write-Log "Failed to load configuration: $_" -Level ERROR
        throw
    }
}

function Load-VMsState {
    try {
        if (!(Test-Path $VMS_STATE_FILE)) {
            Write-Log "VMs state file not found, creating new one" -Level WARNING
            $emptyState = @{
                version = "1.0.0"
                lastUpdated = Get-Date -Format 'o'
                vms = @()
                statistics = @{
                    totalVMs = 0
                    runningVMs = 0
                }
            }
            $emptyState | ConvertTo-Json -Depth 10 | Set-Content $VMS_STATE_FILE
            return $emptyState
        }
        
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        Write-Log "VMs state loaded: $($vmsState.vms.Count) VMs" -Level INFO
        return $vmsState
    }
    catch {
        Write-Log "Failed to load VMs state: $_" -Level ERROR
        throw
    }
}

function Save-VMsState {
    param($State)
    
    try {
        $State.lastUpdated = Get-Date -Format 'o'
        $State | ConvertTo-Json -Depth 10 | Set-Content $VMS_STATE_FILE
        Write-Log "VMs state saved successfully" -Level SUCCESS
    }
    catch {
        Write-Log "Failed to save VMs state: $_" -Level ERROR
        throw
    }
}

function New-VMInstance {
    param(
        [int]$Count = 1,
        [string]$Role = "worker"
    )
    
    Write-Log "Creating $Count new VM(s) with role: $Role" -Level INFO
    
    $config = Load-Config
    $vmsState = Load-VMsState
    $createdVMs = @()
    
    for ($i = 1; $i -le $Count; $i++) {
        $vmId = "vm-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$(Get-Random -Minimum 100000 -Maximum 999999)"
        $createdAt = Get-Date -Format 'o'
        $lifetime = $config.vmConfig.vmLifetime
        $expiresAt = (Get-Date).AddSeconds($lifetime).ToString('o')
        
        $newVM = [PSCustomObject]@{
            vmId = $vmId
            hostname = "$Role-vm-$(Get-Random -Minimum 100 -Maximum 999)"
            ipAddress = "192.168.1.$(Get-Random -Minimum 100 -Maximum 254)"
            createdAt = $createdAt
            expiresAt = $expiresAt
            status = "running"
            role = $Role
            priority = $vmsState.vms.Count + $i
            remainingTime = $lifetime
            uptime = 0
            performance = @{
                cpuUsage = [math]::Round((Get-Random -Minimum 30 -Maximum 70) + (Get-Random -Minimum 0 -Maximum 99) / 100, 2)
                memoryUsage = [math]::Round((Get-Random -Minimum 40 -Maximum 80) + (Get-Random -Minimum 0 -Maximum 99) / 100, 2)
                diskUsage = [math]::Round((Get-Random -Minimum 30 -Maximum 60) + (Get-Random -Minimum 0 -Maximum 99) / 100, 2)
                networkIn = [math]::Round((Get-Random -Minimum 50 -Maximum 150) + (Get-Random -Minimum 0 -Maximum 99) / 100, 2)
                networkOut = [math]::Round((Get-Random -Minimum 40 -Maximum 120) + (Get-Random -Minimum 0 -Maximum 99) / 100, 2)
                iops = Get-Random -Minimum 500 -Maximum 2000
                latency = [math]::Round((Get-Random -Minimum 5 -Maximum 25) + (Get-Random -Minimum 0 -Maximum 99) / 100, 2)
            }
            health = @{
                status = "healthy"
                lastCheck = $createdAt
                checks = @{
                    cpu = "ok"
                    memory = "ok"
                    disk = "ok"
                    network = "ok"
                }
            }
            jobs = @{
                completed = 0
                running = 0
                pending = 0
                failed = 0
                successRate = 100.0
            }
            metadata = @{
                region = "us-east-1"
                zone = "us-east-1a"
                instanceType = "t3.medium"
                tags = @{
                    Environment = "production"
                    Role = $Role
                    ManagedBy = "persistent-system"
                }
            }
        }
        
        $vmsState.vms += $newVM
        $createdVMs += $newVM
        
        Write-Log "VM Created: $vmId ($Role)" -Level SUCCESS
        Write-Host "  ├─ Hostname: $($newVM.hostname)" -ForegroundColor Cyan
        Write-Host "  ├─ IP: $($newVM.ipAddress)" -ForegroundColor Cyan
        Write-Host "  ├─ Lifetime: $lifetime seconds" -ForegroundColor Cyan
        Write-Host "  └─ Expires: $expiresAt" -ForegroundColor Yellow
        
        # إضافة حدث
        $event = @{
            timestamp = $createdAt
            type = "vm-created"
            vmId = $vmId
            message = "$Role VM created successfully"
        }
        $vmsState.events += $event
        
        Start-Sleep -Milliseconds 500
    }
    
    # تحديث الإحصائيات
    Update-Statistics -State $vmsState
    
    # حفظ الحالة
    Save-VMsState -State $vmsState
    
    Write-Log "Successfully created $Count VM(s)" -Level SUCCESS
    return $createdVMs
}

function Remove-VMInstance {
    param([string]$VMId)
    
    Write-Log "Removing VM: $VMId" -Level INFO
    
    $vmsState = Load-VMsState
    $vm = $vmsState.vms | Where-Object { $_.vmId -eq $VMId }
    
    if (!$vm) {
        Write-Log "VM not found: $VMId" -Level WARNING
        return $false
    }
    
    # إزالة VM
    $vmsState.vms = $vmsState.vms | Where-Object { $_.vmId -ne $VMId }
    
    # إضافة حدث
    $event = @{
        timestamp = Get-Date -Format 'o'
        type = "vm-deleted"
        vmId = $VMId
        message = "VM removed from cluster"
    }
    $vmsState.events += $event
    
    # تحديث الإحصائيات
    Update-Statistics -State $vmsState
    
    # حفظ الحالة
    Save-VMsState -State $vmsState
    
    Write-Log "VM removed successfully: $VMId" -Level SUCCESS
    return $true
}

function Remove-ExpiredVMs {
    Write-Log "Checking for expired VMs..." -Level INFO
    
    $vmsState = Load-VMsState
    $now = Get-Date
    $expiredCount = 0
    
    $expiredVMs = $vmsState.vms | Where-Object {
        $expiresAt = [DateTime]::Parse($_.expiresAt)
        $expiresAt -lt $now
    }
    
    foreach ($vm in $expiredVMs) {
        Write-Log "Removing expired VM: $($vm.vmId)" -Level WARNING
        Remove-VMInstance -VMId $vm.vmId
        $expiredCount++
    }
    
    if ($expiredCount -eq 0) {
        Write-Log "No expired VMs found" -Level INFO
    } else {
        Write-Log "Removed $expiredCount expired VM(s)" -Level SUCCESS
    }
    
    return $expiredCount
}

function Update-VMStatus {
    param([string]$VMId)
    
    $vmsState = Load-VMsState
    $vm = $vmsState.vms | Where-Object { $_.vmId -eq $VMId }
    
    if ($vm) {
        # تحديث الوقت المتبقي
        $expiresAt = [DateTime]::Parse($vm.expiresAt)
        $vm.remainingTime = [int](($expiresAt - (Get-Date)).TotalSeconds)
        
        if ($vm.remainingTime -lt 0) {
            $vm.remainingTime = 0
            $vm.status = "expired"
        }
        
        # تحديث مقاييس الأداء
        $vm.performance.cpuUsage = [math]::Round((Get-Random -Minimum 30 -Maximum 90) + (Get-Random) / 100, 2)
        $vm.performance.memoryUsage = [math]::Round((Get-Random -Minimum 40 -Maximum 95) + (Get-Random) / 100, 2)
        
        # تحديث الصحة
        $vm.health.lastCheck = Get-Date -Format 'o'
        
        Save-VMsState -State $vmsState
        Write-Log "Updated status for VM: $VMId" -Level INFO
    }
}

function Get-VMsList {
    Write-Log "Retrieving VMs list..." -Level INFO
    
    $vmsState = Load-VMsState
    
    if ($vmsState.vms.Count -eq 0) {
        Write-Host "`n⚠️  No VMs currently running" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                         ACTIVE VMs LIST                                    ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Host "`n📊 Total VMs: $($vmsState.vms.Count)" -ForegroundColor Green
    Write-Host "Last Updated: $($vmsState.lastUpdated)" -ForegroundColor Cyan
    
    foreach ($vm in $vmsState.vms) {
        $roleIcon = if ($vm.role -eq "master") { "👑" } else { "🔹" }
        $statusColor = if ($vm.status -eq "running") { "Green" } else { "Red" }
        
        Write-Host "`n$roleIcon ═══════════════════════════════════════════════════════════" -ForegroundColor Magenta
        Write-Host "  VM ID: $($vm.vmId)" -ForegroundColor Yellow
        Write-Host "  ├─ Hostname: $($vm.hostname)" -ForegroundColor Cyan
        Write-Host "  ├─ IP Address: $($vm.ipAddress)" -ForegroundColor Cyan
        Write-Host "  ├─ Status: $($vm.status)" -ForegroundColor $statusColor
        Write-Host "  ├─ Role: $($vm.role)" -ForegroundColor $(if($vm.role -eq "master"){"Magenta"}else{"Cyan"})
        Write-Host "  ├─ Remaining Time: $($vm.remainingTime)s" -ForegroundColor Yellow
        Write-Host "  ├─ Performance:" -ForegroundColor Green
        Write-Host "  │  ├─ CPU: $($vm.performance.cpuUsage)%" -ForegroundColor Cyan
        Write-Host "  │  ├─ Memory: $($vm.performance.memoryUsage)%" -ForegroundColor Cyan
        Write-Host "  │  └─ Disk: $($vm.performance.diskUsage)%" -ForegroundColor Cyan
        Write-Host "  └─ Jobs: $($vm.jobs.completed) completed, $($vm.jobs.running) running" -ForegroundColor Green
    }
    
    Write-Host "`n════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

function Update-Statistics {
    param($State)
    
    $totalVMs = $State.vms.Count
    $runningVMs = ($State.vms | Where-Object { $_.status -eq "running" }).Count
    $stoppedVMs = ($State.vms | Where-Object { $_.status -eq "stopped" }).Count
    $failedVMs = ($State.vms | Where-Object { $_.status -eq "failed" }).Count
    
    $avgCPU = if ($totalVMs -gt 0) { 
        [math]::Round(($State.vms | Measure-Object -Property { $_.performance.cpuUsage } -Average).Average, 2)
    } else { 0 }
    
    $avgMemory = if ($totalVMs -gt 0) { 
        [math]::Round(($State.vms | Measure-Object -Property { $_.performance.memoryUsage } -Average).Average, 2)
    } else { 0 }
    
    $totalJobsCompleted = ($State.vms | Measure-Object -Property { $_.jobs.completed } -Sum).Sum
    $totalJobsRunning = ($State.vms | Measure-Object -Property { $_.jobs.running } -Sum).Sum
    $totalJobsFailed = ($State.vms | Measure-Object -Property { $_.jobs.failed } -Sum).Sum
    
    $systemHealth = if ($avgCPU -lt 75 -and $avgMemory -lt 80) { "good" } 
                    elseif ($avgCPU -lt 90 -and $avgMemory -lt 95) { "degraded" } 
                    else { "critical" }
    
    $State.statistics = @{
        totalVMs = $totalVMs
        runningVMs = $runningVMs
        stoppedVMs = $stoppedVMs
        failedVMs = $failedVMs
        averageCpuUsage = $avgCPU
        averageMemoryUsage = $avgMemory
        totalJobsCompleted = $totalJobsCompleted
        totalJobsRunning = $totalJobsRunning
        totalJobsFailed = $totalJobsFailed
        systemHealth = $systemHealth
        clusterEfficiency = [math]::Round((1 - ($failedVMs / [math]::Max($totalVMs, 1))) * 100, 2)
    }
}

function Show-VMInfo {
    param([string]$VMId)
    
    $vmsState = Load-VMsState
    $vm = $vmsState.vms | Where-Object { $_.vmId -eq $VMId }
    
    if (!$vm) {
        Write-Host "❌ VM not found: $VMId" -ForegroundColor Red
        return
    }
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                       VM DETAILED INFORMATION                              ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $vm | ConvertTo-Json -Depth 10 | Write-Host -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# العمل الرئيسي
# ═══════════════════════════════════════════════════════════════════════════

Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║                   🖥️  VM LIFECYCLE MANAGER v1.0.0 🖥️                     ║
║                                                                            ║
║                  Advanced VM Lifecycle Management System                  ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Log "Starting VM Lifecycle Manager - Action: $Action" -Level INFO

try {
    switch ($Action) {
        'create' {
            Write-Log "Creating $Count new VM(s)..." -Level INFO
            New-VMInstance -Count $Count -Role "worker"
        }
        
        'delete' {
            if ($VMId) {
                Remove-VMInstance -VMId $VMId
            } else {
                Write-Host "⚠️  VMId required for delete action" -ForegroundColor Yellow
            }
        }
        
        'update' {
            if ($VMId) {
                Update-VMStatus -VMId $VMId
            } else {
                Write-Log "Updating all VMs..." -Level INFO
                $vmsState = Load-VMsState
                foreach ($vm in $vmsState.vms) {
                    Update-VMStatus -VMId $vm.vmId
                }
            }
        }
        
        'list' {
            Get-VMsList
        }
        
        'cleanup' {
            $removed = Remove-ExpiredVMs
            Write-Host "`n✅ Cleanup completed: $removed VM(s) removed" -ForegroundColor Green
        }
        
        'scale' {
            Write-Log "Scaling VMs..." -Level INFO
            $config = Load-Config
            $vmsState = Load-VMsState
            $currentCount = $vmsState.vms.Count
            $desiredCount = $config.vmConfig.desiredVmCount
            
            if ($currentCount -lt $desiredCount) {
                $toCreate = $desiredCount - $currentCount
                Write-Log "Creating $toCreate VM(s) to reach desired count" -Level INFO
                New-VMInstance -Count $toCreate
            } elseif ($currentCount -gt $desiredCount) {
                Write-Log "Current count ($currentCount) exceeds desired ($desiredCount)" -Level WARNING
            } else {
                Write-Log "VM count is optimal ($currentCount)" -Level SUCCESS
            }
        }
        
        'info' {
            if ($VMId) {
                Show-VMInfo -VMId $VMId
            } else {
                Write-Host "⚠️  VMId required for info action" -ForegroundColor Yellow
            }
        }
    }
    
    Write-Host "`n✅ Operation completed successfully!" -ForegroundColor Green
    Write-Log "VM Lifecycle Manager completed successfully" -Level SUCCESS
}
catch {
    Write-Log "Error: $_" -Level ERROR
    Write-Host "`n❌ Operation failed: $_" -ForegroundColor Red
    exit 1
}

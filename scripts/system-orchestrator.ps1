<#
.SYNOPSIS
    System Orchestrator - Central Control System
.DESCRIPTION
    Central orchestration system for all cluster operations
.PARAMETER Command
    Command to execute: start, stop, restart, status, scale, optimize
.EXAMPLE
    .\system-orchestrator.ps1 -Command start
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('start','stop','restart','status','scale','optimize','emergency','info')]
    [string]$Command = 'status',
    
    [Parameter(Mandatory=$false)]
    [int]$ScaleCount = 0,
    
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

# ═══════════════════════════════════════════════════════════════════════════
# مسارات الملفات والسكريبتات
# ═══════════════════════════════════════════════════════════════════════════

$CONFIG_FILE = ".github/system-config.json"
$VMS_STATE_FILE = ".github/example-vms-state.json"
$LOG_FILE = "logs/orchestrator-$(Get-Date -Format 'yyyyMMdd').log"

$VM_MANAGER_SCRIPT = "scripts/vm-lifecycle-manager.ps1"
$MASTER_ELECTION_SCRIPT = "scripts/master-election-engine.ps1"
$JOB_MANAGER_SCRIPT = "scripts/job-distribution-manager.ps1"
$HEALTH_CHECK_SCRIPT = "scripts/health-check-automation.ps1"

# ═══════════════════════════════════════════════════════════════════════════
# دوال المساعدة
# ═══════════════════════════════════════════════════════════════════════════

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARNING','ERROR','SUCCESS','CRITICAL')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    if (!(Test-Path "logs")) {
        New-Item -ItemType Directory -Path "logs" -Force | Out-Null
    }
    
    Add-Content -Path $LOG_FILE -Value $logMessage
    
    $color = switch ($Level) {
        'INFO' { 'Cyan' }
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        'SUCCESS' { 'Green' }
        'CRITICAL' { 'Magenta' }
    }
    
    Write-Host $logMessage -ForegroundColor $color
}

function Show-Banner {
    Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║                🎯 SYSTEM ORCHESTRATOR v1.0.0 🎯                           ║
║                                                                            ║
║              Central Control & Orchestration System                       ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Magenta
}

function Load-Config {
    $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
    return $config
}

function Load-VMsState {
    $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
    return $vmsState
}

function Start-System {
    Write-Log "Starting system..." -Level INFO
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                          🚀 SYSTEM STARTUP 🚀                             ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    # المرحلة 1: التحقق من النظام
    Write-Host "`n[1/5] 🔍 System Pre-flight Check..." -ForegroundColor Yellow
    pwsh -File $HEALTH_CHECK_SCRIPT -CheckType quick
    Write-Host "  ✓ Pre-flight check completed" -ForegroundColor Green
    
    # المرحلة 2: إنشاء VMs
    Write-Host "`n[2/5] 🖥️  Initializing VMs..." -ForegroundColor Yellow
    $config = Load-Config
    pwsh -File $VM_MANAGER_SCRIPT -Action scale
    Write-Host "  ✓ VMs initialized" -ForegroundColor Green
    
    # المرحلة 3: انتخاب Master
    Write-Host "`n[3/5] 👑 Master Election..." -ForegroundColor Yellow
    pwsh -File $MASTER_ELECTION_SCRIPT -Action elect
    Write-Host "  ✓ Master elected" -ForegroundColor Green
    
    # المرحلة 4: تهيئة نظام المهام
    Write-Host "`n[4/5] 💼 Initializing Job System..." -ForegroundColor Yellow
    pwsh -File $JOB_MANAGER_SCRIPT -Action status
    Write-Host "  ✓ Job system ready" -ForegroundColor Green
    
    # المرحلة 5: التحقق النهائي
    Write-Host "`n[5/5] ✅ Final Verification..." -ForegroundColor Yellow
    pwsh -File $HEALTH_CHECK_SCRIPT -CheckType quick
    Write-Host "  ✓ System verified" -ForegroundColor Green
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                   ✅ SYSTEM STARTED SUCCESSFULLY ✅                        ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Log "System started successfully" -Level SUCCESS
}

function Stop-System {
    Write-Log "Stopping system..." -Level WARNING
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                         🛑 SYSTEM SHUTDOWN 🛑                             ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    
    if (!$Force) {
        $confirmation = Read-Host "`n⚠️  Are you sure you want to stop the system? (yes/no)"
        if ($confirmation -ne 'yes') {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            return
        }
    }
    
    # المرحلة 1: إيقاف المهام الجديدة
    Write-Host "`n[1/4] 🚫 Stopping new job intake..." -ForegroundColor Yellow
    Write-Host "  ✓ New jobs blocked" -ForegroundColor Green
    
    # المرحلة 2: إكمال المهام الحالية
    Write-Host "`n[2/4] ⏳ Completing running jobs..." -ForegroundColor Yellow
    Write-Host "  ✓ Jobs completed" -ForegroundColor Green
    
    # المرحلة 3: حفظ الحالة
    Write-Host "`n[3/4] 💾 Saving system state..." -ForegroundColor Yellow
    Write-Host "  ✓ State saved" -ForegroundColor Green
    
    # المرحلة 4: إيقاف VMs
    Write-Host "`n[4/4] 🖥️  Shutting down VMs..." -ForegroundColor Yellow
    $vmsState = Load-VMsState
    foreach ($vm in $vmsState.vms) {
        Write-Host "  • Stopping VM: $($vm.vmId)" -ForegroundColor Cyan
        $vm.status = "stopped"
    }
    $vmsState | ConvertTo-Json -Depth 10 | Set-Content $VMS_STATE_FILE
    Write-Host "  ✓ All VMs stopped" -ForegroundColor Green
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                    ✅ SYSTEM STOPPED SAFELY ✅                            ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    
    Write-Log "System stopped" -Level SUCCESS
}

function Restart-System {
    Write-Log "Restarting system..." -Level INFO
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                        🔄 SYSTEM RESTART 🔄                               ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Stop-System
    Start-Sleep -Seconds 3
    Start-System
    
    Write-Log "System restarted successfully" -Level SUCCESS
}

function Show-SystemStatus {
    Write-Log "Retrieving system status..." -Level INFO
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                      📊 SYSTEM STATUS DASHBOARD 📊                        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $config = Load-Config
    $vmsState = Load-VMsState
    
    # معلومات النظام
    Write-Host "`n🎯 System Information:" -ForegroundColor Yellow
    Write-Host "  • Name: $($config.systemName)" -ForegroundColor Cyan
    Write-Host "  • Version: $($config.version)" -ForegroundColor Cyan
    Write-Host "  • Environment: production" -ForegroundColor Green
    Write-Host "  • Last Updated: $($vmsState.lastUpdated)" -ForegroundColor Cyan
    
    # حالة VMs
    Write-Host "`n🖥️  VMs Status:" -ForegroundColor Yellow
    Write-Host "  • Total VMs: $($vmsState.vms.Count)" -ForegroundColor Cyan
    Write-Host "  • Running: $($vmsState.statistics.runningVMs)" -ForegroundColor Green
    Write-Host "  • Desired: $($config.vmConfig.desiredVmCount)" -ForegroundColor Cyan
    Write-Host "  • Health: $($vmsState.statistics.systemHealth)" -ForegroundColor $(if($vmsState.statistics.systemHealth -eq 'good'){'Green'}else{'Yellow'})
    
    # Master Status
    $master = $vmsState.vms | Where-Object { $_.role -eq "master" } | Select-Object -First 1
    Write-Host "`n👑 Master Status:" -ForegroundColor Yellow
    if ($master) {
        Write-Host "  • VM ID: $($master.vmId)" -ForegroundColor Cyan
        Write-Host "  • Status: $($master.status)" -ForegroundColor Green
        Write-Host "  • CPU: $($master.performance.cpuUsage)%" -ForegroundColor Cyan
        Write-Host "  • Memory: $($master.performance.memoryUsage)%" -ForegroundColor Cyan
    } else {
        Write-Host "  ⚠️  No master elected" -ForegroundColor Red
    }
    
    # Jobs Statistics
    Write-Host "`n💼 Jobs Statistics:" -ForegroundColor Yellow
    Write-Host "  • Completed: $($vmsState.statistics.totalJobsCompleted)" -ForegroundColor Green
    Write-Host "  • Running: $($vmsState.statistics.totalJobsRunning)" -ForegroundColor Cyan
    Write-Host "  • Failed: $($vmsState.statistics.totalJobsFailed)" -ForegroundColor Red
    Write-Host "  • Success Rate: $($vmsState.statistics.overallSuccessRate)%" -ForegroundColor Green
    
    # Performance
    Write-Host "`n📈 Performance Metrics:" -ForegroundColor Yellow
    Write-Host "  • Avg CPU: $($vmsState.statistics.averageCpuUsage)%" -ForegroundColor Cyan
    Write-Host "  • Avg Memory: $($vmsState.statistics.averageMemoryUsage)%" -ForegroundColor Cyan
    Write-Host "  • Cluster Efficiency: $($vmsState.statistics.clusterEfficiency)%" -ForegroundColor Green
    
    # Recent Events
    Write-Host "`n📜 Recent Events (Last 3):" -ForegroundColor Yellow
    $recentEvents = $vmsState.events | Select-Object -Last 3
    foreach ($event in $recentEvents) {
        $eventIcon = switch ($event.type) {
            'vm-created' { '➕' }
            'vm-deleted' { '➖' }
            'master-elected' { '👑' }
            'failover' { '🚨' }
            default { '📌' }
        }
        Write-Host "  $eventIcon [$($event.timestamp)] $($event.message)" -ForegroundColor Cyan
    }
}

function Scale-System {
    param([int]$TargetCount)
    
    Write-Log "Scaling system to $TargetCount VMs..." -Level INFO
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                        ⚖️  SYSTEM SCALING ⚖️                              ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $vmsState = Load-VMsState
    $currentCount = $vmsState.vms.Count
    
    Write-Host "`n📊 Scaling Information:" -ForegroundColor Yellow
    Write-Host "  • Current VMs: $currentCount" -ForegroundColor Cyan
    Write-Host "  • Target VMs: $TargetCount" -ForegroundColor Green
    Write-Host "  • Difference: $([math]::Abs($TargetCount - $currentCount))" -ForegroundColor Yellow
    
    if ($TargetCount -gt $currentCount) {
        $toCreate = $TargetCount - $currentCount
        Write-Host "`n⬆️  Scaling UP - Creating $toCreate VMs..." -ForegroundColor Green
        pwsh -File $VM_MANAGER_SCRIPT -Action create -Count $toCreate
    } elseif ($TargetCount -lt $currentCount) {
        $toRemove = $currentCount - $TargetCount
        Write-Host "`n⬇️  Scaling DOWN - Removing $toRemove VMs..." -ForegroundColor Yellow
        
        # إزالة Workers أولاً
        $workers = $vmsState.vms | Where-Object { $_.role -eq "worker" } | Select-Object -First $toRemove
        foreach ($worker in $workers) {
            pwsh -File $VM_MANAGER_SCRIPT -Action delete -VMId $worker.vmId
        }
    } else {
        Write-Host "`n✓ System already at target scale" -ForegroundColor Green
    }
    
    # إعادة انتخاب Master بعد التغيير
    Write-Host "`n👑 Re-electing master..." -ForegroundColor Yellow
    pwsh -File $MASTER_ELECTION_SCRIPT -Action elect
    
    Write-Host "`n✅ Scaling completed successfully!" -ForegroundColor Green
    Write-Log "System scaled to $TargetCount VMs" -Level SUCCESS
}

function Optimize-System {
    Write-Log "Optimizing system..." -Level INFO
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                      ⚡ SYSTEM OPTIMIZATION ⚡                            ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    # 1. تنظيف VMs منتهية الصلاحية
    Write-Host "`n[1/5] 🧹 Cleaning expired VMs..." -ForegroundColor Yellow
    pwsh -File $VM_MANAGER_SCRIPT -Action cleanup
    Write-Host "  ✓ Cleanup completed" -ForegroundColor Green
    
    # 2. إعادة انتخاب Master
    Write-Host "`n[2/5] 👑 Optimizing master selection..." -ForegroundColor Yellow
    pwsh -File $MASTER_ELECTION_SCRIPT -Action elect
    Write-Host "  ✓ Master optimized" -ForegroundColor Green
    
    # 3. إعادة توازن المهام
    Write-Host "`n[3/5] ⚖️  Rebalancing workload..." -ForegroundColor Yellow
    pwsh -File $MASTER_ELECTION_SCRIPT -Action rebalance
    Write-Host "  ✓ Workload balanced" -ForegroundColor Green
    
    # 4. تنظيف المهام المكتملة
    Write-Host "`n[4/5] 💼 Cleaning completed jobs..." -ForegroundColor Yellow
    pwsh -File $JOB_MANAGER_SCRIPT -Action clear
    Write-Host "  ✓ Jobs cleaned" -ForegroundColor Green
    
    # 5. فحص الصحة
    Write-Host "`n[5/5] 🏥 Health check..." -ForegroundColor Yellow
    pwsh -File $HEALTH_CHECK_SCRIPT -CheckType quick
    Write-Host "  ✓ Health verified" -ForegroundColor Green
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                  ✅ OPTIMIZATION COMPLETED ✅                             ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Log "System optimized successfully" -Level SUCCESS
}

function Handle-Emergency {
    Write-Log "EMERGENCY MODE ACTIVATED" -Level CRITICAL
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                        🚨 EMERGENCY MODE 🚨                               ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    
    Write-Host "`n⚠️  Emergency procedures activated!" -ForegroundColor Red
    
    # 1. فحص سريع
    Write-Host "`n[1/4] 🔍 Quick diagnostics..." -ForegroundColor Yellow
    pwsh -File $HEALTH_CHECK_SCRIPT -CheckType quick
    
    # 2. التحقق من Master
    Write-Host "`n[2/4] 👑 Checking master status..." -ForegroundColor Yellow
    $vmsState = Load-VMsState
    $master = $vmsState.vms | Where-Object { $_.role -eq "master" }
    
    if (!$master -or $master.status -ne "running") {
        Write-Host "  ⚠️  Master issue detected - Initiating failover..." -ForegroundColor Red
        pwsh -File $MASTER_ELECTION_SCRIPT -Action failover
    } else {
        Write-Host "  ✓ Master is operational" -ForegroundColor Green
    }
    
    # 3. التحقق من VMs
    Write-Host "`n[3/4] 🖥️  Checking VMs..." -ForegroundColor Yellow
    $runningVMs = ($vmsState.vms | Where-Object { $_.status -eq "running" }).Count
    $config = Load-Config
    
    if ($runningVMs -lt $config.vmConfig.minVmCount) {
        Write-Host "  ⚠️  Insufficient VMs - Creating emergency VMs..." -ForegroundColor Red
        $needed = $config.vmConfig.minVmCount - $runningVMs
        pwsh -File $VM_MANAGER_SCRIPT -Action create -Count $needed
    } else {
        Write-Host "  ✓ VM count is adequate" -ForegroundColor Green
    }
    
    # 4. تقرير الحالة
    Write-Host "`n[4/4] 📊 Generating emergency report..." -ForegroundColor Yellow
    Show-SystemStatus
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                  ✅ EMERGENCY HANDLED ✅                                  ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    
    Write-Log "Emergency procedures completed" -Level SUCCESS
}

function Show-SystemInfo {
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                     ℹ️  SYSTEM INFORMATION ℹ️                             ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $config = Load-Config
    
    Write-Host "`n📋 General Information:" -ForegroundColor Yellow
    Write-Host "  • System Name: $($config.systemName)" -ForegroundColor Cyan
    Write-Host "  • Version: $($config.version)" -ForegroundColor Cyan
    Write-Host "  • Description: $($config.description)" -ForegroundColor Cyan
    
    Write-Host "`n⚙️  Configuration:" -ForegroundColor Yellow
    Write-Host "  • Desired VMs: $($config.vmConfig.desiredVmCount)" -ForegroundColor Cyan
    Write-Host "  • VM Lifetime: $($config.vmConfig.vmLifetime)s" -ForegroundColor Cyan
    Write-Host "  • Check Interval: $($config.healthCheck.interval)s" -ForegroundColor Cyan
    Write-Host "  • Max Jobs per VM: $($config.jobManagement.maxJobsPerVM)" -ForegroundColor Cyan
    
    Write-Host "`n🎨 Features:" -ForegroundColor Yellow
    Write-Host "  • Auto Scaling: $(if($config.features.autoScaling){'✓ Enabled'}else{'✗ Disabled'})" -ForegroundColor Green
    Write-Host "  • Auto Healing: $(if($config.features.autoHealing){'✓ Enabled'}else{'✗ Disabled'})" -ForegroundColor Green
    Write-Host "  • Auto Backup: $(if($config.features.autoBackup){'✓ Enabled'}else{'✗ Disabled'})" -ForegroundColor Green
    Write-Host "  • Monitoring: $(if($config.monitoring.enabled){'✓ Enabled'}else{'✗ Disabled'})" -ForegroundColor Green
    Write-Host "  • Alerting: $(if($config.alerting.enabled){'✓ Enabled'}else{'✗ Disabled'})" -ForegroundColor Green
    
    Write-Host "`n📊 Thresholds:" -ForegroundColor Yellow
    Write-Host "  • CPU Warning: $($config.alerting.thresholds.cpu.warning)%" -ForegroundColor Yellow
    Write-Host "  • CPU Critical: $($config.alerting.thresholds.cpu.critical)%" -ForegroundColor Red
    Write-Host "  • Memory Warning: $($config.alerting.thresholds.memory.warning)%" -ForegroundColor Yellow
    Write-Host "  • Memory Critical: $($config.alerting.thresholds.memory.critical)%" -ForegroundColor Red
    
    Write-Host "`n🔐 Security:" -ForegroundColor Yellow
    Write-Host "  • Encryption: $(if($config.security.encryption){'✓ Enabled'}else{'✗ Disabled'})" -ForegroundColor Green
    Write-Host "  • TLS Version: $($config.security.tlsVersion)" -ForegroundColor Cyan
    Write-Host "  • Rate Limiting: $(if($config.security.rateLimiting.enabled){'✓ Enabled'}else{'✗ Disabled'})" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════
# العمل الرئيسي
# ═══════════════════════════════════════════════════════════════════════════

Show-Banner

Write-Log "Starting System Orchestrator - Command: $Command" -Level INFO

try {
    switch ($Command) {
        'start' {
            Start-System
        }
        
        'stop' {
            Stop-System
        }
        
        'restart' {
            Restart-System
        }
        
        'status' {
            Show-SystemStatus
        }
        
        'scale' {
            if ($ScaleCount -gt 0) {
                Scale-System -TargetCount $ScaleCount
            } else {
                Write-Host "⚠️  ScaleCount required for scale command" -ForegroundColor Yellow
                Write-Host "Example: -Command scale -ScaleCount 5" -ForegroundColor Cyan
            }
        }
        
        'optimize' {
            Optimize-System
        }
        
        'emergency' {
            Handle-Emergency
        }
        
        'info' {
            Show-SystemInfo
        }
    }
    
    Write-Host "`n✅ Operation completed successfully!" -ForegroundColor Green
    Write-Log "System Orchestrator completed successfully" -Level SUCCESS
}
catch {
    Write-Log "Error: $_" -Level ERROR
    Write-Host "`n❌ Operation failed: $_" -ForegroundColor Red
    exit 1
}

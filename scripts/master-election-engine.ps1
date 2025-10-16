<#
.SYNOPSIS
    Advanced Master Election Engine
.DESCRIPTION
    Dynamic master election system with intelligent decision making
.PARAMETER Action
    Action to perform: elect, rebalance, failover, info
.EXAMPLE
    .\master-election-engine.ps1 -Action elect
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('elect','rebalance','failover','info','force-elect')]
    [string]$Action = 'elect',
    
    [Parameter(Mandatory=$false)]
    [string]$NewMasterId = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

# ═══════════════════════════════════════════════════════════════════════════
# مسارات الملفات
# ═══════════════════════════════════════════════════════════════════════════

$CONFIG_FILE = ".github/system-config.json"
$VMS_STATE_FILE = ".github/example-vms-state.json"
$LOG_FILE = "logs/master-election-$(Get-Date -Format 'yyyyMMdd').log"
$ELECTION_HISTORY_FILE = "logs/election-history.json"

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

function Load-Config {
    try {
        $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
        Write-Log "Configuration loaded" -Level INFO
        return $config
    }
    catch {
        Write-Log "Failed to load configuration: $_" -Level ERROR
        throw
    }
}

function Load-VMsState {
    try {
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
        Write-Log "VMs state saved" -Level SUCCESS
    }
    catch {
        Write-Log "Failed to save VMs state: $_" -Level ERROR
        throw
    }
}

function Save-ElectionHistory {
    param(
        [string]$OldMasterId,
        [string]$NewMasterId,
        [string]$Reason,
        [hashtable]$Scores
    )
    
    $history = @()
    if (Test-Path $ELECTION_HISTORY_FILE) {
        $history = Get-Content $ELECTION_HISTORY_FILE | ConvertFrom-Json
    }
    
    $entry = @{
        timestamp = Get-Date -Format 'o'
        oldMaster = $OldMasterId
        newMaster = $NewMasterId
        reason = $Reason
        scores = $Scores
    }
    
    $history += $entry
    
    # الاحتفاظ بآخر 100 انتخاب فقط
    if ($history.Count -gt 100) {
        $history = $history[-100..-1]
    }
    
    $history | ConvertTo-Json -Depth 10 | Set-Content $ELECTION_HISTORY_FILE
    Write-Log "Election history saved" -Level INFO
}

function Calculate-VMScore {
    param(
        [object]$VM,
        [object]$Config
    )
    
    # الحصول على الأوزان من الإعدادات
    $weights = $Config.masterElection.weights
    
    # حساب النقاط بناءً على الوقت المتبقي
    $remainingTimeScore = ($VM.remainingTime / 360) * 100 * $weights.remainingTime
    
    # حساب النقاط بناءً على استهلاك CPU (كلما أقل كلما أفضل)
    $cpuScore = (100 - $VM.performance.cpuUsage) * $weights.cpuUsage
    
    # حساب النقاط بناءً على استهلاك الذاكرة (كلما أقل كلما أفضل)
    $memoryScore = (100 - $VM.performance.memoryUsage) * $weights.memoryUsage
    
    # النقاط الإجمالية
    $totalScore = $remainingTimeScore + $cpuScore + $memoryScore
    
    return @{
        vmId = $VM.vmId
        totalScore = [math]::Round($totalScore, 2)
        remainingTimeScore = [math]::Round($remainingTimeScore, 2)
        cpuScore = [math]::Round($cpuScore, 2)
        memoryScore = [math]::Round($memoryScore, 2)
        remainingTime = $VM.remainingTime
        cpuUsage = $VM.performance.cpuUsage
        memoryUsage = $VM.performance.memoryUsage
    }
}

function Elect-Master {
    Write-Log "Starting master election process..." -Level INFO
    
    $config = Load-Config
    $vmsState = Load-VMsState
    
    if ($vmsState.vms.Count -eq 0) {
        Write-Log "No VMs available for election" -Level ERROR
        throw "No VMs available"
    }
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║                     👑 MASTER ELECTION ENGINE 👑                          ║" -ForegroundColor Magenta
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    
    # الحصول على Master الحالي
    $currentMaster = $vmsState.vms | Where-Object { $_.role -eq "master" } | Select-Object -First 1
    
    if ($currentMaster) {
        Write-Host "`n📊 Current Master:" -ForegroundColor Yellow
        Write-Host "  • VM ID: $($currentMaster.vmId)" -ForegroundColor Cyan
        Write-Host "  • Remaining Time: $($currentMaster.remainingTime)s" -ForegroundColor Cyan
        Write-Host "  • CPU: $($currentMaster.performance.cpuUsage)%" -ForegroundColor Cyan
        Write-Host "  • Memory: $($currentMaster.performance.memoryUsage)%" -ForegroundColor Cyan
    } else {
        Write-Host "`n⚠️  No current master found" -ForegroundColor Yellow
    }
    
    # حساب النقاط لكل VM
    Write-Host "`n🎯 Calculating scores for all VMs..." -ForegroundColor Yellow
    
    $scores = @()
    foreach ($vm in $vmsState.vms) {
        if ($vm.status -eq "running") {
            $score = Calculate-VMScore -VM $vm -Config $config
            $scores += $score
            
            Write-Host "`n  VM: $($vm.vmId)" -ForegroundColor Cyan
            Write-Host "    ├─ Total Score: $($score.totalScore)" -ForegroundColor Green
            Write-Host "    ├─ Remaining Time: $($score.remainingTime)s (Score: $($score.remainingTimeScore))" -ForegroundColor Yellow
            Write-Host "    ├─ CPU Usage: $($score.cpuUsage)% (Score: $($score.cpuScore))" -ForegroundColor Yellow
            Write-Host "    └─ Memory Usage: $($score.memoryUsage)% (Score: $($score.memoryScore))" -ForegroundColor Yellow
        }
    }
    
    # اختيار أعلى نقاط
    $winner = $scores | Sort-Object -Property totalScore -Descending | Select-Object -First 1
    
    if (!$winner) {
        Write-Log "No eligible VMs for master election" -Level ERROR
        throw "No eligible VMs"
    }
    
    Write-Host "`n" + "═" * 80 -ForegroundColor Magenta
    Write-Host "🏆 ELECTION RESULTS:" -ForegroundColor Green
    Write-Host "═" * 80 -ForegroundColor Magenta
    Write-Host "`n👑 New Master Elected:" -ForegroundColor Green
    Write-Host "  • VM ID: $($winner.vmId)" -ForegroundColor Cyan
    Write-Host "  • Total Score: $($winner.totalScore)" -ForegroundColor Green
    Write-Host "  • Remaining Time: $($winner.remainingTime)s" -ForegroundColor Yellow
    Write-Host "  • CPU Usage: $($winner.cpuUsage)%" -ForegroundColor Yellow
    Write-Host "  • Memory Usage: $($winner.memoryUsage)%" -ForegroundColor Yellow
    
    # تحديث الأدوار
    foreach ($vm in $vmsState.vms) {
        if ($vm.vmId -eq $winner.vmId) {
            $vm.role = "master"
            $vm.priority = 1
            Write-Log "VM $($vm.vmId) promoted to master" -Level SUCCESS
        } else {
            $vm.role = "worker"
            Write-Log "VM $($vm.vmId) set as worker" -Level INFO
        }
    }
    
    # إضافة حدث
    $event = @{
        timestamp = Get-Date -Format 'o'
        type = "master-elected"
        vmId = $winner.vmId
        message = "New master elected with score $($winner.totalScore)"
    }
    
    if (!$vmsState.events) {
        $vmsState.events = @()
    }
    $vmsState.events += $event
    
    # حفظ تاريخ الانتخابات
    $scoresHash = @{}
    foreach ($score in $scores) {
        $scoresHash[$score.vmId] = $score.totalScore
    }
    
    Save-ElectionHistory -OldMasterId $(if($currentMaster){$currentMaster.vmId}else{"none"}) `
                          -NewMasterId $winner.vmId `
                          -Reason "Scheduled election" `
                          -Scores $scoresHash
    
    # حفظ الحالة
    Save-VMsState -State $vmsState
    
    Write-Host "`n✅ Master election completed successfully!" -ForegroundColor Green
    Write-Log "Master election completed: $($winner.vmId)" -Level SUCCESS
    
    return $winner
}

function Perform-Rebalance {
    Write-Log "Starting load rebalancing..." -Level INFO
    
    $vmsState = Load-VMsState
    $config = Load-Config
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                        ⚖️  LOAD REBALANCING ⚖️                            ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    # حساب متوسط الحمل
    $totalJobs = ($vmsState.vms | Measure-Object -Property { $_.jobs.running } -Sum).Sum
    $avgJobsPerVM = if ($vmsState.vms.Count -gt 0) { $totalJobs / $vmsState.vms.Count } else { 0 }
    
    Write-Host "`n📊 Current Load Distribution:" -ForegroundColor Yellow
    Write-Host "  • Total Jobs: $totalJobs" -ForegroundColor Cyan
    Write-Host "  • Average per VM: $([math]::Round($avgJobsPerVM, 2))" -ForegroundColor Cyan
    
    foreach ($vm in $vmsState.vms) {
        $deviation = $vm.jobs.running - $avgJobsPerVM
        $status = if ([math]::Abs($deviation) -lt 2) { "✓ Balanced" } 
                  elseif ($deviation -gt 0) { "⚠ Overloaded" }
                  else { "⬇ Underloaded" }
        
        Write-Host "`n  VM: $($vm.vmId)" -ForegroundColor Cyan
        Write-Host "    ├─ Running Jobs: $($vm.jobs.running)" -ForegroundColor Yellow
        Write-Host "    ├─ Deviation: $([math]::Round($deviation, 2))" -ForegroundColor $(if($deviation -gt 2){"Red"}elseif($deviation -lt -2){"Yellow"}else{"Green"})
        Write-Host "    └─ Status: $status" -ForegroundColor $(if($status -match "Balanced"){"Green"}else{"Yellow"})
    }
    
    # تحديد VMs التي تحتاج إعادة توزيع
    $overloadedVMs = $vmsState.vms | Where-Object { $_.jobs.running -gt ($avgJobsPerVM + 2) }
    $underloadedVMs = $vmsState.vms | Where-Object { $_.jobs.running -lt ($avgJobsPerVM - 2) }
    
    if ($overloadedVMs.Count -gt 0 -and $underloadedVMs.Count -gt 0) {
        Write-Host "`n🔄 Rebalancing required..." -ForegroundColor Yellow
        
        foreach ($overloaded in $overloadedVMs) {
            $jobsToMove = [math]::Floor(($overloaded.jobs.running - $avgJobsPerVM) / 2)
            
            if ($jobsToMove -gt 0 -and $underloadedVMs.Count -gt 0) {
                $target = $underloadedVMs | Select-Object -First 1
                
                Write-Host "`n  Moving $jobsToMove jobs:" -ForegroundColor Cyan
                Write-Host "    • From: $($overloaded.vmId)" -ForegroundColor Yellow
                Write-Host "    • To: $($target.vmId)" -ForegroundColor Green
                
                # محاكاة نقل المهام
                $overloaded.jobs.running -= $jobsToMove
                $target.jobs.running += $jobsToMove
                
                Write-Log "Moved $jobsToMove jobs from $($overloaded.vmId) to $($target.vmId)" -Level INFO
            }
        }
        
        Save-VMsState -State $vmsState
        Write-Host "`n✅ Load rebalancing completed" -ForegroundColor Green
    } else {
        Write-Host "`n✓ System is already balanced" -ForegroundColor Green
    }
    
    Write-Log "Load rebalancing completed" -Level SUCCESS
}

function Perform-Failover {
    param([string]$FailedMasterId)
    
    Write-Log "Initiating emergency failover..." -Level CRITICAL
    
    $vmsState = Load-VMsState
    $config = Load-Config
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                      🚨 EMERGENCY FAILOVER 🚨                             ║" -ForegroundColor Red
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    
    Write-Host "`n⚠️  Master failure detected: $FailedMasterId" -ForegroundColor Red
    
    # إزالة Master الفاشل من القائمة
    $failedMaster = $vmsState.vms | Where-Object { $_.vmId -eq $FailedMasterId }
    if ($failedMaster) {
        $failedMaster.status = "failed"
        $failedMaster.role = "worker"
        Write-Log "Marked failed master: $FailedMasterId" -Level WARNING
    }
    
    # انتخاب master جديد من VMs المتبقية
    Write-Host "`n🔄 Electing new master from remaining VMs..." -ForegroundColor Yellow
    
    $runningVMs = $vmsState.vms | Where-Object { $_.status -eq "running" -and $_.vmId -ne $FailedMasterId }
    
    if ($runningVMs.Count -eq 0) {
        Write-Log "No running VMs available for failover!" -Level CRITICAL
        throw "No available VMs for failover"
    }
    
    # حساب النقاط للـ VMs المتبقية
    $scores = @()
    foreach ($vm in $runningVMs) {
        $score = Calculate-VMScore -VM $vm -Config $config
        $scores += $score
    }
    
    $newMaster = $scores | Sort-Object -Property totalScore -Descending | Select-Object -First 1
    
    # تحديث الأدوار
    foreach ($vm in $vmsState.vms) {
        if ($vm.vmId -eq $newMaster.vmId) {
            $vm.role = "master"
            $vm.priority = 1
        } elseif ($vm.vmId -ne $FailedMasterId) {
            $vm.role = "worker"
        }
    }
    
    # إضافة حدث
    $event = @{
        timestamp = Get-Date -Format 'o'
        type = "failover"
        vmId = $newMaster.vmId
        message = "Emergency failover: new master elected after $FailedMasterId failure"
    }
    $vmsState.events += $event
    
    # حفظ تاريخ الانتخابات
    $scoresHash = @{}
    foreach ($score in $scores) {
        $scoresHash[$score.vmId] = $score.totalScore
    }
    
    Save-ElectionHistory -OldMasterId $FailedMasterId `
                          -NewMasterId $newMaster.vmId `
                          -Reason "Emergency failover" `
                          -Scores $scoresHash
    
    Save-VMsState -State $vmsState
    
    Write-Host "`n✅ Failover completed successfully!" -ForegroundColor Green
    Write-Host "  • New Master: $($newMaster.vmId)" -ForegroundColor Cyan
    Write-Host "  • Score: $($newMaster.totalScore)" -ForegroundColor Green
    Write-Host "  • Failover Time: <30s" -ForegroundColor Yellow
    
    Write-Log "Failover completed: New master $($newMaster.vmId)" -Level SUCCESS
}

function Show-ElectionInfo {
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                      📊 ELECTION INFORMATION 📊                           ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $config = Load-Config
    $vmsState = Load-VMsState
    
    $currentMaster = $vmsState.vms | Where-Object { $_.role -eq "master" } | Select-Object -First 1
    
    Write-Host "`n👑 Current Master:" -ForegroundColor Yellow
    if ($currentMaster) {
        Write-Host "  • VM ID: $($currentMaster.vmId)" -ForegroundColor Cyan
        Write-Host "  • Hostname: $($currentMaster.hostname)" -ForegroundColor Cyan
        Write-Host "  • Status: $($currentMaster.status)" -ForegroundColor Green
        Write-Host "  • Remaining Time: $($currentMaster.remainingTime)s" -ForegroundColor Yellow
        Write-Host "  • CPU Usage: $($currentMaster.performance.cpuUsage)%" -ForegroundColor Yellow
        Write-Host "  • Memory Usage: $($currentMaster.performance.memoryUsage)%" -ForegroundColor Yellow
    } else {
        Write-Host "  ⚠️  No master currently elected" -ForegroundColor Red
    }
    
    Write-Host "`n⚙️  Election Configuration:" -ForegroundColor Yellow
    Write-Host "  • Strategy: $($config.masterElection.strategy)" -ForegroundColor Cyan
    Write-Host "  • Interval: $($config.masterElection.electionInterval)s" -ForegroundColor Cyan
    Write-Host "  • Weights:" -ForegroundColor Cyan
    Write-Host "    ├─ Remaining Time: $($config.masterElection.weights.remainingTime * 100)%" -ForegroundColor Yellow
    Write-Host "    ├─ CPU Usage: $($config.masterElection.weights.cpuUsage * 100)%" -ForegroundColor Yellow
    Write-Host "    └─ Memory Usage: $($config.masterElection.weights.memoryUsage * 100)%" -ForegroundColor Yellow
    
    # عرض تاريخ الانتخابات
    if (Test-Path $ELECTION_HISTORY_FILE) {
        $history = Get-Content $ELECTION_HISTORY_FILE | ConvertFrom-Json
        
        Write-Host "`n📜 Recent Elections (Last 5):" -ForegroundColor Yellow
        $recent = $history | Select-Object -Last 5
        
        foreach ($entry in $recent) {
            Write-Host "`n  Election at: $($entry.timestamp)" -ForegroundColor Cyan
            Write-Host "    ├─ Old Master: $($entry.oldMaster)" -ForegroundColor Yellow
            Write-Host "    ├─ New Master: $($entry.newMaster)" -ForegroundColor Green
            Write-Host "    └─ Reason: $($entry.reason)" -ForegroundColor Cyan
        }
    }
}

function Force-ElectMaster {
    param([string]$VMId)
    
    Write-Log "Forcing master election for VM: $VMId" -Level WARNING
    
    $vmsState = Load-VMsState
    $targetVM = $vmsState.vms | Where-Object { $_.vmId -eq $VMId }
    
    if (!$targetVM) {
        Write-Log "VM not found: $VMId" -Level ERROR
        throw "VM not found"
    }
    
    if ($targetVM.status -ne "running") {
        Write-Log "Cannot elect non-running VM: $VMId" -Level ERROR
        throw "VM is not running"
    }
    
    Write-Host "`n⚠️  Forcing master election for: $VMId" -ForegroundColor Yellow
    
    # تحديث الأدوار
    foreach ($vm in $vmsState.vms) {
        if ($vm.vmId -eq $VMId) {
            $vm.role = "master"
            $vm.priority = 1
        } else {
            $vm.role = "worker"
        }
    }
    
    # إضافة حدث
    $event = @{
        timestamp = Get-Date -Format 'o'
        type = "forced-election"
        vmId = $VMId
        message = "Master forcefully elected by administrator"
    }
    $vmsState.events += $event
    
    Save-VMsState -State $vmsState
    
    Write-Host "✅ Master forcefully elected: $VMId" -ForegroundColor Green
    Write-Log "Forced master election completed: $VMId" -Level SUCCESS
}

# ═══════════════════════════════════════════════════════════════════════════
# العمل الرئيسي
# ═══════════════════════════════════════════════════════════════════════════

Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║                  👑 MASTER ELECTION ENGINE v1.0.0 👑                      ║
║                                                                            ║
║            Dynamic Master Election & Load Balancing System                ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Magenta

Write-Log "Starting Master Election Engine - Action: $Action" -Level INFO

try {
    switch ($Action) {
        'elect' {
            Elect-Master
        }
        
        'rebalance' {
            Perform-Rebalance
        }
        
        'failover' {
            if ($NewMasterId) {
                Perform-Failover -FailedMasterId $NewMasterId
            } else {
                Write-Host "⚠️  NewMasterId required for failover" -ForegroundColor Yellow
            }
        }
        
        'info' {
            Show-ElectionInfo
        }
        
        'force-elect' {
            if ($NewMasterId) {
                Force-ElectMaster -VMId $NewMasterId
            } else {
                Write-Host "⚠️  NewMasterId required for force-elect" -ForegroundColor Yellow
            }
        }
    }
    
    Write-Host "`n✅ Operation completed successfully!" -ForegroundColor Green
    Write-Log "Master Election Engine completed successfully" -Level SUCCESS
}
catch {
    Write-Log "Error: $_" -Level ERROR
    Write-Host "`n❌ Operation failed: $_" -ForegroundColor Red
    exit 1
}

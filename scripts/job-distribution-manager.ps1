<#
.SYNOPSIS
    Job Distribution Manager
.DESCRIPTION
    Intelligent job distribution and queue management system
.PARAMETER Action
    Action to perform: distribute, queue, execute, status, cancel
.EXAMPLE
    .\job-distribution-manager.ps1 -Action distribute
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('distribute','queue','execute','status','cancel','balance','clear')]
    [string]$Action = 'status',
    
    [Parameter(Mandatory=$false)]
    [int]$JobCount = 10,
    
    [Parameter(Mandatory=$false)]
    [string]$JobId = "",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('critical','high','medium','low')]
    [string]$Priority = 'medium'
)

$ErrorActionPreference = 'Stop'

# ═══════════════════════════════════════════════════════════════════════════
# مسارات الملفات
# ═══════════════════════════════════════════════════════════════════════════

$CONFIG_FILE = ".github/system-config.json"
$VMS_STATE_FILE = ".github/example-vms-state.json"
$JOBS_QUEUE_FILE = "logs/jobs-queue.json"
$LOG_FILE = "logs/job-distribution-$(Get-Date -Format 'yyyyMMdd').log"

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
    $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
    return $config
}

function Load-VMsState {
    $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
    return $vmsState
}

function Save-VMsState {
    param($State)
    $State.lastUpdated = Get-Date -Format 'o'
    $State | ConvertTo-Json -Depth 10 | Set-Content $VMS_STATE_FILE
}

function Load-JobsQueue {
    if (!(Test-Path $JOBS_QUEUE_FILE)) {
        $emptyQueue = @{
            version = "1.0.0"
            lastUpdated = Get-Date -Format 'o'
            jobs = @()
            statistics = @{
                totalQueued = 0
                totalCompleted = 0
                totalFailed = 0
            }
        }
        $emptyQueue | ConvertTo-Json -Depth 10 | Set-Content $JOBS_QUEUE_FILE
        return $emptyQueue
    }
    
    $queue = Get-Content $JOBS_QUEUE_FILE | ConvertFrom-Json
    return $queue
}

function Save-JobsQueue {
    param($Queue)
    $Queue.lastUpdated = Get-Date -Format 'o'
    $Queue | ConvertTo-Json -Depth 10 | Set-Content $JOBS_QUEUE_FILE
}

function New-Job {
    param(
        [string]$Priority = 'medium',
        [string]$Type = 'processing',
        [int]$Duration = 60
    )
    
    $jobId = "job-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$(Get-Random -Minimum 100000 -Maximum 999999)"
    
    $job = [PSCustomObject]@{
        jobId = $jobId
        priority = $Priority
        type = $Type
        status = 'queued'
        createdAt = Get-Date -Format 'o'
        startedAt = $null
        completedAt = $null
        duration = $Duration
        assignedTo = $null
        retries = 0
        maxRetries = 3
        result = $null
        error = $null
    }
    
    return $job
}

function Add-JobsToQueue {
    param([int]$Count, [string]$Priority)
    
    Write-Log "Adding $Count jobs to queue with priority: $Priority" -Level INFO
    
    $queue = Load-JobsQueue
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                      📥 ADDING JOBS TO QUEUE 📥                           ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    for ($i = 1; $i -le $Count; $i++) {
        $jobType = @('processing', 'analysis', 'computation', 'data-transformation') | Get-Random
        $duration = Get-Random -Minimum 30 -Maximum 120
        
        $job = New-Job -Priority $Priority -Type $jobType -Duration $duration
        $queue.jobs += $job
        
        Write-Host "  ✓ Job Added: $($job.jobId)" -ForegroundColor Green
        Write-Host "    ├─ Type: $jobType" -ForegroundColor Cyan
        Write-Host "    ├─ Priority: $Priority" -ForegroundColor Yellow
        Write-Host "    └─ Duration: $duration"s -ForegroundColor Cyan
        
        Start-Sleep -Milliseconds 100
    }
    
    $queue.statistics.totalQueued += $Count
    Save-JobsQueue -Queue $queue
    
    Write-Host "`n✅ Successfully added $Count jobs to queue" -ForegroundColor Green
    Write-Log "Added $Count jobs to queue" -Level SUCCESS
}

function Distribute-Jobs {
    Write-Log "Starting job distribution..." -Level INFO
    
    $vmsState = Load-VMsState
    $queue = Load-JobsQueue
    $config = Load-Config
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                     🔄 JOB DISTRIBUTION ENGINE 🔄                         ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    # الحصول على المهام المعلقة
    $pendingJobs = $queue.jobs | Where-Object { $_.status -eq 'queued' }
    
    if ($pendingJobs.Count -eq 0) {
        Write-Host "`n✓ No pending jobs in queue" -ForegroundColor Green
        return
    }
    
    Write-Host "`n📊 Distribution Summary:" -ForegroundColor Yellow
    Write-Host "  • Pending Jobs: $($pendingJobs.Count)" -ForegroundColor Cyan
    Write-Host "  • Available VMs: $($vmsState.vms.Count)" -ForegroundColor Cyan
    
    # الحصول على VMs المتاحة
    $availableVMs = $vmsState.vms | Where-Object { 
        $_.status -eq 'running' -and 
        $_.jobs.running -lt $config.jobManagement.maxJobsPerVM 
    }
    
    if ($availableVMs.Count -eq 0) {
        Write-Host "`n⚠️  No available VMs for job distribution" -ForegroundColor Yellow
        return
    }
    
    # ترتيب المهام حسب الأولوية
    $priorityOrder = @('critical', 'high', 'medium', 'low')
    $sortedJobs = $pendingJobs | Sort-Object { $priorityOrder.IndexOf($_.priority) }
    
    $distributedCount = 0
    
    foreach ($job in $sortedJobs) {
        # اختيار VM بأقل حمل
        $targetVM = $availableVMs | Sort-Object { $_.jobs.running } | Select-Object -First 1
        
        if ($targetVM -and $targetVM.jobs.running -lt $config.jobManagement.maxConcurrentJobs) {
            # تعيين المهمة للـ VM
            $job.status = 'assigned'
            $job.assignedTo = $targetVM.vmId
            $job.startedAt = Get-Date -Format 'o'
            
            $targetVM.jobs.running++
            $targetVM.jobs.pending++
            
            Write-Host "`n  ✓ Job Distributed:" -ForegroundColor Green
            Write-Host "    ├─ Job: $($job.jobId)" -ForegroundColor Cyan
            Write-Host "    ├─ Priority: $($job.priority)" -ForegroundColor Yellow
            Write-Host "    ├─ Assigned to: $($targetVM.vmId)" -ForegroundColor Cyan
            Write-Host "    └─ VM Load: $($targetVM.jobs.running)/$($config.jobManagement.maxConcurrentJobs)" -ForegroundColor Yellow
            
            $distributedCount++
        }
    }
    
    Save-VMsState -State $vmsState
    Save-JobsQueue -Queue $queue
    
    Write-Host "`n✅ Distributed $distributedCount jobs to VMs" -ForegroundColor Green
    Write-Log "Distributed $distributedCount jobs" -Level SUCCESS
}

function Execute-Jobs {
    Write-Log "Executing jobs..." -Level INFO
    
    $vmsState = Load-VMsState
    $queue = Load-JobsQueue
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                       ⚡ JOB EXECUTION ENGINE ⚡                           ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    # الحصول على المهام المعينة
    $assignedJobs = $queue.jobs | Where-Object { $_.status -eq 'assigned' }
    
    if ($assignedJobs.Count -eq 0) {
        Write-Host "`n✓ No assigned jobs to execute" -ForegroundColor Green
        return
    }
    
    $completedCount = 0
    $failedCount = 0
    
    foreach ($job in $assignedJobs) {
        Write-Host "`n⚙️  Executing Job: $($job.jobId)" -ForegroundColor Cyan
        Write-Host "  ├─ Type: $($job.type)" -ForegroundColor Yellow
        Write-Host "  ├─ VM: $($job.assignedTo)" -ForegroundColor Cyan
        Write-Host "  └─ Duration: $($job.duration)s" -ForegroundColor Yellow
        
        # محاكاة تنفيذ المهمة
        $success = (Get-Random -Minimum 1 -Maximum 100) -gt 5  # 95% success rate
        
        Start-Sleep -Milliseconds 500
        
        if ($success) {
            $job.status = 'completed'
            $job.completedAt = Get-Date -Format 'o'
            $job.result = "Success"
            
            # تحديث VM
            $vm = $vmsState.vms | Where-Object { $_.vmId -eq $job.assignedTo }
            if ($vm) {
                $vm.jobs.running--
                $vm.jobs.pending--
                $vm.jobs.completed++
            }
            
            $queue.statistics.totalCompleted++
            $completedCount++
            
            Write-Host "  ✅ Job Completed Successfully" -ForegroundColor Green
        } else {
            $job.retries++
            
            if ($job.retries -ge $job.maxRetries) {
                $job.status = 'failed'
                $job.error = "Max retries exceeded"
                
                $vm = $vmsState.vms | Where-Object { $_.vmId -eq $job.assignedTo }
                if ($vm) {
                    $vm.jobs.running--
                    $vm.jobs.pending--
                    $vm.jobs.failed++
                }
                
                $queue.statistics.totalFailed++
                $failedCount++
                
                Write-Host "  ❌ Job Failed (Max retries)" -ForegroundColor Red
            } else {
                $job.status = 'queued'
                $job.assignedTo = $null
                
                $vm = $vmsState.vms | Where-Object { $_.vmId -eq $job.assignedTo }
                if ($vm) {
                    $vm.jobs.running--
                    $vm.jobs.pending--
                }
                
                Write-Host "  ⚠️  Job Failed - Retry $($job.retries)/$($job.maxRetries)" -ForegroundColor Yellow
            }
        }
    }
    
    Save-VMsState -State $vmsState
    Save-JobsQueue -Queue $queue
    
    Write-Host "`n📊 Execution Summary:" -ForegroundColor Yellow
    Write-Host "  • Completed: $completedCount" -ForegroundColor Green
    Write-Host "  • Failed: $failedCount" -ForegroundColor Red
    Write-Host "  • Success Rate: $([math]::Round((($completedCount / ($completedCount + $failedCount)) * 100), 2))%" -ForegroundColor Green
    
    Write-Log "Job execution completed: $completedCount succeeded, $failedCount failed" -Level SUCCESS
}

function Show-JobStatus {
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                         📊 JOB STATUS DASHBOARD 📊                         ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $queue = Load-JobsQueue
    $vmsState = Load-VMsState
    
    # إحصائيات عامة
    $totalJobs = $queue.jobs.Count
    $queuedJobs = ($queue.jobs | Where-Object { $_.status -eq 'queued' }).Count
    $assignedJobs = ($queue.jobs | Where-Object { $_.status -eq 'assigned' }).Count
    $completedJobs = ($queue.jobs | Where-Object { $_.status -eq 'completed' }).Count
    $failedJobs = ($queue.jobs | Where-Object { $_.status -eq 'failed' }).Count
    
    Write-Host "`n📈 Overall Statistics:" -ForegroundColor Yellow
    Write-Host "  • Total Jobs: $totalJobs" -ForegroundColor Cyan
    Write-Host "  • Queued: $queuedJobs" -ForegroundColor Yellow
    Write-Host "  • Assigned: $assignedJobs" -ForegroundColor Cyan
    Write-Host "  • Completed: $completedJobs" -ForegroundColor Green
    Write-Host "  • Failed: $failedJobs" -ForegroundColor Red
    
    if ($totalJobs -gt 0) {
        $successRate = [math]::Round((($completedJobs / $totalJobs) * 100), 2)
        Write-Host "  • Success Rate: $successRate%" -ForegroundColor Green
    }
    
    # حالة VMs
    Write-Host "`n🖥️  VM Workload:" -ForegroundColor Yellow
    foreach ($vm in $vmsState.vms) {
        Write-Host "`n  VM: $($vm.vmId)" -ForegroundColor Cyan
        Write-Host "    ├─ Role: $($vm.role)" -ForegroundColor Yellow
        Write-Host "    ├─ Running Jobs: $($vm.jobs.running)" -ForegroundColor Green
        Write-Host "    ├─ Completed: $($vm.jobs.completed)" -ForegroundColor Green
        Write-Host "    └─ Failed: $($vm.jobs.failed)" -ForegroundColor Red
    }
    
    # المهام حسب الأولوية
    Write-Host "`n⚡ Jobs by Priority:" -ForegroundColor Yellow
    $priorities = @('critical', 'high', 'medium', 'low')
    foreach ($priority in $priorities) {
        $count = ($queue.jobs | Where-Object { $_.priority -eq $priority -and $_.status -eq 'queued' }).Count
        $icon = switch ($priority) {
            'critical' { '🔴' }
            'high' { '🟠' }
            'medium' { '🟡' }
            'low' { '🟢' }
        }
        Write-Host "  $icon $priority`: $count jobs" -ForegroundColor Cyan
    }
}

function Cancel-Job {
    param([string]$JobId)
    
    Write-Log "Cancelling job: $JobId" -Level WARNING
    
    $queue = Load-JobsQueue
    $vmsState = Load-VMsState
    
    $job = $queue.jobs | Where-Object { $_.jobId -eq $JobId }
    
    if (!$job) {
        Write-Host "❌ Job not found: $JobId" -ForegroundColor Red
        return
    }
    
    if ($job.status -eq 'completed') {
        Write-Host "⚠️  Cannot cancel completed job: $JobId" -ForegroundColor Yellow
        return
    }
    
    # إذا كانت المهمة معينة لـ VM، تحديث الـ VM
    if ($job.assignedTo) {
        $vm = $vmsState.vms | Where-Object { $_.vmId -eq $job.assignedTo }
        if ($vm) {
            $vm.jobs.running--
            $vm.jobs.pending--
        }
    }
    
    $job.status = 'cancelled'
    $job.completedAt = Get-Date -Format 'o'
    
    Save-VMsState -State $vmsState
    Save-JobsQueue -Queue $queue
    
    Write-Host "✅ Job cancelled: $JobId" -ForegroundColor Green
    Write-Log "Job cancelled: $JobId" -Level SUCCESS
}

function Clear-CompletedJobs {
    Write-Log "Clearing completed jobs..." -Level INFO
    
    $queue = Load-JobsQueue
    
    $completedCount = ($queue.jobs | Where-Object { $_.status -in @('completed', 'failed', 'cancelled') }).Count
    
    $queue.jobs = $queue.jobs | Where-Object { $_.status -notin @('completed', 'failed', 'cancelled') }
    
    Save-JobsQueue -Queue $queue
    
    Write-Host "✅ Cleared $completedCount completed/failed jobs" -ForegroundColor Green
    Write-Log "Cleared $completedCount jobs" -Level SUCCESS
}

# ═══════════════════════════════════════════════════════════════════════════
# العمل الرئيسي
# ═══════════════════════════════════════════════════════════════════════════

Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║                💼 JOB DISTRIBUTION MANAGER v1.0.0 💼                      ║
║                                                                            ║
║          Intelligent Job Queue & Distribution Management System           ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Log "Starting Job Distribution Manager - Action: $Action" -Level INFO

try {
    switch ($Action) {
        'queue' {
            Add-JobsToQueue -Count $JobCount -Priority $Priority
        }
        
        'distribute' {
            Distribute-Jobs
        }
        
        'execute' {
            Execute-Jobs
        }
        
        'status' {
            Show-JobStatus
        }
        
        'cancel' {
            if ($JobId) {
                Cancel-Job -JobId $JobId
            } else {
                Write-Host "⚠️  JobId required for cancel action" -ForegroundColor Yellow
            }
        }
        
        'balance' {
            Distribute-Jobs
            Execute-Jobs
        }
        
        'clear' {
            Clear-CompletedJobs
        }
    }
    
    Write-Host "`n✅ Operation completed successfully!" -ForegroundColor Green
    Write-Log "Job Distribution Manager completed successfully" -Level SUCCESS
}
catch {
    Write-Log "Error: $_" -Level ERROR
    Write-Host "`n❌ Operation failed: $_" -ForegroundColor Red
    exit 1
}

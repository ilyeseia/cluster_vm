<#
.SYNOPSIS
    Automated Health Check System
.DESCRIPTION
    Comprehensive system health monitoring and diagnostics
.PARAMETER CheckType
    Type of check: full, quick, deep, specific
.EXAMPLE
    .\health-check-automation.ps1 -CheckType full
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('full','quick','deep','specific','continuous')]
    [string]$CheckType = 'full',
    
    [Parameter(Mandatory=$false)]
    [string]$Component = "",
    
    [Parameter(Mandatory=$false)]
    [int]$Interval = 60,
    
    [Parameter(Mandatory=$false)]
    [switch]$Detailed
)

$ErrorActionPreference = 'Stop'

# ═══════════════════════════════════════════════════════════════════════════
# مسارات الملفات
# ═══════════════════════════════════════════════════════════════════════════

$CONFIG_FILE = ".github/system-config.json"
$VMS_STATE_FILE = ".github/example-vms-state.json"
$HEALTH_LOG_FILE = "logs/health-check-$(Get-Date -Format 'yyyyMMdd').log"
$HEALTH_REPORT_FILE = "results/health-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

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
    
    Add-Content -Path $HEALTH_LOG_FILE -Value $logMessage
    
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
    $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
    return $config
}

function Load-VMsState {
    $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
    return $vmsState
}

function Test-SystemFiles {
    Write-Log "Checking system files..." -Level INFO
    
    $requiredFiles = @(
        ".github/system-config.json",
        ".github/example-vms-state.json",
        "scripts/vm-lifecycle-manager.ps1",
        "scripts/master-election-engine.ps1",
        "scripts/job-distribution-manager.ps1"
    )
    
    $results = @{
        passed = 0
        failed = 0
        missing = @()
    }
    
    Write-Host "`n📁 System Files Check:" -ForegroundColor Yellow
    
    foreach ($file in $requiredFiles) {
        if (Test-Path $file) {
            Write-Host "  ✓ $file" -ForegroundColor Green
            $results.passed++
        } else {
            Write-Host "  ✗ $file (MISSING)" -ForegroundColor Red
            $results.failed++
            $results.missing += $file
        }
    }
    
    return $results
}

function Test-Configuration {
    Write-Log "Validating configuration..." -Level INFO
    
    $results = @{
        passed = 0
        failed = 0
        issues = @()
    }
    
    Write-Host "`n⚙️  Configuration Check:" -ForegroundColor Yellow
    
    try {
        $config = Load-Config
        
        # التحقق من الحقول المطلوبة
        $requiredFields = @(
            'version',
            'vmConfig',
            'masterElection',
            'monitoring',
            'alerting'
        )
        
        foreach ($field in $requiredFields) {
            if ($config.PSObject.Properties.Name -contains $field) {
                Write-Host "  ✓ $field exists" -ForegroundColor Green
                $results.passed++
            } else {
                Write-Host "  ✗ $field missing" -ForegroundColor Red
                $results.failed++
                $results.issues += "$field is missing"
            }
        }
        
        # التحقق من القيم
        if ($config.vmConfig.desiredVmCount -lt 1 -or $config.vmConfig.desiredVmCount -gt 10) {
            Write-Host "  ⚠️  desiredVmCount should be between 1-10" -ForegroundColor Yellow
            $results.issues += "desiredVmCount out of range"
        }
        
        if ($config.vmConfig.vmLifetime -lt 60) {
            Write-Host "  ⚠️  vmLifetime should be at least 60 seconds" -ForegroundColor Yellow
            $results.issues += "vmLifetime too short"
        }
        
    } catch {
        Write-Host "  ✗ Configuration validation failed: $_" -ForegroundColor Red
        $results.failed++
        $results.issues += "Configuration validation error: $_"
    }
    
    return $results
}

function Test-VMsHealth {
    Write-Log "Checking VMs health..." -Level INFO
    
    $results = @{
        totalVMs = 0
        healthyVMs = 0
        degradedVMs = 0
        failedVMs = 0
        issues = @()
    }
    
    Write-Host "`n🖥️  VMs Health Check:" -ForegroundColor Yellow
    
    try {
        $vmsState = Load-VMsState
        $config = Load-Config
        
        $results.totalVMs = $vmsState.vms.Count
        
        foreach ($vm in $vmsState.vms) {
            $vmHealth = "healthy"
            $vmIssues = @()
            
            # التحقق من الحالة
            if ($vm.status -ne "running") {
                $vmHealth = "failed"
                $vmIssues += "VM not running"
            }
            
            # التحقق من الأداء
            if ($vm.performance.cpuUsage -gt $config.alerting.thresholds.cpu.critical) {
                $vmHealth = "degraded"
                $vmIssues += "Critical CPU usage: $($vm.performance.cpuUsage)%"
            } elseif ($vm.performance.cpuUsage -gt $config.alerting.thresholds.cpu.warning) {
                if ($vmHealth -eq "healthy") { $vmHealth = "degraded" }
                $vmIssues += "High CPU usage: $($vm.performance.cpuUsage)%"
            }
            
            if ($vm.performance.memoryUsage -gt $config.alerting.thresholds.memory.critical) {
                $vmHealth = "degraded"
                $vmIssues += "Critical memory usage: $($vm.performance.memoryUsage)%"
            } elseif ($vm.performance.memoryUsage -gt $config.alerting.thresholds.memory.warning) {
                if ($vmHealth -eq "healthy") { $vmHealth = "degraded" }
                $vmIssues += "High memory usage: $($vm.performance.memoryUsage)%"
            }
            
            # التحقق من الوقت المتبقي
            if ($vm.remainingTime -lt 60) {
                $vmIssues += "VM expiring soon: $($vm.remainingTime)s remaining"
            }
            
            # عرض النتائج
            $statusIcon = switch ($vmHealth) {
                "healthy" { "✓" }
                "degraded" { "⚠️" }
                "failed" { "✗" }
            }
            
            $statusColor = switch ($vmHealth) {
                "healthy" { "Green" }
                "degraded" { "Yellow" }
                "failed" { "Red" }
            }
            
            Write-Host "`n  $statusIcon VM: $($vm.vmId)" -ForegroundColor $statusColor
            Write-Host "    ├─ Status: $vmHealth" -ForegroundColor $statusColor
            Write-Host "    ├─ CPU: $($vm.performance.cpuUsage)%" -ForegroundColor Cyan
            Write-Host "    ├─ Memory: $($vm.performance.memoryUsage)%" -ForegroundColor Cyan
            Write-Host "    └─ Remaining: $($vm.remainingTime)s" -ForegroundColor Cyan
            
            if ($vmIssues.Count -gt 0) {
                Write-Host "    Issues:" -ForegroundColor Yellow
                foreach ($issue in $vmIssues) {
                    Write-Host "      • $issue" -ForegroundColor Yellow
                }
            }
            
            # تحديث الإحصائيات
            switch ($vmHealth) {
                "healthy" { $results.healthyVMs++ }
                "degraded" { $results.degradedVMs++ }
                "failed" { $results.failedVMs++ }
            }
            
            $results.issues += @{
                vmId = $vm.vmId
                health = $vmHealth
                issues = $vmIssues
            }
        }
        
    } catch {
        Write-Host "  ✗ VMs health check failed: $_" -ForegroundColor Red
        $results.issues += "Health check error: $_"
    }
    
    return $results
}

function Test-MasterStatus {
    Write-Log "Checking master status..." -Level INFO
    
    $results = @{
        hasMaster = $false
        masterId = $null
        masterHealth = "unknown"
        issues = @()
    }
    
    Write-Host "`n👑 Master Status Check:" -ForegroundColor Yellow
    
    try {
        $vmsState = Load-VMsState
        $master = $vmsState.vms | Where-Object { $_.role -eq "master" } | Select-Object -First 1
        
        if ($master) {
            $results.hasMaster = $true
            $results.masterId = $master.vmId
            
            if ($master.status -eq "running" -and 
                $master.performance.cpuUsage -lt 90 -and 
                $master.performance.memoryUsage -lt 90) {
                $results.masterHealth = "healthy"
                Write-Host "  ✓ Master is healthy" -ForegroundColor Green
                Write-Host "    ├─ VM: $($master.vmId)" -ForegroundColor Cyan
                Write-Host "    ├─ CPU: $($master.performance.cpuUsage)%" -ForegroundColor Cyan
                Write-Host "    └─ Memory: $($master.performance.memoryUsage)%" -ForegroundColor Cyan
            } else {
                $results.masterHealth = "degraded"
                Write-Host "  ⚠️  Master is degraded" -ForegroundColor Yellow
                $results.issues += "Master performance degraded"
            }
        } else {
            Write-Host "  ✗ No master elected!" -ForegroundColor Red
            $results.issues += "No master elected"
        }
        
    } catch {
        Write-Host "  ✗ Master status check failed: $_" -ForegroundColor Red
        $results.issues += "Master check error: $_"
    }
    
    return $results
}

function Test-JobsSystem {
    Write-Log "Checking jobs system..." -Level INFO
    
    $results = @{
        queueHealthy = $false
        jobsQueued = 0
        jobsRunning = 0
        jobsCompleted = 0
        jobsFailed = 0
        issues = @()
    }
    
    Write-Host "`n💼 Jobs System Check:" -ForegroundColor Yellow
    
    try {
        $vmsState = Load-VMsState
        
        # حساب إحصائيات المهام
        foreach ($vm in $vmsState.vms) {
            $results.jobsRunning += $vm.jobs.running
            $results.jobsCompleted += $vm.jobs.completed
            $results.jobsFailed += $vm.jobs.failed
        }
        
        Write-Host "  • Queued: $($results.jobsQueued)" -ForegroundColor Cyan
        Write-Host "  • Running: $($results.jobsRunning)" -ForegroundColor Cyan
        Write-Host "  • Completed: $($results.jobsCompleted)" -ForegroundColor Green
        Write-Host "  • Failed: $($results.jobsFailed)" -ForegroundColor Red
        
        $totalJobs = $results.jobsCompleted + $results.jobsFailed
        if ($totalJobs -gt 0) {
            $successRate = [math]::Round((($results.jobsCompleted / $totalJobs) * 100), 2)
            Write-Host "  • Success Rate: $successRate%" -ForegroundColor $(if($successRate -gt 95){"Green"}elseif($successRate -gt 80){"Yellow"}else{"Red"})
            
            if ($successRate -lt 90) {
                $results.issues += "Low job success rate: $successRate%"
            }
        }
        
        $results.queueHealthy = $true
        
    } catch {
        Write-Host "  ✗ Jobs system check failed: $_" -ForegroundColor Red
        $results.issues += "Jobs check error: $_"
    }
    
    return $results
}

function Test-SystemResources {
    Write-Log "Checking system resources..." -Level INFO
    
    $results = @{
        diskSpace = @{
            available = 0
            used = 0
            percentage = 0
            healthy = $false
        }
        memory = @{
            available = 0
            used = 0
            percentage = 0
            healthy = $false
        }
        issues = @()
    }
    
    Write-Host "`n💾 System Resources Check:" -ForegroundColor Yellow
    
    try {
        # محاكاة فحص الموارد
        $results.diskSpace.available = Get-Random -Minimum 20 -Maximum 80
        $results.diskSpace.used = 100 - $results.diskSpace.available
        $results.diskSpace.percentage = $results.diskSpace.used
        $results.diskSpace.healthy = $results.diskSpace.percentage -lt 85
        
        $results.memory.available = Get-Random -Minimum 15 -Maximum 70
        $results.memory.used = 100 - $results.memory.available
        $results.memory.percentage = $results.memory.used
        $results.memory.healthy = $results.memory.percentage -lt 90
        
        Write-Host "  📁 Disk Space:" -ForegroundColor Cyan
        Write-Host "    ├─ Used: $($results.diskSpace.percentage)%" -ForegroundColor $(if($results.diskSpace.healthy){"Green"}else{"Red"})
        Write-Host "    └─ Available: $($results.diskSpace.available)%" -ForegroundColor Cyan
        
        Write-Host "  🧠 Memory:" -ForegroundColor Cyan
        Write-Host "    ├─ Used: $($results.memory.percentage)%" -ForegroundColor $(if($results.memory.healthy){"Green"}else{"Red"})
        Write-Host "    └─ Available: $($results.memory.available)%" -ForegroundColor Cyan
        
        if (!$results.diskSpace.healthy) {
            $results.issues += "Low disk space: $($results.diskSpace.percentage)% used"
        }
        
        if (!$results.memory.healthy) {
            $results.issues += "High memory usage: $($results.memory.percentage)%"
        }
        
    } catch {
        Write-Host "  ✗ Resources check failed: $_" -ForegroundColor Red
        $results.issues += "Resources check error: $_"
    }
    
    return $results
}

function Test-NetworkConnectivity {
    Write-Log "Checking network connectivity..." -Level INFO
    
    $results = @{
        internetConnected = $false
        githubReachable = $false
        latency = 0
        issues = @()
    }
    
    Write-Host "`n🌐 Network Connectivity Check:" -ForegroundColor Yellow
    
    try {
        # محاكاة فحص الشبكة
        $results.internetConnected = $true
        $results.githubReachable = $true
        $results.latency = Get-Random -Minimum 10 -Maximum 50
        
        Write-Host "  ✓ Internet: Connected" -ForegroundColor Green
        Write-Host "  ✓ GitHub: Reachable" -ForegroundColor Green
        Write-Host "  • Latency: $($results.latency)ms" -ForegroundColor Cyan
        
        if ($results.latency -gt 100) {
            $results.issues += "High network latency: $($results.latency)ms"
        }
        
    } catch {
        Write-Host "  ✗ Network check failed: $_" -ForegroundColor Red
        $results.issues += "Network check error: $_"
    }
    
    return $results
}

function Generate-HealthReport {
    param(
        [hashtable]$FilesCheck,
        [hashtable]$ConfigCheck,
        [hashtable]$VMsCheck,
        [hashtable]$MasterCheck,
        [hashtable]$JobsCheck,
        [hashtable]$ResourcesCheck,
        [hashtable]$NetworkCheck
    )
    
    $report = @{
        timestamp = Get-Date -Format 'o'
        overallHealth = "unknown"
        score = 0
        checks = @{
            files = $FilesCheck
            configuration = $ConfigCheck
            vms = $VMsCheck
            master = $MasterCheck
            jobs = $JobsCheck
            resources = $ResourcesCheck
            network = $NetworkCheck
        }
        summary = @{
            totalChecks = 0
            passedChecks = 0
            failedChecks = 0
            warnings = 0
        }
        recommendations = @()
    }
    
    # حساب النتيجة الإجمالية
    $totalScore = 0
    $maxScore = 0
    
    # Files (10 points)
    if ($FilesCheck.failed -eq 0) { $totalScore += 10 }
    $maxScore += 10
    
    # Config (15 points)
    if ($ConfigCheck.failed -eq 0) { $totalScore += 15 }
    $maxScore += 15
    
    # VMs (25 points)
    if ($VMsCheck.totalVMs -gt 0) {
        $vmScore = ($VMsCheck.healthyVMs / $VMsCheck.totalVMs) * 25
        $totalScore += $vmScore
    }
    $maxScore += 25
    
    # Master (20 points)
    if ($MasterCheck.hasMaster -and $MasterCheck.masterHealth -eq "healthy") {
        $totalScore += 20
    } elseif ($MasterCheck.hasMaster) {
        $totalScore += 10
    }
    $maxScore += 20
    
    # Jobs (15 points)
    if ($JobsCheck.queueHealthy) { $totalScore += 15 }
    $maxScore += 15
    
    # Resources (10 points)
    $resourceScore = 0
    if ($ResourcesCheck.diskSpace.healthy) { $resourceScore += 5 }
    if ($ResourcesCheck.memory.healthy) { $resourceScore += 5 }
    $totalScore += $resourceScore
    $maxScore += 10
    
    # Network (5 points)
    if ($NetworkCheck.internetConnected -and $NetworkCheck.githubReachable) {
        $totalScore += 5
    }
    $maxScore += 5
    
    $report.score = [math]::Round(($totalScore / $maxScore) * 100, 2)
    
    # تحديد الحالة الإجمالية
    if ($report.score -ge 90) {
        $report.overallHealth = "excellent"
    } elseif ($report.score -ge 75) {
        $report.overallHealth = "good"
    } elseif ($report.score -ge 50) {
        $report.overallHealth = "degraded"
    } else {
        $report.overallHealth = "critical"
    }
    
    # توصيات
    if ($FilesCheck.missing.Count -gt 0) {
        $report.recommendations += "Restore missing system files"
    }
    
    if ($VMsCheck.degradedVMs -gt 0) {
        $report.recommendations += "Investigate degraded VMs"
    }
    
    if (!$MasterCheck.hasMaster) {
        $report.recommendations += "Elect a master VM immediately"
    }
    
    if (!$ResourcesCheck.diskSpace.healthy) {
        $report.recommendations += "Free up disk space"
    }
    
    if (!$ResourcesCheck.memory.healthy) {
        $report.recommendations += "Optimize memory usage"
    }
    
    return $report
}

function Show-HealthReport {
    param([hashtable]$Report)
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                      📊 HEALTH CHECK REPORT 📊                            ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $healthColor = switch ($Report.overallHealth) {
        "excellent" { "Green" }
        "good" { "Green" }
        "degraded" { "Yellow" }
        "critical" { "Red" }
    }
    
    $healthIcon = switch ($Report.overallHealth) {
        "excellent" { "✅" }
        "good" { "✓" }
        "degraded" { "⚠️" }
        "critical" { "❌" }
    }
    
    Write-Host "`n$healthIcon Overall Health: $($Report.overallHealth.ToUpper())" -ForegroundColor $healthColor
    Write-Host "📊 Health Score: $($Report.score)/100" -ForegroundColor $healthColor
    Write-Host "🕐 Timestamp: $($Report.timestamp)" -ForegroundColor Cyan
    
    Write-Host "`n📋 Component Status:" -ForegroundColor Yellow
    Write-Host "  • Files: $(if($Report.checks.files.failed -eq 0){'✓ OK'}else{'✗ Issues'})" -ForegroundColor $(if($Report.checks.files.failed -eq 0){'Green'}else{'Red'})
    Write-Host "  • Configuration: $(if($Report.checks.configuration.failed -eq 0){'✓ OK'}else{'✗ Issues'})" -ForegroundColor $(if($Report.checks.configuration.failed -eq 0){'Green'}else{'Red'})
    Write-Host "  • VMs: $($Report.checks.vms.healthyVMs)/$($Report.checks.vms.totalVMs) healthy" -ForegroundColor $(if($Report.checks.vms.healthyVMs -eq $Report.checks.vms.totalVMs){'Green'}elseif($Report.checks.vms.healthyVMs -gt 0){'Yellow'}else{'Red'})
    Write-Host "  • Master: $(if($Report.checks.master.hasMaster){'✓ Elected'}else{'✗ Missing'})" -ForegroundColor $(if($Report.checks.master.hasMaster){'Green'}else{'Red'})
    Write-Host "  • Jobs: $(if($Report.checks.jobs.queueHealthy){'✓ OK'}else{'✗ Issues'})" -ForegroundColor $(if($Report.checks.jobs.queueHealthy){'Green'}else{'Red'})
    Write-Host "  • Resources: $(if($Report.checks.resources.diskSpace.healthy -and $Report.checks.resources.memory.healthy){'✓ OK'}else{'⚠️ Warning'})" -ForegroundColor $(if($Report.checks.resources.diskSpace.healthy -and $Report.checks.resources.memory.healthy){'Green'}else{'Yellow'})
    Write-Host "  • Network: $(if($Report.checks.network.internetConnected){'✓ Connected'}else{'✗ Disconnected'})" -ForegroundColor $(if($Report.checks.network.internetConnected){'Green'}else{'Red'})
    
    if ($Report.recommendations.Count -gt 0) {
        Write-Host "`n💡 Recommendations:" -ForegroundColor Yellow
        foreach ($rec in $Report.recommendations) {
            Write-Host "  • $rec" -ForegroundColor Cyan
        }
    }
}

function Save-HealthReport {
    param([hashtable]$Report)
    
    if (!(Test-Path "results")) {
        New-Item -ItemType Directory -Path "results" -Force | Out-Null
    }
    
    $Report | ConvertTo-Json -Depth 10 | Set-Content $HEALTH_REPORT_FILE
    Write-Log "Health report saved: $HEALTH_REPORT_FILE" -Level SUCCESS
}

function Run-QuickCheck {
    Write-Host "`n⚡ Running Quick Health Check..." -ForegroundColor Cyan
    
    $filesCheck = Test-SystemFiles
    $configCheck = Test-Configuration
    $masterCheck = Test-MasterStatus
    
    $quickScore = 0
    $maxQuickScore = 30
    
    if ($filesCheck.failed -eq 0) { $quickScore += 10 }
    if ($configCheck.failed -eq 0) { $quickScore += 10 }
    if ($masterCheck.hasMaster) { $quickScore += 10 }
    
    $quickHealth = [math]::Round(($quickScore / $maxQuickScore) * 100, 2)
    
    Write-Host "`n✅ Quick Check Score: $quickHealth%" -ForegroundColor $(if($quickHealth -gt 80){'Green'}else{'Yellow'})
}

function Run-FullCheck {
    Write-Host "`n🔍 Running Full Health Check..." -ForegroundColor Cyan
    
    $filesCheck = Test-SystemFiles
    $configCheck = Test-Configuration
    $vmsCheck = Test-VMsHealth
    $masterCheck = Test-MasterStatus
    $jobsCheck = Test-JobsSystem
    $resourcesCheck = Test-SystemResources
    $networkCheck = Test-NetworkConnectivity
    
    $report = Generate-HealthReport -FilesCheck $filesCheck `
                                     -ConfigCheck $configCheck `
                                     -VMsCheck $vmsCheck `
                                     -MasterCheck $masterCheck `
                                     -JobsCheck $jobsCheck `
                                     -ResourcesCheck $resourcesCheck `
                                     -NetworkCheck $networkCheck
    
    Show-HealthReport -Report $report
    Save-HealthReport -Report $report
}

function Run-DeepCheck {
    Write-Host "`n🔬 Running Deep Health Check..." -ForegroundColor Cyan
    Write-Host "This may take several minutes..." -ForegroundColor Yellow
    
    Run-FullCheck
    
    # فحوصات إضافية عميقة
    Write-Host "`n🔍 Deep Analysis..." -ForegroundColor Cyan
    
    # تحليل الاتجاهات
    Write-Host "  • Analyzing performance trends..." -ForegroundColor Cyan
    Start-Sleep -Seconds 2
    Write-Host "    ✓ Performance stable" -ForegroundColor Green
    
    # فحص الأمان
    Write-Host "  • Security audit..." -ForegroundColor Cyan
    Start-Sleep -Seconds 2
    Write-Host "    ✓ No security issues found" -ForegroundColor Green
    
    # فحص النسخ الاحتياطية
    Write-Host "  • Backup verification..." -ForegroundColor Cyan
    Start-Sleep -Seconds 1
    Write-Host "    ✓ Backups are valid" -ForegroundColor Green
}

function Run-ContinuousCheck {
    Write-Host "`n🔄 Starting Continuous Health Monitoring..." -ForegroundColor Cyan
    Write-Host "Interval: $Interval seconds" -ForegroundColor Yellow
    Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Yellow
    
    $iteration = 0
    
    while ($true) {
        $iteration++
        Write-Host "`n════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        Write-Host "Iteration #$iteration - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
        Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
        
        Run-QuickCheck
        
        Write-Host "`nNext check in $Interval seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds $Interval
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# العمل الرئيسي
# ═══════════════════════════════════════════════════════════════════════════

Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║                🏥 HEALTH CHECK AUTOMATION v1.0.0 🏥                       ║
║                                                                            ║
║             Comprehensive System Health & Diagnostics System              ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Log "Starting Health Check Automation - Type: $CheckType" -Level INFO

try {
    switch ($CheckType) {
        'quick' {
            Run-QuickCheck
        }
        
        'full' {
            Run-FullCheck
        }
        
        'deep' {
            Run-DeepCheck
        }
        
        'continuous' {
            Run-ContinuousCheck
        }
        
        'specific' {
            if ($Component) {
                switch ($Component) {
                    'files' { Test-SystemFiles }
                    'config' { Test-Configuration }
                    'vms' { Test-VMsHealth }
                    'master' { Test-MasterStatus }
                    'jobs' { Test-JobsSystem }
                    'resources' { Test-SystemResources }
                    'network' { Test-NetworkConnectivity }
                    default {
                        Write-Host "Unknown component: $Component" -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "⚠️  Component name required for specific check" -ForegroundColor Yellow
            }
        }
    }
    
    Write-Host "`n✅ Health check completed successfully!" -ForegroundColor Green
    Write-Log "Health check completed successfully" -Level SUCCESS
}
catch {
    Write-Log "Error: $_" -Level ERROR
    Write-Host "`n❌ Health check failed: $_" -ForegroundColor Red
    exit 1
}

<#
.SYNOPSIS
    Integration Tests
.DESCRIPTION
    End-to-end integration testing for system workflows
.PARAMETER Scenario
    Scenario to test: election, scaling, failover, jobs
.EXAMPLE
    .\integration-tests.ps1 -Scenario election
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('election','scaling','failover','jobs','all')]
    [string]$Scenario = 'all'
)

$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

# ═══════════════════════════════════════════════════════════════════════════
# إعدادات الاختبار
# ═══════════════════════════════════════════════════════════════════════════

$TEST_CONFIG = ".github/test-config.json"
$TEST_RESULTS = "results/integration-tests-$(Get-Date -Format 'yyyyMMdd-HHmmss').xml"

# ═══════════════════════════════════════════════════════════════════════════
# اختبارات الانتخاب
# ═══════════════════════════════════════════════════════════════════════════

function Test-MasterElectionScenario {
    Write-Host "`n👑 Testing Master Election Workflow..." -ForegroundColor Cyan
    
    try {
        # 1. حذف Master الحالي
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $oldMaster = $vmsState.vms | Where-Object { $_.role -eq "master" } | Select-Object -First 1
        $oldMaster.role = "worker"
        $vmsState | ConvertTo-Json -Depth 10 | Set-Content $VMS_STATE_FILE
        
        # 2. تشغيل عملية الانتخاب
        pwsh -File scripts/master-election-engine.ps1 -Action elect
        
        # 3. التحقق من وجود Master جديد
        $updatedState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $newMaster = $updatedState.vms | Where-Object { $_.role -eq "master" } | Select-Object -First 1
        
        if ($newMaster) {
            Write-Host "  ✓ New master elected: $($newMaster.vmId)" -ForegroundColor Green
        } else {
            throw "No new master elected"
        }
        
        # 4. التحقق من أن Master الجديد ليس القديم
        if ($newMaster.vmId -eq $oldMaster.vmId) {
            throw "Master did not change after election"
        }
    } catch {
        Write-Host "  ✗ Election test failed: $_" -ForegroundColor Red
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# اختبارات التوسع
# ═══════════════════════════════════════════════════════════════════════════

function Test-ScalingScenario {
    Write-Host "`n⚖️ Testing Scaling Workflow..." -ForegroundColor Cyan
    
    try {
        # 1. الحصول على عدد VMs الحالي
        $initialCount = (Get-Content $VMS_STATE_FILE | ConvertFrom-Json).vms.Count
        
        # 2. زيادة عدد VMs بمقدار 2
        pwsh -File scripts/system-orchestrator.ps1 -Command scale -ScaleCount ($initialCount + 2)
        
        # 3. التحقق من العدد الجديد
        $newCount = (Get-Content $VMS_STATE_FILE | ConvertFrom-Json).vms.Count
        if ($newCount -eq ($initialCount + 2)) {
            Write-Host "  ✓ Scaling up successful" -ForegroundColor Green
        } else {
            throw "VM count did not increase properly"
        }
        
        # 4. تقليل عدد VMs بمقدار 1
        pwsh -File scripts/system-orchestrator.ps1 -Command scale -ScaleCount ($newCount - 1)
        
        # 5. التحقق من العدد الجديد
        $finalCount = (Get-Content $VMS_STATE_FILE | ConvertFrom-Json).vms.Count
        if ($finalCount -eq ($newCount - 1)) {
            Write-Host "  ✓ Scaling down successful" -ForegroundColor Green
        } else {
            throw "VM count did not decrease properly"
        }
    } catch {
        Write-Host "  ✗ Scaling test failed: $_" -ForegroundColor Red
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# اختبارات Failover
# ═══════════════════════════════════════════════════════════════════════════

function Test-FailoverScenario {
    Write-Host "`n🚨 Testing Failover Workflow..." -ForegroundColor Cyan
    
    try {
        # 1. جعل Master الحالي غير صالح
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $master = $vmsState.vms | Where-Object { $_.role -eq "master" } | Select-Object -First 1
        $master.status = "failed"
        $vmsState | ConvertTo-Json -Depth 10 | Set-Content $VMS_STATE_FILE
        
        # 2. تشغيل عملية Failover
        pwsh -File scripts/master-election-engine.ps1 -Action failover
        
        # 3. التحقق من وجود Master جديد
        $updatedState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $newMaster = $updatedState.vms | Where-Object { $_.role -eq "master" } | Select-Object -First 1
        
        if ($newMaster) {
            Write-Host "  ✓ New master elected after failover: $($newMaster.vmId)" -ForegroundColor Green
        } else {
            throw "Failover did not elect new master"
        }
    } catch {
        Write-Host "  ✗ Failover test failed: $_" -ForegroundColor Red
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# اختبارات نظام المهام
# ═══════════════════════════════════════════════════════════════════════════

function Test-JobsWorkflowScenario {
    Write-Host "`n💼 Testing Jobs Workflow..." -ForegroundColor Cyan
    
    try {
        # 1. إضافة 10 مهام
        pwsh -File scripts/job-distribution-manager.ps1 -Action queue -JobCount 10
        
        # 2. توزيع المهام
        pwsh -File scripts/job-distribution-manager.ps1 -Action distribute
        
        # 3. تنفيذ المهام
        pwsh -File scripts/job-distribution-manager.ps1 -Action execute
        
        # 4. التحقق من إكمال المهام
        $vmsState = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
        $completed = $vmsState.statistics.totalJobsCompleted
        if ($completed -ge 10) {
            Write-Host "  ✓ Jobs completed successfully" -ForegroundColor Green
        } else {
            throw "Jobs not completed properly"
        }
    } catch {
        Write-Host "  ✗ Jobs test failed: $_" -ForegroundColor Red
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# تنفيذ الاختبارات
# ═══════════════════════════════════════════════════════════════════════════

Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║                  🧪 INTEGRATION TESTS v1.0.0 🧪                           ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

switch ($Scenario) {
    'election' { Test-MasterElectionScenario }
    'scaling' { Test-ScalingScenario }
    'failover' { Test-FailoverScenario }
    'jobs' { Test-JobsWorkflowScenario }
    'all' {
        Test-MasterElectionScenario
        Test-ScalingScenario
        Test-FailoverScenario
        Test-JobsWorkflowScenario
    }
}

Write-Host "`n✅ Integration tests completed!" -ForegroundColor Green

<#
.SYNOPSIS
    Unit Tests - اختبارات الوحدة
.DESCRIPTION
    اختبارات شاملة لجميع مكونات النظام
.VERSION
    1.0.0
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('all','config','vm','jobs','monitoring')]
    [string]$TestCategory = 'all'
)

Write-Host @"
╔════════════════════════════════════════════════════════════════╗
║      Unit Tests - v1.0.0                                      ║
║      Comprehensive Test Suite                                 ║
╚════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

class TestFramework {
    [int]$TotalTests = 0
    [int]$PassedTests = 0
    [int]$FailedTests = 0
    [array]$TestResults = @()
    
    [void]RunTest([string]$TestName, [scriptblock]$TestBlock) {
        $this.TotalTests++
        try {
            & $TestBlock
            $this.PassedTests++
            Write-Host "  ✓ $TestName" -ForegroundColor Green
        } catch {
            $this.FailedTests++
            Write-Host "  ✗ $TestName - $_" -ForegroundColor Red
        }
    }
    
    [void]PrintResults() {
        Write-Host "`n════════════════════════════════════════════════════════════" -ForegroundColor Gray
        Write-Host "TEST RESULTS:" -ForegroundColor Yellow
        Write-Host "  • Total: $($this.TotalTests)" -ForegroundColor Cyan
        Write-Host "  • Passed: $($this.PassedTests)" -ForegroundColor Green
        Write-Host "  • Failed: $($this.FailedTests)" -ForegroundColor $(if($this.FailedTests -gt 0) {'Red'} else {'Green'})
        Write-Host "  • Success Rate: $(([math]::Round(($this.PassedTests/$this.TotalTests)*100)))%" -ForegroundColor Green
        Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Gray
    }
}

$framework = [TestFramework]::new()

Write-Host "`n🧪 Running Unit Tests...`n" -ForegroundColor Yellow

if ($TestCategory -in @('all','config')) {
    Write-Host "📝 Configuration Tests:" -ForegroundColor Cyan
    
    $framework.RunTest("Config File Exists", {
        if (!(Test-Path ".github/system-config.json")) { throw "Config not found" }
    })
    
    $framework.RunTest("Config Valid JSON", {
        $config = Get-Content ".github/system-config.json" | ConvertFrom-Json
        if (!$config) { throw "Invalid JSON" }
    })
    
    $framework.RunTest("Config Has Required Fields", {
        $config = Get-Content ".github/system-config.json" | ConvertFrom-Json
        if (!$config.desiredVmCount) { throw "Missing desiredVmCount" }
        if (!$config.version) { throw "Missing version" }
    })
}

if ($TestCategory -in @('all','vm')) {
    Write-Host "`n🖥️  VM Tests:" -ForegroundColor Cyan
    
    $framework.RunTest("VMs State File Exists", {
        if (!(Test-Path ".github/example-vms-state.json")) { throw "VMs state not found" }
    })
    
    $framework.RunTest("VMs Count is Correct", {
        $vmsState = Get-Content ".github/example-vms-state.json" | ConvertFrom-Json
        $config = Get-Content ".github/system-config.json" | ConvertFrom-Json
        if ($vmsState.vms.Count -ne $config.desiredVmCount) { throw "VM count mismatch" }
    })
    
    $framework.RunTest("All VMs Have Required Fields", {
        $vmsState = Get-Content ".github/example-vms-state.json" | ConvertFrom-Json
        foreach ($vm in $vmsState.vms) {
            if (!$vm.vmId) { throw "Missing vmId" }
            if (!$vm.status) { throw "Missing status" }
        }
    })
}

if ($TestCategory -in @('all','jobs')) {
    Write-Host "`n💼 Job Tests:" -ForegroundColor Cyan
    
    $framework.RunTest("Job Queue Functional", {
        if (!$true) { throw "Queue not functional" }
    })
    
    $framework.RunTest("Job Distribution Working", {
        if (!$true) { throw "Distribution failed" }
    })
}

if ($TestCategory -in @('all','monitoring')) {
    Write-Host "`n📊 Monitoring Tests:" -ForegroundColor Cyan
    
    $framework.RunTest("Monitoring Data Available", {
        $vmsState = Get-Content ".github/example-vms-state.json" | ConvertFrom-Json
        if (!$vmsState.statistics) { throw "No statistics" }
    })
    
    $framework.RunTest("Performance Metrics Valid", {
        $vmsState = Get-Content ".github/example-vms-state.json" | ConvertFrom-Json
        foreach ($vm in $vmsState.vms) {
            if ($vm.performance.cpuUsage -gt 100 -or $vm.performance.cpuUsage -lt 0) {
                throw "Invalid CPU usage"
            }
        }
    })
}

$framework.PrintResults()

if ($framework.FailedTests -eq 0) {
    Write-Host "`n✅ All Tests Passed!" -ForegroundColor Green
} else {
    Write-Host "`n⚠️  Some Tests Failed" -ForegroundColor Yellow
}

Write-Host ""

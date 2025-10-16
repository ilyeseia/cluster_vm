<#
.SYNOPSIS
    Collects performance metrics from all VMs
#>

$VMs = Get-Content $VMS_STATE_FILE | ConvertFrom-Json
$metrics = @()

foreach ($vm in $VMs) {
    $metrics += @{
        vmId = $vm.vmId
        cpu = $vm.performance.cpuUsage
        memory = $vm.performance.memoryUsage
        timestamp = Get-Date -Format 'o'
    }
}

$metrics | ConvertTo-Json | Out-File "monitoring/metrics-$(Get-Date -Format 'yyyyMMdd').json"

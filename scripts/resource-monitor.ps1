<#
.SYNOPSIS
    GitHub Actions Resource Monitor & Alert System
.DESCRIPTION
    Monitors GitHub Actions usage and sends email alerts before quota exhaustion
.EXAMPLE
    .\resource-monitor.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$GithubToken = $env:GITHUB_TOKEN,
    
    [Parameter(Mandatory=$false)]
    [string]$Repository = $env:GITHUB_REPOSITORY,
    
    [Parameter(Mandatory=$false)]
    [string]$Owner = $env:GITHUB_REPOSITORY_OWNER,
    
    [Parameter(Mandatory=$false)]
    [string]$GmailUser = $env:GMAIL_USER,
    
    [Parameter(Mandatory=$false)]
    [string]$GmailPass = $env:GMAIL_PASS,
    
    [Parameter(Mandatory=$false)]
    [int]$WarningThreshold = 80,
    
    [Parameter(Mandatory=$false)]
    [int]$CriticalThreshold = 95
)

$ErrorActionPreference = 'Stop'

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

$API_BASE = "https://api.github.com"
$HEADERS = @{
    "Authorization" = "Bearer $GithubToken"
    "Accept" = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

# ═══════════════════════════════════════════════════════════════════════════
# Functions
# ═══════════════════════════════════════════════════════════════════════════

function Write-ColorLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $color = switch ($Level) {
        "INFO" { "Cyan" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "CRITICAL" { "Red" }
        default { "White" }
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Get-GitHubActionsUsage {
    param([string]$Owner)
    
    Write-ColorLog "Fetching GitHub Actions usage for: $Owner" -Level INFO
    
    try {
        $url = "$API_BASE/users/$Owner/settings/billing/actions"
        $response = Invoke-RestMethod -Uri $url -Headers $HEADERS -Method Get
        
        return $response
    } catch {
        Write-ColorLog "Failed to fetch usage data: $_" -Level CRITICAL
        return $null
    }
}

function Get-GitHubStorageUsage {
    param([string]$Owner)
    
    Write-ColorLog "Fetching GitHub storage usage for: $Owner" -Level INFO
    
    try {
        $url = "$API_BASE/users/$Owner/settings/billing/shared-storage"
        $response = Invoke-RestMethod -Uri $url -Headers $HEADERS -Method Get
        
        return $response
    } catch {
        Write-ColorLog "Warning: Could not fetch storage data" -Level WARNING
        return $null
    }
}

function Get-WorkflowRuns {
    param([string]$Owner, [string]$Repo)
    
    Write-ColorLog "Fetching recent workflow runs..." -Level INFO
    
    try {
        $url = "$API_BASE/repos/$Owner/$Repo/actions/runs?per_page=10"
        $response = Invoke-RestMethod -Uri $url -Headers $HEADERS -Method Get
        
        return $response.workflow_runs
    } catch {
        Write-ColorLog "Warning: Could not fetch workflow runs" -Level WARNING
        return @()
    }
}

function Calculate-UsagePercentage {
    param(
        [int]$Used,
        [int]$Total
    )
    
    if ($Total -eq 0) { return 0 }
    return [math]::Round(($Used / $Total) * 100, 2)
}

function Get-AlertLevel {
    param([double]$Percentage)
    
    if ($Percentage -ge $CriticalThreshold) { return "CRITICAL" }
    if ($Percentage -ge $WarningThreshold) { return "WARNING" }
    return "OK"
}

function Format-Minutes {
    param([int]$Minutes)
    
    $hours = [math]::Floor($Minutes / 60)
    $mins = $Minutes % 60
    
    if ($hours -gt 0) {
        return "$hours hours $mins minutes"
    } else {
        return "$mins minutes"
    }
}

function Format-Bytes {
    param([long]$Bytes)
    
    if ($Bytes -ge 1GB) {
        return "$([math]::Round($Bytes / 1GB, 2)) GB"
    } elseif ($Bytes -ge 1MB) {
        return "$([math]::Round($Bytes / 1MB, 2)) MB"
    } else {
        return "$([math]::Round($Bytes / 1KB, 2)) KB"
    }
}

function Send-ResourceAlert {
    param(
        [hashtable]$UsageData,
        [string]$AlertLevel,
        [string]$RecipientEmail
    )
    
    Write-ColorLog "Preparing alert email (Level: $AlertLevel)..." -Level INFO
    
    $alertIcon = switch ($AlertLevel) {
        "CRITICAL" { "🚨" }
        "WARNING" { "⚠️" }
        default { "ℹ️" }
    }
    
    $alertColor = switch ($AlertLevel) {
        "CRITICAL" { "#dc3545" }
        "WARNING" { "#ffc107" }
        default { "#17a2b8" }
    }
    
    $htmlBody = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            margin: 0;
        }
        .container {
            max-width: 700px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        .header {
            background: $alertColor;
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 32px;
        }
        .alert-level {
            font-size: 48px;
            margin: 10px 0;
        }
        .content {
            padding: 30px;
        }
        .alert-message {
            background: #fff3cd;
            border-left: 5px solid #ffc107;
            padding: 20px;
            margin: 20px 0;
            border-radius: 5px;
        }
        .critical-message {
            background: #f8d7da;
            border-left-color: #dc3545;
        }
        .usage-card {
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            padding: 20px;
            margin: 15px 0;
            border-radius: 10px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }
        .usage-header {
            font-size: 18px;
            font-weight: bold;
            color: #2c3e50;
            margin-bottom: 15px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        .progress-bar-container {
            background: #e9ecef;
            border-radius: 10px;
            height: 30px;
            overflow: hidden;
            margin: 10px 0;
            position: relative;
        }
        .progress-bar {
            height: 100%;
            transition: width 0.3s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: bold;
            color: white;
        }
        .progress-ok { background: linear-gradient(90deg, #28a745, #20c997); }
        .progress-warning { background: linear-gradient(90deg, #ffc107, #ff9800); }
        .progress-critical { background: linear-gradient(90deg, #dc3545, #c82333); }
        .stat-row {
            display: flex;
            justify-content: space-between;
            padding: 10px 0;
            border-bottom: 1px solid rgba(0,0,0,0.1);
        }
        .stat-label {
            font-weight: 600;
            color: #555;
        }
        .stat-value {
            font-family: 'Courier New', monospace;
            background: white;
            padding: 5px 12px;
            border-radius: 5px;
            font-weight: bold;
        }
        .recommendations {
            background: #d1ecf1;
            border-left: 5px solid #17a2b8;
            padding: 20px;
            margin: 20px 0;
            border-radius: 5px;
        }
        .recommendations h3 {
            margin-top: 0;
            color: #0c5460;
        }
        .recommendations ul {
            margin: 10px 0;
            padding-left: 20px;
        }
        .recommendations li {
            margin: 8px 0;
            color: #0c5460;
        }
        .workflow-table {
            width: 100%;
            border-collapse: collapse;
            margin: 15px 0;
        }
        .workflow-table th {
            background: #6c757d;
            color: white;
            padding: 12px;
            text-align: left;
        }
        .workflow-table td {
            padding: 10px;
            border-bottom: 1px solid #dee2e6;
        }
        .workflow-table tr:hover {
            background: #f8f9fa;
        }
        .status-badge {
            padding: 5px 10px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: bold;
        }
        .status-success { background: #d4edda; color: #155724; }
        .status-failure { background: #f8d7da; color: #721c24; }
        .status-running { background: #fff3cd; color: #856404; }
        .footer {
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            color: #6c757d;
            font-size: 13px;
        }
        .footer a {
            color: #667eea;
            text-decoration: none;
            font-weight: bold;
        }
        .timestamp {
            color: #6c757d;
            font-size: 12px;
            margin-top: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="alert-level">$alertIcon</div>
            <h1>GitHub Actions Resource Alert</h1>
            <p style="margin: 5px 0; opacity: 0.9;">$AlertLevel Alert Level</p>
            <div class="timestamp">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')</div>
        </div>
        
        <div class="content">
"@

    # Alert Message
    if ($AlertLevel -eq "CRITICAL") {
        $htmlBody += @"
            <div class="alert-message critical-message">
                <h3 style="margin-top: 0; color: #721c24;">🚨 CRITICAL: Immediate Action Required!</h3>
                <p><strong>Your GitHub Actions quota is nearly exhausted!</strong></p>
                <p>You have less than <strong>$($UsageData.RemainingMinutes) minutes</strong> remaining. Please backup your work and prepare for service interruption.</p>
            </div>
"@
    } elseif ($AlertLevel -eq "WARNING") {
        $htmlBody += @"
            <div class="alert-message">
                <h3 style="margin-top: 0; color: #856404;">⚠️ WARNING: Resource Usage High</h3>
                <p><strong>Your GitHub Actions usage is approaching the limit.</strong></p>
                <p>You have <strong>$($UsageData.RemainingMinutes) minutes</strong> remaining. Consider optimizing workflows or upgrading your plan.</p>
            </div>
"@
    }

    # Actions Usage Card
    $actionsPercentage = $UsageData.ActionsUsagePercentage
    $progressClass = if ($actionsPercentage -ge $CriticalThreshold) { "progress-critical" } 
                     elseif ($actionsPercentage -ge $WarningThreshold) { "progress-warning" }
                     else { "progress-ok" }

    $htmlBody += @"
            <div class="usage-card">
                <div class="usage-header">
                    ⚡ GitHub Actions Minutes
                </div>
                <div class="progress-bar-container">
                    <div class="progress-bar $progressClass" style="width: $actionsPercentage%">
                        $actionsPercentage%
                    </div>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Used:</span>
                    <span class="stat-value" style="color: #dc3545;">$($UsageData.UsedMinutes) minutes</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Total Included:</span>
                    <span class="stat-value" style="color: #17a2b8;">$($UsageData.TotalMinutes) minutes</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Remaining:</span>
                    <span class="stat-value" style="color: #28a745;">$($UsageData.RemainingMinutes) minutes</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Estimated Days Left:</span>
                    <span class="stat-value" style="color: #ffc107;">$($UsageData.EstimatedDaysLeft) days</span>
                </div>
            </div>
"@

    # Storage Usage Card (if available)
    if ($UsageData.StorageUsed -ne $null) {
        $storagePercentage = $UsageData.StorageUsagePercentage
        $storageProgressClass = if ($storagePercentage -ge $CriticalThreshold) { "progress-critical" } 
                               elseif ($storagePercentage -ge $WarningThreshold) { "progress-warning" }
                               else { "progress-ok" }

        $htmlBody += @"
            <div class="usage-card">
                <div class="usage-header">
                    💾 Storage Usage
                </div>
                <div class="progress-bar-container">
                    <div class="progress-bar $storageProgressClass" style="width: $storagePercentage%">
                        $storagePercentage%
                    </div>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Used:</span>
                    <span class="stat-value" style="color: #dc3545;">$($UsageData.StorageUsedFormatted)</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Total Included:</span>
                    <span class="stat-value" style="color: #17a2b8;">$($UsageData.StorageTotalFormatted)</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Remaining:</span>
                    <span class="stat-value" style="color: #28a745;">$($UsageData.StorageRemainingFormatted)</span>
                </div>
            </div>
"@
    }

    # Recent Workflow Runs
    if ($UsageData.RecentWorkflows -and $UsageData.RecentWorkflows.Count -gt 0) {
        $htmlBody += @"
            <div class="usage-card">
                <div class="usage-header">
                    🔄 Recent Workflow Runs
                </div>
                <table class="workflow-table">
                    <thead>
                        <tr>
                            <th>Workflow</th>
                            <th>Status</th>
                            <th>Duration</th>
                            <th>Date</th>
                        </tr>
                    </thead>
                    <tbody>
"@

        foreach ($workflow in $UsageData.RecentWorkflows | Select-Object -First 5) {
            $statusClass = switch ($workflow.Status) {
                "completed" { "status-success" }
                "failure" { "status-failure" }
                default { "status-running" }
            }

            $htmlBody += @"
                        <tr>
                            <td style="font-weight: 500;">$($workflow.Name)</td>
                            <td><span class="status-badge $statusClass">$($workflow.Status)</span></td>
                            <td>$($workflow.Duration)</td>
                            <td style="color: #6c757d; font-size: 12px;">$($workflow.Date)</td>
                        </tr>
"@
        }

        $htmlBody += @"
                    </tbody>
                </table>
            </div>
"@
    }

    # Recommendations
    $htmlBody += @"
            <div class="recommendations">
                <h3>💡 Recommendations to Optimize Usage:</h3>
                <ul>
"@

    if ($AlertLevel -eq "CRITICAL") {
        $htmlBody += @"
                    <li><strong>URGENT:</strong> Backup all important data immediately</li>
                    <li><strong>Disable</strong> non-critical scheduled workflows</li>
                    <li><strong>Consider upgrading</strong> to a paid plan for more minutes</li>
                    <li><strong>Archive artifacts</strong> to free up storage space</li>
"@
    } elseif ($AlertLevel -eq "WARNING") {
        $htmlBody += @"
                    <li>Review and optimize workflow configurations</li>
                    <li>Reduce workflow frequency where possible</li>
                    <li>Use workflow concurrency limits</li>
                    <li>Clean up old artifacts and logs</li>
                    <li>Monitor usage daily</li>
"@
    } else {
        $htmlBody += @"
                    <li>Continue monitoring usage regularly</li>
                    <li>Implement workflow caching to reduce runtime</li>
                    <li>Use conditional job execution</li>
                    <li>Archive old workflows and artifacts</li>
"@
    }

    $htmlBody += @"
                </ul>
            </div>
            
            <div style="text-align: center; margin: 30px 0;">
                <a href="https://github.com/settings/billing" style="display: inline-block; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 15px 40px; text-decoration: none; border-radius: 30px; font-weight: bold; font-size: 16px;">
                    View Billing Dashboard
                </a>
            </div>
        </div>
        
        <div class="footer">
            <p>🤖 Automated Resource Monitor | GitHub Actions</p>
            <p style="margin: 10px 0;">
                <a href="https://github.com/$($env:GITHUB_REPOSITORY)/actions">View Workflows</a> | 
                <a href="https://github.com/$($env:GITHUB_REPOSITORY)">Repository</a>
            </p>
            <p style="margin-top: 15px; font-size: 11px; color: #adb5bd;">
                This is an automated alert. Please do not reply to this email.
            </p>
        </div>
    </div>
</body>
</html>
"@

    # Send Email
    try {
        Write-ColorLog "Sending email to: $RecipientEmail" -Level INFO
        
        $securePassword = ConvertTo-SecureString $GmailPass -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($GmailUser, $securePassword)
        
        $subject = "[$AlertLevel] GitHub Actions Resource Alert - $($UsageData.ActionsUsagePercentage)% Used"
        
        $mailParams = @{
            From = $GmailUser
            To = $RecipientEmail
            Subject = $subject
            Body = $htmlBody
            BodyAsHtml = $true
            SmtpServer = "smtp.gmail.com"
            Port = 587
            UseSsl = $true
            Credential = $credential
        }
        
        Send-MailMessage @mailParams
        
        Write-ColorLog "Email sent successfully!" -Level SUCCESS
        return $true
        
    } catch {
        Write-ColorLog "Failed to send email: $_" -Level CRITICAL
        return $false
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Main Execution
# ═══════════════════════════════════════════════════════════════════════════

Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║              📊 GITHUB ACTIONS RESOURCE MONITOR v2.0 📊                   ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-ColorLog "Starting resource monitoring..." -Level INFO
Write-ColorLog "Owner: $Owner" -Level INFO
Write-ColorLog "Repository: $Repository" -Level INFO

# Get Actions Usage
$actionsUsage = Get-GitHubActionsUsage -Owner $Owner

if (-not $actionsUsage) {
    Write-ColorLog "Failed to retrieve usage data. Exiting." -Level CRITICAL
    exit 1
}

# Get Storage Usage
$storageUsage = Get-GitHubStorageUsage -Owner $Owner

# Get Recent Workflows
$recentWorkflows = Get-WorkflowRuns -Owner $Owner -Repo ($Repository -split '/')[-1]

# Calculate Statistics
$usedMinutes = $actionsUsage.total_minutes_used
$totalMinutes = $actionsUsage.included_minutes
$remainingMinutes = $totalMinutes - $usedMinutes
$usagePercentage = Calculate-UsagePercentage -Used $usedMinutes -Total $totalMinutes

# Estimate days left (assuming average daily usage)
$daysInMonth = (Get-Date).Day
$avgDailyUsage = if ($daysInMonth -gt 0) { $usedMinutes / $daysInMonth } else { 0 }
$estimatedDaysLeft = if ($avgDailyUsage -gt 0) { [math]::Floor($remainingMinutes / $avgDailyUsage) } else { 999 }

Write-ColorLog "`nUsage Statistics:" -Level INFO
Write-ColorLog "  Used: $usedMinutes / $totalMinutes minutes ($usagePercentage%)" -Level INFO
Write-ColorLog "  Remaining: $remainingMinutes minutes" -Level INFO
Write-ColorLog "  Estimated days left: $estimatedDaysLeft days" -Level INFO

# Prepare usage data
$usageData = @{
    UsedMinutes = $usedMinutes
    TotalMinutes = $totalMinutes
    RemainingMinutes = $remainingMinutes
    ActionsUsagePercentage = $usagePercentage
    EstimatedDaysLeft = $estimatedDaysLeft
    RecentWorkflows = @()
}

# Add storage data if available
if ($storageUsage) {
    $storageUsed = $storageUsage.days_left_in_billing_cycle
    $storageTotal = $storageUsage.estimated_storage_for_month
    $storageRemaining = $storageTotal - $storageUsed
    $storagePercentage = Calculate-UsagePercentage -Used $storageUsed -Total $storageTotal
    
    $usageData.StorageUsed = $storageUsed
    $usageData.StorageTotal = $storageTotal
    $usageData.StorageRemaining = $storageRemaining
    $usageData.StorageUsagePercentage = $storagePercentage
    $usageData.StorageUsedFormatted = Format-Bytes $storageUsed
    $usageData.StorageTotalFormatted = Format-Bytes $storageTotal
    $usageData.StorageRemainingFormatted = Format-Bytes $storageRemaining
}

# Add recent workflows
if ($recentWorkflows) {
    foreach ($workflow in $recentWorkflows | Select-Object -First 5) {
        $duration = if ($workflow.run_started_at -and $workflow.updated_at) {
            $start = [DateTime]::Parse($workflow.run_started_at)
            $end = [DateTime]::Parse($workflow.updated_at)
            $diff = $end - $start
            "$([math]::Floor($diff.TotalMinutes))m $($diff.Seconds)s"
        } else {
            "N/A"
        }
        
        $usageData.RecentWorkflows += @{
            Name = $workflow.name
            Status = $workflow.conclusion ?? $workflow.status
            Duration = $duration
            Date = ([DateTime]::Parse($workflow.created_at)).ToString('MMM dd, HH:mm')
        }
    }
}

# Determine alert level
$alertLevel = Get-AlertLevel -Percentage $usagePercentage

Write-ColorLog "`nAlert Level: $alertLevel" -Level $alertLevel

# Save report
New-Item -ItemType Directory -Path "reports" -Force | Out-Null
$reportFile = "reports/resource-usage-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$usageData | ConvertTo-Json -Depth 10 | Set-Content $reportFile
Write-ColorLog "Report saved: $reportFile" -Level SUCCESS

# Send alert if needed
if ($alertLevel -ne "OK") {
    Write-ColorLog "`n⚠️ Sending alert email..." -Level WARNING
    $emailSent = Send-ResourceAlert -UsageData $usageData -AlertLevel $alertLevel -RecipientEmail $GmailUser
    
    if ($emailSent) {
        Write-ColorLog "Alert notification sent successfully!" -Level SUCCESS
    }
} else {
    Write-ColorLog "`n✅ Usage is within normal limits. No alert needed." -Level SUCCESS
}

Write-Host "`n✨ Resource monitoring completed!" -ForegroundColor Green

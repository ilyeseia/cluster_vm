<#
.SYNOPSIS
    Email Notification System
.DESCRIPTION
    Sends VM credentials and Tailscale information via email
.PARAMETER To
    Recipient email address
.PARAMETER Subject
    Email subject
.PARAMETER CredentialsFile
    Path to credentials JSON file
.EXAMPLE
    .\email-notifier.ps1 -To "admin@example.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$To,
    
    [Parameter(Mandatory=$false)]
    [string]$Subject = "VM Credentials & Tailscale Network Info",
    
    [Parameter(Mandatory=$false)]
    [string]$CredentialsFile = "",
    
    [Parameter(Mandatory=$false)]
    [string]$SmtpServer = $env:SMTP_SERVER,
    
    [Parameter(Mandatory=$false)]
    [int]$SmtpPort = [int]$env:SMTP_PORT,
    
    [Parameter(Mandatory=$false)]
    [string]$SmtpUsername = $env:SMTP_USERNAME,
    
    [Parameter(Mandatory=$false)]
    [string]$SmtpPassword = $env:SMTP_PASSWORD
)

$ErrorActionPreference = 'Stop'

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

if ([string]::IsNullOrEmpty($CredentialsFile)) {
    # البحث عن أحدث ملف credentials
    $CredentialsFile = Get-ChildItem "results/vm-credentials-*.json" | 
        Sort-Object LastWriteTime -Descending | 
        Select-Object -First 1 -ExpandProperty FullName
}

# ═══════════════════════════════════════════════════════════════════════════
# Functions
# ═══════════════════════════════════════════════════════════════════════════

function Send-CredentialsEmail {
    param(
        [array]$Credentials,
        [string]$RecipientEmail
    )
    
    Write-Host "📧 Preparing email..." -ForegroundColor Cyan
    
    # إنشاء HTML email
    $htmlBody = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 20px; }
        .container { background-color: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        .vm-card { 
            background-color: #ecf0f1; 
            padding: 20px; 
            margin: 15px 0; 
            border-radius: 8px;
            border-left: 5px solid #3498db;
        }
        .vm-card.master { border-left-color: #e74c3c; }
        .label { font-weight: bold; color: #7f8c8d; }
        .value { color: #2c3e50; font-family: 'Courier New', monospace; background-color: #fff; padding: 5px; border-radius: 3px; }
        .warning { background-color: #fff3cd; padding: 15px; border-radius: 5px; border-left: 4px solid #ffc107; margin: 20px 0; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #7f8c8d; font-size: 12px; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #3498db; color: white; }
        tr:hover { background-color: #f5f5f5; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔐 VM Credentials & Network Information</h1>
        
        <div class="warning">
            ⚠️ <strong>Important:</strong> This email contains sensitive information. Please store these credentials securely and delete this email after saving them to a password manager.
        </div>
        
        <h2>📊 Cluster Overview</h2>
        <p>Total VMs: <strong>$($Credentials.Count)</strong></p>
        <p>Master VMs: <strong>$(($Credentials | Where-Object { $_.role -eq 'master' }).Count)</strong></p>
        <p>Worker VMs: <strong>$(($Credentials | Where-Object { $_.role -eq 'worker' }).Count)</strong></p>
        <p>Generated: <strong>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')</strong></p>
        
        <h2>🖥️ Virtual Machines</h2>
"@

    foreach ($vm in $Credentials) {
        $cardClass = if ($vm.role -eq 'master') { 'vm-card master' } else { 'vm-card' }
        $roleIcon = if ($vm.role -eq 'master') { '👑' } else { '🔹' }
        
        $htmlBody += @"
        <div class="$cardClass">
            <h3>$roleIcon $($vm.vmId.ToUpper())</h3>
            <table>
                <tr>
                    <td class="label">Role:</td>
                    <td class="value">$($vm.role)</td>
                </tr>
                <tr>
                    <td class="label">Status:</td>
                    <td class="value">$($vm.status)</td>
                </tr>
                <tr>
                    <td class="label">Public IP:</td>
                    <td class="value">$($vm.publicIP)</td>
                </tr>
                <tr>
                    <td class="label">Tailscale IP:</td>
                    <td class="value" style="background-color: #d4edda; font-weight: bold;">$($vm.tailscaleIP)</td>
                </tr>
                <tr>
                    <td class="label">Username:</td>
                    <td class="value">$($vm.username)</td>
                </tr>
                <tr>
                    <td class="label">Password:</td>
                    <td class="value" style="background-color: #fff3cd;">$($vm.password)</td>
                </tr>
                <tr>
                    <td class="label">SSH Command:</td>
                    <td class="value" style="background-color: #e8f4f8;">$($vm.sshCommand)</td>
                </tr>
            </table>
        </div>
"@
    }
    
    $htmlBody += @"
        <h2>🔗 Tailscale Network</h2>
        <p>All VMs are connected through a secure Tailscale mesh network. You can access any VM using its Tailscale IP address from any device connected to your Tailscale network.</p>
        
        <h3>Quick Start:</h3>
        <ol>
            <li>Install Tailscale on your local machine: <a href="https://tailscale.com/download">https://tailscale.com/download</a></li>
            <li>Connect to your Tailscale network</li>
            <li>Use the SSH commands above to connect to VMs</li>
        </ol>
        
        <div class="footer">
            <p>This is an automated message from the Persistent Master-Slave System.</p>
            <p>For support, please contact your system administrator.</p>
        </div>
    </div>
</body>
</html>
"@

    # إعداد بيانات البريد
    $emailParams = @{
        From = $SmtpUsername
        To = $RecipientEmail
        Subject = $Subject
        Body = $htmlBody
        BodyAsHtml = $true
        SmtpServer = $SmtpServer
        Port = $SmtpPort
        UseSsl = $true
        Credential = New-Object System.Management.Automation.PSCredential($SmtpUsername, (ConvertTo-SecureString $SmtpPassword -AsPlainText -Force))
    }
    
    try {
        Send-MailMessage @emailParams
        Write-Host "✅ Email sent successfully to: $RecipientEmail" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "❌ Failed to send email: $_" -ForegroundColor Red
        return $false
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Main Execution
# ═══════════════════════════════════════════════════════════════════════════

Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║                  📧 EMAIL NOTIFICATION SYSTEM v1.0.0 📧                   ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# تحميل بيانات الاعتماد
if (-not (Test-Path $CredentialsFile)) {
    Write-Host "❌ Credentials file not found: $CredentialsFile" -ForegroundColor Red
    exit 1
}

$credentials = Get-Content $CredentialsFile | ConvertFrom-Json

Write-Host "`n📋 Loaded $($credentials.Count) VM credentials" -ForegroundColor Cyan
Write-Host "📧 Sending to: $To" -ForegroundColor Cyan

# إرسال البريد
$result = Send-CredentialsEmail -Credentials $credentials -RecipientEmail $To

if ($result) {
    Write-Host "`n✨ Email notification completed successfully!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n❌ Email notification failed!" -ForegroundColor Red
    exit 1
}

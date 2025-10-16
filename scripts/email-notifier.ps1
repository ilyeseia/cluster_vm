[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$To,
    
    [Parameter(Mandatory=$false)]
    [string]$Subject = "🔐 VM Credentials & Tailscale Network Info",
    
    [Parameter(Mandatory=$false)]
    [string]$CredentialsFile = "",
    
    [Parameter(Mandatory=$false)]
    [string]$GmailUser = $env:GMAIL_USER,
    
    [Parameter(Mandatory=$false)]
    [string]$GmailPass = $env:GMAIL_PASS
)

# ... (باقي الكود يبقى نفسه، فقط استبدل SMTP بـ Gmail)

$emailParams = @{
    From = $GmailUser
    To = $To
    Subject = $Subject
    Body = $htmlBody
    BodyAsHtml = $true
    SmtpServer = "smtp.gmail.com"
    Port = 587
    UseSsl = $true
    Credential = New-Object System.Management.Automation.PSCredential(
        $GmailUser, 
        (ConvertTo-SecureString $GmailPass -AsPlainText -Force)
    )
}

Send-MailMessage @emailParams

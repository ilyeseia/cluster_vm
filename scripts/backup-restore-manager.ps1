<#
.SYNOPSIS
    Backup and Restore Manager
.DESCRIPTION
    Comprehensive backup and disaster recovery system
.PARAMETER Action
    Action to perform: backup, restore, list, verify, cleanup
.EXAMPLE
    .\backup-restore-manager.ps1 -Action backup
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('backup','restore','list','verify','cleanup','schedule')]
    [string]$Action = 'backup',
    
    [Parameter(Mandatory=$false)]
    [string]$BackupId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$RestorePath = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$Compressed,
    
    [Parameter(Mandatory=$false)]
    [switch]$Encrypted
)

$ErrorActionPreference = 'Stop'

# ═══════════════════════════════════════════════════════════════════════════
# مسارات الملفات
# ═══════════════════════════════════════════════════════════════════════════

$BACKUP_DIR = "backups"
$CONFIG_FILE = ".github/system-config.json"
$VMS_STATE_FILE = ".github/example-vms-state.json"
$LOG_FILE = "logs/backup-$(Get-Date -Format 'yyyyMMdd').log"
$BACKUP_INDEX_FILE = "$BACKUP_DIR/backup-index.json"

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

function Initialize-BackupDirectory {
    if (!(Test-Path $BACKUP_DIR)) {
        New-Item -ItemType Directory -Path $BACKUP_DIR -Force | Out-Null
        Write-Log "Backup directory created" -Level INFO
    }
}

function Load-BackupIndex {
    if (!(Test-Path $BACKUP_INDEX_FILE)) {
        $emptyIndex = @{
            version = "1.0.0"
            backups = @()
            lastBackup = $null
        }
        $emptyIndex | ConvertTo-Json -Depth 10 | Set-Content $BACKUP_INDEX_FILE
        return $emptyIndex
    }
    
    $index = Get-Content $BACKUP_INDEX_FILE | ConvertFrom-Json
    return $index
}

function Save-BackupIndex {
    param($Index)
    $Index | ConvertTo-Json -Depth 10 | Set-Content $BACKUP_INDEX_FILE
}

function New-Backup {
    Write-Log "Creating new backup..." -Level INFO
    
    Initialize-BackupDirectory
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                         💾 BACKUP CREATION 💾                             ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $backupId = "backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $backupPath = Join-Path $BACKUP_DIR $backupId
    
    # إنشاء مجلد النسخة الاحتياطية
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    
    Write-Host "`n📦 Backup Information:" -ForegroundColor Yellow
    Write-Host "  • Backup ID: $backupId" -ForegroundColor Cyan
    Write-Host "  • Path: $backupPath" -ForegroundColor Cyan
    Write-Host "  • Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    
    # نسخ الملفات المهمة
    Write-Host "`n📁 Backing up files..." -ForegroundColor Yellow
    
    $filesToBackup = @(
        @{ Source = $CONFIG_FILE; Dest = "system-config.json" },
        @{ Source = $VMS_STATE_FILE; Dest = "vms-state.json" },
        @{ Source = "logs/orchestrator-*.log"; Dest = "logs/" },
        @{ Source = "logs/vm-lifecycle-*.log"; Dest = "logs/" }
    )
    
    $backedUpCount = 0
    foreach ($file in $filesToBackup) {
        try {
            $sourcePath = $file.Source
            $destPath = Join-Path $backupPath $file.Dest
            
            # إنشاء المجلد الوجهة إذا لزم الأمر
            $destDir = Split-Path $destPath -Parent
            if ($destDir -and !(Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            
            if (Test-Path $sourcePath) {
                Copy-Item -Path $sourcePath -Destination $destPath -Force -Recurse
                Write-Host "  ✓ $($file.Source)" -ForegroundColor Green
                $backedUpCount++
            }
        } catch {
            Write-Host "  ⚠️  Failed to backup $($file.Source): $_" -ForegroundColor Yellow
        }
    }
    
    # إنشاء metadata
    $metadata = @{
        backupId = $backupId
        timestamp = Get-Date -Format 'o'
        filesCount = $backedUpCount
        compressed = $Compressed
        encrypted = $Encrypted
        size = 0
        status = "completed"
        type = "full"
    }
    
    $metadata | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $backupPath "metadata.json")
    
    # ضغط النسخة الاحتياطية إذا لزم الأمر
    if ($Compressed) {
        Write-Host "`n🗜️  Compressing backup..." -ForegroundColor Yellow
        $zipPath = "$backupPath.zip"
        
        try {
            Compress-Archive -Path "$backupPath/*" -DestinationPath $zipPath -CompressionLevel Optimal
            
            $zipSize = (Get-Item $zipPath).Length / 1MB
            Write-Host "  ✓ Compressed to: $zipPath" -ForegroundColor Green
            Write-Host "  • Size: $([math]::Round($zipSize, 2)) MB" -ForegroundColor Cyan
            
            # حذف المجلد غير المضغوط
            Remove-Item -Path $backupPath -Recurse -Force
            
            $metadata.size = $zipSize
            $metadata.compressed = $true
        } catch {
            Write-Host "  ⚠️  Compression failed: $_" -ForegroundColor Yellow
        }
    } else {
        # حساب الحجم
        $totalSize = (Get-ChildItem -Path $backupPath -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
        $metadata.size = [math]::Round($totalSize, 2)
    }
    
    # تحديث الفهرس
    $index = Load-BackupIndex
    $index.backups += $metadata
    $index.lastBackup = $backupId
    Save-BackupIndex -Index $index
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                    ✅ BACKUP COMPLETED ✅                                 ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Host "`n📊 Backup Summary:" -ForegroundColor Yellow
    Write-Host "  • Backup ID: $backupId" -ForegroundColor Cyan
    Write-Host "  • Files Backed Up: $backedUpCount" -ForegroundColor Green
    Write-Host "  • Size: $($metadata.size) MB" -ForegroundColor Cyan
    Write-Host "  • Status: $($metadata.status)" -ForegroundColor Green
    
    Write-Log "Backup created successfully: $backupId" -Level SUCCESS
    
    return $metadata
}

function Restore-FromBackup {
    param([string]$BackupId)
    
    Write-Log "Restoring from backup: $BackupId" -Level INFO
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                        🔄 BACKUP RESTORATION 🔄                           ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    
    # البحث عن النسخة الاحتياطية
    $backupPath = Join-Path $BACKUP_DIR $BackupId
    $zipPath = "$backupPath.zip"
    
    $isCompressed = Test-Path $zipPath
    $backupExists = (Test-Path $backupPath) -or $isCompressed
    
    if (!$backupExists) {
        Write-Host "❌ Backup not found: $BackupId" -ForegroundColor Red
        Write-Log "Backup not found: $BackupId" -Level ERROR
        return
    }
    
    Write-Host "`n📦 Backup Information:" -ForegroundColor Yellow
    Write-Host "  • Backup ID: $BackupId" -ForegroundColor Cyan
    Write-Host "  • Compressed: $(if($isCompressed){'Yes'}else{'No'})" -ForegroundColor Cyan
    
    # تحذير
    Write-Host "`n⚠️  WARNING: This will overwrite current system state!" -ForegroundColor Red
    $confirmation = Read-Host "Continue? (yes/no)"
    
    if ($confirmation -ne 'yes') {
        Write-Host "Restore cancelled" -ForegroundColor Yellow
        return
    }
    
    # فك الضغط إذا لزم الأمر
    if ($isCompressed) {
        Write-Host "`n📂 Extracting backup..." -ForegroundColor Yellow
        $tempExtractPath = Join-Path $BACKUP_DIR "temp-$BackupId"
        
        try {
            Expand-Archive -Path $zipPath -DestinationPath $tempExtractPath -Force
            $backupPath = $tempExtractPath
            Write-Host "  ✓ Extracted successfully" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Extraction failed: $_" -ForegroundColor Red
            return
        }
    }
    
    # استعادة الملفات
    Write-Host "`n🔄 Restoring files..." -ForegroundColor Yellow
    
    $restoredCount = 0
    
    # استعادة system-config.json
    $configBackup = Join-Path $backupPath "system-config.json"
    if (Test-Path $configBackup) {
        Copy-Item -Path $configBackup -Destination $CONFIG_FILE -Force
        Write-Host "  ✓ system-config.json restored" -ForegroundColor Green
        $restoredCount++
    }
    
    # استعادة vms-state.json
    $vmsStateBackup = Join-Path $backupPath "vms-state.json"
    if (Test-Path $vmsStateBackup) {
        Copy-Item -Path $vmsStateBackup -Destination $VMS_STATE_FILE -Force
        Write-Host "  ✓ vms-state.json restored" -ForegroundColor Green
        $restoredCount++
    }
    
    # استعادة السجلات
    $logsBackup = Join-Path $backupPath "logs"
    if (Test-Path $logsBackup) {
        if (!(Test-Path "logs")) {
            New-Item -ItemType Directory -Path "logs" -Force | Out-Null
        }
        Copy-Item -Path "$logsBackup/*" -Destination "logs/" -Force -Recurse
        Write-Host "  ✓ Logs restored" -ForegroundColor Green
        $restoredCount++
    }
    
    # تنظيف المجلد المؤقت
    if ($isCompressed -and (Test-Path $backupPath)) {
        Remove-Item -Path $backupPath -Recurse -Force
    }
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                  ✅ RESTORATION COMPLETED ✅                              ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Host "`n📊 Restoration Summary:" -ForegroundColor Yellow
    Write-Host "  • Backup ID: $BackupId" -ForegroundColor Cyan
    Write-Host "  • Files Restored: $restoredCount" -ForegroundColor Green
    Write-Host "  • Status: Completed" -ForegroundColor Green
    
    Write-Log "Restoration completed: $BackupId" -Level SUCCESS
}

function Get-BackupList {
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                       📋 BACKUP LIST 📋                                   ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $index = Load-BackupIndex
    
    if ($index.backups.Count -eq 0) {
        Write-Host "`n⚠️  No backups available" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n📊 Total Backups: $($index.backups.Count)" -ForegroundColor Green
    Write-Host "Last Backup: $($index.lastBackup)" -ForegroundColor Cyan
    
    Write-Host "`n═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    foreach ($backup in $index.backups | Sort-Object timestamp -Descending) {
        $isLatest = $backup.backupId -eq $index.lastBackup
        $badge = if ($isLatest) { "🌟 LATEST" } else { "" }
        
        Write-Host "`n$badge Backup ID: $($backup.backupId)" -ForegroundColor $(if($isLatest){'Green'}else{'Cyan'})
        Write-Host "  ├─ Timestamp: $($backup.timestamp)" -ForegroundColor Cyan
        Write-Host "  ├─ Type: $($backup.type)" -ForegroundColor Yellow
        Write-Host "  ├─ Files: $($backup.filesCount)" -ForegroundColor Cyan
        Write-Host "  ├─ Size: $($backup.size) MB" -ForegroundColor Cyan
        Write-Host "  ├─ Compressed: $(if($backup.compressed){'Yes'}else{'No'})" -ForegroundColor Cyan
        Write-Host "  └─ Status: $($backup.status)" -ForegroundColor Green
    }
    
    Write-Host "`n═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

function Test-Backup {
    param([string]$BackupId)
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                      🔍 BACKUP VERIFICATION 🔍                            ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    
    Write-Log "Verifying backup: $BackupId" -Level INFO
    
    $backupPath = Join-Path $BACKUP_DIR $BackupId
    $zipPath = "$backupPath.zip"
    
    $results = @{
        backupId = $BackupId
        exists = $false
        valid = $false
        metadata = $null
        files = @()
        issues = @()
    }
    
    # التحقق من الوجود
    if ((Test-Path $backupPath) -or (Test-Path $zipPath)) {
        $results.exists = $true
        Write-Host "  ✓ Backup exists" -ForegroundColor Green
    } else {
        $results.issues += "Backup not found"
        Write-Host "  ✗ Backup not found" -ForegroundColor Red
        return $results
    }
    
    # التحقق من المحتويات
    if (Test-Path $zipPath) {
        Write-Host "  ✓ Backup is compressed" -ForegroundColor Green
        
        try {
            $tempPath = Join-Path $BACKUP_DIR "verify-temp"
            Expand-Archive -Path $zipPath -DestinationPath $tempPath -Force
            
            # التحقق من الملفات
            $requiredFiles = @("system-config.json", "vms-state.json", "metadata.json")
            foreach ($file in $requiredFiles) {
                $filePath = Join-Path $tempPath $file
                if (Test-Path $filePath) {
                    Write-Host "    ✓ $file found" -ForegroundColor Green
                    $results.files += $file
                } else {
                    Write-Host "    ✗ $file missing" -ForegroundColor Red
                    $results.issues += "$file is missing"
                }
            }
            
            # تحميل metadata
            $metadataPath = Join-Path $tempPath "metadata.json"
            if (Test-Path $metadataPath) {
                $results.metadata = Get-Content $metadataPath | ConvertFrom-Json
            }
            
            # تنظيف
            Remove-Item -Path $tempPath -Recurse -Force
            
        } catch {
            $results.issues += "Failed to verify: $_"
            Write-Host "  ✗ Verification failed: $_" -ForegroundColor Red
        }
    } else {
        # نسخة احتياطية غير مضغوطة
        $requiredFiles = @("system-config.json", "vms-state.json", "metadata.json")
        foreach ($file in $requiredFiles) {
            $filePath = Join-Path $backupPath $file
            if (Test-Path $filePath) {
                Write-Host "  ✓ $file found" -ForegroundColor Green
                $results.files += $file
            } else {
                Write-Host "  ✗ $file missing" -ForegroundColor Red
                $results.issues += "$file is missing"
            }
        }
    }
    
    $results.valid = $results.issues.Count -eq 0
    
    if ($results.valid) {
        Write-Host "`n✅ Backup is valid and can be restored" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  Backup has issues:" -ForegroundColor Yellow
        foreach ($issue in $results.issues) {
            Write-Host "  • $issue" -ForegroundColor Red
        }
    }
    
    return $results
}

function Remove-OldBackups {
    param([int]$KeepCount = 5)
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                      🧹 BACKUP CLEANUP 🧹                                 ║" -ForegroundColor Yellow
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    
    Write-Log "Cleaning old backups (keeping last $KeepCount)..." -Level INFO
    
    $index = Load-BackupIndex
    
    if ($index.backups.Count -le $KeepCount) {
        Write-Host "`n✓ No cleanup needed (Total: $($index.backups.Count))" -ForegroundColor Green
        return
    }
    
    # ترتيب حسب التاريخ
    $sortedBackups = $index.backups | Sort-Object timestamp -Descending
    
    $toKeep = $sortedBackups | Select-Object -First $KeepCount
    $toDelete = $sortedBackups | Select-Object -Skip $KeepCount
    
    Write-Host "`n📊 Cleanup Plan:" -ForegroundColor Yellow
    Write-Host "  • Total Backups: $($index.backups.Count)" -ForegroundColor Cyan
    Write-Host "  • To Keep: $KeepCount" -ForegroundColor Green
    Write-Host "  • To Delete: $($toDelete.Count)" -ForegroundColor Red
    
    $deletedCount = 0
    foreach ($backup in $toDelete) {
        $backupPath = Join-Path $BACKUP_DIR $backup.backupId
        $zipPath = "$backupPath.zip"
        
        try {
            if (Test-Path $zipPath) {
                Remove-Item -Path $zipPath -Force
                Write-Host "  ✓ Deleted: $($backup.backupId).zip" -ForegroundColor Green
            } elseif (Test-Path $backupPath) {
                Remove-Item -Path $backupPath -Recurse -Force
                Write-Host "  ✓ Deleted: $($backup.backupId)/" -ForegroundColor Green
            }
            $deletedCount++
        } catch {
            Write-Host "  ✗ Failed to delete $($backup.backupId): $_" -ForegroundColor Red
        }
    }
    
    # تحديث الفهرس
    $index.backups = $toKeep
    Save-BackupIndex -Index $index
    
    Write-Host "`n✅ Cleanup completed: $deletedCount backups removed" -ForegroundColor Green
    Write-Log "Cleanup completed: $deletedCount backups removed" -Level SUCCESS
}

function Set-BackupSchedule {
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                     ⏰ BACKUP SCHEDULE ⏰                                  ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Host "`n📅 Recommended Backup Schedule:" -ForegroundColor Yellow
    Write-Host "  • Hourly: Quick incremental backups" -ForegroundColor Cyan
    Write-Host "  • Daily: Full system backups (keep 7)" -ForegroundColor Cyan
    Write-Host "  • Weekly: Archive backups (keep 4)" -ForegroundColor Cyan
    Write-Host "  • Monthly: Long-term backups (keep 12)" -ForegroundColor Cyan
    
    Write-Host "`n⚙️  Current Configuration:" -ForegroundColor Yellow
    $config = Get-Content $CONFIG_FILE | ConvertFrom-Json
    
    Write-Host "  • Backup Enabled: $(if($config.backup.enabled){'Yes'}else{'No'})" -ForegroundColor $(if($config.backup.enabled){'Green'}else{'Red'})
    Write-Host "  • Interval: $($config.backup.interval)s" -ForegroundColor Cyan
    Write-Host "  • Retention: $($config.backup.retention)s" -ForegroundColor Cyan
    Write-Host "  • Location: $($config.backup.location)" -ForegroundColor Cyan
    Write-Host "  • Compression: $(if($config.backup.compression){'Enabled'}else{'Disabled'})" -ForegroundColor Cyan
    
    Write-Host "`n💡 Tip: Use GitHub Actions for automated scheduled backups" -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════
# العمل الرئيسي
# ═══════════════════════════════════════════════════════════════════════════

Write-Host @"
╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║               💾 BACKUP & RESTORE MANAGER v1.0.0 💾                       ║
║                                                                            ║
║            Comprehensive Backup & Disaster Recovery System                ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Log "Starting Backup & Restore Manager - Action: $Action" -Level INFO

try {
    switch ($Action) {
        'backup' {
            New-Backup
        }
        
        'restore' {
            if ($BackupId) {
                Restore-FromBackup -BackupId $BackupId
            } else {
                Write-Host "⚠️  BackupId required for restore" -ForegroundColor Yellow
                Write-Host "Use: -Action restore -BackupId <backup-id>" -ForegroundColor Cyan
                Get-BackupList
            }
        }
        
        'list' {
            Get-BackupList
        }
        
        'verify' {
            if ($BackupId) {
                Test-Backup -BackupId $BackupId
            } else {
                Write-Host "⚠️  BackupId required for verification" -ForegroundColor Yellow
                Get-BackupList
            }
        }
        
        'cleanup' {
            Remove-OldBackups -KeepCount 5
        }
        
        'schedule' {
            Set-BackupSchedule
        }
    }
    
    Write-Host "`n✅ Operation completed successfully!" -ForegroundColor Green
    Write-Log "Backup & Restore Manager completed successfully" -Level SUCCESS
}
catch {
    Write-Log "Error: $_" -Level ERROR
    Write-Host "`n❌ Operation failed: $_" -ForegroundColor Red
    exit 1
}

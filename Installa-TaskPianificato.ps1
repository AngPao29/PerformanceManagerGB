#Requires -RunAsAdministrator
# ============================================================================
# Installa/Aggiorna il Task Pianificato per PerformanceManagerGB
# Eseguire una sola volta da un terminale con privilegi di Amministratore
# ============================================================================

$taskName   = "Performance Manager for Galaxy Book"
$scriptPath = "C:\Scripts\PerformanceManagerGB.ps1"

# Verifica che lo script esista
if (-not (Test-Path $scriptPath)) {
    Write-Error "Script non trovato: $scriptPath"
    exit 1
}

# Rimuovi task con il vecchio nome (migrazione)
$legacyNames = @(
    "Samsung Performance Mode Manager",
    "Samsung Performance Manager",
    "GestoreModalitaConsumo"
)
foreach ($legacy in $legacyNames) {
    $legacyTask = Get-ScheduledTask -TaskName $legacy -ErrorAction SilentlyContinue
    if ($legacyTask) {
        Write-Host "Task legacy '$legacy' trovato. Rimuovo..." -ForegroundColor Yellow
        Stop-ScheduledTask -TaskName $legacy -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $legacy -Confirm:$false
    }
}

# Rimuovi eventuale task precedente (stesso nome attuale)
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Task esistente trovato. Rimuovo..." -ForegroundColor Yellow
    Stop-ScheduledTask  -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

# --- Azione: preferisce PS7 (path assoluto), fallback a Windows PowerShell 5.1 ---
$pwshCmd = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
$psExe   = if ($pwshCmd) { $pwshCmd.Source } else { 'powershell.exe' }
Write-Host "Runtime selezionato: $psExe" -ForegroundColor Cyan
$action = New-ScheduledTaskAction `
    -Execute $psExe `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""

# --- Trigger: all'accesso dell'utente corrente ---
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# --- Impostazioni ---
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable

# --- Principal: esegui con privilegi elevati ---
$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -RunLevel Highest `
    -LogonType Interactive

# --- Registra ---
Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Gestisce automaticamente la modalita performance Samsung in base allo stato di alimentazione e carica batteria."

# --- Verifica ---
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "`n=== Task registrato con successo ===" -ForegroundColor Green
    Write-Host "  Nome:      $($task.TaskName)"
    Write-Host "  Stato:     $($task.State)"
    Write-Host "  Trigger:   All'accesso di $env:USERNAME"
    Write-Host "  Eseguito come: Amministratore (nascosto)"
    Write-Host ""
    Write-Host "Per avviarlo subito senza riavviare:" -ForegroundColor Cyan
    Write-Host "  Start-ScheduledTask -TaskName '$taskName'"
    Write-Host ""
    Write-Host "Per rimuoverlo in futuro:" -ForegroundColor Cyan
    Write-Host "  Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false"
}
else {
    Write-Error "Registrazione fallita."
    exit 1
}

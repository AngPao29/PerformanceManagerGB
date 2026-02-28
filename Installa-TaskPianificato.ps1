#Requires -RunAsAdministrator
# ============================================================================
# Installa/Aggiorna il Task Pianificato per GestoreModalitaConsumo
# Eseguire una sola volta da un terminale con privilegi di Amministratore
# ============================================================================

$taskName   = "Samsung Performance Mode Manager"
$scriptPath = "C:\Scripts\GestoreModalitaConsumo.ps1"

# Verifica che lo script esista
if (-not (Test-Path $scriptPath)) {
    Write-Error "Script non trovato: $scriptPath"
    exit 1
}

# Rimuovi eventuale task precedente
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Task esistente trovato. Rimuovo..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# --- Azione: PowerShell 7+ nascosto, non interattivo ---
$action = New-ScheduledTaskAction `
    -Execute "pwsh.exe" `
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

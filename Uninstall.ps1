#Requires -RunAsAdministrator
# ==============================================================================
# Uninstall.ps1 — Rimozione completa di PerformanceManagerGB
# ==============================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  ATTENZIONE: stai per disinstallare PerformanceManagerGB." -ForegroundColor Yellow
Write-Host "  Verranno rimossi il Task Pianificato e gli script in C:\Scripts." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""

$conferma = Read-Host "Digitare CONFERMA per procedere (qualsiasi altro tasto per annullare)"

if ($conferma -ine 'CONFERMA') {
    Write-Host "Annullato." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Avvio disinstallazione..." -ForegroundColor Cyan

# --------------------------------------------------------------------------
# 1. Ferma e rimuove tutti i task pianificati associati
# --------------------------------------------------------------------------
$taskNames = @(
    "Performance Manager for Galaxy Book",
    "Samsung Performance Mode Manager",
    "Samsung Performance Manager",
    "GestoreModalitaConsumo"
)

foreach ($taskName in $taskNames) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        Write-Host "Arresto del task: $taskName" -ForegroundColor Cyan
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Write-Host "Rimozione del task: $taskName" -ForegroundColor Cyan
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Task rimosso: $taskName" -ForegroundColor Green
    } else {
        Write-Host "Task non trovato (ignorato): $taskName" -ForegroundColor Cyan
    }
}

# --------------------------------------------------------------------------
# 2. Rimozione script principali
# --------------------------------------------------------------------------
$filesToRemove = @(
    'C:\Scripts\PerformanceManagerGB.ps1',
    'C:\Scripts\Installa-TaskPianificato.ps1'
)

foreach ($file in $filesToRemove) {
    if (Test-Path $file) {
        Write-Host "Rimozione file: $file" -ForegroundColor Cyan
        Remove-Item $file -Force
        Write-Host "File rimosso: $file" -ForegroundColor Green
    } else {
        Write-Host "File non trovato (ignorato): $file" -ForegroundColor Cyan
    }
}

# --------------------------------------------------------------------------
# Riepilogo finale
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Disinstallazione completata con successo." -ForegroundColor Green
Write-Host "  I task pianificati e gli script sono stati rimossi." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

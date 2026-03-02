# ==============================================================================
# Install.ps1 — Installazione one-liner di PerformanceManagerGB
# Uso: irm https://raw.githubusercontent.com/AngPao29/PerformanceManagerGB/main/Install.ps1 | iex
# ==============================================================================

# Forza TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --------------------------------------------------------------------------
# Elevazione automatica: se non siamo admin, salviamo lo script in TEMP
# e ri-lanciamo con privilegi elevati
# --------------------------------------------------------------------------
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Privilegi insufficienti — rilancio come Amministratore..." -ForegroundColor Cyan

    # Scarica (o copia) lo script in TEMP per poterlo passare a -File
    $tempScript = "$env:TEMP\Install_PMG.ps1"

    # Se lo script viene eseguito via piping (MyInvocation.ScriptName è vuoto)
    # o da file, ci comportiamo di conseguenza
    if ($MyInvocation.ScriptName -and (Test-Path $MyInvocation.ScriptName)) {
        Copy-Item $MyInvocation.ScriptName $tempScript -Force
    } else {
        # Scarica nuovamente da GitHub
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/AngPao29/PerformanceManagerGB/main/Install.ps1' `
            -OutFile $tempScript -ErrorAction Stop
    }

    $psExe = $null
    foreach ($candidate in @('pwsh.exe', 'powershell.exe')) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) {
            $psExe = $candidate
            break
        }
    }
    if (-not $psExe) {
        Write-Host "Impossibile trovare un eseguibile PowerShell." -ForegroundColor Red
        exit 1
    }

    Start-Process $psExe -ArgumentList "-ExecutionPolicy Bypass -File `"$tempScript`"" -Verb RunAs
    exit 0
}

# ==============================================================================
# Da qui in poi siamo Amministratori
# ==============================================================================

Write-Host "=== PerformanceManagerGB — Installazione ===" -ForegroundColor Cyan

# --------------------------------------------------------------------------
# 1. Recupera l'ultima release da GitHub
# --------------------------------------------------------------------------
Write-Host "Recupero informazioni sull'ultima release..." -ForegroundColor Cyan
try {
    $release = Invoke-RestMethod 'https://api.github.com/repos/AngPao29/PerformanceManagerGB/releases/latest' `
        -ErrorAction Stop
} catch {
    Write-Host "Errore nel recupero della release: $_" -ForegroundColor Red
    exit 1
}

# --------------------------------------------------------------------------
# 2. Filtra asset ZIP
# --------------------------------------------------------------------------
$asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
if (-not $asset) {
    Write-Host "Nessun asset .zip trovato nella release." -ForegroundColor Red
    exit 1
}
Write-Host "Asset trovato: $($asset.name)  (release $($release.tag_name))" -ForegroundColor Cyan

# --------------------------------------------------------------------------
# 3. Download ZIP
# --------------------------------------------------------------------------
$zipPath = "$env:TEMP\PerformanceManagerGB.zip"
Write-Host "Download in corso: $($asset.browser_download_url)" -ForegroundColor Cyan
try {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -ErrorAction Stop
} catch {
    Write-Host "Errore durante il download: $_" -ForegroundColor Red
    exit 1
}
Write-Host "Download completato." -ForegroundColor Green

# --------------------------------------------------------------------------
# 4. Crea C:\Scripts se non esiste
# --------------------------------------------------------------------------
if (-not (Test-Path 'C:\Scripts')) {
    Write-Host "Creazione directory C:\Scripts..." -ForegroundColor Cyan
    try {
        New-Item -ItemType Directory -Path 'C:\Scripts' -Force | Out-Null
    } catch {
        Write-Host "Errore nella creazione di C:\Scripts: $_" -ForegroundColor Red
        exit 1
    }
}

# --------------------------------------------------------------------------
# 5. Estrazione ZIP
# --------------------------------------------------------------------------
Write-Host "Estrazione dei file in C:\Scripts..." -ForegroundColor Cyan
try {
    Expand-Archive -Path $zipPath -DestinationPath 'C:\Scripts' -Force
} catch {
    Write-Host "Errore durante l'estrazione: $_" -ForegroundColor Red
    exit 1
}
Write-Host "Estrazione completata." -ForegroundColor Green

# --------------------------------------------------------------------------
# 6. Verifica presenza di Installa-TaskPianificato.ps1
# --------------------------------------------------------------------------
if (-not (Test-Path 'C:\Scripts\Installa-TaskPianificato.ps1')) {
    Write-Host "File Installa-TaskPianificato.ps1 non trovato in C:\Scripts dopo l'estrazione." -ForegroundColor Red
    exit 1
}

# --------------------------------------------------------------------------
# 7. Esegui il task pianificato
# --------------------------------------------------------------------------
Write-Host "Registrazione del Task Pianificato..." -ForegroundColor Cyan
try {
    & 'C:\Scripts\Installa-TaskPianificato.ps1'
} catch {
    Write-Host "Errore durante la registrazione del task: $_" -ForegroundColor Red
    exit 1
}

# 8. Riavvia il task per applicare subito il nuovo codice
Write-Host "Riavvio del Task Pianificato..." -ForegroundColor Cyan
Stop-ScheduledTask  -TaskName 'Performance Manager for Galaxy Book' -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName 'Performance Manager for Galaxy Book' -ErrorAction SilentlyContinue

# 9. Pulizia file temporanei
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Installazione completata con successo! ===" -ForegroundColor Green
Write-Host "PerformanceManagerGB $($release.tag_name) e' installato in C:\Scripts." -ForegroundColor Green
Write-Host "Il task e' gia' in esecuzione con l'ultima versione." -ForegroundColor Green

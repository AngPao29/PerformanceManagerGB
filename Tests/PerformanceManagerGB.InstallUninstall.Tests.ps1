# ==============================================================================
# Pester v5 — Test per Install.ps1 e Uninstall.ps1 di PerformanceManagerGB
#
# Scenari coperti:
#   1. Install — nessun asset ZIP           → exit 1
#   2. Install — API GitHub non raggiungibile → exit 1
#   3. Install — file estratto mancante     → exit 1
#   4. Uninstall — conferma negativa        → esce senza rimuovere nulla
#   5. Uninstall — task inesistente         → nessun errore, messaggio "ignorato"
#   6. Uninstall — file assente in C:\Scripts → nessun errore, messaggio "ignorato"
#   7. Uninstall — scenario completo        → task rimosso, file rimossi
#
# NON richiede privilegi di amministratore.
# Autocontenuto: le funzioni logiche sono ridefinite inline nel BeforeAll.
#
# Esecuzione:
#   Invoke-Pester -Path 'Tests\PerformanceManagerGB.InstallUninstall.Tests.ps1' -Output Detailed
# ==============================================================================

Describe 'PerformanceManagerGB - Install.ps1 e Uninstall.ps1' {

    BeforeAll {

        # ------------------------------------------------------------------ #
        #  INSTALL — logica core estratta in una funzione testabile           #
        #  Parametri:                                                          #
        #    $ApiUrl  : URL GitHub API releases/latest                         #
        #    $DestDir : directory di destinazione (default C:\Scripts)         #
        #  Restituisce:                                                         #
        #    [int] 0 = successo, 1 = errore                                    #
        # ------------------------------------------------------------------ #
        function script:Invoke-InstallCoreLogic {
            param(
                [string]$ApiUrl  = 'https://api.github.com/repos/AngPao29/PerformanceManagerGB/releases/latest',
                [string]$DestDir = 'C:\Scripts'
            )

            # 1. Recupera release
            try {
                $release = Invoke-RestMethod $ApiUrl -ErrorAction Stop
            } catch {
                Write-Host "Errore nel recupero della release: $_" -ForegroundColor Red
                return 1
            }

            # 2. Filtra asset ZIP
            $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
            if (-not $asset) {
                Write-Host "Nessun asset .zip trovato nella release." -ForegroundColor Red
                return 1
            }

            # 3. Download ZIP
            $zipPath = "$env:TEMP\PerformanceManagerGB.zip"
            try {
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -ErrorAction Stop
            } catch {
                Write-Host "Errore durante il download: $_" -ForegroundColor Red
                return 1
            }

            # 4. Crea directory destinazione se assente
            if (-not (Test-Path $DestDir)) {
                try {
                    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
                } catch {
                    Write-Host "Errore nella creazione di ${DestDir}: $_" -ForegroundColor Red
                    return 1
                }
            }

            # 5. Estrazione ZIP
            try {
                Expand-Archive -Path $zipPath -DestinationPath $DestDir -Force
            } catch {
                Write-Host "Errore durante l'estrazione: $_" -ForegroundColor Red
                return 1
            }

            # 6. Verifica presenza script post-estrazione
            $installerScript = Join-Path $DestDir 'Installa-TaskPianificato.ps1'
            if (-not (Test-Path $installerScript)) {
                Write-Host "File Installa-TaskPianificato.ps1 non trovato in ${DestDir} dopo l'estrazione." -ForegroundColor Red
                return 1
            }

            return 0
        }

        # ------------------------------------------------------------------ #
        #  UNINSTALL — logica core estratta in una funzione testabile          #
        #  Parametri:                                                           #
        #    $Conferma : stringa inserita dall'utente (sostituisce Read-Host)   #
        #    $DestDir  : directory degli script (default C:\Scripts)            #
        #  Restituisce:                                                          #
        #    [hashtable] { Annullato, TasksRemoved, FilesRemoved, Output }      #
        # ------------------------------------------------------------------ #
        function script:Invoke-UninstallCoreLogic {
            param(
                [string]$Conferma,
                [string]$DestDir = 'C:\Scripts'
            )

            $result = @{
                Annullato    = $false
                TasksRemoved = [System.Collections.Generic.List[string]]::new()
                FilesRemoved = [System.Collections.Generic.List[string]]::new()
                Output       = [System.Collections.Generic.List[string]]::new()
            }

            # Conferma utente
            if ($Conferma -ine 'CONFERMA') {
                $result.Annullato = $true
                $result.Output.Add('Annullato.')
                return $result
            }

            # Task pianificati
            $taskNames = @(
                'Performance Manager for Galaxy Book',
                'Samsung Performance Mode Manager',
                'Samsung Performance Manager',
                'GestoreModalitaConsumo'
            )

            foreach ($taskName in $taskNames) {
                $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
                if ($task) {
                    Stop-ScheduledTask       -TaskName $taskName -ErrorAction SilentlyContinue
                    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
                    $result.TasksRemoved.Add($taskName)
                    $result.Output.Add("Task rimosso: $taskName")
                } else {
                    $result.Output.Add("Task non trovato (ignorato): $taskName")
                }
            }

            # File script
            $filesToRemove = @(
                (Join-Path $DestDir 'PerformanceManagerGB.ps1'),
                (Join-Path $DestDir 'Installa-TaskPianificato.ps1')
            )

            foreach ($file in $filesToRemove) {
                if (Test-Path $file) {
                    Remove-Item $file -Force
                    $result.FilesRemoved.Add($file)
                    $result.Output.Add("File rimosso: $file")
                } else {
                    $result.Output.Add("File non trovato (ignorato): $file")
                }
            }

            return $result
        }

        # Costanti utili nei test
        $script:DestDir  = 'C:\Scripts'
        $script:ApiUrl   = 'https://api.github.com/repos/AngPao29/PerformanceManagerGB/releases/latest'
        $script:ValidRelease = [PSCustomObject]@{
            tag_name = 'v1.0.0'
            assets   = @(
                [PSCustomObject]@{
                    name                 = 'PerformanceManagerGB.zip'
                    browser_download_url = 'https://example.com/PerformanceManagerGB.zip'
                }
            )
        }
    }

    # ========================================================================
    # SEZIONE INSTALL
    # ========================================================================
    Describe 'Install.ps1 — logica core' {

        # ---------------------------------------------------------- Scenario 1
        Context 'Scenario 1 — nessun asset ZIP nella release' {

            It 'restituisce exit code 1 quando assets e vuoto' {
                Mock Invoke-RestMethod {
                    return [PSCustomObject]@{ tag_name = 'v1.0.0'; assets = @() }
                }

                $exitCode = Invoke-InstallCoreLogic -ApiUrl $script:ApiUrl -DestDir $script:DestDir

                $exitCode | Should -Be 1
            }

            It 'restituisce exit code 1 quando nessun asset ha estensione .zip' {
                Mock Invoke-RestMethod {
                    return [PSCustomObject]@{
                        tag_name = 'v1.0.0'
                        assets   = @(
                            [PSCustomObject]@{
                                name                 = 'release-notes.txt'
                                browser_download_url = 'https://example.com/release-notes.txt'
                            }
                        )
                    }
                }

                $exitCode = Invoke-InstallCoreLogic -ApiUrl $script:ApiUrl -DestDir $script:DestDir

                $exitCode | Should -Be 1
            }
        }

        # ---------------------------------------------------------- Scenario 2
        Context 'Scenario 2 — API GitHub non raggiungibile' {

            It 'restituisce exit code 1 quando Invoke-RestMethod lancia eccezione di rete' {
                Mock Invoke-RestMethod { throw 'Impossibile connettersi al server remoto.' }

                $exitCode = Invoke-InstallCoreLogic -ApiUrl $script:ApiUrl -DestDir $script:DestDir

                $exitCode | Should -Be 1
            }

            It 'non propaga l eccezione al chiamante' {
                Mock Invoke-RestMethod { throw 'Timeout della connessione.' }

                { Invoke-InstallCoreLogic -ApiUrl $script:ApiUrl -DestDir $script:DestDir } | Should -Not -Throw
            }
        }

        # ---------------------------------------------------------- Scenario 3
        Context 'Scenario 3 — file estratto mancante dopo Expand-Archive' {

            BeforeEach {
                # API e download simulati con successo
                Mock Invoke-RestMethod { return $script:ValidRelease }
                Mock Invoke-WebRequest {}
                # Expand-Archive non crea nulla (no-op)
                Mock Expand-Archive {}
                # Test-Path: C:\Scripts esiste, ma Installa-TaskPianificato.ps1 NON esiste
                Mock Test-Path {
                    param([string]$Path)
                    if ($Path -like '*Installa-TaskPianificato.ps1') { return $false }
                    return $true
                }
            }

            It 'restituisce exit code 1 quando lo script non viene creato dall estrazione' {
                $exitCode = Invoke-InstallCoreLogic -ApiUrl $script:ApiUrl -DestDir $script:DestDir

                $exitCode | Should -Be 1
            }

            It 'invoca Expand-Archive esattamente una volta' {
                Invoke-InstallCoreLogic -ApiUrl $script:ApiUrl -DestDir $script:DestDir

                Should -Invoke Expand-Archive -Exactly 1
            }
        }

        # ---------------------------------------------------------- Percorso felice
        Context 'Percorso felice — installazione completa con successo' {

            BeforeEach {
                Mock Invoke-RestMethod { return $script:ValidRelease }
                Mock Invoke-WebRequest {}
                Mock Expand-Archive {}
                Mock Test-Path { return $true }
                Mock New-Item {}
            }

            It 'restituisce exit code 0 quando tutto riesce' {
                $exitCode = Invoke-InstallCoreLogic -ApiUrl $script:ApiUrl -DestDir $script:DestDir

                $exitCode | Should -Be 0
            }

            It 'chiama Invoke-WebRequest con l URL dell asset' {
                Invoke-InstallCoreLogic -ApiUrl $script:ApiUrl -DestDir $script:DestDir

                Should -Invoke Invoke-WebRequest -Exactly 1 -ParameterFilter {
                    $Uri -eq 'https://example.com/PerformanceManagerGB.zip'
                }
            }
        }
    }

    # ========================================================================
    # SEZIONE UNINSTALL
    # ========================================================================
    Describe 'Uninstall.ps1 — logica core' {

        # ---------------------------------------------------------- Scenario 4
        Context 'Scenario 4 — conferma negativa' {

            It 'imposta Annullato=$true quando l utente digita stringa vuota' {
                Mock Get-ScheduledTask {}
                Mock Remove-Item {}

                $result = Invoke-UninstallCoreLogic -Conferma '' -DestDir $script:DestDir

                $result.Annullato | Should -BeTrue
            }

            It 'non rimuove nessun task quando la conferma e sbagliata' {
                Mock Get-ScheduledTask {}
                Mock Remove-Item {}

                Invoke-UninstallCoreLogic -Conferma 'no' -DestDir $script:DestDir

                Should -Invoke Get-ScheduledTask -Exactly 0
            }

            It 'non rimuove nessun file quando la conferma e sbagliata' {
                Mock Get-ScheduledTask {}
                Mock Remove-Item {}

                Invoke-UninstallCoreLogic -Conferma 'ANNULLA' -DestDir $script:DestDir

                Should -Invoke Remove-Item -Exactly 0
            }

            It 'il confronto e case-insensitive: "conferma" minuscolo viene accettato' {
                Mock Get-ScheduledTask { return $null }
                Mock Test-Path { return $false }
                Mock Stop-ScheduledTask {}
                Mock Unregister-ScheduledTask {}
                Mock Remove-Item {}

                $result = Invoke-UninstallCoreLogic -Conferma 'conferma' -DestDir $script:DestDir

                $result.Annullato | Should -BeFalse
            }
        }

        # ---------------------------------------------------------- Scenario 5
        Context 'Scenario 5 — task pianificato inesistente' {

            BeforeEach {
                # Tutti i task restituiscono $null → non trovati
                Mock Get-ScheduledTask { return $null }
                Mock Stop-ScheduledTask {}
                Mock Unregister-ScheduledTask {}
                Mock Test-Path { return $false }
                Mock Remove-Item {}
            }

            It 'non lancia eccezioni quando nessun task esiste' {
                { Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir } | Should -Not -Throw
            }

            It 'non chiama Unregister-ScheduledTask quando i task non esistono' {
                Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                Should -Invoke Unregister-ScheduledTask -Exactly 0
            }

            It 'l output contiene il messaggio "ignorato" per ogni task mancante' {
                $result = Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                $tasksTrovati = $result.Output | Where-Object { $_ -like '*ignorato*' }
                $tasksTrovati.Count | Should -BeGreaterOrEqual 4
            }

            It 'TasksRemoved e vuoto quando nessun task viene trovato' {
                $result = Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                $result.TasksRemoved.Count | Should -Be 0
            }
        }

        # ---------------------------------------------------------- Scenario 6
        Context 'Scenario 6 — file script assenti in C:\Scripts' {

            BeforeEach {
                Mock Get-ScheduledTask { return $null }
                Mock Stop-ScheduledTask {}
                Mock Unregister-ScheduledTask {}
                # Test-Path restituisce $false per tutti i file → file non presenti
                Mock Test-Path { return $false }
                Mock Remove-Item {}
            }

            It 'non lancia eccezioni quando i file non esistono' {
                { Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir } | Should -Not -Throw
            }

            It 'non chiama Remove-Item quando i file sono assenti' {
                Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                Should -Invoke Remove-Item -Exactly 0
            }

            It 'l output contiene il messaggio "ignorato" per ogni file mancante' {
                $result = Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                $fileMancanti = $result.Output | Where-Object { $_ -like '*ignorato*' -and $_ -like '*File*' }
                $fileMancanti.Count | Should -BeGreaterOrEqual 2
            }

            It 'FilesRemoved e vuoto quando i file non esistono' {
                $result = Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                $result.FilesRemoved.Count | Should -Be 0
            }
        }

        # ---------------------------------------------------------- Scenario 7
        Context 'Scenario 7 — scenario completo: task e file rimossi correttamente' {

            BeforeEach {
                # Tutti e 4 i task esistono
                Mock Get-ScheduledTask {
                    param([string]$TaskName)
                    return [PSCustomObject]@{ TaskName = $TaskName; State = 'Running' }
                }
                Mock Stop-ScheduledTask {}
                Mock Unregister-ScheduledTask {}
                # Entrambi i file esistono
                Mock Test-Path { return $true }
                Mock Remove-Item {}
                Mock New-Item {}
            }

            It 'rimuove tutti e 4 i task pianificati' {
                $result = Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                $result.TasksRemoved.Count | Should -Be 4
            }

            It 'chiama Unregister-ScheduledTask esattamente 4 volte' {
                Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                Should -Invoke Unregister-ScheduledTask -Exactly 4
            }

            It 'chiama Stop-ScheduledTask esattamente 4 volte' {
                Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                Should -Invoke Stop-ScheduledTask -Exactly 4
            }

            It 'rimuove entrambi i file script' {
                $result = Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                $result.FilesRemoved.Count | Should -Be 2
            }

            It 'chiama Remove-Item esattamente 2 volte' {
                Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                Should -Invoke Remove-Item -Exactly 2
            }

            It 'TasksRemoved contiene "Performance Manager for Galaxy Book"' {
                $result = Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                $result.TasksRemoved | Should -Contain 'Performance Manager for Galaxy Book'
            }

            It 'FilesRemoved contiene il percorso di PerformanceManagerGB.ps1' {
                $result = Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                $result.FilesRemoved | Should -Contain (Join-Path $script:DestDir 'PerformanceManagerGB.ps1')
            }

            It 'FilesRemoved contiene il percorso di Installa-TaskPianificato.ps1' {
                $result = Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                $result.FilesRemoved | Should -Contain (Join-Path $script:DestDir 'Installa-TaskPianificato.ps1')
            }

            It 'Annullato e $false quando la conferma e corretta' {
                $result = Invoke-UninstallCoreLogic -Conferma 'CONFERMA' -DestDir $script:DestDir

                $result.Annullato | Should -BeFalse
            }
        }
    }
}

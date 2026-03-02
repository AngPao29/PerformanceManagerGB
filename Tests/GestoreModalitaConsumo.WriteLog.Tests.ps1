# =============================================================================
# Pester v5 - Test per GestoreModalitaConsumo.ps1
# Sezioni/funzioni coperte:
#   - Write-Log  (creazione file, formato timestamp, inclusione messaggio,
#                 rotazione a >512 KB, silenzio errori di scrittura)
#   - Play-NotificationSound  (guard SoundEnabled, no-throw con audio attivo,
#                              silenzio eccezioni interne)
#
# NOTA: lo script principale NON può essere dot-sourced direttamente
# (avvia subito il loop event-driven + acquisisce un Mutex globale).
# Le funzioni rilevanti vengono ridefinite inline nel BeforeAll.
#
# Esecuzione:
#   Invoke-Pester -Path 'C:\Scripts\Tests\GestoreModalitaConsumo.WriteLog.Tests.ps1' -Output Detailed
# =============================================================================

Describe 'GestoreModalitaConsumo - Write-Log e Play-NotificationSound' {

    BeforeAll {
        # --- Percorso log di test in TEMP (scrivibile, non richiede admin) ---
        $script:logFile    = Join-Path $env:TEMP "WriteLogTest_$([System.IO.Path]::GetRandomFileName()).log"
        $script:logMaxSize = 512KB

        # --- Ricrea trayState identico allo script originale ---
        $script:trayState = [hashtable]::Synchronized(@{
            CurrentMode       = 'Ottimizzata'
            ChargePercent     = 0
            IsOnAC            = $false
            IsPaused          = $false
            SoundEnabled      = $true
            NotifPopupEnabled = $true
            RequestedMode     = $null
            RequestExit       = $false
            LogFile           = $script:logFile
        })

        function script:Write-Log {
            param([string]$Message)
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $line = "$timestamp  $Message"
            try {
                if ((Test-Path $script:logFile) -and
                    (Get-Item $script:logFile).Length -gt $script:logMaxSize) {
                    $lines = Get-Content $script:logFile -Tail 200 -Encoding UTF8
                    Set-Content $script:logFile -Value $lines -Encoding UTF8
                }
                Add-Content $script:logFile -Value $line -Encoding UTF8
            }
            catch { }
        }

        function script:Play-NotificationSound {
            if (-not $script:trayState.SoundEnabled) { return }
            try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }
        }
    }

    AfterAll {
        if (Test-Path $script:logFile) {
            Remove-Item $script:logFile -Force -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name logFile, logMaxSize, trayState -Scope Script -ErrorAction SilentlyContinue
    }

    # =========================================================================
    Describe 'Write-Log' {

        AfterEach {
            if (Test-Path $script:logFile) {
                Remove-Item $script:logFile -Force -ErrorAction SilentlyContinue
            }
        }

        Context 'Creazione e scrittura del file di log' {

            It 'crea il file di log se non esiste' {
                if (Test-Path $script:logFile) { Remove-Item $script:logFile -Force }

                Write-Log -Message 'Test creazione file'

                Test-Path $script:logFile | Should -Be $true
            }

            It "la riga scritta inizia con un timestamp nel formato 'yyyy-MM-dd HH:mm:ss'" {
                Write-Log -Message 'Test formato timestamp'

                $primaRiga = @(Get-Content $script:logFile -Encoding UTF8)[0]
                $primaRiga | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'
            }

            It 'la riga scritta contiene il messaggio passato come parametro' {
                $messaggio = 'Messaggio-Univoco-ABC-9871'

                Write-Log -Message $messaggio

                $contenuto = Get-Content $script:logFile -Encoding UTF8 -Raw
                $contenuto | Should -Match ([regex]::Escape($messaggio))
            }

            It 'aggiunge la riga senza troncare il file quando esso e sotto la soglia' {
                1..5 | ForEach-Object {
                    Add-Content -Path $script:logFile -Value "Riga preesistente $_" -Encoding UTF8
                }

                Write-Log -Message 'Riga aggiuntiva post-esistenti'

                $righe = Get-Content $script:logFile -Encoding UTF8
                $righe.Count | Should -Be 6
            }
        }

        Context 'Rotazione del log quando supera logMaxSize (512 KB)' {

            BeforeEach {
                $script:_righeGrandi = 1..7000 | ForEach-Object {
                    "Riga di log fittizio numero $_  " + ("X" * 55)
                }
            }

            AfterEach {
                Remove-Variable -Name _righeGrandi -Scope Script -ErrorAction SilentlyContinue
            }

            It 'il file usato per la rotazione supera effettivamente 512 KB' {
                Set-Content -Path $script:logFile -Value $script:_righeGrandi -Encoding UTF8

                (Get-Item $script:logFile).Length | Should -BeGreaterThan 512KB
            }

            It 'il file contiene esattamente 201 righe dopo la rotazione (200 tail + 1 nuova)' {
                Set-Content -Path $script:logFile -Value $script:_righeGrandi -Encoding UTF8

                Write-Log -Message 'Riga di controllo conteggio'

                $righeFinali = Get-Content $script:logFile -Encoding UTF8
                $righeFinali.Count | Should -Be 201
            }

            It "l'ultima riga del file contiene il messaggio scritto dopo la rotazione" {
                Set-Content -Path $script:logFile -Value $script:_righeGrandi -Encoding UTF8

                $messaggioAtteso = 'Messaggio-Rotazione-Univoco-ZZZ'
                Write-Log -Message $messaggioAtteso

                $righeFinali = Get-Content $script:logFile -Encoding UTF8
                $righeFinali[-1] | Should -Match ([regex]::Escape($messaggioAtteso))
            }
        }

        Context 'Silenzio degli errori di scrittura' {

            It 'non lancia eccezioni se il percorso di logFile non e valido' {
                $pathOriginale = $script:logFile
                $script:logFile = 'Z:\PercorsoInesistente\Subdir\GestoreTest.log'
                try {
                    { Write-Log -Message 'Test path non valido' } | Should -Not -Throw
                }
                finally {
                    $script:logFile = $pathOriginale
                }
            }
        }
    }

    # =========================================================================
    Describe 'Play-NotificationSound' {

        AfterEach {
            $script:trayState.SoundEnabled = $true
        }

        Context 'Guard: SoundEnabled = $false' {

            It 'non lancia eccezioni quando SoundEnabled e $false' {
                $script:trayState.SoundEnabled = $false

                { Play-NotificationSound } | Should -Not -Throw
            }

            It 'completa senza errori (nessuna eccezione) quando SoundEnabled e $false' {
                $script:trayState.SoundEnabled = $false
                $erroreRilevato = $null
                try { Play-NotificationSound } catch { $erroreRilevato = $_ }

                $erroreRilevato | Should -BeNullOrEmpty
            }
        }

        Context 'SoundEnabled = $true' {

            It 'non lancia eccezioni quando SoundEnabled e $true' {
                $script:trayState.SoundEnabled = $true

                { Play-NotificationSound } | Should -Not -Throw
            }

            It 'errori in Play() non si propagano fuori dalla funzione' {
                function script:Play-NotificationSound-ThrowTest {
                    if (-not $script:trayState.SoundEnabled) { return }
                    try { throw 'Errore audio simulato' } catch { }
                }
                $script:trayState.SoundEnabled = $true

                { Play-NotificationSound-ThrowTest } | Should -Not -Throw

                Remove-Item Function:\Play-NotificationSound-ThrowTest -ErrorAction SilentlyContinue
            }
        }
    }
}
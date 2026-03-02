# =============================================================================
# Pester v5 - Test per GestoreModalitaConsumo.ps1
# Sezioni/funzioni coperte:
#   - $script:trayState  (chiave NotifPopupEnabled)
#   - Show-ModeNotification  (guard + creazione runspace STA)
#   - Menu tray popup item  (pattern CheckedChanged)
#
# NOTA: lo script principale NON può essere dot-sourced direttamente
# (avvia subito il loop event-driven + acquisisce un Mutex globale).
# Le funzioni rilevanti vengono ridefinite inline nel BeforeAll.
# =============================================================================

Describe 'GestoreModalitaConsumo - Notifiche Popup' {

    BeforeAll {
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
            LogFile           = "$env:TEMP\test_gestore.log"
        })

        # --- Ridefinizione inline di Show-ModeNotification ---
        # Riproduce fedelmente la guard + la creazione del runspace STA.
        # Il blocco XAML/AddScript è omesso: l'obiettivo è isolare
        # il comportamento del gate NotifPopupEnabled e della costruzione
        # del runspace, non l'UI della notifica stessa.
        function script:Show-ModeNotification {
            param(
                [string]$ModeName,
                [string]$IconGlyph,
                [string]$AccentColor,
                [string]$Subtitle = ''
            )
            # GUARD - identica allo script originale
            if (-not $script:trayState.NotifPopupEnabled) { return }
            try {
                # Pulizia runspace precedente
                if ($script:_notifPS) {
                    try { $script:_notifPS.Stop();  $script:_notifPS.Dispose() } catch {}
                    try { $script:_notifRS.Close(); $script:_notifRS.Dispose() } catch {}
                }
                # Creazione runspace STA (identica allo script originale)
                $script:_notifRS = [runspacefactory]::CreateRunspace()
                $script:_notifRS.ApartmentState = 'STA'
                $script:_notifRS.ThreadOptions  = 'ReuseThread'
                $script:_notifRS.Open()

                $script:_notifPS = [powershell]::Create()
                $script:_notifPS.Runspace = $script:_notifRS
                # (AddScript con XAML omesso: non necessario per questi test)
            }
            catch { }
        }

        # --- Helper che replica la closure CheckedChanged del popupItem ---
        # Originale:  $State.NotifPopupEnabled = $popupItem.Checked
        function script:Invoke-PopupItemCheckedChanged {
            param(
                [System.Collections.Hashtable]$State,
                [bool]$NewChecked
            )
            $State.NotifPopupEnabled = $NewChecked
        }
    }

    AfterAll {
        # Pulizia runspace aperti durante i test
        if ($script:_notifPS) {
            try { $script:_notifPS.Stop();  $script:_notifPS.Dispose() } catch {}
        }
        if ($script:_notifRS) {
            try { $script:_notifRS.Close(); $script:_notifRS.Dispose() } catch {}
        }
        Remove-Variable -Name trayState, _notifPS, _notifRS -Scope Script -ErrorAction SilentlyContinue
    }

    # =========================================================================
    Context 'trayState - valori predefiniti' {

        It 'NotifPopupEnabled deve essere $true per default' {
            $script:trayState.NotifPopupEnabled | Should -Be $true
        }

        It 'trayState deve essere una Synchronized Hashtable' {
            $script:trayState.GetType().Name | Should -Be 'SyncHashtable'
        }

        It 'tutte le chiavi attese devono essere presenti nel trayState' {
            $expectedKeys = @(
                'CurrentMode', 'ChargePercent', 'IsOnAC', 'IsPaused',
                'SoundEnabled', 'NotifPopupEnabled', 'RequestedMode',
                'RequestExit', 'LogFile'
            )
            foreach ($key in $expectedKeys) {
                $script:trayState.ContainsKey($key) |
                    Should -Be $true -Because "la chiave '$key' e' richiesta nel trayState"
            }
        }
    }

    # =========================================================================
    Context 'Show-ModeNotification - guard NotifPopupEnabled' {

        BeforeEach {
            # Azzera i riferimenti ai runspace prima di ogni test
            $script:_notifRS = $null
            $script:_notifPS = $null
        }

        AfterEach {
            # Chiude il runspace se Show-ModeNotification ne ha creato uno
            if ($script:_notifPS) {
                try { $script:_notifPS.Stop();  $script:_notifPS.Dispose() } catch {}
            }
            if ($script:_notifRS) {
                try { $script:_notifRS.Close(); $script:_notifRS.Dispose() } catch {}
            }
            $script:_notifRS = $null
            $script:_notifPS = $null
        }

        It 'NON deve creare il runspace quando NotifPopupEnabled = $false' {
            $script:trayState.NotifPopupEnabled = $false

            Show-ModeNotification -ModeName 'Ottimizzata' -IconGlyph '' -AccentColor '#60CDFF'

            $script:_notifRS | Should -BeNullOrEmpty
        }

        It 'DEVE creare il runspace quando NotifPopupEnabled = $true' {
            $script:trayState.NotifPopupEnabled = $true

            Show-ModeNotification -ModeName 'Prestazioni Elevate' -IconGlyph '' -AccentColor '#FFAA2C'

            $script:_notifRS | Should -Not -BeNullOrEmpty
        }

        It 'il runspace creato deve avere ApartmentState = STA' {
            $script:trayState.NotifPopupEnabled = $true

            Show-ModeNotification -ModeName 'Ottimizzata' -IconGlyph '' -AccentColor '#60CDFF'

            $script:_notifRS.ApartmentState | Should -Be 'STA'
        }

        It 'il runspace creato deve essere nello stato Opened' {
            $script:trayState.NotifPopupEnabled = $true

            Show-ModeNotification -ModeName 'Ottimizzata' -IconGlyph '' -AccentColor '#60CDFF'

            $script:_notifRS.RunspaceStateInfo.State | Should -Be 'Opened'
        }

        It 'NON deve modificare _notifRS se la guard blocca l esecuzione (valore sentinella)' {
            $script:trayState.NotifPopupEnabled = $false
            $script:_notifRS = $null   # sentinella esplicita

            Show-ModeNotification -ModeName 'Ottimizzata' -IconGlyph '' -AccentColor '#60CDFF'

            $script:_notifRS | Should -BeNullOrEmpty
        }
    }

    # =========================================================================
    Context 'Menu tray - popupItem CheckedChanged toggle' {

        BeforeEach {
            $script:trayState.NotifPopupEnabled = $true   # ripristina default
            $script:_notifRS = $null
            $script:_notifPS = $null
        }

        AfterEach {
            if ($script:_notifPS) {
                try { $script:_notifPS.Stop();  $script:_notifPS.Dispose() } catch {}
            }
            if ($script:_notifRS) {
                try { $script:_notifRS.Close(); $script:_notifRS.Dispose() } catch {}
            }
            $script:_notifRS = $null
            $script:_notifPS = $null
        }

        It 'il toggle a $false deve impostare NotifPopupEnabled = $false nel trayState' {
            Invoke-PopupItemCheckedChanged -State $script:trayState -NewChecked $false

            $script:trayState.NotifPopupEnabled | Should -Be $false
        }

        It 'il toggle a $true deve impostare NotifPopupEnabled = $true nel trayState' {
            $script:trayState.NotifPopupEnabled = $false   # parte da false

            Invoke-PopupItemCheckedChanged -State $script:trayState -NewChecked $true

            $script:trayState.NotifPopupEnabled | Should -Be $true
        }

        It 'dopo toggle $false Show-ModeNotification non deve creare il runspace' {
            Invoke-PopupItemCheckedChanged -State $script:trayState -NewChecked $false

            Show-ModeNotification -ModeName 'Ottimizzata' -IconGlyph '' -AccentColor '#60CDFF'

            $script:_notifRS | Should -BeNullOrEmpty
        }

        It 'dopo toggle $true Show-ModeNotification DEVE creare il runspace' {
            $script:trayState.NotifPopupEnabled = $false
            Invoke-PopupItemCheckedChanged -State $script:trayState -NewChecked $true

            Show-ModeNotification -ModeName 'Prestazioni Elevate' -IconGlyph '' -AccentColor '#FFAA2C'

            $script:_notifRS | Should -Not -BeNullOrEmpty
        }

        It 'il toggle ripetuto deve riflettersi sempre correttamente nel trayState' {
            # Sequenza: default(true) -> false -> true -> false
            $script:trayState.NotifPopupEnabled | Should -Be $true

            Invoke-PopupItemCheckedChanged -State $script:trayState -NewChecked $false
            $script:trayState.NotifPopupEnabled | Should -Be $false

            Invoke-PopupItemCheckedChanged -State $script:trayState -NewChecked $true
            $script:trayState.NotifPopupEnabled | Should -Be $true

            Invoke-PopupItemCheckedChanged -State $script:trayState -NewChecked $false
            $script:trayState.NotifPopupEnabled | Should -Be $false
        }

        It 'il trayState modificato da Invoke-PopupItemCheckedChanged deve essere lo stesso oggetto (Synchronized)' {
            $before = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($script:trayState)

            Invoke-PopupItemCheckedChanged -State $script:trayState -NewChecked $false

            $after = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($script:trayState)
            $after | Should -Be $before
        }
    }
}

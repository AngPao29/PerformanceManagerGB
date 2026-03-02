# =============================================================================
# Pester v5 - Test di compatibilita' per PerformanceManagerGB.ps1
#             e Installa-TaskPianificato.ps1
#
# Logiche coperte (6 scenari minimo):
#   1. Installa-TaskPianificato.ps1 – rilevamento runtime PS
#      a. PS7 disponibile  -> $psExe e' il path assoluto di pwsh.exe
#      b. PS7 non disponibile -> $psExe e' 'powershell.exe'
#   2. PerformanceManagerGB.ps1 – $prevModeName (if/else, ex ??)
#      a. $MODE_NAMES[$key] esiste    -> nome leggibile
#      b. $MODE_NAMES[$key] non esiste -> valore numerico come stringa
#   3. PerformanceManagerGB.ps1 – Add-Type refs condizionali
#      a. PS7+ -> $addTypeRefs[0] e' un path assoluto (contiene \ o /)
#      b. PS5.1 -> $addTypeRefs contiene 'System.Core' e 'System.Management'
#
# NOTA: lo script principale NON e' dot-sourced (avvia loop event-driven +
# acquisisce Mutex globale). Le logiche sono riprodotte inline in BeforeAll.
#
# Esecuzione:
#   Invoke-Pester -Path 'C:\Scripts\Tests\PerformanceManagerGB.Compatibility.Tests.ps1' -Output Detailed
# =============================================================================

# ---------------------------------------------------------------------------
# SEZIONE 1 – Installa-TaskPianificato.ps1: rilevamento runtime PS
# ---------------------------------------------------------------------------
Describe 'Installa-TaskPianificato - Rilevamento runtime PowerShell' {

    BeforeAll {
        # Riproduce la logica minima dell'script di installazione:
        #   $pwshCmd = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
        #   $psExe   = if ($pwshCmd) { $pwshCmd.Source } else { 'powershell.exe' }
        function script:Get-RuntimeExecutable {
            $pwshCmd = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
            $psExe   = if ($pwshCmd) { $pwshCmd.Source } else { 'powershell.exe' }
            return $psExe
        }
    }

    Context 'PS7 disponibile (pwsh.exe trovato nel PATH)' {

        BeforeAll {
            $script:fakePwshPath = 'C:\Program Files\PowerShell\7\pwsh.exe'
            $script:fakeCmd      = [PSCustomObject]@{ Source = $script:fakePwshPath }

            Mock -CommandName Get-Command `
                 -MockWith     { return $script:fakeCmd } `
                 -ParameterFilter { $Name -eq 'pwsh.exe' }
        }

        It 'restituisce il path assoluto di pwsh.exe' {
            $result = Get-RuntimeExecutable
            $result | Should -Be $script:fakePwshPath
        }

        It 'il path risultante non e'' "powershell.exe"' {
            $result = Get-RuntimeExecutable
            $result | Should -Not -Be 'powershell.exe'
        }

        It 'il path risultante contiene "pwsh.exe"' {
            $result = Get-RuntimeExecutable
            $result | Should -Match 'pwsh\.exe'
        }
    }

    Context 'PS7 non disponibile (pwsh.exe assente dal PATH)' {

        BeforeAll {
            Mock -CommandName Get-Command `
                 -MockWith     { return $null } `
                 -ParameterFilter { $Name -eq 'pwsh.exe' }
        }

        It 'restituisce "powershell.exe" come fallback' {
            $result = Get-RuntimeExecutable
            $result | Should -Be 'powershell.exe'
        }

        It 'il valore di fallback non e'' un path assoluto' {
            $result = Get-RuntimeExecutable
            $result | Should -Not -Match '[/\\]'
        }
    }
}

# ---------------------------------------------------------------------------
# SEZIONE 2 – PerformanceManagerGB.ps1: $prevModeName (if/else, ex ??)
# ---------------------------------------------------------------------------
Describe 'PerformanceManagerGB - $prevModeName: risoluzione nome modalita''' {

    BeforeAll {
        # Riproduce la mappa e la logica del blocco safe-default:
        #   $prevModeName = if ($null -ne $MODE_NAMES[$currentModeAtStart]) {
        #       $MODE_NAMES[$currentModeAtStart]
        #   } else { "$currentModeAtStart" }
        $script:MODE_NAMES_COMPAT = @{
            2 = 'Ottimizzata'
            3 = 'Prestazioni Elevate'
        }

        function script:Resolve-PrevModeName {
            param([int]$CurrentModeAtStart)
            $result = if ($null -ne $script:MODE_NAMES_COMPAT[$CurrentModeAtStart]) {
                $script:MODE_NAMES_COMPAT[$CurrentModeAtStart]
            } else {
                "$CurrentModeAtStart"
            }
            return $result
        }
    }

    Context 'Chiave presente nella mappa MODE_NAMES' {

        It 'modalita'' 3 -> restituisce "Prestazioni Elevate"' {
            Resolve-PrevModeName -CurrentModeAtStart 3 | Should -Be 'Prestazioni Elevate'
        }

        It 'modalita'' 2 -> restituisce "Ottimizzata"' {
            Resolve-PrevModeName -CurrentModeAtStart 2 | Should -Be 'Ottimizzata'
        }

        It 'il risultato e'' una stringa non vuota' {
            $r = Resolve-PrevModeName -CurrentModeAtStart 3
            $r | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Chiave assente nella mappa MODE_NAMES' {

        It 'modalita'' sconosciuta 99 -> restituisce "99" (stringa)' {
            $r = Resolve-PrevModeName -CurrentModeAtStart 99
            $r | Should -Be '99'
        }

        It 'modalita'' sconosciuta 0 -> restituisce "0" (stringa)' {
            $r = Resolve-PrevModeName -CurrentModeAtStart 0
            $r | Should -Be '0'
        }

        It 'il risultato e'' comunque una stringa (non $null)' {
            $r = Resolve-PrevModeName -CurrentModeAtStart 99
            $r | Should -BeOfType [string]
        }

        It 'il risultato coincide con il numero passato come stringa' {
            $mode = 42
            $r    = Resolve-PrevModeName -CurrentModeAtStart $mode
            $r    | Should -Be "$mode"
        }
    }
}

# ---------------------------------------------------------------------------
# SEZIONE 3 – PerformanceManagerGB.ps1: Add-Type refs condizionali
# ---------------------------------------------------------------------------
Describe 'PerformanceManagerGB - Add-Type refs condizionali per versione PS' {

    BeforeAll {
        # Riproduce la logica di selezione assembly per Add-Type:
        #
        #   if ($PSVersionTable.PSVersion.Major -ge 7) {
        #       $interopDll = Join-Path $runtimeDir 'System.Runtime.InteropServices.dll'
        #       if (-not (Test-Path $interopDll)) {
        #           $interopDll = [System.Runtime.InteropServices.Marshal].Assembly.Location
        #       }
        #       $addTypeRefs = @($interopDll, <EventLogWatcher.dll>, <Management.dll>)
        #   } else {
        #       $addTypeRefs = @('System.Core', 'System.Management')
        #   }
        #
        # Il parametro PSMajorVersion sostituisce $PSVersionTable.PSVersion.Major
        # per isolare la logica dal runtime corrente del test.
        function script:Resolve-AddTypeRefs {
            param([int]$PSMajorVersion)
            $runtimeDir = [System.IO.Path]::GetDirectoryName([object].Assembly.Location)
            if ($PSMajorVersion -ge 7) {
                $interopDll = Join-Path $runtimeDir 'System.Runtime.InteropServices.dll'
                if (-not (Test-Path $interopDll)) {
                    $interopDll = [System.Runtime.InteropServices.Marshal].Assembly.Location
                }
                return @(
                    $interopDll,
                    [System.Diagnostics.Eventing.Reader.EventLogWatcher].Assembly.Location,
                    [System.Management.ManagementEventWatcher].Assembly.Location
                )
            }
            else {
                return @('System.Core', 'System.Management')
            }
        }
    }

    Context 'Runtime PS7+ (.NET 5+): path assoluti obbligatori' {

        It '$addTypeRefs[0] e'' un path assoluto (contiene \ o /)' {
            $refs = Resolve-AddTypeRefs -PSMajorVersion 7
            $refs[0] | Should -Match '[/\\]'
        }

        It 'tutti gli elementi sono path assoluti (nessun nome breve GAC)' {
            $refs = Resolve-AddTypeRefs -PSMajorVersion 7
            foreach ($r in $refs) {
                $r | Should -Match '[/\\]'
            }
        }

        It 'restituisce almeno 3 riferimenti assembly' {
            $refs = Resolve-AddTypeRefs -PSMajorVersion 7
            $refs.Count | Should -BeGreaterOrEqual 3
        }

        It 'nessun elemento e'' $null o vuoto' {
            $refs = Resolve-AddTypeRefs -PSMajorVersion 7
            foreach ($r in $refs) {
                $r | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Runtime PS5.1 (.NET Framework): nomi brevi GAC' {

        It '$addTypeRefs contiene "System.Core"' {
            $refs = Resolve-AddTypeRefs -PSMajorVersion 5
            $refs | Should -Contain 'System.Core'
        }

        It '$addTypeRefs contiene "System.Management"' {
            $refs = Resolve-AddTypeRefs -PSMajorVersion 5
            $refs | Should -Contain 'System.Management'
        }

        It 'restituisce esattamente 2 riferimenti' {
            $refs = Resolve-AddTypeRefs -PSMajorVersion 5
            $refs.Count | Should -Be 2
        }

        It 'nessun elemento e'' un path assoluto (solo nomi GAC)' {
            $refs = Resolve-AddTypeRefs -PSMajorVersion 5
            foreach ($r in $refs) {
                $r | Should -Not -Match '[/\\]'
            }
        }
    }

    Context 'Boundary: PSMajorVersion = 6 trattato come PS5.1 (soglia e'' -ge 7)' {

        # La condizione nello script e' -ge 7: PS6 cade nel ramo .NET Framework.
        It 'PSMajorVersion=6 -> contiene "System.Core" (ramo GAC)' {
            $refs = Resolve-AddTypeRefs -PSMajorVersion 6
            $refs | Should -Contain 'System.Core'
        }

        It 'PSMajorVersion=6 -> contiene "System.Management" (ramo GAC)' {
            $refs = Resolve-AddTypeRefs -PSMajorVersion 6
            $refs | Should -Contain 'System.Management'
        }

        It 'PSMajorVersion=6 -> restituisce esattamente 2 riferimenti' {
            $refs = Resolve-AddTypeRefs -PSMajorVersion 6
            $refs.Count | Should -Be 2
        }
    }

    Context 'Boundary: PSMajorVersion = 4 trattato come PS5.1' {

        It 'PSMajorVersion=4 -> contiene "System.Core"' {
            $refs = Resolve-AddTypeRefs -PSMajorVersion 4
            $refs | Should -Contain 'System.Core'
        }

        It 'PSMajorVersion=4 -> contiene "System.Management"' {
            $refs = Resolve-AddTypeRefs -PSMajorVersion 4
            $refs | Should -Contain 'System.Management'
        }
    }
}

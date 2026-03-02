# =============================================================================
# Pester v5 - Test per GestoreModalitaConsumo.ps1
# Funzione coperta: Get-BatteryProtectionLimit
#
# Copre:
#   - Protezione attiva (OnOff=1) con Value presente (80 e 85)
#   - Protezione attiva (OnOff=1) con Value assente -> defaultProtectionLimit (80)
#   - Protezione disabilitata (OnOff=0) -> 100
#   - Eccezione / chiave registro non trovata -> 100 (fallback sicuro)
#   - Il valore restituito e sempre di tipo [int]
#
# Esecuzione:
#   Invoke-Pester -Path 'C:\Scripts\Tests\' -Output Detailed
#
# NON richiede privilegi di amministratore.
# NON accede al registro reale: usa Mock di Pester su Get-ItemProperty.
# =============================================================================

Describe 'GestoreModalitaConsumo - Get-BatteryProtectionLimit' {

    BeforeAll {
        $script:regProtectBattery      = 'HKLM:\SOFTWARE\Samsung\SamsungSettings\ModuleProtectBattery'
        $script:defaultProtectionLimit = 80

        function Get-BatteryProtectionLimit {
            try {
                $protectBattery = Get-ItemProperty -Path $script:regProtectBattery -ErrorAction Stop
                if ($protectBattery.OnOff -eq 1) {
                    if ($null -ne $protectBattery.Value) {
                        return [int]$protectBattery.Value
                    }
                    else {
                        return $script:defaultProtectionLimit
                    }
                }
                else {
                    return 100
                }
            }
            catch {
                return 100
            }
        }
    }

    # -------------------------------------------------------------------------
    Context 'Protezione batteria attiva (OnOff = 1)' {

        It 'Value presente (80) -> restituisce 80' {
            Mock Get-ItemProperty { return [PSCustomObject]@{ OnOff = 1; Value = 80 } }

            $result = Get-BatteryProtectionLimit

            $result | Should -Be 80
        }

        It 'Value presente (85) -> restituisce 85' {
            Mock Get-ItemProperty { return [PSCustomObject]@{ OnOff = 1; Value = 85 } }

            $result = Get-BatteryProtectionLimit

            $result | Should -Be 85
        }

        It 'Value assente ($null) -> restituisce defaultProtectionLimit (80)' {
            Mock Get-ItemProperty { return [PSCustomObject]@{ OnOff = 1; Value = $null } }

            $result = Get-BatteryProtectionLimit

            $result | Should -Be 80
        }
    }

    # -------------------------------------------------------------------------
    Context 'Protezione batteria disabilitata (OnOff = 0)' {

        It '-> restituisce 100' {
            Mock Get-ItemProperty { return [PSCustomObject]@{ OnOff = 0; Value = 80 } }

            $result = Get-BatteryProtectionLimit

            $result | Should -Be 100
        }
    }

    # -------------------------------------------------------------------------
    Context 'Errore lettura registro' {

        It 'eccezione -> restituisce 100 (fallback sicuro)' {
            Mock Get-ItemProperty { throw 'Chiave non trovata' }

            $result = Get-BatteryProtectionLimit

            $result | Should -Be 100
        }
    }

    # -------------------------------------------------------------------------
    Context 'Tipo restituito' {

        It 'con Value presente il valore e sempre un [int]' {
            Mock Get-ItemProperty { return [PSCustomObject]@{ OnOff = 1; Value = 80 } }

            $result = Get-BatteryProtectionLimit

            $result | Should -BeOfType [int]
        }

        It 'con Value assente il valore e sempre un [int]' {
            Mock Get-ItemProperty { return [PSCustomObject]@{ OnOff = 1; Value = $null } }

            $result = Get-BatteryProtectionLimit

            $result | Should -BeOfType [int]
        }

        It 'con protezione disabilitata il valore e sempre un [int]' {
            Mock Get-ItemProperty { return [PSCustomObject]@{ OnOff = 0; Value = 80 } }

            $result = Get-BatteryProtectionLimit

            $result | Should -BeOfType [int]
        }

        It 'in caso di eccezione il valore e sempre un [int]' {
            Mock Get-ItemProperty { throw 'Chiave non trovata' }

            $result = Get-BatteryProtectionLimit

            $result | Should -BeOfType [int]
        }
    }
}
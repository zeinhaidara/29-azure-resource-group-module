BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..\src\AzResourceGroupKit\AzResourceGroupKit.psd1'
    Import-Module $modulePath -Force
}

Describe 'New-ResourceGroupName' {
    It 'builds a name from env/app/region' {
        New-ResourceGroupName -Environment prod -Application billing -Region eastus |
            Should -Be 'prod-billing-eastus-rg'
    }

    It 'lower-cases mixed-case input' {
        New-ResourceGroupName -Environment PROD -Application Billing -Region EastUS |
            Should -Be 'prod-billing-eastus-rg'
    }

    It 'rejects an invalid environment' {
        { New-ResourceGroupName -Environment qa -Application billing -Region eastus } |
            Should -Throw
    }

    It 'rejects an application name starting with a hyphen' {
        { New-ResourceGroupName -Environment prod -Application '-billing' -Region eastus } |
            Should -Throw
    }
}

Describe 'Test-ResourceGroupName' {
    It 'accepts a conforming name' {
        Test-ResourceGroupName -Name 'dev-webapp-westeurope-rg' | Should -BeTrue
    }

    It 'rejects a name missing the rg suffix' {
        Test-ResourceGroupName -Name 'dev-webapp-westeurope' | Should -BeFalse
    }

    It 'rejects an uppercase name' {
        Test-ResourceGroupName -Name 'Dev-Webapp-WestEurope-rg' | Should -BeFalse
    }
}

Describe 'New-StandardResourceGroup' {
    BeforeEach {
        Mock Get-AzResourceGroup -ModuleName AzResourceGroupKit { $null }
        Mock New-AzResourceGroup -ModuleName AzResourceGroupKit { [pscustomobject]@{ ResourceGroupName = $Name; Location = $Location; Tags = $Tag } }
        Mock Set-AzResourceGroup -ModuleName AzResourceGroupKit { [pscustomobject]@{ ResourceGroupName = $Name; Tags = $Tag } }
    }

    It 'creates a new resource group when none exists' {
        New-StandardResourceGroup -Name 'prod-billing-eastus-rg' -Location eastus -Tag @{ owner = 'platform' }
        Should -Invoke New-AzResourceGroup -ModuleName AzResourceGroupKit -Times 1
        Should -Invoke Set-AzResourceGroup -ModuleName AzResourceGroupKit -Times 0
    }

    It 'rejects a name that fails the naming convention before calling Azure' {
        { New-StandardResourceGroup -Name 'invalid name' -Location eastus } | Should -Throw
        Should -Invoke New-AzResourceGroup -ModuleName AzResourceGroupKit -Times 0
    }

    It 'is idempotent: merges tags instead of recreating when the group already exists in the same location' {
        Mock Get-AzResourceGroup -ModuleName AzResourceGroupKit {
            [pscustomobject]@{ ResourceGroupName = 'prod-billing-eastus-rg'; Location = 'eastus'; Tags = @{ owner = 'platform' } }
        }

        New-StandardResourceGroup -Name 'prod-billing-eastus-rg' -Location eastus -Tag @{ team = 'billing' }

        Should -Invoke New-AzResourceGroup -ModuleName AzResourceGroupKit -Times 0
        Should -Invoke Set-AzResourceGroup -ModuleName AzResourceGroupKit -Times 1
    }

    It 'throws on a location conflict rather than silently reusing the group' {
        Mock Get-AzResourceGroup -ModuleName AzResourceGroupKit {
            [pscustomobject]@{ ResourceGroupName = 'prod-billing-eastus-rg'; Location = 'westus'; Tags = @{} }
        }

        { New-StandardResourceGroup -Name 'prod-billing-eastus-rg' -Location eastus } | Should -Throw
        Should -Invoke New-AzResourceGroup -ModuleName AzResourceGroupKit -Times 0
    }

    It 'makes no Azure calls under -WhatIf' {
        New-StandardResourceGroup -Name 'prod-billing-eastus-rg' -Location eastus -WhatIf
        Should -Invoke New-AzResourceGroup -ModuleName AzResourceGroupKit -Times 0
    }
}

Describe 'Set-ResourceGroupDeleteLock' {
    It 'applies a new lock when none exists' {
        Mock Get-AzResourceLock -ModuleName AzResourceGroupKit { @() }
        Mock New-AzResourceLock -ModuleName AzResourceGroupKit { [pscustomobject]@{ Name = $LockName; Properties = @{ Level = 'CanNotDelete' } } }

        Set-ResourceGroupDeleteLock -ResourceGroupName 'prod-billing-eastus-rg'
        Should -Invoke New-AzResourceLock -ModuleName AzResourceGroupKit -Times 1
    }

    It 'is idempotent when the matching lock already exists' {
        Mock Get-AzResourceLock -ModuleName AzResourceGroupKit {
            @([pscustomobject]@{ Name = 'standard-delete-lock'; Properties = @{ Level = 'CanNotDelete' } })
        }
        Mock New-AzResourceLock -ModuleName AzResourceGroupKit { throw 'should not be called' }

        Set-ResourceGroupDeleteLock -ResourceGroupName 'prod-billing-eastus-rg'
        Should -Invoke New-AzResourceLock -ModuleName AzResourceGroupKit -Times 0
    }

    It 'throws instead of overwriting a lock with a different level' {
        Mock Get-AzResourceLock -ModuleName AzResourceGroupKit {
            @([pscustomobject]@{ Name = 'standard-delete-lock'; Properties = @{ Level = 'ReadOnly' } })
        }
        Mock New-AzResourceLock -ModuleName AzResourceGroupKit { throw 'should not be called' }

        { Set-ResourceGroupDeleteLock -ResourceGroupName 'prod-billing-eastus-rg' } | Should -Throw
    }

    It 'makes no Azure calls under -WhatIf' {
        Mock Get-AzResourceLock -ModuleName AzResourceGroupKit { @() }
        Mock New-AzResourceLock -ModuleName AzResourceGroupKit { throw 'should not be called' }

        Set-ResourceGroupDeleteLock -ResourceGroupName 'prod-billing-eastus-rg' -WhatIf
        Should -Invoke New-AzResourceLock -ModuleName AzResourceGroupKit -Times 0
    }
}

Describe 'New-ResourceGroupBudget' {
    BeforeEach {
        Mock Invoke-AzRestMethod -ModuleName AzResourceGroupKit {
            if ($Method -eq 'GET') {
                return [pscustomobject]@{ StatusCode = 404; Content = '' }
            }
            [pscustomobject]@{ StatusCode = 201; Content = '{"properties":{"amount":500}}' }
        }
    }

    It 'rejects a threshold outside 1-100 before calling Azure' {
        { New-ResourceGroupBudget -ResourceGroupName 'prod-billing-eastus-rg' -SubscriptionId '00000000-0000-0000-0000-000000000000' -Amount 500 -AlertThreshold 150 -ContactEmail 'team@example.com' } |
            Should -Throw
        Should -Invoke Invoke-AzRestMethod -ModuleName AzResourceGroupKit -Times 0
    }

    It 'creates a budget when none exists' {
        New-ResourceGroupBudget -ResourceGroupName 'prod-billing-eastus-rg' -SubscriptionId '00000000-0000-0000-0000-000000000000' -Amount 500 -AlertThreshold 80, 100 -ContactEmail 'team@example.com'
        Should -Invoke Invoke-AzRestMethod -ModuleName AzResourceGroupKit -ParameterFilter { $Method -eq 'PUT' } -Times 1
    }

    It 'is idempotent when amount and thresholds already match' {
        Mock Invoke-AzRestMethod -ModuleName AzResourceGroupKit {
            if ($Method -eq 'GET') {
                return [pscustomobject]@{
                    StatusCode = 200
                    Content    = '{"properties":{"amount":500,"notifications":{"Actual_80":{"threshold":80},"Actual_100":{"threshold":100}}}}'
                }
            }
            throw 'PUT should not be called'
        }

        New-ResourceGroupBudget -ResourceGroupName 'prod-billing-eastus-rg' -SubscriptionId '00000000-0000-0000-0000-000000000000' -Amount 500 -AlertThreshold 80, 100 -ContactEmail 'team@example.com'
        Should -Invoke Invoke-AzRestMethod -ModuleName AzResourceGroupKit -ParameterFilter { $Method -eq 'PUT' } -Times 0
    }

    It 'updates the budget when the amount has changed' {
        Mock Invoke-AzRestMethod -ModuleName AzResourceGroupKit {
            if ($Method -eq 'GET') {
                return [pscustomobject]@{
                    StatusCode = 200
                    Content    = '{"properties":{"amount":300,"notifications":{"Actual_80":{"threshold":80},"Actual_100":{"threshold":100}}}}'
                }
            }
            [pscustomobject]@{ StatusCode = 200; Content = '{"properties":{"amount":500}}' }
        }

        New-ResourceGroupBudget -ResourceGroupName 'prod-billing-eastus-rg' -SubscriptionId '00000000-0000-0000-0000-000000000000' -Amount 500 -AlertThreshold 80, 100 -ContactEmail 'team@example.com'
        Should -Invoke Invoke-AzRestMethod -ModuleName AzResourceGroupKit -ParameterFilter { $Method -eq 'PUT' } -Times 1
    }

    It 'throws when the API returns an error status' {
        Mock Invoke-AzRestMethod -ModuleName AzResourceGroupKit {
            if ($Method -eq 'GET') { return [pscustomobject]@{ StatusCode = 404; Content = '' } }
            [pscustomobject]@{ StatusCode = 400; Content = '{"error":"bad request"}' }
        }

        { New-ResourceGroupBudget -ResourceGroupName 'prod-billing-eastus-rg' -SubscriptionId '00000000-0000-0000-0000-000000000000' -Amount 500 -AlertThreshold 80 -ContactEmail 'team@example.com' } |
            Should -Throw
    }

    It 'makes no PUT call under -WhatIf' {
        New-ResourceGroupBudget -ResourceGroupName 'prod-billing-eastus-rg' -SubscriptionId '00000000-0000-0000-0000-000000000000' -Amount 500 -AlertThreshold 80 -ContactEmail 'team@example.com' -WhatIf
        Should -Invoke Invoke-AzRestMethod -ModuleName AzResourceGroupKit -ParameterFilter { $Method -eq 'PUT' } -Times 0
    }
}

Describe 'Invoke-ResourceGroupBootstrap' {
    It 'composes name, create, lock and budget steps' {
        Mock New-ResourceGroupName -ModuleName AzResourceGroupKit { 'prod-billing-eastus-rg' }
        Mock New-StandardResourceGroup -ModuleName AzResourceGroupKit { [pscustomobject]@{ ResourceGroupName = 'prod-billing-eastus-rg' } }
        Mock Set-ResourceGroupDeleteLock -ModuleName AzResourceGroupKit { [pscustomobject]@{ Name = 'standard-delete-lock' } }
        Mock New-ResourceGroupBudget -ModuleName AzResourceGroupKit { [pscustomobject]@{ properties = @{ amount = 500 } } }

        $result = Invoke-ResourceGroupBootstrap -Environment prod -Application billing -Region eastus -Location eastus `
            -SubscriptionId '00000000-0000-0000-0000-000000000000' -BudgetAmount 500 -AlertThreshold 80, 100 -ContactEmail 'team@example.com'

        $result.Name | Should -Be 'prod-billing-eastus-rg'
        Should -Invoke New-StandardResourceGroup -ModuleName AzResourceGroupKit -Times 1
        Should -Invoke Set-ResourceGroupDeleteLock -ModuleName AzResourceGroupKit -Times 1
        Should -Invoke New-ResourceGroupBudget -ModuleName AzResourceGroupKit -Times 1
    }

    It 'propagates -WhatIf to every step' {
        Mock New-ResourceGroupName -ModuleName AzResourceGroupKit { 'prod-billing-eastus-rg' }
        Mock New-StandardResourceGroup -ModuleName AzResourceGroupKit { }
        Mock Set-ResourceGroupDeleteLock -ModuleName AzResourceGroupKit { }
        Mock New-ResourceGroupBudget -ModuleName AzResourceGroupKit { }

        Invoke-ResourceGroupBootstrap -Environment prod -Application billing -Region eastus -Location eastus `
            -SubscriptionId '00000000-0000-0000-0000-000000000000' -BudgetAmount 500 -AlertThreshold 80 -ContactEmail 'team@example.com' -WhatIf

        Should -Invoke New-StandardResourceGroup -ModuleName AzResourceGroupKit -ParameterFilter { $WhatIf -eq $true } -Times 1
        Should -Invoke Set-ResourceGroupDeleteLock -ModuleName AzResourceGroupKit -ParameterFilter { $WhatIf -eq $true } -Times 1
        Should -Invoke New-ResourceGroupBudget -ModuleName AzResourceGroupKit -ParameterFilter { $WhatIf -eq $true } -Times 1
    }
}

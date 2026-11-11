@{
    RootModule        = 'AzResourceGroupKit.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b3f2a1d4-7c6e-4a2b-9f3d-1e5c6a7b8c9d'
    Author            = 'Code Clinic'
    CompanyName       = 'Unaffiliated'
    Copyright         = '(c) Code Clinic. All rights reserved.'
    Description       = 'Standardized Azure resource group creation with naming, delete locks, and budget alerts.'
    PowerShellVersion = '7.2'
    RequiredModules   = @(
        @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.19.0' },
        @{ ModuleName = 'Az.Resources'; ModuleVersion = '6.16.1' }
    )
    FunctionsToExport = @(
        'New-ResourceGroupName',
        'Test-ResourceGroupName',
        'New-StandardResourceGroup',
        'Set-ResourceGroupDeleteLock',
        'New-ResourceGroupBudget',
        'Invoke-ResourceGroupBootstrap'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Azure', 'ResourceGroup', 'Governance')
            ProjectUri = 'https://example.com'
        }
    }
}

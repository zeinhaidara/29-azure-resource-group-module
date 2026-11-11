function Invoke-ResourceGroupBootstrap {
    <#
    .SYNOPSIS
        Creates a standardized resource group, locks it, and attaches a budget in one call.
    .DESCRIPTION
        Composes New-ResourceGroupName, New-StandardResourceGroup, Set-ResourceGroupDeleteLock
        and New-ResourceGroupBudget. Every step is idempotent on its own, so re-running this
        with the same parameters converges to the same end state rather than erroring or
        duplicating locks/budgets.
    .EXAMPLE
        Invoke-ResourceGroupBootstrap -Environment prod -Application billing -Region eastus `
            -Location eastus -SubscriptionId '00000000-0000-0000-0000-000000000000' `
            -BudgetAmount 500 -AlertThreshold 80,100 -ContactEmail 'team@example.com'
    .NOTES
        This function has no side effects of its own; it only composes calls to the four
        step functions, each of which owns its own idempotency logic. ShouldProcess here
        gates the whole composite action and its result sets $WhatIfPreference for the
        remainder of the call, which is forwarded explicitly to every step below.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('dev', 'test', 'stage', 'prod')]
        [string]$Environment,

        [Parameter(Mandatory)]
        [string]$Application,

        [Parameter(Mandatory)]
        [string]$Region,

        [Parameter(Mandatory)]
        [string]$Location,

        [Parameter(Mandatory)]
        [string]$SubscriptionId,

        [Parameter(Mandatory)]
        [double]$BudgetAmount,

        [Parameter(Mandatory)]
        [int[]]$AlertThreshold,

        [Parameter(Mandatory)]
        [string[]]$ContactEmail,

        [hashtable]$Tag = @{}
    )

    $name = New-ResourceGroupName -Environment $Environment -Application $Application -Region $Region

    $proceed = $PSCmdlet.ShouldProcess($name, 'Bootstrap resource group, lock and budget')
    if (-not $proceed -and -not $WhatIfPreference) {
        # Declined via -Confirm. Under -WhatIf, $WhatIfPreference is already true and we
        # fall through so each step prints its own what-if message.
        return
    }

    $resourceGroup = New-StandardResourceGroup -Name $name -Location $Location -Tag $Tag -WhatIf:$WhatIfPreference
    $lock = Set-ResourceGroupDeleteLock -ResourceGroupName $name -WhatIf:$WhatIfPreference
    $budget = New-ResourceGroupBudget -ResourceGroupName $name -SubscriptionId $SubscriptionId `
        -Amount $BudgetAmount -AlertThreshold $AlertThreshold -ContactEmail $ContactEmail -WhatIf:$WhatIfPreference

    [pscustomobject]@{
        Name          = $name
        ResourceGroup = $resourceGroup
        Lock          = $lock
        Budget        = $budget
    }
}

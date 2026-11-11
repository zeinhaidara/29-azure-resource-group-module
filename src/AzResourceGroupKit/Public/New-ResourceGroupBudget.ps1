function New-ResourceGroupBudget {
    <#
    .SYNOPSIS
        Idempotently creates (or updates) a monthly cost budget scoped to a resource group.
    .DESCRIPTION
        Az.Billing / Az.CostManagement have no clean resource-group-scoped budget cmdlet,
        so this calls the Microsoft.Consumption budgets REST API directly through
        Invoke-AzRestMethod, which is the standard, supported way to reach ARM APIs the
        Az PowerShell modules don't wrap. The budget is a monthly recurring cost budget
        with one notification per alert threshold.
    .EXAMPLE
        New-ResourceGroupBudget -ResourceGroupName 'prod-billing-eastus-rg' -SubscriptionId '00000000-0000-0000-0000-000000000000' -Amount 500 -AlertThreshold 80,100 -ContactEmail 'team@example.com'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [string]$SubscriptionId,

        [Parameter(Mandatory)]
        [ValidateRange(1, [double]::MaxValue)]
        [double]$Amount,

        [Parameter(Mandatory)]
        [int[]]$AlertThreshold,

        [Parameter(Mandatory)]
        [string[]]$ContactEmail,

        [string]$BudgetName = 'standard-monthly-budget'
    )

    Assert-ValidBudgetThreshold -Threshold $AlertThreshold

    $path = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Consumption/budgets/$BudgetName`?api-version=2023-05-01"

    $notifications = @{}
    foreach ($threshold in $AlertThreshold) {
        $notifications["Actual_$threshold"] = @{
            enabled        = $true
            operator       = 'GreaterThan'
            threshold      = $threshold
            contactEmails  = $ContactEmail
            thresholdType  = 'Actual'
        }
    }

    $startOfMonth = (Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0).ToString('yyyy-MM-ddTHH:mm:ssZ')

    $body = @{
        properties = @{
            category    = 'Cost'
            amount      = $Amount
            timeGrain   = 'Monthly'
            timePeriod  = @{ startDate = $startOfMonth }
            notifications = $notifications
        }
    } | ConvertTo-Json -Depth 10

    $existing = Invoke-AzRestMethod -Path $path -Method GET

    if ($existing.StatusCode -eq 200) {
        $current = $existing.Content | ConvertFrom-Json
        $sameAmount = [double]$current.properties.amount -eq $Amount
        $sameThresholds = @(
            Compare-Object -ReferenceObject ($current.properties.notifications.PSObject.Properties.Value.threshold | Sort-Object) `
                -DifferenceObject ($AlertThreshold | Sort-Object)
        ).Count -eq 0

        if ($sameAmount -and $sameThresholds) {
            Write-Verbose "Budget '$BudgetName' on '$ResourceGroupName' already matches desired state."
            return $current
        }
    }

    if ($PSCmdlet.ShouldProcess($ResourceGroupName, "Create/update budget '$BudgetName' ($Amount, thresholds $($AlertThreshold -join ','))")) {
        $result = Invoke-AzRestMethod -Path $path -Method PUT -Payload $body
        if ($result.StatusCode -notin 200, 201) {
            throw "Failed to create budget '$BudgetName' on '$ResourceGroupName': HTTP $($result.StatusCode) $($result.Content)"
        }
        return $result.Content | ConvertFrom-Json
    }
}

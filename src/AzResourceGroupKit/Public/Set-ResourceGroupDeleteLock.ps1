function Set-ResourceGroupDeleteLock {
    <#
    .SYNOPSIS
        Idempotently applies a CanNotDelete management lock to a resource group.
    .DESCRIPTION
        Looks for an existing lock with the same name first. If one is already in
        place with CanNotDelete, nothing is changed. A differently-named lock with
        a different lock level is left alone; this function only manages the single
        lock name it owns.
    .EXAMPLE
        Set-ResourceGroupDeleteLock -ResourceGroupName 'prod-billing-eastus-rg'
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [string]$LockName = 'standard-delete-lock'
    )

    $existingLock = Get-AzResourceLock -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $LockName }

    if ($existingLock) {
        if ($existingLock.Properties.Level -eq 'CanNotDelete') {
            Write-Verbose "Lock '$LockName' already applied to '$ResourceGroupName' as CanNotDelete."
            return $existingLock
        }
        throw "Lock '$LockName' exists on '$ResourceGroupName' with level '$($existingLock.Properties.Level)', not CanNotDelete. Refusing to overwrite."
    }

    if ($PSCmdlet.ShouldProcess($ResourceGroupName, "Apply CanNotDelete lock '$LockName'")) {
        New-AzResourceLock -ResourceGroupName $ResourceGroupName -LockName $LockName -LockLevel CanNotDelete -Force
    }
}

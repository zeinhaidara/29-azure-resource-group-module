function Assert-ValidBudgetThreshold {
    <#
    .SYNOPSIS
        Throws if any alert threshold percentage is outside 1-100.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int[]]$Threshold
    )

    foreach ($value in $Threshold) {
        if ($value -lt 1 -or $value -gt 100) {
            throw "Budget alert threshold '$value' is out of range. Must be between 1 and 100."
        }
    }
}

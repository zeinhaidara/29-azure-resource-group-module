function Get-ResourceGroupNamePattern {
    <#
    .SYNOPSIS
        Returns the compiled naming-convention regex: <env>-<app>-<region>-rg
    .DESCRIPTION
        env   = dev | test | stage | prod
        app   = lowercase alphanumeric, hyphens allowed, 2-30 chars
        region = lowercase alphanumeric Azure region short name (e.g. eastus, westeurope)
        suffix = literal 'rg'
    #>
    '^(dev|test|stage|prod)-[a-z][a-z0-9-]{1,29}-[a-z][a-z0-9]{2,20}-rg$'
}

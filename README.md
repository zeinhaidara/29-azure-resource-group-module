# Azure resource group PowerShell module

A small PowerShell module that standardizes how resource groups get created in
Azure: a fixed naming convention, a mandatory delete lock, and a monthly cost
budget with alert thresholds, all in one idempotent call.

## Problem

> Build a reusable PowerShell or Python module for Azure that automates the
> creation of Resource Groups with consistent naming, locking, and budget
> alerts.

Teams tend to create resource groups ad hoc: inconsistent names, no delete
protection, no cost visibility until the bill arrives. This module wraps the
three steps (name, create, lock, budget) behind one function so every
resource group a team creates looks the same and has the same guardrails.

## Scope

- PowerShell only, built against **PowerShell 7.2+** and the `Az.Accounts` /
  `Az.Resources` modules. Windows PowerShell 5.1 is not supported (the module
  manifest declares `PowerShellVersion = '7.2'`).
- One real cloud concept implemented per step: naming, resource group
  creation, a `CanNotDelete` management lock, and a `Microsoft.Consumption`
  budget. There is no drift-detection, no deletion of resource groups, and no
  support for policy assignments or RBAC.
- The budget is created through `Invoke-AzRestMethod` against the
  `Microsoft.Consumption/budgets` REST API directly, because neither
  `Az.Billing` nor `Az.CostManagement` exposes a clean resource-group-scoped
  budget cmdlet. This is the standard, supported way to reach an ARM API the
  Az modules don't wrap.

## Naming convention

```
<environment>-<application>-<region>-rg
```

- `environment` is one of `dev`, `test`, `stage`, `prod`.
- `application` is lowercase letters/digits/hyphens, 2-30 characters.
- `region` is a lowercase Azure region short name with no hyphens (e.g.
  `eastus`, `westeurope`).
- The literal suffix is always `-rg`.

Example: `prod-billing-eastus-rg`. `New-ResourceGroupName` builds a
conforming name from parts; `Test-ResourceGroupName` validates an arbitrary
string against the same pattern.

## Flow

```mermaid
flowchart TD
    A[New-ResourceGroupName] --> B[New-StandardResourceGroup]
    B --> C{Resource group\nexists already?}
    C -- no --> D[Create resource group]
    C -- yes, same location --> E[Merge tags]
    C -- yes, different location --> F[Throw: conflict]
    D --> G[Set-ResourceGroupDeleteLock]
    E --> G
    G --> H{CanNotDelete lock\nalready present?}
    H -- no --> I[Create lock]
    H -- yes --> J[Leave as-is]
    H -- yes, different level --> K[Throw: refuse to overwrite]
    I --> L[New-ResourceGroupBudget]
    J --> L
    L --> M{Budget exists with\nsame amount/thresholds?}
    M -- no --> N[PUT budget via Invoke-AzRestMethod]
    M -- yes --> O[Leave as-is]
```

`Invoke-ResourceGroupBootstrap` runs all four steps in order and returns the
resulting resource group, lock, and budget objects.

## Usage

```powershell
Import-Module ./src/AzResourceGroupKit/AzResourceGroupKit.psd1

Invoke-ResourceGroupBootstrap `
    -Environment prod -Application billing -Region eastus `
    -Location eastus `
    -SubscriptionId '00000000-0000-0000-0000-000000000000' `
    -BudgetAmount 500 -AlertThreshold 80,100 `
    -ContactEmail 'team@example.com'

# Preview changes without calling Azure
Invoke-ResourceGroupBootstrap -Environment prod -Application billing -Region eastus `
    -Location eastus -SubscriptionId '00000000-0000-0000-0000-000000000000' `
    -BudgetAmount 500 -AlertThreshold 80,100 -ContactEmail 'team@example.com' -WhatIf
```

Each step function (`New-StandardResourceGroup`, `Set-ResourceGroupDeleteLock`,
`New-ResourceGroupBudget`) can also be called on its own and supports
`-WhatIf`.

## Idempotency

- **Resource group**: if a group with the target name already exists in the
  same location, its tags are merged (not replaced) instead of calling
  `New-AzResourceGroup` again. If it exists in a *different* location this is
  treated as a conflict and the function throws, rather than silently
  continuing against the wrong resource group.
- **Lock**: the module only manages a single named lock
  (`standard-delete-lock` by default). If that lock already exists as
  `CanNotDelete`, nothing changes. If it exists with a different level, the
  function throws instead of overwriting it.
- **Budget**: the current budget is read first; if the amount and the full
  set of alert thresholds already match, no `PUT` is issued.

## Lookup errors

Both lookups fail loudly instead of guessing:

- **Resource group:** `Get-AzResourceGroup -Name` runs with
  `-ErrorAction Stop` inside `try`/`catch`. Only the not-found error counts
  as "absent" and leads to `New-AzResourceGroup`; any other error (sign-in,
  network, throttling, a permission error that surfaces differently) is
  rethrown, and nothing is created or updated.
- **Lock:** `Get-AzResourceLock` runs with `-ErrorAction Stop`. A group with
  no locks returns an empty list, which needs no error suppression, so any
  error from the lookup is a real failure and stops the function before
  `New-AzResourceLock` is considered.

**What "not found" looks like, and what this relies on.** The Az.Resources
docs page for `Get-AzResourceGroup` (azps-17.0.0) doesn't say how a missing
group is reported. The module's source in `Azure/azure-powershell` does: the
get-by-name path catches the REST client's `CloudException` and writes a
non-terminating error with the message **"Provided resource group does not
exist."** (resource `ResourceGroupDoesntExists`), prefixed with a timestamp.
That is the same in the `v11.6.0-April2024` release (Az.Resources 6.16.x,
next to the 6.16.1 pinned in CI) and on `main`, and Az's own scenario tests
match it as `*Provided resource group does not exist.`. This module matches
`*Provided resource group does not exist*`.

Caveat from the same source: the cmdlet maps **any** `CloudException` from
that get call to the same message, so a permission error on reading that
specific group can be reported as "does not exist". In that case the module
goes on to `New-AzResourceGroup`, which fails with its own authorization
error, so it still fails loudly, just one step later. Errors that aren't
`CloudException` (not signed in, network, token problems) are rethrown at
the lookup.

## Security notes

- No credentials are stored or required to run the tests — every Az cmdlet
  used by the module is mocked in Pester. Running the module for real still
  requires a normal `Connect-AzAccount` session with the Az PowerShell
  modules, same as any other Az script.
- The least-privilege Azure RBAC actions needed to run this for real:
  `Microsoft.Resources/subscriptions/resourceGroups/read` (the lookup),
  `Microsoft.Resources/subscriptions/resourceGroups/write`,
  `Microsoft.Authorization/locks/write`, `Microsoft.Authorization/locks/read`,
  and `Microsoft.Consumption/budgets/write` (and `/read`) scoped to the
  target resource group/subscription.
- All subscription IDs and emails in this repository are placeholders
  (`00000000-0000-0000-0000-000000000000`, `team@example.com`). No real
  tenant, subscription, or credential is referenced anywhere.

## Validation level

**This module has never been run against a real Azure subscription.** Every
test mocks the underlying `Az.Resources` / `Invoke-AzRestMethod` calls with
Pester's `Mock`; no network call, authentication, or live Azure API response
has ever been exercised. That means:

- Tested: naming-convention generation and validation (including negative
  cases), idempotency and conflict handling for the resource group, lock,
  and budget steps, `-WhatIf` making zero mocked calls at every level, input
  validation (invalid environment, invalid threshold range), and lookup
  errors with mocked Az cmdlets: a not-found error still creates the group,
  while a permission error from either lookup makes the function throw and
  `New-AzResourceGroup` / `New-AzResourceLock` are never called.
- Not tested: actual Azure API behavior, and whether real permission errors
  look like the mocked ones (the mocks use the not-found message read from
  the Az source and an `AuthorizationFailed` message; see "Lookup errors" for
  how a real 403 on the group can be reported as not-found), API
  throttling, the real shape of `Invoke-AzRestMethod` responses beyond what
  this module's tests assume, and any Az module version skew.
- Linted with PSScriptAnalyzer (1.22.0); 0 findings.

Treat this as a reviewed design, not a battle-tested tool — validate against
a real (non-production) subscription before using it anywhere that matters.

## Running locally

```powershell
Install-Module Pester -RequiredVersion 5.6.1 -Scope CurrentUser
Install-Module PSScriptAnalyzer -RequiredVersion 1.22.0 -Scope CurrentUser
Install-Module Az.Accounts -RequiredVersion 2.19.0 -Scope CurrentUser
Install-Module Az.Resources -RequiredVersion 6.16.1 -Scope CurrentUser

Invoke-ScriptAnalyzer -Path ./src -Recurse -Severity Warning,Error
Invoke-Pester -Path ./tests/AzResourceGroupKit.Tests.ps1
```

Requires PowerShell 7.2+ (`pwsh`), not Windows PowerShell 5.1.

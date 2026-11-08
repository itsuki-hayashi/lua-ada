param(
    [Parameter(Mandatory)][string] $RepositoryRoot,
    [Parameter(Mandatory)][string] $Executable,
    [Parameter(Mandatory)][string] $ExecutableSha256,
    [Parameter(Mandatory)][string] $ReceiptPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AUnitLaunch.psm1') -Force
# Invoked only after alr exec has selected tests/alire.toml. The child process
# inherits that environment and runs with repository-relative fixture paths.
$receipt=Invoke-AUnitContextProcess -RepositoryRoot $RepositoryRoot -Executable $Executable `
    -ExecutableSha256 $ExecutableSha256 -ReceiptPath $ReceiptPath
if (-not $receipt.completed) { throw 'AUnit child timed out' }
exit $receipt.exit_code

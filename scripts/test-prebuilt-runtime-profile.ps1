param(
    [ValidateSet('static', 'static-pic', 'relocatable')]
    [string] $LibraryType = 'static',
    [ValidateSet('development', 'validation', 'release')]
    [string] $Profile = 'validation',
    [ValidateSet('default', 'upstream-test')]
    [string] $Configuration = 'upstream-test'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$savedLocation = Get-Location
$configurationPart = if ($Configuration -eq 'default') { '' } else { 'upstream-test/' }
$directory = Join-Path $root "lib/$configurationPart$Profile/$LibraryType"
$imageName = if ($LibraryType -ne 'relocatable') { 'liblua.a' }
    elseif ($IsWindows) { 'liblua.dll' } elseif ($IsMacOS) { 'liblua.dylib' } else { 'liblua.so' }
$image = Join-Path $directory $imageName
$receiptDirectory = Join-Path $root ('reports/instrumented/prebuilt-profile/' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($receiptDirectory)
$setupProfile = if ($Profile -eq 'development') { 'validation' } else { 'development' }
$before = ''
$setup = $null
$after = $null
$completed = $false
$failure = $null

function Get-RootProfile {
    # Generated files are observations, never edited inputs. Verify both the
    # generated GPR used by consumers and the root's independently remembered
    # profile: a pinned dependency's test-crate setting cannot establish this.
    $gpr = [IO.File]::ReadAllText((Join-Path $root 'config/lua_ada_config.gpr'))
    $generated = [regex]::Matches($gpr,
        '(?m)^\s*Build_Profile\s*:\s*Build_Profile_Kind\s*:=\s*"([a-z]+)";\s*$')
    $settings = [IO.File]::ReadAllText((Join-Path $root 'alire/settings.toml'))
    $remembered = [regex]::Matches($settings, '(?m)^last_build_profile\s*=\s*"([^"]*)"\s*$')
    if ($generated.Count -ne 1 -or $remembered.Count -ne 1) {
        throw 'Cannot observe the generated and remembered root profiles'
    }
    $rootProfile = @($remembered[0].Groups[1].Value.Split(',') | Where-Object { $_ -match '^lua_ada=' })
    if ($rootProfile.Count -ne 1) { throw 'Remembered root profile is absent or ambiguous' }
    return [ordered]@{
        generated = $generated[0].Groups[1].Value
        remembered = $rootProfile[0].Substring('lua_ada='.Length).ToLowerInvariant()
    }
}

try {
    Set-Location $root
    # The runtime must exist before this regression. Both profile transitions
    # stop at generation, and the core-image driver imports the same SAL as
    # externally built. Only the real consumers run, exactly once.
    $before = (Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash.ToLowerInvariant()
    & alr -n build "--$setupProfile" --stop-after=generation
    if ($LASTEXITCODE -ne 0) { throw 'Cannot select the deliberately wrong root profile' }
    $setup = Get-RootProfile
    if ($setup.generated -cne $setupProfile -or $setup.remembered -cne $setupProfile) {
        throw 'Wrong-profile precondition was not established'
    }
    if ((Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash.ToLowerInvariant() -cne $before) {
        throw 'Wrong-profile generation changed the prebuilt runtime image'
    }
    Write-Output "PROFILE REGRESSION: root remembers $setupProfile; requested prebuilt image uses $Profile"
    & "$PSScriptRoot/check-core-image.ps1" -Profile $Profile -LibraryType $LibraryType `
        -Configuration $Configuration -UseExistingRuntime
    if ($LASTEXITCODE -ne 0) { throw 'Prebuilt profile consumer campaign failed' }
    $after = Get-RootProfile
    if ($after.generated -cne $Profile -or $after.remembered -cne $Profile) {
        throw 'Prebuilt consumers did not restore the requested root profile'
    }
    if ((Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash.ToLowerInvariant() -cne $before) {
        throw 'Prebuilt profile regression changed the runtime image'
    }
    $completed = $true
    Write-Output "PASS: prebuilt $Configuration/$Profile/$LibraryType consumers recover from remembered $setupProfile without rebuilding the runtime"
} catch {
    $failure = $_.Exception.Message
    throw
} finally {
    # Keep this receipt outside core-image/: one actual consumer run must
    # remain one matrix context, not an extra synthetic consumer report.
    $afterHash = if (Test-Path -LiteralPath $image -PathType Leaf) {
        (Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash.ToLowerInvariant()
    } else { $null }
    [ordered]@{ schema_version = 1; kind = 'real-prebuilt-runtime-profile-regression';
        configuration = $Configuration; profile = $Profile; library_type = $LibraryType;
        setup_profile = $setupProfile; setup_observation = $setup; final_observation = $after;
        image = $image; before_sha256 = $before; after_sha256 = $afterHash;
        completed = $completed; failure = $failure; runtime_build_requested = $false;
        runtime_image_unchanged = ($before -cne '' -and $before -ceq $afterHash);
        scoped_acceptance = $false; full_m3_acceptance = $false } | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $receiptDirectory 'result.json') -Encoding utf8
    Set-Location $savedLocation
}

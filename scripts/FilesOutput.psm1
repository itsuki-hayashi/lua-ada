function Convert-MacFilesError {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)
    # Only the PID is nondeterministic. Keep command, signal, whitespace and
    # ordering intact, and reject any output outside the measured shell cases.
    $signalPattern = "(?m)^(sh: line 1: )[1-9][0-9]*( Hangup: 1 +sh -c 'kill -s HUP \`$\`$')$"
    $missing = 'sh: not-to-be-found-command: command not found'
    $lines = @($Text.Split("`n", [StringSplitOptions]::RemoveEmptyEntries))
    $signals = 0
    $commands = 0
    foreach ($line in $lines) {
        if ($line -cmatch $signalPattern) { $signals++ }
        elseif ($line -ceq $missing) { $commands++ }
        else { throw "Unexpected macOS files stderr: $line" }
    }
    if ($signals -ne 6 -or $commands -ne 4) {
        throw 'Incomplete macOS files shell diagnostics'
    }
    return [regex]::Replace($Text, $signalPattern, '${1}[pid]${2}')
}
Export-ModuleMember -Function Convert-MacFilesError

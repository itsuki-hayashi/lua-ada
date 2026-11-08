$ErrorActionPreference='Stop'
$root=$PWD.Path;$utf8=[Text.UTF8Encoding]::new($false)
function Hash([string]$path){(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()}
function Relative([string]$path){[IO.Path]::GetRelativePath($root,$path).Replace('\','/')}
$paths=@(
 'reports/cli-msghandler/346457279dd348848b95b0c6dd38c977/index.json',
 'reports/cli-msghandler-handler-refusal/fb10d07d6cfb4802b37d2935febc390c/index.json',
 'reports/cli-msghandler-fixture/8b34d39c9ec64e5eb48c34f0a88f1dc6/index.json',
 'reports/cli-msghandler-print/793a163077b3400e8048ccd3e123ef90/index.json',
 'reports/cli-msghandler-hooks/91a4c87d4c5441f8a5b84693e72e769d/index.json',
 'reports/cli-main-prefix/9dc6874d714a487fa0ba655e6beed3d6/index.json')
$groups=@();$count=0;$balanced=0
foreach($path in $paths){
 $data=Get-Content $path -Raw|ConvertFrom-Json -AsHashtable
 $raws=if($data -is [array]){$data}elseif($data.ContainsKey('records')){$data.records}else{@($data)}
 $rows=@()
 foreach($r in $raws){
  $p=$r.process;$cfg=$r.configuration
  if($p.timed_out -or $p.capture_exceeded -or $p.pipe_drain_failed -or $p.output_drain_failed -or $p.input_write_failed -or $p.process_tree_kill_error -or $p.abnormal_exit_kind){throw 'Actual process capture failure'}
  if((Hash $p.stdout_path) -cne $p.stdout_sha256 -or (Hash $p.stderr_path) -cne $p.stderr_sha256){throw 'Raw stream hash drift'}
  $case=if($r.ContainsKey('case')){$r.case}elseif($r.ContainsKey('mode')){'persistent-main-prefix-'+$r.mode}elseif($path -like '*cli-msghandler-hooks*'){'persistent-main-hook-events'}elseif($r.ContainsKey('setup')){'print-table-repl'}else{'entered-handler-memory'}
  $t=if($r.ContainsKey('telemetry')){$r.telemetry}elseif($r.ContainsKey('sidecar')){$r.sidecar}else{$null}
  $cleanup='not measured: typed exit bypasses launcher finish'
  if($null -ne $t){
   if($t.run_id -cne $r.run_id -or $t.process_id -ne $p.process_id -or $t.configuration -cne $cfg -or $t.allocator_limit_bytes -ne 2147483648 -or $t.outstanding_bytes -ne 0 -or $t.outstanding_blocks -ne 0){throw 'Actual provider/PID/run/config mismatch'}
   $cleanup='actual zero outstanding selected bytes and blocks';$balanced++
  }elseif($case -notin @('exit-close','exit-no-close')){throw 'Missing non-exit allocator sidecar'}
  $defect=$cfg -ceq 'upstream-test' -and $case -ceq 'exit-no-close'
  $rows+=[ordered]@{case=$case;configuration=$cfg;process_id=$p.process_id;run_id=$r.run_id;arguments=$p.arguments;exit_code=$p.exit_code;timeout_seconds=$p.timeout_seconds;elapsed_milliseconds=$p.elapsed_milliseconds;source=$(if($r.ContainsKey('source_path')){[ordered]@{path=(Relative $r.source_path);sha256=$r.source_sha256}}elseif($r.ContainsKey('source')){[ordered]@{path=(Relative $r.source);sha256=$r.source_sha256}}else{$null});stdout=[ordered]@{path=(Relative $p.stdout_path);sha256=$p.stdout_sha256;bytes=$p.stdout_bytes};stderr=[ordered]@{path=(Relative $p.stderr_path);sha256=$p.stderr_sha256;bytes=$p.stderr_bytes};telemetry=$t;cleanup_evidence=$cleanup;native_oracle_cleanup_failed=$defect;runtime_acceptance=$false}
  $count++
 }
 $groups+=[ordered]@{raw_index=$path;raw_index_sha256=(Hash $path);records=$rows}
}
$initial=Get-Content $paths[0] -Raw|ConvertFrom-Json -AsHashtable
$images=@($initial.images|ForEach-Object{[ordered]@{configuration=$_.configuration;source=$_.source;path=(Relative $_.path);sha256=$_.sha256}})
$sources=@('references/lua/lua.c','references/lua/lauxlib.c','references/lua/lapi.c','references/lua/ldo.c','tests/lua/cli_message_handler_controls.lua')|ForEach-Object{[ordered]@{path=$_;sha256=(Hash $_)}}
$output=[ordered]@{schema_version=1;kind='cli-message-handler-native-author-observation';author='Codex /root/remaining_suite';date='2026-11-08';source_head=(&git rev-parse HEAD).Trim();reference_revision='7579fc9d7ed90240487251dfb69168f8e64e9294';platform='windows-x86_64';images=$images;source_counterparts=$sources;process_count=$count;actual_balanced_nonexit_sidecars=$balanced;groups=$groups;facts=@('String/number original errors convert before metamethod lookup.','Only an actual string returned by raw/callable __tostring bypasses traceback.','Primitive fallback ignores __name and uses actual arg1 after callback debug.setlocal mutation.','Handler callback observes one anonymous C parent, original C argument and non-yieldability.','Compilation and argument lookup/length precede handler installation.','Handler-entered permanent refusal reports canonical memory failure without traceback.','Nonstring REPL print error reports error calling print with (null), without __tostring.');limits=@('Native observations only: no Ada execution, runtime acceptance, source adaptation, exclusion or whole-main completion.','Native T os.exit(false) retains actual atexit allocator assertion; no cleanup pass. Both exit forms have no finish sidecar, so exit cleanup is unmeasured.','Cold numeric error under refusal does not certify exact handler-entry timing.','All primary ordinary cases use900seconds/2GiB; no-close exit uses an explicitly secondary5second watchdog.','No terminal, Unix or signal behavior is measured here.');runtime_acceptance=$false;coverage_authority=$false;source_adaptation_authority=$false}
$dest='tests/conformance/targets/remaining-upstream-compatibility/cli-message-handler.native.author-observation.json'
[IO.File]::WriteAllText($dest,($output|ConvertTo-Json -Depth 40).Replace("`r`n","`n")+"`n",$utf8)
Write-Host ('processes='+$count+' measured_balanced='+$balanced);Get-FileHash $dest
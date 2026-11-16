<?php
// a directive php removed, set to a nonzero number, fails the startup with
// an E_CORE_ERROR and exit status 1; zero or another directive runs
$base = escapeshellarg(PHP_BINARY) . ' -n -d display_errors=1 -d log_errors=0 -d fatal_error_backtraces=0';
foreach (['magic_quotes_gpc=1', 'safe_mode=On', 'track_errors=2', 'register_globals=0', 'asp_tags=off'] as $setting) {
    $out = [];
    exec("$base -d $setting -r " . escapeshellarg('echo 7;') . ' 2>&1', $out, $status);
    echo $setting, ": ", trim(implode("\n", $out)), " (", $status, ")\n";
}

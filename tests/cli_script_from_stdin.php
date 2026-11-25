<?php
// php run with options and no script reads the script from stdin ("Standard
// input code"); `--` passes arguments to it; -r code has no script file
$code = '<?php var_dump(__FILE__, $argv, $_SERVER["SCRIPT_FILENAME"], $_SERVER["SCRIPT_NAME"], $_SERVER["PATH_TRANSLATED"], __DIR__ === getcwd()); echo strtoupper(fgets(STDIN) ?: "eof"), "\n";';
foreach ([' -n', ' -n -- a b', ' -d display_errors=1'] as $flags) {
    $proc = proc_open(escapeshellarg(PHP_BINARY) . $flags, [0 => ['pipe', 'r'], 1 => ['pipe', 'w']], $pipes);
    fwrite($pipes[0], $code);
    fclose($pipes[0]);
    echo stream_get_contents($pipes[1]);
    fclose($pipes[1]);
    var_dump(proc_close($proc));
}
echo shell_exec(escapeshellarg(PHP_BINARY) . ' -n -r ' . escapeshellarg('var_dump($_SERVER["SCRIPT_FILENAME"], $_SERVER["PATH_TRANSLATED"], $_SERVER["PHP_SELF"]);'));

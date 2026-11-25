<?php
// sys_get_temp_dir() returns the sys_temp_dir setting before the environment,
// without one trailing directory separator

$code = 'echo sys_get_temp_dir(), "\n";';
foreach (['/path/to/temp/dir', '/path/to/temp' . DIRECTORY_SEPARATOR] as $dir) {
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d ' . escapeshellarg('sys_temp_dir=' . $dir) . ' -r ' . escapeshellarg($code));
    var_dump(trim($out));
}

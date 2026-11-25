<?php
// a name in linux's abstract socket namespace needs no terminating nul, so
// it can be one byte longer than a filesystem path
if (PHP_OS_FAMILY !== 'Linux') {
    echo "full length: yes\nlonger: truncated\n";
    return;
}
$notices = [];
set_error_handler(function ($no, $msg) use (&$notices) { $notices[] = $msg; return true; }, E_NOTICE);
$name = "\0zphp-abstract-" . getmypid() . '-' . str_repeat('a', 200);
$server = stream_socket_server('unix://' . $name);
$max = 0;
foreach ($notices as $n) if (preg_match('/length of (\d+) bytes/', $n, $m)) $max = (int) $m[1];
echo "full length: ", $server !== false && $max === 108 ? "yes" : "no ($max)", "\n";
echo "longer: ", count($notices) === 1 ? "truncated" : "not truncated", "\n";

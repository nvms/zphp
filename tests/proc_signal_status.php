<?php
// a child killed by a signal has no exit code: proc_get_status reports -1
// with the signal, and proc_close returns the raw wait status
$p = proc_open(['sleep', '5'], [], $pipes);
proc_terminate($p);
do { usleep(20000); $s = proc_get_status($p); } while ($s['running']);
var_dump($s['signaled'], $s['termsig'], $s['exitcode']);
var_dump(proc_close($p));

$p = proc_open(['sleep', '5'], [], $pipes);
proc_terminate($p, 9);
var_dump(proc_close($p));

$p = proc_open(['sh', '-c', 'exit 3'], [], $pipes);
do { usleep(20000); $s = proc_get_status($p); } while ($s['running']);
var_dump($s['signaled'], $s['exitcode'], proc_close($p));

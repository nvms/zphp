<?php
// a script whose output reader goes away ends as php's aborted connection:
// no error message, exit status 255
$p = proc_open([PHP_BINARY, '-r', 'usleep(200000); echo str_repeat("x", 300000);'], [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
fclose($pipes[1]);
$err = stream_get_contents($pipes[2]);
fclose($pipes[2]);
var_dump(proc_close($p), $err);

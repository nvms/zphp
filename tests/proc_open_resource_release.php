<?php
// a process resource nothing references closes its pipes, as php's resource
// destructor does; the pipes don't keep the process alive
$proc = proc_open(['sh', '-c', 'echo hello; sleep 0.2'], [1 => ['pipe', 'w']], $pipes);
var_dump($pipes);
var_dump(fgets($pipes[1]));
unset($proc);
var_dump($pipes);
try {
    fgets($pipes[1]);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
proc_open(['true'], [3 => ['pipe', 'w'], 4 => ['pipe', 'r']], $pipes);
var_dump($pipes);
$proc = proc_open(['sh', '-c', 'exit 3'], [1 => ['pipe', 'w']], $pipes);
fclose($pipes[1]);
var_dump(proc_close($proc));

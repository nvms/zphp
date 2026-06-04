<?php

// proc_open spawns the child at open time (like php). stdin is fed through the
// pipe, stdout/stderr are captured, the exit code is real, and proc_get_status
// reports a real pid. these are version/platform-stable shell behaviors.

// stdin -> child -> stdout roundtrip
$desc = [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
$proc = proc_open('cat', $desc, $pipes);
fwrite($pipes[0], "hello from stdin");
fclose($pipes[0]);
echo "cat stdout: ", stream_get_contents($pipes[1]), "\n"; // hello from stdin
fclose($pipes[1]);
fclose($pipes[2]);
echo "cat exit: ", proc_close($proc), "\n"; // 0

// real pid (> 0) reported by proc_get_status
$p2 = proc_open('exit 3', [], $pipes2);
$st = proc_get_status($p2);
echo "pid positive: ", ($st['pid'] > 0 ? 'y' : 'n'), "\n"; // y
echo "command: ", $st['command'], "\n"; // exit 3
echo "exit3 close: ", proc_close($p2), "\n"; // 3

// stderr capture
$p3 = proc_open('echo oops 1>&2', [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes3);
echo "stderr: ", trim(stream_get_contents($pipes3[2])), "\n"; // oops
fclose($pipes3[1]);
fclose($pipes3[2]);
proc_close($p3);

// nonzero exit propagates
$p4 = proc_open('exit 42', [], $pipes4);
echo "exit42: ", proc_close($p4), "\n"; // 42

// a proc opened and never closed must not crash or leak (reaped at shutdown)
$p5 = proc_open('sleep 30', [], $pipes5);
echo "opened long-runner: ", ($p5 !== false ? 'y' : 'n'), "\n"; // y

echo "done\n";

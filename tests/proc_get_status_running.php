<?php

// proc_get_status reports real liveness: running is true while the child is
// alive and flips to false once it exits, with the real exit code captured.

$proc = proc_open('sleep 1; exit 5', [], $pipes);

$st = proc_get_status($proc);
echo "while alive: running=", ($st['running'] ? 'y' : 'n'), " exitcode=", $st['exitcode'], "\n"; // y -1

// wait for it to finish, polling without blocking proc_close
$tries = 0;
while ($tries < 200) {
    $st = proc_get_status($proc);
    if (!$st['running']) {
        break;
    }
    usleep(50000);
    $tries++;
}

echo "after exit: running=", ($st['running'] ? 'y' : 'n'), " exitcode=", $st['exitcode'], " signaled=", ($st['signaled'] ? 'y' : 'n'), "\n"; // n 5 n

// proc_close returns the same exit code even though status already reaped it
echo "close: ", proc_close($proc), "\n"; // 5

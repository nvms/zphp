<?php

// the payoff of live proc pipe fds: stream_select can wait on a child's stdout
// and read it incrementally, instead of the whole output materializing at once.
// a shell that emits a line, then sleeps, then emits another exercises real
// readiness transitions on the live fd.

$desc = [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
$proc = proc_open('printf "first\n"; sleep 1; printf "second\n"', $desc, $pipes);
fclose($pipes[0]);
stream_set_blocking($pipes[1], false);

$chunks = [];
while (true) {
    $read = [$pipes[1]];
    $w = null;
    $e = null;
    // block up to 3s waiting for the next chunk or EOF
    $n = stream_select($read, $w, $e, 3);
    if ($n === false) {
        break;
    }
    if ($n === 0) {
        echo "timeout\n";
        break;
    }
    $data = fread($pipes[1], 8192);
    if ($data === '' || $data === false) {
        // readable + empty == EOF (child closed stdout)
        break;
    }
    $chunks[] = trim($data);
}

fclose($pipes[1]);
fclose($pipes[2]);
$exit = proc_close($proc);

// both lines arrived, in order, across two readiness events
echo "lines: ", implode(',', array_filter($chunks)), "\n";
echo "exit: ", $exit, "\n";

<?php
// proc_open reads its descriptor spec as php does: bad entries are
// ValueErrors or warnings that start nothing, null and redirect descriptors
// work, and an argument array is checked element by element
set_error_handler(function ($no, $msg) { echo "warning: ", $msg, "\n"; return true; });
function attempt(callable $f) {
    try {
        var_dump($f());
    } catch (ValueError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
$pipes = 'untouched';
attempt(fn() => proc_open('true', [1 => ['pi']], $pipes));
attempt(fn() => proc_open('true', [1 => 1], $pipes));
attempt(fn() => proc_open('true', ['a' => ['pipe', 'w']], $pipes));
attempt(fn() => proc_open('true', [1 => []], $pipes));
attempt(fn() => proc_open('true', [1 => ['pipe']], $pipes));
attempt(fn() => proc_open('true', [1 => ['file']], $pipes));
attempt(fn() => proc_open('true', [1 => ['file', '/nonexistent/dir/x']], $pipes));
attempt(fn() => proc_open('true', [1 => ['file', '/nonexistent/dir/x', 'w']], $pipes));
attempt(fn() => proc_open('true', [1 => ['redirect']], $pipes));
attempt(fn() => proc_open('true', [1 => ['redirect', '2']], $pipes));
attempt(fn() => proc_open('true', [1 => ['redirect', 42]], $pipes));
attempt(fn() => proc_open([], [], $pipes));
attempt(fn() => proc_open([''], [], $pipes));
attempt(fn() => proc_open(["sh\0x"], [], $pipes));
attempt(fn() => proc_open(['sh', "a\0b"], [], $pipes));
var_dump($pipes);

$proc = proc_open(['sh', '-c', 'echo out; echo err >&2'], [1 => ['null'], 2 => ['pipe', 'w']], $pipes);
var_dump(array_keys($pipes), stream_get_contents($pipes[2]));
proc_close($proc);
$proc = proc_open(['sh', '-c', 'echo out; echo err >&2'], [1 => ['pipe', 'w'], 2 => ['redirect', 1]], $pipes);
var_dump(array_keys($pipes), stream_get_contents($pipes[1]));
proc_close($proc);
// a mode other than one starting with "w" is the child's to read
$proc = proc_open(['cat'], [0 => ['pipe', 'x'], 1 => ['pipe', 'w']], $pipes);
fwrite($pipes[0], "fed\n");
fclose($pipes[0]);
var_dump(stream_get_contents($pipes[1]));
proc_close($proc);

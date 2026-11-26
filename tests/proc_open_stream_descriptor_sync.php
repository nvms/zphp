<?php
// a file stream handed to proc_open as a descriptor syncs its buffer first:
// the child reads on from the stream's position, not from where the read
// ahead left the descriptor
$f = tempnam(sys_get_temp_dir(), 'c');
file_put_contents($f, "one\ntwo\nthree\n");
$h = fopen($f, 'r');
var_dump(fgets($h));
$p = proc_open('cat', [0 => $h, 1 => ['pipe', 'w']], $pipes);
var_dump(stream_get_contents($pipes[1]));
proc_close($p);
var_dump(ftell($h), fgets($h));

$h = fopen($f, 'r');
fseek($h, 4);
var_dump(fread($h, 2));
$p = proc_open('cat', [0 => $h, 1 => ['pipe', 'w']], $pipes);
var_dump(stream_get_contents($pipes[1]));
proc_close($p);

$w = fopen($f, 'w');
fwrite($w, "written\n");
$p = proc_open('cat ' . escapeshellarg($f), [1 => ['pipe', 'w']], $pipes);
var_dump(stream_get_contents($pipes[1]));
proc_close($p);
$p = proc_open('echo child', [1 => $w], $pipes);
proc_close($p);
fclose($w);
var_dump(file_get_contents($f));
unlink($f);

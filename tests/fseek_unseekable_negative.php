<?php
// a pipe cannot seek, and seeking a file before its start fails
$pipes = [];
$proc = proc_open("cat", [0 => ["pipe", "r"], 1 => ["pipe", "w"]], $pipes);
var_dump(fseek($pipes[1], 10), rewind($pipes[1]));
fclose($pipes[0]);
fclose($pipes[1]);
proc_close($proc);

$file = sys_get_temp_dir() . "/zphp_seek_" . getmypid();
file_put_contents($file, "0123456789");
$fp = fopen($file, "r");
fseek($fp, 4);
var_dump(fseek($fp, -5), ftell($fp), fseek($fp, -2, SEEK_END), fread($fp, 5));
fclose($fp);
unlink($file);

<?php
// a pipe cannot seek, linux's memory devices can, and seeking a file before
// its start fails
$pipes = [];
$proc = proc_open("cat", [0 => ["pipe", "r"], 1 => ["pipe", "w"]], $pipes);
var_dump(fseek($pipes[1], 10), rewind($pipes[1]));
fclose($pipes[0]);
fclose($pipes[1]);
proc_close($proc);

foreach (["/dev/null", "/dev/zero"] as $device) {
    $fp = fopen($device, "rb");
    var_dump(fseek($fp, 1024 * 1024), stream_get_meta_data($fp)['seekable']);
    fclose($fp);
}

$file = sys_get_temp_dir() . "/zphp_seek_" . getmypid();
file_put_contents($file, "0123456789");
$fp = fopen($file, "r");
fseek($fp, 4);
var_dump(fseek($fp, -5), ftell($fp), fseek($fp, -2, SEEK_END), fread($fp, 5));
fclose($fp);
unlink($file);

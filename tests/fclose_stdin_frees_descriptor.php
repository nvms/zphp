<?php
// fclose(STDIN) closes descriptor 0 in php's cli, so the next file opened
// takes descriptor 0 and php://stdin reads that file

$file = sys_get_temp_dir() . '/zphp_fclose_stdin_' . getmypid() . '.txt';
file_put_contents($file, "from the file\n");
$code = 'fclose(STDIN); $f = fopen(' . var_export($file, true) . ', "r"); echo fgets(fopen("php://stdin", "r"));';
$proc = proc_open([PHP_BINARY, '-n', '-r', $code], [0 => ['pipe', 'r'], 1 => ['pipe', 'w']], $pipes);
fwrite($pipes[0], "from the pipe\n");
fclose($pipes[0]);
echo stream_get_contents($pipes[1]);
fclose($pipes[1]);
var_dump(proc_close($proc));
unlink($file);

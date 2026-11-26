<?php
// every "pty" descriptor is an end of one pseudoterminal: what the child
// writes to its stdout is read from any of the parent's pty streams
$cmd = '(echo "out"; echo "err" >&2; exit 5) 3>/dev/null; code=$?; echo $code >&3; exit $code';
$process = proc_open($cmd, [["pty"], ["pty"], ["pty"], ["pipe", "w"]], $pipes);
var_dump(count($pipes));
$got = '';
while (($chunk = @fread($pipes[0], 1000)) !== false && $chunk !== '') {
    $got .= $chunk;
}
var_dump($got);
var_dump(stream_get_contents($pipes[3]));
fclose($pipes[0]);
fclose($pipes[1]);
fclose($pipes[2]);
fclose($pipes[3]);
var_dump(proc_close($process));

<?php
// popen runs the command live through a real pipe
echo "before\n";
$p = popen('echo one; echo two; exit 3', 'r');
var_dump(fgets($p));
$m = stream_get_meta_data($p);
var_dump($m['stream_type'], $m['mode'], $m['seekable'], isset($m['uri']), isset($m['wrapper_type']));
var_dump(stream_is_local($p));
$r = [$p];
$w = null;
$e = null;
var_dump(stream_select($r, $w, $e, 5));
var_dump(fgets($p), fgets($p), feof($p));
var_dump(pclose($p));

$p = popen('cat', 'w');
fwrite($p, "to cat\n");
var_dump(pclose($p));
$p = popen('read x; echo "got $x"; exit 7', 'wb');
fwrite($p, "abc\n");
var_dump(pclose($p));

// a signal's raw wait status
$p = popen('kill -9 $$', 'r');
var_dump(fread($p, 10));
var_dump(pclose($p));

// fclose is pclose too: a failing child makes it false
$p = popen('exit 0', 'r');
var_dump(fclose($p));
$p = popen('exit 2', 'r');
var_dump(fclose($p));
$p = popen('true', 'w');
var_dump(fclose($p));

// reads wait for the child
$p = popen('sleep 0.2; echo late', 'r');
var_dump(fread($p, 100));
fclose($p);

// the child writes to the script's stdout, in order with its output
echo "a\n";
$p = popen('echo b', 'r');
echo fread($p, 10);
pclose($p);
$p = popen('echo c >&1', 'w');
pclose($p);
echo "d\n";

// fgets buffers what the pipe holds; handing the stream to another process loses it
$p = popen('echo 1; echo 2', 'r');
usleep(100000);
var_dump(fgets($p));
$proc = proc_open('cat', [0 => $p, 1 => ['pipe', 'w']], $pipes);
var_dump(stream_get_contents($pipes[1]));
proc_close($proc);
pclose($p);
echo "after\n";

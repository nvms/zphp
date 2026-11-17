<?php
$s = file_get_contents('/proc/self/statm');
var_dump(strlen($s) > 0, substr_count($s, ' '));
$c = file_get_contents('/proc/cpuinfo');
var_dump(strlen($c) > 1000);
var_dump(strlen(file_get_contents('/proc/self/status')) > 100);
$f = file('/proc/self/status');
var_dump(count($f) > 5);
var_dump(strlen(file_get_contents('/proc/self/statm', false, null, 2)) > 0);
var_dump(file_get_contents('/proc/self/statm', false, null, 0, 3) !== false);
var_dump(strlen(file_get_contents('/proc/self/statm', false, null, 0, 3)));
$fp = fopen('/proc/self/status', 'r');
var_dump(strlen(stream_get_contents($fp)) > 100);
var_dump(strlen(fread(fopen('/proc/self/status', 'r'), 8192)) > 100);
readfile('/proc/sys/kernel/ostype');
var_dump(filesize('/proc/self/status'));

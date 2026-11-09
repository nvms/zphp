<?php
// reading a write-only stream and writing a read-only one fail with php's
// errno notice; fwrite with a length of zero or less writes nothing
$file = sys_get_temp_dir() . "/zphp_rw_" . getmypid();
file_put_contents($file, "line one\nline two\n");

$w = fopen($file, "a");
var_dump(fread($w, 10), fgets($w), fgetc($w), fpassthru($w));
var_dump(fwrite($w, "x", 0), fwrite($w, "x", -5), fwrite($w, ""));
fclose($w);

$r = fopen($file, "r");
var_dump(fwrite($r, "data"), fputs($r, "more"));
var_dump(fpassthru($r));
fclose($r);

// an unknown whence leaves the position where it was
$r = fopen($file, "r");
fseek($r, 5);
var_dump(fseek($r, 0, 512), ftell($r));
fclose($r);

unlink($file);

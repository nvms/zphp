<?php
// flock, ftruncate, fgets, and popen check their arguments as php does
$file = sys_get_temp_dir() . "/zphp_args_" . getmypid();
file_put_contents($file, str_repeat("x", 2000) . "\nshort\n");

$fp = fopen($file, "r+");
foreach ([0, 4, 8, -1] as $op) {
    try {
        var_dump(flock($fp, $op));
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
try {
    flock($fp, []);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
$would = "unset";
var_dump(flock($fp, LOCK_EX | LOCK_NB, $would), $would);
$other = fopen($file, "r");
$would = "unset";
var_dump(flock($other, LOCK_EX | LOCK_NB, $would), $would);
var_dump(flock($fp, LOCK_UN), flock($other, LOCK_SH, $would), $would);
fclose($other);

try {
    ftruncate($fp, -1);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
foreach ([0, -10] as $len) {
    try {
        fgets($fp, $len);
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
var_dump(fgets($fp, 1));
// without a length a line comes back whole, however long
var_dump(strlen(fgets($fp)), fgets($fp));
fclose($fp);

foreach (["x", "rw", "rwb", "bb"] as $mode) {
    try {
        popen("true", $mode);
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
unlink($file);

<?php
// fsync and fdatasync flush a plain file and refuse other streams
$file = sys_get_temp_dir() . "/zphp_fsync_" . getmypid();
$fp = fopen($file, "w");
fwrite($fp, "data");
var_dump(fsync($fp), fdatasync($fp));
fclose($fp);
var_dump(file_get_contents($file));

$mem = fopen("php://memory", "w");
var_dump(fsync($mem), fdatasync($mem));
$data = fopen("data://text/plain,abc", "r");
var_dump(fsync($data));
try {
    fsync($fp);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
unlink($file);

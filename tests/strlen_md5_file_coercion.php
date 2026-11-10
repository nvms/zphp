<?php
// strlen of a float counts the text php makes of it, and the hash file
// functions take their path as a string parameter
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });
var_dump(strlen(1.23456789012345678), strlen(-0.5), strlen(1e100), strlen(0.1 + 0.2));
ini_set("precision", "5");
var_dump(strlen(1.23456789012345678));
ini_restore("precision");
var_dump(md5_file(12), sha1_file(1.5));
try {
    md5_file([]);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
$f = tempnam(sys_get_temp_dir(), "md5");
file_put_contents($f, "abc");
var_dump(md5_file($f), sha1_file($f, true) === sha1("abc", true));
unlink($f);

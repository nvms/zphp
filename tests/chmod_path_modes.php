<?php
// chmod changes the mode through the path: directories and files without
// read or write permission included, and it warns when it cannot
$dir = sys_get_temp_dir() . "/zphp_chmod_" . getmypid();
mkdir($dir);
var_dump(chmod($dir, 0750));
clearstatcache();
printf("%o\n", fileperms($dir));
var_dump(chmod($dir, 01777));
clearstatcache();
printf("%o\n", fileperms($dir));

$file = "$dir/f";
touch($file);
var_dump(chmod($file, 0));
clearstatcache();
printf("%o\n", fileperms($file));
var_dump(chmod($file, "0644"));
clearstatcache();
printf("%o\n", fileperms($file));
var_dump(chmod($file, 0640.0));
clearstatcache();
printf("%o\n", fileperms($file));

var_dump(chmod("/zphp_no_such_dir/f", 0777));
try {
    chmod($file, "rw");
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    chmod("$file\0x", 0644);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}

unlink($file);
rmdir($dir);

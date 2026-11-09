<?php
// tempnam names the file after the prefix's last segment plus 19 random
// characters, in the real directory, and falls back to the system's
// temporary directory with a notice when the one given cannot hold it
$base = sys_get_temp_dir() . "/zphp_tempnam_" . getmypid();
mkdir($base);
$tmp = realpath(sys_get_temp_dir());

$name = tempnam($base, "pre_");
var_dump(dirname($name) === realpath($base), strlen(basename($name)), str_starts_with(basename($name), "pre_"));
printf("%o\n", fileperms($name) & 0777);
unlink($name);

$name = tempnam("$base/./", "some/dir/x");
var_dump(dirname($name) === realpath($base), strlen(basename($name)), str_starts_with(basename($name), "x"));
unlink($name);

$name = tempnam($base, str_repeat("p", 80));
var_dump(strlen(basename($name)));
unlink($name);

$name = tempnam("/zphp_no_such_dir", "q");
var_dump(dirname($name) === $tmp);
unlink($name);

$name = tempnam("", "q");
var_dump(dirname($name) === $tmp);
unlink($name);

try {
    tempnam("$base\0", "x");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
rmdir($base);

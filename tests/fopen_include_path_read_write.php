<?php
// fopen's use_include_path finds an existing file for r+ as it does for r
$base = sys_get_temp_dir() . "/zphp_incpath_" . getmypid();
mkdir($base);
mkdir("$base/inc");
mkdir("$base/work");
file_put_contents("$base/inc/data.txt", "from include path");
set_include_path("$base/inc");
chdir("$base/work");
foreach (["r", "r+", "rb", "r+b"] as $mode) {
    $h = fopen("data.txt", $mode, true);
    var_dump(fread($h, 100));
    fclose($h);
}
chdir("/");
unlink("$base/inc/data.txt");
rmdir("$base/inc");
rmdir("$base/work");
rmdir($base);

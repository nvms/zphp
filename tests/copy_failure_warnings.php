<?php
// copy refuses directories with php's warnings, reports the stream that
// failed to open, and fails quietly when copying a file onto itself
$base = sys_get_temp_dir() . "/zphp_copy_" . getmypid();
mkdir($base);
$src = "$base/src.txt";
file_put_contents($src, "contents");

var_dump(copy($base, "$base/x"));
var_dump(copy($src, $base));
var_dump(file_exists("$base/x"));
var_dump(copy($src, $src), file_get_contents($src));
var_dump(@copy("/zphp_no_such_dir/f", "$base/x"), error_get_last()['message']);
var_dump(@copy($src, "/zphp_no_such_dir/f"), error_get_last()['message']);
foreach ([["", "$base/x"], [$src, ""]] as [$from, $to]) {
    try {
        copy($from, $to);
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}

file_put_contents("$base/dst.txt", "a much longer previous body");
var_dump(copy($src, "$base/dst.txt"), file_get_contents("$base/dst.txt"));
var_dump(copy("data://text/plain,from data", "$base/data.txt"), file_get_contents("$base/data.txt"));

try {
    copy("$src\0", "$base/x");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}

foreach (['src.txt', 'dst.txt', 'data.txt'] as $f) unlink("$base/$f");
rmdir($base);

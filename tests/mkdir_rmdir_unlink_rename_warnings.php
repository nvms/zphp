<?php
// directory and file removal and renaming warn with the reason, as php does
$base = sys_get_temp_dir() . "/zphp_fsops_" . getmypid();
$missing = "/zphp_no_such_dir/x";

var_dump(mkdir($missing));
var_dump(mkdir("$missing/deeper", 0777, true));
var_dump(mkdir($base));
var_dump(@mkdir($base), error_get_last()['message']);
var_dump(mkdir("$base/a/b", 0755, true));
var_dump(@mkdir("$base/a/b", 0755, true), error_get_last()['message']);
var_dump(@mkdir(""), error_get_last()['message']);

var_dump(@rmdir($missing), error_get_last()['message'] === "rmdir($missing): No such file or directory");
var_dump(@rmdir("$base/a"), str_ends_with(error_get_last()['message'], "): Directory not empty"));
var_dump(rmdir("$base/a/b"), rmdir("$base/a"));

touch("$base/f");
var_dump(@unlink($missing), error_get_last()['message'] === "unlink($missing): No such file or directory");
var_dump(@unlink(""), error_get_last()['message']);
var_dump(@unlink(false), error_get_last()['message']);
mkdir("$base/d");
var_dump(@unlink("$base/d"), str_ends_with(error_get_last()['message'], "/d): Is a directory"));

var_dump(@rename($missing, "$base/g"), str_ends_with(error_get_last()['message'], "/g): No such file or directory"));
var_dump(@rename("$base/f", ""), str_ends_with(error_get_last()['message'], "/f,): No such file or directory"));
var_dump(@rename("$base/f", "$base/d"), str_ends_with(error_get_last()['message'], "/d): Is a directory"));
var_dump(rename("$base/f", "$base/g"), file_exists("$base/g"));

foreach (['mkdir', 'rmdir', 'unlink'] as $fn) {
    try {
        $fn("$base\0x");
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
try {
    rename("$base/g", "$base\0x");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
try {
    mkdir([]);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}

unlink("$base/g");
rmdir("$base/d");
var_dump(rmdir($base), file_exists($base));

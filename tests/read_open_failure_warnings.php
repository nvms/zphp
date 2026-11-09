<?php
// the whole-file readers report why a path could not be opened, validate
// their arguments, and read data: urls the way php's rfc2397 wrapper does
$missing = "/zphp_no_such_dir/file.txt";
var_dump(file_get_contents($missing));
var_dump(file($missing));
var_dump(readfile($missing));
var_dump(parse_ini_file($missing));

foreach (['file_get_contents', 'file', 'readfile'] as $fn) {
    try {
        $fn("");
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
    try {
        $fn("a\0b");
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
try {
    parse_ini_file("");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}

$file = sys_get_temp_dir() . "/zphp_read_" . getmypid();
file_put_contents($file, "line1\nline2\n");
foreach ([8, 10, -1, 32] as $flags) {
    try {
        file($file, $flags);
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
var_dump(file($file, FILE_IGNORE_NEW_LINES | FILE_NO_DEFAULT_CONTEXT));
try {
    file_get_contents($file, false, null, 0, -1);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
var_dump(file_get_contents($file, false, null, -100));
var_dump(file_get_contents($file, false, null, -6));
var_dump(file_get_contents($file, false, null, 100));
var_dump(file_get_contents($file, false, null, 2, 3));
unlink($file);

foreach ([
    'data://,;test',
    'data://text/plain;charset=US-ASCII,test',
    'data://;charset=UTF-8,Hello',
    'data:;base64,Zm9vYmFy',
    'data:;base64,Zm9vYg',
    'data:;base64,#Zm9vYmFy',
    'data:text/plain,a%20b',
    'data:text/plain',
    'data:text/plain;foo,x',
] as $url) {
    var_dump(file_get_contents($url));
}
var_dump(fopen('data:,', 'r') !== false, fopen('data:nocomma', 'r'));

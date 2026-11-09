<?php
// basename, dirname, and pathinfo split paths the way php's own helpers do
foreach (["/", "//", "", ".", "./", "/.", "a//", "/a/b//", "c://test", "c://test//", ".cvsignore", "/usr/include/arpa/inet.h", "a.b.c", "dir/.", 0, 1234] as $p) {
    var_dump(basename($p), dirname($p), pathinfo($p));
}
var_dump(basename("file.txt", ".txt"), basename(".txt", ".txt"), basename("a/b.php/", ".php"));
var_dump(dirname("/a/b/c/d", 2), dirname("/a/b/c/d", 10), dirname("a/b", 3));
try {
    dirname("/a", 0);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
$f = "/usr/include/arpa/inet.h";
foreach ([PATHINFO_DIRNAME, PATHINFO_BASENAME, PATHINFO_EXTENSION, PATHINFO_FILENAME,
          PATHINFO_EXTENSION | PATHINFO_FILENAME, PATHINFO_DIRNAME | PATHINFO_BASENAME, 0, 16] as $flags) {
    var_dump(pathinfo($f, $flags));
}
var_dump(pathinfo("noext", PATHINFO_EXTENSION), pathinfo("", PATHINFO_DIRNAME));

<?php
// symlink, link, readlink, and linkinfo warn with the reason they failed
$base = sys_get_temp_dir() . "/zphp_links_" . getmypid();
mkdir($base);
$file = "$base/file";
touch($file);

var_dump(symlink($file, "$base/sym"), readlink("$base/sym") === $file);
var_dump(linkinfo("$base/sym") === lstat("$base/sym")['dev']);
var_dump(symlink($file, "$base/sym"));
var_dump(link($file, "$base/hard"), fileinode("$base/hard") === fileinode($file));
var_dump(link($file, "$base/hard"));
var_dump(link("$base/missing", "$base/other"));
var_dump(symlink($file, "/zphp_no_such_dir/sym"));
var_dump(symlink("", "$base/x"), symlink($file, ""), link("", "$base/x"));
// a url is only a path here
var_dump(symlink("php://memory", "$base/x"), link($file, "file://$base/y"));
var_dump(readlink($file), readlink("$base/missing"), readlink(""));
var_dump(linkinfo("$base/missing"), linkinfo(""));
var_dump(realpath("") === getcwd());
// a relative target is stored as given and resolved against the link
var_dump(symlink("file", "$base/rel"), readlink("$base/rel"), file_exists("$base/rel"));

foreach (['symlink', 'link'] as $fn) {
    try {
        $fn("a\0b", "$base/x");
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
foreach (['readlink', 'linkinfo', 'realpath'] as $fn) {
    try {
        $fn("a\0b");
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}

foreach (['sym', 'hard', 'rel', 'x', 'file'] as $f) unlink("$base/$f");
rmdir($base);

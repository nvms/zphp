<?php
// finfo::file() and finfo_file() refuse an empty filename or one with a nul
// byte, naming the argument as the method or the function numbers it
$finfo = new finfo();
foreach (['', "\0", "a\0b"] as $name) {
    try {
        var_dump($finfo->file($name));
    } catch (ValueError $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
    try {
        var_dump(finfo_file($finfo, $name));
    } catch (ValueError $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}

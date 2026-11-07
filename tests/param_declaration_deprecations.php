<?php
// deprecations php raises while compiling parameter lists: an implicitly
// nullable typed parameter, an optional parameter before a required one, and
// a by-reference void function. they come before the included file runs, in
// source order, and a parameter that fits says nothing
error_reporting(E_ALL);
set_error_handler(function ($no, $message, $file, $line) {
    echo "[$no] $message (", basename($file), ":$line)\n";
    return true;
});
require __DIR__ . '/include/declarations/params.php';
echo "included\n";
var_dump((new ReflectionFunction('legacy'))->getNumberOfRequiredParameters());
try {
    legacy(1, 2);
} catch (ArgumentCountError $e) {
    echo $e->getMessage(), "\n";
}

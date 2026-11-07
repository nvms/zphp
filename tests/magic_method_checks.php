<?php
// php checks magic method declarations while compiling: a non-public one is a
// warning raised before the file runs (so an error handler set earlier sees
// it), declarations that fit are quiet
set_error_handler(function ($no, $message, $file, $line) {
    echo "[$no] $message (", basename($file), ":$line)\n";
    return true;
});
echo "before include\n";
require __DIR__ . '/include/magic_methods/hidden.php';
echo "after include\n";
var_dump((new ReflectionClass('Hidden'))->hasMethod('__get'));

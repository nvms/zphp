<?php
// data: is a url wrapper: an include refuses it unless allow_url_include is
// on, with or without the slashes, while fopen still reads it
set_error_handler(function ($no, $msg) {
    echo "warning: ", preg_replace("/ \\(include_path='[^']*'\\)/", "", $msg), "\n";
    return true;
});
var_dump(include 'data://text/plain;base64,' . base64_encode('<?php return 42;'));
var_dump(include 'data:text/plain,<?php return 43;');
try {
    require 'data://text/plain,<?php return 44;';
} catch (Error $e) {
    echo get_class($e), ": ", preg_replace("/ \\(include_path='[^']*'\\)/", "", $e->getMessage()), "\n";
}
var_dump(file_get_contents('data:text/plain,<?php return 45;'));
var_dump(stream_get_contents(fopen('data://text/plain;base64,' . base64_encode('read'), 'r')));

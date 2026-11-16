<?php
// html_errors, docref links and error_prepend_string/error_append_string in
// the displayed copy of an error
ini_set('display_errors', '1');
ini_set('log_errors', '0');
ob_start(function ($out) {
    return str_replace([__FILE__, str_replace('/', DIRECTORY_SEPARATOR, __FILE__)], 'FILE', $out);
});

$u = $undefined1;
ini_set('error_prepend_string', '[pre]');
ini_set('error_append_string', '[post]');
$u = $undefined2;
ini_set('error_prepend_string', '');
ini_set('error_append_string', '');

ini_set('html_errors', '1');
$u = $undefined3;
trigger_error("user <b>message</b> & more", E_USER_WARNING);
@file_get_contents('/nonexistent/x');
file_get_contents('/nonexistent/<dir>/"q"');
ini_set('docref_root', 'http://example.test/');
ini_set('docref_ext', '.html');
file_get_contents('/nonexistent/x');
fopen('/nonexistent/y', 'r');
array_chunk([1], 1, false);
echo "\n";
ini_set('error_prepend_string', '<pre>');
ini_set('error_append_string', '</pre>');
$u = $undefined4;
ini_set('error_prepend_string', '');
ini_set('error_append_string', '');
throw new Exception("bad <thing> & 'co'");

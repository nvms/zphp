<?php
// raw percent-encoded
echo file_get_contents('data://text/plain,Hello%20World') . "\n";
// base64
echo file_get_contents('data://text/plain;base64,SGVsbG8gV29ybGQ=') . "\n";
// no media type
echo file_get_contents('data://,raw%20data') . "\n";
// no media type with base64
echo file_get_contents('data://;base64,YmFzZTY0') . "\n";
// charset parameter is ignored, comma still found
echo file_get_contents('data://text/plain;charset=utf-8,utf%208') . "\n";

// fopen + fread + feof + rewind
$f = fopen('data://text/plain;base64,YWJjZGVmZ2hpag==', 'r');
echo fread($f, 5) . "\n";
echo fread($f, 100) . "\n";
echo (feof($f) ? "eof yes" : "eof no") . "\n";
rewind($f);
echo fread($f, 100) . "\n";
fclose($f);

// fgets across encoded newlines
$f = fopen('data://text/plain,a%0Ab%0Ac%0A', 'r');
echo fgets($f);
echo fgets($f);
echo fgets($f);
fclose($f);

// raw bytes
echo bin2hex(file_get_contents('data://application/octet-stream,%00%01%02%FF')) . "\n";

// missing comma returns false
$r = @file_get_contents('data://text/plain;no-comma');
echo var_export($r, true) . "\n";

// in stream_get_wrappers
$w = stream_get_wrappers();
echo (in_array('data', $w) ? "data ok" : "data missing") . "\n";
echo (in_array('php', $w) ? "php ok" : "php missing") . "\n";
echo (in_array('file', $w) ? "file ok" : "file missing") . "\n";

<?php
// regression: curl_multi_* concurrent transfer interface + CURLFile upload
// descriptor. previously curl_multi_init and friends were undefined functions
// and CURLFile didn't exist as a class, so any code doing parallel HTTP or
// multipart file uploads crashed. these don't make network calls in the test
// (CI has no outbound) - they exercise the handle lifecycle and data classes.

// curl_multi handle lifecycle
$mh = curl_multi_init();
echo gettype($mh) . "\n";
$ch1 = curl_init("http://localhost:1/a");
$ch2 = curl_init("http://localhost:1/b");
echo "add1: " . curl_multi_add_handle($mh, $ch1) . "\n";
echo "add2: " . curl_multi_add_handle($mh, $ch2) . "\n";
echo "remove1: " . curl_multi_remove_handle($mh, $ch1) . "\n";
echo "remove2: " . curl_multi_remove_handle($mh, $ch2) . "\n";
curl_close($ch1);
curl_close($ch2);
curl_multi_close($mh);

echo curl_multi_strerror(0) . "\n";
echo "errno: " . curl_multi_errno(curl_multi_init()) . "\n";

// CURLFile via constructor
$f = new CURLFile('/etc/hostname', 'text/plain', 'host.txt');
echo $f->getFilename() . "\n";
echo $f->getMimeType() . "\n";
echo $f->getPostFilename() . "\n";
$f->setMimeType('application/octet-stream');
$f->setPostFilename('renamed.bin');
echo $f->getMimeType() . "\n";
echo $f->getPostFilename() . "\n";

// CURLFile via curl_file_create
$f2 = curl_file_create('/tmp/x.png', 'image/png', 'pic.png');
echo get_class($f2) . "\n";
echo $f2->getFilename() . " " . $f2->getMimeType() . " " . $f2->getPostFilename() . "\n";

// public properties accessible directly (PHP exposes name/mime/postname)
$f3 = new CURLFile('/a/b.txt');
echo $f3->name . "\n";
echo "[" . $f3->mime . "]\n";

var_dump($f instanceof CURLFile);
var_dump(class_exists('CURLFile'));
var_dump(function_exists('curl_multi_init'));

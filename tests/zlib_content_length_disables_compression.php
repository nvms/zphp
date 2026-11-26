<?php
// a script's own Content-Length turns zlib output compression off, so the
// output goes out as written
$_SERVER['HTTP_ACCEPT_ENCODING'] = 'gzip';
ini_set('zlib.output_compression', '1');
$on = (int) ini_get('zlib.output_compression');
header("X-Content-Length: 5");
$still = (int) ini_get('zlib.output_compression');
header("content-LENGTH: 5");
$off = (int) ini_get('zlib.output_compression');
echo "plain $on $still $off\n";

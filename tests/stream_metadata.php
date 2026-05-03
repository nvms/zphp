<?php

// stream_context resource type matches PHP-canonical name
$ctx = stream_context_create(['http' => ['method' => 'GET']]);
echo "ctx: " . get_resource_type($ctx) . "\n";

// stream_get_meta_data includes wrapper_type as 'plainfile' for fopen'd files
$tmp = tempnam(sys_get_temp_dir(), 'meta');
file_put_contents($tmp, "abcdefghij");
$f = fopen($tmp, 'r');
$meta = stream_get_meta_data($f);
echo "wrapper: " . $meta['wrapper_type'] . "\n";
echo "stream_type: " . $meta['stream_type'] . "\n";
echo "mode: " . $meta['mode'] . "\n";
echo "has uri key: " . (isset($meta['uri']) ? 'yes' : 'no') . "\n";

// stream_get_contents respects offset and length
$slice = stream_get_contents($f, 4, 2);
echo "slice(4 from 2): '$slice'\n";
echo "after offset, ftell: " . ftell($f) . "\n";

// length=-1 reads to EOF from current position
fseek($f, 0);
echo "all: '" . stream_get_contents($f, -1) . "'\n";

// length only (no offset)
fseek($f, 0);
echo "first 3: '" . stream_get_contents($f, 3) . "'\n";

fclose($f);
unlink($tmp);

// stream_set_timeout / set_blocking always succeed for regular files
$tmp = tempnam(sys_get_temp_dir(), 'meta');
$f = fopen($tmp, 'r+');
echo "set_blocking: " . var_export(stream_set_blocking($f, true), true) . "\n";
fclose($f);
unlink($tmp);

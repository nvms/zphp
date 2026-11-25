<?php
// php://temp and data: streams keep an inner php://memory stream that is a
// resource of its own; directory iterators hold a directory stream. both take
// resource ids, and fclose() refuses them

$f = fopen('php://temp', 'r+b');
fwrite($f, "hello");
$r = get_resources();
$inner = end($r);
var_dump((int) $inner - (int) $f);
var_dump(fclose($inner));
$meta = stream_get_meta_data($inner);
var_dump($meta['stream_type'], $meta['mode'], isset($meta['wrapper_type']), isset($meta['uri']));
rewind($f);
var_dump(fread($f, 10));
fclose($f);
var_dump(get_resource_type($inner));

$base = (int) fopen('php://memory', 'r+');
$d = fopen('data:,abc', 'r');
var_dump((int) $d - $base);
var_dump((int) fopen('php://memory', 'r+') - $base);

// a php://temp stream past its maxmemory moves to a temporary file stream
$x = fopen('php://temp/maxmemory:4', 'r+b');
$after_open = (int) fopen('php://memory', 'r+');
fwrite($x, "ab");
var_dump((int) fopen('php://memory', 'r+') - $after_open);
fwrite($x, "cdef");
var_dump((int) fopen('php://memory', 'r+') - $after_open);
fwrite($x, "ghij");
var_dump((int) fopen('php://memory', 'r+') - $after_open);
rewind($x);
var_dump(stream_get_contents($x));

$t = new SplTempFileObject();
var_dump((int) fopen('php://memory', 'r+') - $after_open);

$dir = __DIR__;
$before = (int) fopen('php://memory', 'r+');
$it = new DirectoryIterator($dir);
$fs = new FilesystemIterator($dir);
$g = new GlobIterator($dir . '/*.nothing-matches-this');
var_dump((int) fopen('php://memory', 'r+') - $before);
$resources = get_resources();
fclose(end($resources));
var_dump($g->count());

try {
    new DirectoryIterator($dir . '/does-not-exist');
} catch (UnexpectedValueException $e) {
    echo get_class($e), "\n";
}
var_dump((int) fopen('php://memory', 'r+') - $before);

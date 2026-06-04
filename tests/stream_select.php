<?php

// stream_select polls the underlying fds of the stream objects in each by-ref
// array and rewrites each array to the ready subset, returning the count.
// regular-file fds are always ready, so they're a deterministic test.

$path = sys_get_temp_dir() . '/zphp_stream_select_' . getmypid() . '.txt';
file_put_contents($path, "payload");

// a readable file is ready for read
$r = fopen($path, 'r');
$read = [$r];
$write = null;
$except = null;
$n = stream_select($read, $write, $except, 0);
echo "read ready: n=$n count=", count($read), " same=", ($read[0] === $r ? 'y' : 'n'), "\n"; // 1 1 y

// a writable file is ready for write
$w = fopen($path, 'r+');
$r2 = null;
$write2 = [$w];
$e2 = null;
$n2 = stream_select($r2, $write2, $e2, 0);
echo "write ready: n=$n2 count=", count($write2), "\n"; // 1 1

// both read and write in one call, counts sum across arrays
$ra = [$r];
$wa = [$w];
$ea = null;
$n3 = stream_select($ra, $wa, $ea, 0, 0);
echo "both: n=$n3 read=", count($ra), " write=", count($wa), "\n"; // 2 1 1

// all-empty arrays -> ValueError
try {
    $z1 = [];
    $z2 = [];
    $z3 = [];
    stream_select($z1, $z2, $z3, 0);
    echo "no-throw\n";
} catch (\ValueError $e) {
    echo "empty: ", $e->getMessage(), "\n"; // No stream arrays were passed
}

fclose($r);
fclose($w);
@unlink($path);

<?php

// stream_socket_pair creates a connected pair of socket streams (socketpair(2)).
// it also lets us exercise stream_select's not-ready FILTERING: a fresh socket
// with no pending data is not ready for read and gets removed from the array.

$pair = stream_socket_pair(STREAM_PF_UNIX, STREAM_SOCK_STREAM, 0);
echo "created: ", ($pair !== false ? 'y' : 'n'), " count=", count($pair), "\n"; // y 2
[$a, $b] = $pair;

// $a has no pending data -> not ready for read -> filtered out
$read = [$a];
$write = null;
$except = null;
$n = stream_select($read, $write, $except, 0);
echo "before write: n=$n count=", count($read), "\n"; // 0 0

// write to the other end -> $a becomes ready for read
fwrite($b, "hello");
$read = [$a];
$n = stream_select($read, $write, $except, 0);
echo "after write: n=$n count=", count($read), "\n"; // 1 1

echo "received: ", fread($a, 5), "\n"; // hello

// both ends are writable
$r2 = null;
$w2 = [$a, $b];
$e2 = null;
$n2 = stream_select($r2, $w2, $e2, 0);
echo "writable: n=$n2 count=", count($w2), "\n"; // 2 2

fclose($a);
fclose($b);

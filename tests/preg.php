<?php
echo preg_match('/hello/', 'hello world');
echo "\n";

echo preg_match('/xyz/', 'hello world');
echo "\n";

$matches = [];
preg_match('/(\d+)-(\d+)/', 'call 555-1234 now', $matches);
echo $matches[0];
echo "\n";
echo $matches[1];
echo "\n";
echo $matches[2];
echo "\n";

echo preg_match('/HELLO/i', 'hello world');
echo "\n";

$n = preg_match_all('/\d+/', 'a1b22c333', $matches);
echo $n;
echo "\n";
echo implode(',', $matches[0]);
echo "\n";

echo preg_replace('/\d+/', 'X', 'a1b22c333');
echo "\n";

echo preg_replace('/world/', 'PHP', 'hello world');
echo "\n";

$parts = preg_split('/[\s,]+/', 'one, two, three four');
echo implode('|', $parts);
echo "\n";

echo preg_replace('/(\w+)\s(\w+)/', '$2 $1', 'hello world');
echo "\n";

<?php
echo true ? 'yes' : 'no';
echo "\n";
echo false ? 'yes' : 'no';
echo "\n";

$x = 42;
echo $x ? 'truthy' : 'falsy';
echo "\n";

$x = 0;
echo $x ? 'truthy' : 'falsy';
echo "\n";

$x = null;
echo $x ?? 'default';
echo "\n";
echo 42 ?? 'default';
echo "\n";

echo 'hello' ?: 'fallback';
echo "\n";
echo '' ?: 'fallback';
echo "\n";

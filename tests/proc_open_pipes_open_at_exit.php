<?php
// a script may end with a child's pipes still open: they are closed at exit
// after the script's own objects are gone

$proc = proc_open([PHP_BINARY, '-r', 'echo "hello"; fgets(STDIN); echo "bye";'], [
    ['pipe', 'r'],
    ['socket'],
    ['pipe', 'w'],
], $pipes);

stream_set_blocking($pipes[1], true);
echo fread($pipes[1], 5), "\n";
fwrite($pipes[0], "go\n");
echo stream_get_contents($pipes[1]), "\n";
echo "done\n";

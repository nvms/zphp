<?php
// covers: fopen, fwrite, fread, fgets, fseek, ftell, rewind, feof, fclose,
//   file_put_contents, file_get_contents, stream_get_wrappers,
//   php://stdout, php://output, php://stderr, php://memory, php://temp, php://input

// stream wrappers should at minimum include the built-in ones
$wrappers = stream_get_wrappers();
echo "has file: " . (in_array('file', $wrappers) ? "yes" : "no") . "\n";
echo "has http: " . (in_array('http', $wrappers) ? "yes" : "no") . "\n";

// php://stdout via fopen+fwrite
$out = fopen('php://stdout', 'w');
fwrite($out, "to stdout via fopen\n");
fclose($out);

// php://output via file_put_contents
file_put_contents('php://output', "to output via file_put_contents\n");

// php://memory: write, rewind, read, check eof
$mem = fopen('php://memory', 'w+');
$wrote = fwrite($mem, "memory contents");
echo "wrote: $wrote\n";
echo "tell: " . ftell($mem) . "\n";
rewind($mem);
echo "after rewind tell: " . ftell($mem) . "\n";
echo "read: " . fread($mem, 100) . "\n";
echo "eof: " . (feof($mem) ? "yes" : "no") . "\n";
fclose($mem);

// php://temp: line-by-line via fgets
$tmp = fopen('php://temp', 'w+');
fwrite($tmp, "line one\nline two\nline three\n");
rewind($tmp);
echo "fgets 1: " . fgets($tmp);
echo "fgets 2: " . fgets($tmp);
echo "fgets 3: " . fgets($tmp);
echo "feof: " . (feof($tmp) ? "yes" : "no") . "\n";
fclose($tmp);

// php://memory with fseek SEEK_SET, SEEK_CUR, SEEK_END
$buf = fopen('php://memory', 'w+');
fwrite($buf, "abcdefghij");
fseek($buf, 0, SEEK_SET);
echo "seek 0: " . fread($buf, 3) . "\n";
fseek($buf, 2, SEEK_CUR);
echo "after +2: " . fread($buf, 3) . "\n";
fseek($buf, -2, SEEK_END);
echo "from end: " . fread($buf, 2) . "\n";
fclose($buf);

echo "Done\n";

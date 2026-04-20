<?php
// php://stdout via fopen+fwrite
$out = fopen('php://stdout', 'w');
fwrite($out, "stdout via fopen\n");
fclose($out);

// php://output via file_put_contents
file_put_contents('php://output', "output via fpc\n");

// php://memory write+read
$mem = fopen('php://memory', 'w+');
$wrote = fwrite($mem, "memory data");
echo "wrote: $wrote\n";
echo "tell: " . ftell($mem) . "\n";
rewind($mem);
echo "after rewind: " . ftell($mem) . "\n";
echo "read: " . fread($mem, 100) . "\n";
echo "eof: " . (feof($mem) ? "yes" : "no") . "\n";
fclose($mem);

// php://temp fgets
$tmp = fopen('php://temp', 'w+');
fwrite($tmp, "alpha\nbeta\ngamma\n");
rewind($tmp);
echo "fgets: " . fgets($tmp);
echo "fgets: " . fgets($tmp);
echo "fgets: " . fgets($tmp);
echo "feof: " . (feof($tmp) ? "yes" : "no") . "\n";
fclose($tmp);

// fseek modes
$buf = fopen('php://memory', 'w+');
fwrite($buf, "0123456789");
fseek($buf, 0, SEEK_SET);
echo "seek_set: " . fread($buf, 3) . "\n";
fseek($buf, 1, SEEK_CUR);
echo "seek_cur: " . fread($buf, 3) . "\n";
fseek($buf, -2, SEEK_END);
echo "seek_end: " . fread($buf, 2) . "\n";
fclose($buf);

// stream_get_wrappers
$w = stream_get_wrappers();
echo "wrappers includes file: " . (in_array('file', $w) ? "yes" : "no") . "\n";
echo "wrappers includes http: " . (in_array('http', $w) ? "yes" : "no") . "\n";

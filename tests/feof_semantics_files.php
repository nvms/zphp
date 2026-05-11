<?php
$tmp = tempnam(sys_get_temp_dir(), "zphp_");
file_put_contents($tmp, "line1\nline2\nline3\n");

$f = fopen($tmp, "r");
echo fgets($f);
echo fgets($f);
echo fgets($f);
echo feof($f) ? "y" : "n", "\n";
echo fgets($f) === false ? "f" : "ok", "\n";
echo feof($f) ? "y" : "n", "\n";
fclose($f);

$f = fopen($tmp, "r");
echo fread($f, 1000), "\n";
echo feof($f) ? "y" : "n", "\n";
fread($f, 100);
echo feof($f) ? "y" : "n", "\n";
fclose($f);

$f = fopen($tmp, "r");
fseek($f, 0, SEEK_END);
echo feof($f) ? "y" : "n", "\n";
echo fgets($f) === false ? "f" : "ok", "\n";
echo feof($f) ? "y" : "n", "\n";
fclose($f);

$mem = fopen("php://temp", "w+");
fwrite($mem, "a\nb\nc\n");
rewind($mem);
echo fgets($mem);
echo fgets($mem);
echo fgets($mem);
echo feof($mem) ? "y" : "n", "\n";
fclose($mem);

$mem = fopen("php://memory", "w+");
fwrite($mem, "hello world");
rewind($mem);
echo fread($mem, 100), "\n";
echo feof($mem) ? "y" : "n", "\n";
fclose($mem);

$f = fopen($tmp, "r");
$lines = 0;
while (!feof($f)) {
    $l = fgets($f);
    if ($l !== false) $lines++;
}
echo "$lines lines\n";
fclose($f);

unlink($tmp);

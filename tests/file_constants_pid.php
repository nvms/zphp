<?php

// FILE_IGNORE_NEW_LINES strips trailing newlines from each entry
$tmp = tempnam(sys_get_temp_dir(), 'zphp_');
file_put_contents($tmp, "alpha\nbeta\ngamma\n");
$lines = file($tmp, FILE_IGNORE_NEW_LINES);
foreach ($lines as $i => $l) echo "$i:'$l'(" . strlen($l) . ")\n";
unlink($tmp);

// FILE_SKIP_EMPTY_LINES drops blank entries
$tmp = tempnam(sys_get_temp_dir(), 'zphp_');
file_put_contents($tmp, "x\n\n\ny\n\nz\n");
$lines = file($tmp, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
print_r($lines);
unlink($tmp);

// scandir default-asc
$d = sys_get_temp_dir() . '/zphp_scan_' . getmypid();
@mkdir($d);
file_put_contents("$d/zz", '');
file_put_contents("$d/aa", '');
file_put_contents("$d/mm", '');

$asc = scandir($d);
echo "asc: " . implode(',', $asc) . "\n";

$desc = scandir($d, SCANDIR_SORT_DESCENDING);
echo "desc: " . implode(',', $desc) . "\n";

unlink("$d/aa"); unlink("$d/mm"); unlink("$d/zz"); rmdir($d);

// process info
echo "pid > 0: " . (getmypid() > 0 ? 'yes' : 'no') . "\n";
echo "uid >= 0: " . (getmyuid() >= 0 ? 'yes' : 'no') . "\n";
echo "gid >= 0: " . (getmygid() >= 0 ? 'yes' : 'no') . "\n";

<?php

$tmp = tempnam(sys_get_temp_dir(), "flock_test_");
$f = fopen($tmp, "w");
echo flock($f, LOCK_EX) ? "locked" : "failed";
echo "\n";
fwrite($f, "test data");
echo flock($f, LOCK_UN) ? "unlocked" : "failed";
echo "\n";
fclose($f);

// shared lock
$f2 = fopen($tmp, "r");
echo flock($f2, LOCK_SH) ? "shared" : "failed";
echo "\n";
echo flock($f2, LOCK_UN) ? "unlocked" : "failed";
echo "\n";
fclose($f2);
unlink($tmp);

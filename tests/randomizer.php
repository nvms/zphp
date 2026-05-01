<?php

$r = new Random\Randomizer();

// getBytes returns the requested length
echo strlen($r->getBytes(8)) . "\n";
echo strlen($r->getBytes(32)) . "\n";

// getInt is in range
$ok = true;
for ($i = 0; $i < 100; $i++) {
    $n = $r->getInt(1, 10);
    if ($n < 1 || $n > 10) { $ok = false; break; }
}
echo $ok ? "range-ok" : "range-fail";
echo "\n";

// getFloat is in range
$ok = true;
for ($i = 0; $i < 100; $i++) {
    $f = $r->getFloat(0.0, 1.0);
    if ($f < 0.0 || $f > 1.0) { $ok = false; break; }
}
echo $ok ? "float-ok" : "float-fail";
echo "\n";

// shuffleArray preserves length and contents
$src = [1,2,3,4,5];
$shuf = $r->shuffleArray($src);
echo count($shuf) . "\n";
$sorted = $shuf;
sort($sorted);
echo implode(",", $sorted) . "\n";

// shuffleBytes preserves length
$bytes = $r->shuffleBytes("abcdefgh");
echo strlen($bytes) . "\n";

// pickArrayKeys returns the requested count
$keys = $r->pickArrayKeys(['a' => 1, 'b' => 2, 'c' => 3, 'd' => 4], 2);
echo count($keys) . "\n";

// engines parse and accept seed (output divergent from PHP)
$rs = new Random\Randomizer(new Random\Engine\Mt19937(42));
$n = $rs->getInt(1, 100);
echo (($n >= 1 && $n <= 100) ? "engine-ok" : "fail") . "\n";

$rs2 = new Random\Randomizer(new Random\Engine\Secure());
echo strlen($rs2->getBytes(4)) . "\n";

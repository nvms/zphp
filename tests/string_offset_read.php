<?php
// a string offset names a byte by an integer-numeric key; other keys warn,
// are cast, or are a TypeError, as php resolves them
$s = "abcdef";
foreach (["1.5", " 1", "1 ", "0x1", "1e1", "-1", "", "01", "9999999999999999999999", 2.0, 1.5, -1.0, false] as $k) {
  try { var_dump($s[$k]); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
}
$r = fopen("php://memory", "r");
try { var_dump($s[$r]); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
foreach (["1.5", "1x", "x", 1.5, null, 10] as $k) var_dump($s[$k] ?? "D", isset($s[$k]));
try { var_dump($s[[]] ?? "D"); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
var_dump(isset($s[[]]), isset($s["1x"]), isset($s[" 1"]), isset($s[-6]), isset($s[-7]));
var_dump($s[10], $s[-7], $s[-6]);
[$c] = "ab";
var_dump($c);

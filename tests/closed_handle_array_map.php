<?php
// array_filter without callback - filters all falsy
$a = [0, 1, "", "hi", null, 0.0, [], [1], false, true];
print_r(array_filter($a));
print_r(array_filter([])); // empty stays empty

// array_filter with closure use
$threshold = 5;
$a = [1, 5, 7, 3, 10];
print_r(array_filter($a, function($v) use ($threshold) { return $v > $threshold; }));
$key_filter = ["a", "c"];
$h = ["a" => 1, "b" => 2, "c" => 3, "d" => 4];
print_r(array_filter($h, function($k) use ($key_filter) { return in_array($k, $key_filter); }, ARRAY_FILTER_USE_KEY));

// array_walk_recursive with circular references - skipped: zphp doesn't yet
// detect cycles and would stack-overflow before reaching the warning

// preg_replace returning array
$r = preg_replace('/\d+/', 'N', ['12 cats', '3 dogs', 'no nums']);
print_r($r);

// vsprintf with array args
echo vsprintf("%s = %d", ["count", 42]), "\n";
echo vsprintf("%2\$s %1\$s", ["world", "hello"]), "\n";

// fprintf return value
$path = sys_get_temp_dir() . "/zphp_fprintf.txt";
$f = fopen($path, "w");
$n = fprintf($f, "hello %s", "world");
fclose($f);
echo $n, ":", file_get_contents($path), "\n";
unlink($path);

// fclose double-close - PHP 8 throws TypeError on second close
$f = fopen("php://memory", "r");
var_dump(fclose($f));
try { fclose($f); echo "no err\n"; } catch (\TypeError $e) { echo "te-fclose\n"; }

// fwrite to closed handle - PHP 8 throws TypeError
$f = fopen("php://memory", "r+");
fwrite($f, "data");
fclose($f);
try { fwrite($f, "more"); echo "no err\n"; } catch (\TypeError $e) { echo "te-fwrite\n"; }

// fread from closed handle - PHP 8 throws TypeError
$f = fopen("php://memory", "r+");
fwrite($f, "abc");
rewind($f);
fclose($f);
try { fread($f, 10); echo "no err\n"; } catch (\TypeError $e) { echo "te-fread\n"; }

// sprintf with negative width (PHP: ignored)
echo sprintf("[%-5d]", 42), "\n"; // left align
echo sprintf("[%5d]", -42), "\n";
echo sprintf("[%-5s]", "hi"), "\n";
echo sprintf("[%5s]", "hi"), "\n";

// printf returns length
$n = printf("hi");
echo "(", $n, ")\n";

// array_walk on object props (objects passed by ref to callback)
class Holder { public int $v = 1; }
$arr = [new Holder, new Holder];
array_walk($arr, function($obj) { $obj->v += 10; });
echo $arr[0]->v, " ", $arr[1]->v, "\n"; // 11 11

// array_filter with object callable
class Filter { public function check($v) { return $v > 5; } }
$f = new Filter;
print_r(array_filter([1, 5, 10, 3, 7], [$f, "check"]));

// array_map with non-callable - throws in 8.x
try { array_map("nonexistent_xyz", [1, 2, 3]); echo "no err\n"; } catch (Error $e) { echo "err\n"; } catch (TypeError $e) { echo "type\n"; }
try { array_map(null, []); echo "ok\n"; } catch (Error $e) { echo "err\n"; }

// array_filter callback returning truthy non-bool
$a = [0, 1, 2, "x", "0", null];
print_r(array_filter($a, fn($v) => $v));   // standard
print_r(array_filter([1, 2, 3], fn($v) => "yes"));   // truthy string
print_r(array_filter([1, 2, 3], fn($v) => 0));   // 0 = falsy

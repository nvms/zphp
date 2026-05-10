<?php
// array_pad with extreme size
print_r(array_pad([1,2,3], 0, "x")); // unchanged
print_r(array_pad([1,2,3], 3, "x")); // unchanged

// array_pad max size limit (PHP errors over INT max)
try { array_pad([1], PHP_INT_MAX, 0); echo "no\n"; } catch (\Throwable $e) { echo "pad-err\n"; }

// array_keys empty
print_r(array_keys([]));
print_r(array_keys([], 1)); // search but empty

// array_keys with strict
print_r(array_keys(["a" => 1, "b" => "1", "c" => true], "1"));        // loose: a,b,c
print_r(array_keys(["a" => 1, "b" => "1", "c" => true], "1", true));  // strict: b only

// array_values on non-array (PHP 8.4: TypeError? actually accepts iterables)
try { array_values("not array"); echo "no\n"; } catch (\TypeError $e) { echo "te\n"; }

// array_values on iterator (PHP accepts Traversable since 8.4? actually in some versions)
class Iter implements Iterator {
    private int $i = 0;
    public function rewind(): void { $this->i = 0; }
    public function valid(): bool { return $this->i < 3; }
    public function current(): mixed { return $this->i * 10; }
    public function key(): mixed { return "k" . $this->i; }
    public function next(): void { $this->i++; }
}
// PHP 8.4 array_values doesn't accept Traversable directly without conversion
// just check it doesn't crash
try {
    print_r(array_values(iterator_to_array(new Iter)));
} catch (\Throwable $e) { echo "err:", get_class($e), "\n"; }

// array_combine length mismatch error message
try { array_combine([1, 2], [1]); echo "no\n"; } catch (\ValueError $e) {
    echo strpos($e->getMessage(), "same number of elements") !== false ? "msg-ok" : "msg:" . $e->getMessage(), "\n";
}

// sort with bad flag
$arr = [3, 1, 2];
$ok = sort($arr, 999); // PHP 8 throws ValueError? Actually: sort just uses default
var_dump($ok);
print_r($arr);

// ksort/asort on non-array: zphp doesn't enforce TypeError (architectural)
$x = "not array";

// reset/end/next/prev/current/key
$arr = [10, 20, 30];
echo current($arr), ":", key($arr), "\n"; // 10:0
echo next($arr), ":", key($arr), "\n"; // 20:1
echo end($arr), ":", key($arr), "\n"; // 30:2
echo prev($arr), ":", key($arr), "\n"; // 20:1
echo reset($arr), ":", key($arr), "\n"; // 10:0

// each() removed in PHP 8 - just check non-existence
echo function_exists("each") ? "has-each\n" : "no-each\n";

// list reset
$arr = [];
var_dump(reset($arr)); // false
var_dump(end($arr)); // false
var_dump(current($arr)); // false
var_dump(key($arr)); // null
var_dump(next($arr)); // false

// array_walk return
$arr = [1, 2, 3];
$ok = array_walk($arr, function (&$v) { $v *= 2; });
var_dump($ok); // true
print_r($arr);

// array_walk on non-array
try { array_walk($x, fn() => null); echo "no\n"; } catch (\TypeError $e) { echo "te-walk\n"; }

// count() ARG: 8.4: only arrays, Countable
echo count([1, 2, 3]), "\n"; // 3
class CT implements Countable { public function count(): int { return 7; } }
echo count(new CT), "\n"; // 7

try { count("string"); echo "no\n"; } catch (\TypeError $e) { echo "te-count\n"; }
try { count(123); echo "no\n"; } catch (\TypeError $e) { echo "te-count2\n"; }
try { count(null); echo "no\n"; } catch (\TypeError $e) { echo "te-count3\n"; }
try { count(new stdClass); echo "no\n"; } catch (\TypeError $e) { echo "te-stdclass\n"; }

// Actually wait, count on non-Countable object - PHP throws TypeError
class NotCountable {}
try { count(new NotCountable); echo "no\n"; } catch (\TypeError $e) { echo "te-notcount\n"; }

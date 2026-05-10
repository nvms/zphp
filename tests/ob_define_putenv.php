<?php
// array_map on Generator
function gen() { yield 1; yield 2; yield 3; }
// PHP: array_map requires arrays not iterables
try {
    $r = array_map(fn($x) => $x * 10, gen());
    print_r($r);
} catch (\TypeError $e) { echo "te:array_map-gen\n"; }

// iterator_to_array
$r = iterator_to_array(gen());
print_r($r); // [0=>1, 1=>2, 2=>3]

// iterator_to_array on object iterator
class CountIter implements Iterator {
    private int $i = 0;
    public function __construct(private int $max) {}
    public function rewind(): void { $this->i = 0; }
    public function valid(): bool { return $this->i < $this->max; }
    public function current(): mixed { return $this->i * 10; }
    public function key(): mixed { return "k" . $this->i; }
    public function next(): void { $this->i++; }
}
$r = iterator_to_array(new CountIter(3));
print_r($r);

// preserve_keys=false
$r = iterator_to_array(new CountIter(3), false);
print_r($r);

// ob_start/get_clean nested
ob_start();
echo "outer1|";
ob_start();
echo "inner1|";
$inner = ob_get_clean();
echo "outer2|";
$outer = ob_get_clean();
echo "captured: outer=[$outer] inner=[$inner]\n";

// ob_get_contents (peek without clearing)
ob_start();
echo "abc";
$peek = ob_get_contents();
echo "def";
$final = ob_get_clean();
echo "peek=[$peek] final=[$final]\n";

// ob_get_level
echo ob_get_level(), "\n"; // 0 (or 1+)
ob_start();
echo ob_get_level(), "|"; // current+1
ob_start();
echo ob_get_level(), "|";
ob_end_clean();
echo ob_get_level(), "|";
ob_end_clean();
echo ob_get_level(), "\n";

// ob_flush (passes content out without ending)
ob_start();
echo "X|";
$dummy = ob_get_clean();
echo "after-clean|";
echo "got:$dummy\n";

// $argv access
echo gettype($argv ?? null), "\n"; // array (or NULL if not in CLI)
echo isset($argv) ? "set" : "unset", "\n";

// getenv/putenv
putenv("ZPHP_TEST=hello world");
echo getenv("ZPHP_TEST"), "\n";
echo getenv("ZPHP_NOT_SET") === false ? "false" : "set", "\n";
putenv("ZPHP_BACKSLASH=foo\\bar");
echo getenv("ZPHP_BACKSLASH"), "\n";

// getenv("name", true) returns local-only
$result = getenv("ZPHP_TEST", true);
echo $result, "\n";

// $_ENV / $_SERVER access
echo isset($_ENV) ? "env-set" : "env-unset", "\n";
echo isset($_SERVER) ? "server-set" : "server-unset", "\n";
// $_SERVER['PHP_SELF'] format varies by environment; skip exact value

// define() / defined() / constant()
defined("ZPHP_C1") ? "y" : "n";
echo defined("ZPHP_C1") ? "y\n" : "n\n";
define("ZPHP_C1", "hello");
echo defined("ZPHP_C1") ? "y\n" : "n\n";
echo constant("ZPHP_C1"), "\n";
echo ZPHP_C1, "\n";

// define case-sensitive
define("ZPHP_LOWER", "lo");
echo defined("zphp_lower") ? "y" : "n", "\n"; // n (case-sens)
echo defined("ZPHP_LOWER") ? "y" : "n", "\n"; // y

// redefine: PHP emits warning but both return false on duplicate
$ok = @define("ZPHP_C1", "again");
var_dump($ok); // false

// constant on enum case
enum Color: string { case Red = "red"; }
echo constant("Color::Red") === Color::Red ? "y\n" : "n\n";

// constant on class const
class K { const V = 42; }
echo constant("K::V"), "\n";

// constant() with non-existent
try { constant("nonexistent_const"); echo "no\n"; } catch (\Throwable $e) { echo "err:", get_class($e), "\n"; }

// get_defined_constants
$defs = get_defined_constants(true);
echo gettype($defs), "\n";
echo isset($defs['user']) ? "user-set" : "no", "\n";
echo isset($defs['user']['ZPHP_C1']) ? "in-user" : "not-in-user", "\n";

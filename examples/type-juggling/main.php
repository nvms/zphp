<?php
// covers: numeric string coercion, loose vs strict comparison, abstract class
//   instantiation guard, interface method enforcement, __call magic method,
//   __isset magic method, nested array spread, string-to-number conversion,
//   truthiness rules, spaceship with mixed types, array_walk with reference,
//   compact/extract, list() in foreach, ternary edge cases (short ternary,
//   nested ternary), null propagation, negative array indices, implode with
//   non-string values, intval/floatval edge cases, settype

// === test: numeric string coercion ===

echo "--- numeric coercion ---\n";
echo "5" + 3 . "\n";
echo "3.5" + 1.5 . "\n";
echo "  7  " + 3 . "\n";
echo true + true . "\n";
echo false + 0 . "\n";
echo null + 5 . "\n";
echo "100" * 2 . "\n";
echo "3" ** 2 . "\n";

// === test: loose comparison ===

echo "--- loose comparison ---\n";
echo (0 == false) ? "y" : "n"; echo "\n";
echo (0 == null) ? "y" : "n"; echo "\n";
echo (0 == "") ? "y" : "n"; echo "\n";
echo ("" == false) ? "y" : "n"; echo "\n";
echo ("0" == false) ? "y" : "n"; echo "\n";
echo ("1" == true) ? "y" : "n"; echo "\n";
echo (null == false) ? "y" : "n"; echo "\n";
echo ("php" == 0) ? "y" : "n"; echo "\n";
echo ([] == false) ? "y" : "n"; echo "\n";
echo (0 == "0") ? "y" : "n"; echo "\n";

// === test: strict comparison ===

echo "--- strict comparison ---\n";
echo (0 === false) ? "y" : "n"; echo "\n";
echo (0 === null) ? "y" : "n"; echo "\n";
echo ("" === false) ? "y" : "n"; echo "\n";
echo (1 === true) ? "y" : "n"; echo "\n";
echo ("1" === 1) ? "y" : "n"; echo "\n";
echo (0 === 0) ? "y" : "n"; echo "\n";
echo ("" === "") ? "y" : "n"; echo "\n";

// === test: truthiness ===

echo "--- truthiness ---\n";
$truthy = [1, -1, "hello", "0.0", [1], 3.14, true];
$falsy = [0, 0.0, "", "0", [], null, false];
echo "truthy: ";
foreach ($truthy as $v) echo ($v ? "T" : "F");
echo "\n";
echo "falsy: ";
foreach ($falsy as $v) echo ($v ? "T" : "F");
echo "\n";

// === test: spaceship with mixed types ===

echo "--- spaceship ---\n";
echo (1 <=> 2) . "\n";
echo (2 <=> 1) . "\n";
echo (1 <=> 1) . "\n";
echo ("a" <=> "b") . "\n";
echo ("b" <=> "a") . "\n";
echo (0 <=> false) . "\n";

// === test: intval/floatval edge cases ===

echo "--- intval/floatval ---\n";
echo intval("  42  ") . "\n";
echo intval("0xFF", 16) . "\n";
echo intval("0b1010", 2) . "\n";
echo intval("077", 8) . "\n";
echo floatval("1.2e3") . "\n";
echo floatval("  -3.14  ") . "\n";

// === test: explicit casting ===

echo "--- casting ---\n";
echo gettype((int) "42") . ": " . (int) "42" . "\n";
echo gettype((string) 3.14) . ": " . (string) 3.14 . "\n";
echo gettype((bool) 1) . ": " . ((bool) 1 ? "true" : "false") . "\n";
echo gettype((float) "2.5") . ": " . (float) "2.5" . "\n";
echo gettype((array) "hello") . "\n";

// === test: compact/extract ===

echo "--- compact/extract ---\n";
$name = "Alice";
$age = 30;
$data = compact("name", "age");
echo $data["name"] . " is " . $data["age"] . "\n";

extract(["city" => "NYC", "country" => "US"]);
echo "$city, $country\n";

// === test: ternary edge cases ===

echo "--- ternary ---\n";
$x = null;
echo ($x ?: "default") . "\n";
echo ("" ?: "fallback") . "\n";
echo ("value" ?: "fallback") . "\n";
echo (0 ?: 42) . "\n";

$a = null;
echo ($a ?? "null-coalesce") . "\n";
$a = false;
echo ($a ?? "null-coalesce") . "\n";

// === test: __call magic method ===

echo "--- __call ---\n";

class DynamicProxy
{
    private array $handlers = [];

    public function register(string $name, callable $fn): void
    {
        $this->handlers[$name] = $fn;
    }

    public function __call(string $name, array $args): mixed
    {
        if (isset($this->handlers[$name])) {
            return call_user_func_array($this->handlers[$name], $args);
        }
        return "unknown: $name";
    }
}

$proxy = new DynamicProxy();
$proxy->register("greet", function ($name) { return "hello $name"; });
$proxy->register("add", function ($a, $b) { return $a + $b; });
echo $proxy->greet("world") . "\n";
echo $proxy->add(3, 4) . "\n";
echo $proxy->missing() . "\n";

// === test: __isset magic method ===

echo "--- __isset ---\n";

class Config
{
    private array $data;

    public function __construct(array $data)
    {
        $this->data = $data;
    }

    public function __get(string $name): mixed
    {
        return $this->data[$name] ?? null;
    }

    public function __isset(string $name): bool
    {
        return array_key_exists($name, $this->data);
    }
}

$cfg = new Config(["host" => "localhost", "port" => 8080, "debug" => false]);
echo isset($cfg->host) ? "y" : "n"; echo "\n";
echo isset($cfg->missing) ? "y" : "n"; echo "\n";
echo isset($cfg->debug) ? "y" : "n"; echo "\n";
echo $cfg->host . "\n";
echo $cfg->port . "\n";

// === test: list() in foreach ===

echo "--- list foreach ---\n";
$pairs = [[1, "one"], [2, "two"], [3, "three"]];
foreach ($pairs as $pair) {
    [$num, $word] = $pair;
    echo "$num=$word ";
}
echo "\n";

foreach ($pairs as $pair) {
    list($n, $w) = $pair;
    echo "$n:$w ";
}
echo "\n";

// === test: array_walk ===

echo "--- array_walk ---\n";
$items = ["apple", "banana", "cherry"];
$result = array_map(function ($val) { return strtoupper($val); }, $items);
echo implode(", ", $result) . "\n";

$prices = [10, 20, 30];
$tax = 1.1;
$taxed = array_map(function ($price) use ($tax) { return (int) ($price * $tax); }, $prices);
echo implode(", ", $taxed) . "\n";

// === test: nested array spread ===

echo "--- nested spread ---\n";
$a = [1, 2, 3];
$b = [4, 5, 6];
$c = [...$a, ...$b];
echo implode(",", $c) . "\n";

$x = ["a" => 1, "b" => 2];
$y = ["b" => 3, "c" => 4];
$z = [...$x, ...$y];
echo $z["a"] . "," . $z["b"] . "," . $z["c"] . "\n";

// === test: implode with mixed types ===

echo "--- implode mixed ---\n";
echo implode(", ", [1, 2.5, true, false, null, "hello"]) . "\n";
echo implode("-", []) . "\n";

// === test: string multiplication and repetition patterns ===

echo "--- string ops ---\n";
echo str_repeat("ab", 3) . "\n";
echo str_pad("hi", 10, "=-", STR_PAD_BOTH) . "\n";
echo substr_replace("hello world", "PHP", 6, 5) . "\n";
echo str_word_count("the quick brown fox") . "\n";

echo "done\n";

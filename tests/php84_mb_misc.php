<?php
// PHP 8.4 mb_trim/mb_ltrim/mb_rtrim
echo function_exists("mb_trim") ? "y" : "n", "\n";
echo function_exists("mb_ltrim") ? "y" : "n", "\n";
echo function_exists("mb_rtrim") ? "y" : "n", "\n";
echo function_exists("mb_ucfirst") ? "y" : "n", "\n";
echo function_exists("mb_lcfirst") ? "y" : "n", "\n";

// mb_trim default (whitespace)
echo "[", mb_trim("  hello  "), "]\n";
echo "[", mb_trim("\t\nfoo\r\n\t"), "]\n";
// mb_trim with chars
echo "[", mb_trim("...hello...", "."), "]\n";
echo "[", mb_trim("xxhelloxx", "x"), "]\n";

// mb_ltrim
echo "[", mb_ltrim("  hello  "), "]\n";
echo "[", mb_ltrim("xxhelloxx", "x"), "]\n";

// mb_rtrim
echo "[", mb_rtrim("  hello  "), "]\n";
echo "[", mb_rtrim("xxhelloxx", "x"), "]\n";

// multibyte
echo "[", mb_trim("éémainéé", "é"), "]\n";

// mb_ucfirst / mb_lcfirst
echo mb_ucfirst("hello"), "\n";       // Hello
echo mb_ucfirst("héllo"), "\n";       // Héllo
echo mb_ucfirst(""), "|\n";
echo mb_lcfirst("Hello"), "\n";       // hello
echo mb_lcfirst("HELLO"), "\n";       // hELLO
echo mb_lcfirst("Über"), "\n";        // über

// PHP 8.3 str_increment / str_decrement
echo function_exists("str_increment") ? "y" : "n", "\n";
echo function_exists("str_decrement") ? "y" : "n", "\n";

// Random\Randomizer (PHP 8.2+)
echo class_exists("Random\\Randomizer") ? "y" : "n", "\n";

// Closure::call() vs ->call()
class C { private int $x = 5; }
$cl = function () { return $this->x; };
$bound = Closure::bind($cl, new C, C::class);
echo $bound(), "\n"; // 5

// Use ->call() - more compact
$cl2 = function () { return $this->x; };
echo $cl2->call(new C), "\n"; // 5

// PHP 8.4: array spread with string keys
$base = ["a" => 1, "b" => 2];
$over = ["b" => 99, "c" => 3];
$merged = [...$base, ...$over];
print_r($merged);

// new feature: Property hooks (PHP 8.4)
class Person {
    public string $fullName {
        get => "John " . $this->lastName;
    }
    public function __construct(public string $lastName) {}
}
echo (new Person("Doe"))->fullName, "\n";

// PHP 8.4: asymmetric visibility
class Bag {
    public private(set) array $items = [];
    public function add(string $i): void { $this->items[] = $i; }
}
$b = new Bag;
$b->add("apple");
$b->add("banana");
print_r($b->items);
try { $b->items = []; echo "no\n"; } catch (\Error $e) { echo "cant-set\n"; }

// PHP 8.4: new MyClass()->method() (no parens)
class Builder {
    public static function make(): self { return new self; }
    public function name(): string { return "B"; }
}
echo (new Builder())->name(), "\n";
echo Builder::make()->name(), "\n";
echo new Builder()->name(), "\n"; // PHP 8.4 (zphp may not support)

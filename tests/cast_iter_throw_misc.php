<?php
// stream_filter_register / stream filters
$path = sys_get_temp_dir() . "/zphp_sf_" . getmypid();
file_put_contents($path, "hello\n");

$h = fopen($path, "r");
$data = "";
while (!feof($h)) {
    $data .= fread($h, 1024);
}
fclose($h);
echo $data;

// Symbolic methods
class A {
    public function __toString(): string { return "[A]"; }
}
echo (string)(new A), "\n";
echo "wrapped:" . new A . ":end\n";

// __toString throwing
class Bad {
    public function __toString(): string { throw new RuntimeException("nope"); }
}
try { echo (string)(new Bad); } catch (\RuntimeException $e) { echo "caught:", $e->getMessage(), "\n"; }

// Iterator protocol with throw in current()
class BadIter implements Iterator {
    private int $i = 0;
    public function rewind(): void { $this->i = 0; }
    public function valid(): bool { return $this->i < 3; }
    public function current(): mixed {
        if ($this->i === 1) throw new RuntimeException("at $this->i");
        return $this->i;
    }
    public function key(): mixed { return $this->i; }
    public function next(): void { $this->i++; }
}
try {
    foreach (new BadIter as $v) echo "$v ";
} catch (\RuntimeException $e) { echo "iter-err:", $e->getMessage(), "\n"; }

// generator that yields and throws
function bad_gen() {
    yield 1;
    throw new RuntimeException("from gen");
}
try {
    foreach (bad_gen() as $v) echo "$v ";
} catch (\RuntimeException $e) { echo "gen-err:", $e->getMessage(), "\n"; }

// nested generators with throw in inner
function inner() {
    yield 10;
    throw new RuntimeException("inner-throw");
}
function outer() {
    yield 1;
    yield from inner();
    yield 99; // never reached
}
try {
    foreach (outer() as $v) echo "$v ";
} catch (\RuntimeException $e) { echo "nest-err:", $e->getMessage(), "\n"; }

// ArrayAccess returning bool from offsetExists
class AA implements ArrayAccess {
    private array $data = ["a" => 1, "b" => null, "c" => 0];
    public function offsetExists($k): bool { return array_key_exists($k, $this->data); }
    public function offsetGet($k): mixed { return $this->data[$k] ?? null; }
    public function offsetSet($k, $v): void { $this->data[$k] = $v; }
    public function offsetUnset($k): void { unset($this->data[$k]); }
}
$a = new AA;
echo isset($a["a"]) ? "y" : "n", "|"; // user ArrayAccess: PHP only calls offsetExists, returns true
echo isset($a["b"]) ? "y" : "n", "|"; // PHP: only offsetExists called, true
echo isset($a["c"]) ? "y" : "n", "|"; // true
echo isset($a["x"]) ? "y" : "n", "\n"; // false

echo $a->offsetExists("b") ? "y" : "n", "\n";

// JSON edge: very long array
$big = range(1, 1000);
$j = json_encode($big);
echo strlen($j) > 1000 ? "ok\n" : "no\n";
$d = json_decode($j, true);
echo count($d), "\n";

// deeply nested ref-traversal not supported in zphp (architectural)

// JSON encode with options
echo json_encode(["url" => "https://example.com/path"]), "\n"; // escaped slash
echo json_encode(["url" => "https://example.com/path"], JSON_UNESCAPED_SLASHES), "\n";

echo json_encode(["x" => "héllo"]), "\n"; // unicode escape
echo json_encode(["x" => "héllo"], JSON_UNESCAPED_UNICODE), "\n";

echo json_encode([1,2,3], JSON_PRETTY_PRINT), "\n";
echo json_encode(["a"=>1,"b"=>2], JSON_PRETTY_PRINT), "\n";

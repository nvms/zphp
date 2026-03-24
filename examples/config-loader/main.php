<?php
// covers: heredoc/nowdoc, array destructuring (list, [...] = ..., keyed),
//   spread operator ([...$a, ...$b], fn(...$args)), named arguments,
//   pass-by-reference (&$param), first-class callable syntax (strlen(...)),
//   null coalescing assignment (??=), clone, type casting ((int), (string), (array)),
//   serialize/unserialize, preg_replace_callback, preg_split, switch/case,
//   static variables in functions, class constants, readonly properties,
//   date/time (date, time), sprintf, array_key_exists, array_merge

// --- config value with readonly ---

class ConfigValue
{
    public readonly string $key;
    public readonly mixed $value;
    public readonly string $type;

    public function __construct(string $key, mixed $value)
    {
        $this->key = $key;
        $this->value = $value;
        $this->type = gettype($value);
    }

    public function cast(string $to): mixed
    {
        return match ($to) {
            "int" => (int) $this->value,
            "float" => (float) $this->value,
            "string" => (string) $this->value,
            "bool" => (bool) $this->value,
            "array" => (array) $this->value,
            default => $this->value,
        };
    }
}

// --- config bag with class constants ---

class Config
{
    const SEPARATOR = ".";
    const MAX_DEPTH = 10;

    private array $data = [];
    private array $defaults = [];

    public function set(string $key, mixed $value): void
    {
        $this->data[$key] = $value;
    }

    public function get(string $key, mixed $default = null): mixed
    {
        return $this->data[$key] ?? $default;
    }

    public function has(string $key): bool
    {
        return array_key_exists($key, $this->data);
    }

    public function all(): array
    {
        return $this->data;
    }

    public function merge(array ...$sources): void
    {
        foreach ($sources as $source) {
            $this->data = [...$this->data, ...$source];
        }
    }

    public function setDefaults(array $defaults): void
    {
        $this->defaults = $defaults;
    }

    public function resolve(): array
    {
        $resolved = $this->defaults;
        foreach ($this->data as $k => $v) {
            $resolved[$k] = $v;
        }
        return $resolved;
    }
}

// --- parse helpers using pass-by-reference and static vars ---

function parseEnvLine(string $line, string &$key, string &$val): bool
{
    $line = trim($line);
    if ($line === "" || $line[0] === "#") return false;
    $pos = strpos($line, "=");
    if ($pos === false) return false;
    $key = trim(substr($line, 0, $pos));
    $val = trim(substr($line, $pos + 1));
    if (strlen($val) >= 2 && $val[0] === '"' && $val[strlen($val) - 1] === '"') {
        $val = substr($val, 1, strlen($val) - 2);
    }
    return true;
}

function generateId(): string
{
    static $counter = 0;
    $counter++;
    return sprintf("cfg_%04d", $counter);
}

// --- interpolation using preg_replace_callback ---

function interpolate(string $template, array $vars): string
{
    return preg_replace_callback('/\{\{(\w+)\}\}/', function ($matches) use ($vars) {
        $key = $matches[1];
        return $vars[$key] ?? "";
    }, $template);
}

// --- type coercion with switch ---

function coerceType(string $value): mixed
{
    switch (true) {
        case $value === "true":
            return true;
        case $value === "false":
            return false;
        case $value === "null":
            return null;
        case ctype_digit($value):
            return (int) $value;
        case is_numeric($value):
            return (float) $value;
        default:
            return $value;
    }
}

// === test: heredoc and nowdoc ===

$envContent = <<<'ENV'
# database config
DB_HOST=localhost
DB_PORT=5432
DB_NAME="my_database"
DB_DEBUG=true
DB_TIMEOUT=30
DB_RATE=0.75
EMPTY_VAL=
ENV;

$config = new Config();
$lines = preg_split('/\n/', $envContent);
$key = "";
$val = "";
foreach ($lines as $line) {
    if (parseEnvLine($line, $key, $val)) {
        $config->set($key, coerceType($val));
    }
}

echo "DB_HOST: " . $config->get("DB_HOST") . "\n";
echo "DB_PORT: " . $config->get("DB_PORT") . "\n";
echo "DB_NAME: " . $config->get("DB_NAME") . "\n";
echo "DB_DEBUG: " . ($config->get("DB_DEBUG") === true ? "bool:true" : "other") . "\n";
echo "DB_TIMEOUT type: " . gettype($config->get("DB_TIMEOUT")) . "\n";
echo "DB_RATE type: " . gettype($config->get("DB_RATE")) . "\n";
echo "missing: " . ($config->get("NOPE", "fallback")) . "\n";

// === test: heredoc with interpolation ===

$name = "zphp";
$version = "0.1.0";
$banner = <<<BANNER
Welcome to $name v$version
Built on {$name}
BANNER;
echo $banner . "\n";

// === test: array destructuring ===

$pair = ["host", "localhost"];
[$dKey, $dVal] = $pair;
echo "destructured: $dKey=$dVal\n";

$record = ["name" => "Alice", "age" => 30, "role" => "admin"];
["name" => $n, "age" => $a, "role" => $r] = $record;
echo "keyed: $n is $a ($r)\n";

$nested = [[1, 2], [3, 4]];
[[$a1, $a2], [$b1, $b2]] = $nested;
echo "nested: $a1,$a2,$b1,$b2\n";

list($x, , $z) = [10, 20, 30];
echo "list skip: $x,$z\n";

// === test: spread operator ===

$base = ["app" => "myapp", "debug" => false];
$override = ["debug" => true, "version" => "1.0"];
$merged = [...$base, ...$override];
echo "spread merge: " . $merged["app"] . " debug=" . ($merged["debug"] ? "true" : "false") . " v=" . $merged["version"] . "\n";

function joinAll(string $sep, string ...$parts): string
{
    return implode($sep, $parts);
}

$items = ["a", "b", "c"];
echo "spread call: " . joinAll("-", ...$items) . "\n";

// === test: named arguments ---

function formatEntry(string $key, string $value, string $separator = ": "): string
{
    return $key . $separator . $value;
}

echo "named: " . formatEntry(value: "bar", key: "foo") . "\n";
echo "named sep: " . formatEntry(key: "x", value: "y", separator: " = ") . "\n";

// === test: first-class callable syntax ===

$trimmer = trim(...);
echo "callable: " . $trimmer("  hello  ") . "\n";

$values = ["  foo ", " bar  ", "  baz"];
$trimmed = array_map(trim(...), $values);
echo "map callable: " . implode(",", $trimmed) . "\n";

// === test: null coalescing assignment ===

$settings = [];
$settings["theme"] ??= "dark";
$settings["theme"] ??= "light";
echo "nullish: " . $settings["theme"] . "\n";

// === test: clone ===

$original = new Config();
$original->set("key1", "val1");
$original->set("key2", "val2");

$cloned = clone $original;
$cloned->set("key1", "modified");

echo "original: " . $original->get("key1") . "\n";
echo "cloned: " . $cloned->get("key1") . "\n";

// === test: type casting ===

$cv = new ConfigValue("port", "8080");
echo "readonly: " . $cv->key . " type=" . $cv->type . "\n";
echo "cast int: " . $cv->cast("int") . "\n";
echo "cast float: " . $cv->cast("float") . "\n";

$cv2 = new ConfigValue("flag", "1");
echo "cast bool: " . ($cv2->cast("bool") ? "true" : "false") . "\n";

// === test: serialize/unserialize ===

$data = ["host" => "localhost", "port" => 5432, "debug" => true];
$serialized = serialize($data);
echo "serialized: " . (strlen($serialized) > 0 ? "ok" : "empty") . "\n";
$restored = unserialize($serialized);
echo "restored: " . $restored["host"] . " port=" . $restored["port"] . "\n";

// === test: preg_replace_callback for template interpolation ===

$template = "Hello {{name}}, welcome to {{place}}!";
$vars = ["name" => "World", "place" => "zphp"];
echo interpolate($template, $vars) . "\n";

// === test: static variables ===

echo generateId() . "\n";
echo generateId() . "\n";
echo generateId() . "\n";

// === test: class constants ===

echo "separator: " . Config::SEPARATOR . "\n";
echo "max depth: " . Config::MAX_DEPTH . "\n";

// === test: merge with spread and resolve with defaults ===

$config2 = new Config();
$config2->setDefaults(["timeout" => 30, "retries" => 3, "host" => "0.0.0.0"]);
$config2->merge(
    ["host" => "127.0.0.1", "port" => 8080],
    ["debug" => true]
);
$resolved = $config2->resolve();
echo "resolved: host=" . $resolved["host"] . " port=" . $resolved["port"] . " timeout=" . $resolved["timeout"] . " debug=" . ($resolved["debug"] ? "yes" : "no") . "\n";

// === test: date/time ===

$ts = mktime(14, 30, 0, 6, 15, 2025);
echo "date: " . date("Y-m-d", $ts) . "\n";
echo "time: " . date("H:i:s", $ts) . "\n";

// === test: sprintf ===

echo sprintf("config has %d entries, version %s\n", 7, "1.0");

echo "done\n";

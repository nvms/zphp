<?php
// covers: json_encode/decode flags, unicode escaping, float precision,
//   nested depth, object vs array, JsonSerializable, error reporting,
//   integer overflow handling, big numbers as strings

class Point implements JsonSerializable {
    public function __construct(public float $x, public float $y) {}
    public function jsonSerialize(): array {
        return ['x' => $this->x, 'y' => $this->y, '__type' => 'point'];
    }
}

echo "=== basic encode/decode round-trip ===\n";
$data = [
    'string' => "hello",
    'unicode' => "héllo 世界",
    'int' => 42,
    'neg' => -7,
    'float' => 3.14,
    'bool' => true,
    'null' => null,
    'array' => [1, 2, 3],
    'object' => ['nested' => true],
];
$json = json_encode($data);
echo "encoded length: " . strlen($json) . "\n";
$back = json_decode($json, true);
echo "round-trip ok: " . ($back === $data ? "yes" : "no") . "\n";

echo "\n=== unicode escaping ===\n";
echo "default (escaped): " . json_encode("café") . "\n";
echo "unescaped: " . json_encode("café", JSON_UNESCAPED_UNICODE) . "\n";
echo "slashes unescaped: " . json_encode("https://example.com/path", JSON_UNESCAPED_SLASHES) . "\n";
echo "pretty:\n" . json_encode(['a' => 1, 'b' => [2, 3]], JSON_PRETTY_PRINT) . "\n";

echo "\n=== forced object syntax for empty/numeric arrays ===\n";
echo "empty as array: " . json_encode([]) . "\n";
echo "empty as object: " . json_encode(new stdClass()) . "\n";
echo "force object on empty: " . json_encode([], JSON_FORCE_OBJECT) . "\n";
echo "numeric list as object: " . json_encode([1, 2, 3], JSON_FORCE_OBJECT) . "\n";

echo "\n=== decode object vs assoc ===\n";
$j = '{"a":1,"b":2}';
$obj = json_decode($j);
echo "decoded as object: type=" . gettype($obj) . " a=" . $obj->a . "\n";
$arr = json_decode($j, true);
echo "decoded assoc: type=" . gettype($arr) . " a=" . $arr['a'] . "\n";

echo "\n=== JsonSerializable ===\n";
$p = new Point(1.5, 2.5);
echo json_encode($p) . "\n";
echo json_encode([new Point(1, 2), new Point(3, 4)]) . "\n";

echo "\n=== nested depth ===\n";
$nested = $build = [];
$ref = &$nested;
for ($i = 0; $i < 5; $i++) {
    $ref['child'] = [];
    $ref = &$ref['child'];
}
$ref['leaf'] = true;
unset($ref);
echo "deep encode ok: " . (json_encode($nested) !== false ? "yes" : "no") . "\n";

$decoded = json_decode(json_encode($nested), true);
echo "decode default depth ok: " . ($decoded !== null ? "yes" : "no") . "\n";

echo "\n=== invalid JSON ===\n";
$invalid = ['{', '}', '{"a":}', 'undefined', '{"a": 1,}'];
foreach ($invalid as $j) {
    $r = json_decode($j, true);
    echo sprintf("  %-15s -> %s (err: %s)\n", $j, var_export($r, true), json_last_error_msg());
}

echo "\n=== json_last_error after valid decode ===\n";
json_decode('[]');
echo "error: " . json_last_error() . " msg: " . json_last_error_msg() . "\n";

echo "\n=== float precision ===\n";
echo json_encode(1.5) . "\n";
echo json_encode(1.0) . "\n";
echo json_encode(0.1 + 0.2) . "\n";
echo json_encode(1.7976931348623157e+308) . "\n";

echo "\n=== integer edge cases ===\n";
echo "max int: " . json_encode(PHP_INT_MAX) . "\n";
echo "min int: " . json_encode(PHP_INT_MIN) . "\n";
echo "big number decode as string with flag: " . var_export(json_decode("9999999999999999999", true, 512, JSON_BIGINT_AS_STRING), true) . "\n";

echo "\n=== keys with special chars ===\n";
$keyed = ["key with spaces" => 1, "with\nnewline" => 2, "" => 3];
echo json_encode($keyed) . "\n";

echo "\n=== throw on error vs return false ===\n";
try {
    json_decode('not json', true, 512, JSON_THROW_ON_ERROR);
    echo "no throw\n";
} catch (JsonException $e) {
    echo "threw JsonException: " . $e->getMessage() . "\n";
}

try {
    $bad = "\xff\xfe";
    json_encode($bad, JSON_THROW_ON_ERROR);
    echo "no throw on invalid UTF-8\n";
} catch (JsonException $e) {
    echo "threw on bad utf-8: yes\n";
}

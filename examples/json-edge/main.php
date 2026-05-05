<?php
// covers: json_encode, json_decode, json_last_error, json_last_error_msg,
//   JSON_PRETTY_PRINT, JSON_UNESCAPED_SLASHES, JSON_UNESCAPED_UNICODE,
//   JSON_THROW_ON_ERROR, JSON_FORCE_OBJECT, JSON_PRESERVE_ZERO_FRACTION,
//   JsonException, var_export, gettype, is_array, is_object, is_string,
//   is_int, is_float, is_bool, is_null, str_repeat, strlen

function show(string $label, $val): void {
    $enc = json_encode($val);
    echo sprintf("  %-30s %s\n", $label, $enc === false ? '(false)' : $enc);
}

echo "=== scalar encoding ===\n";
show('null', null);
show('bool true', true);
show('bool false', false);
show('int zero', 0);
show('int negative', -42);
show('int max safe', PHP_INT_MAX);
show('float pi', 3.14);
show('float zero', 0.0);
show('float neg', -1.5);
show('float exponent', 1.5e10);
show('string empty', '');
show('string ascii', 'hello');
show('string with quote', 'say "hi"');
show('string newline', "line1\nline2");
show('string tab', "a\tb");
show('string backslash', "a\\b");
show('string slash', 'a/b');
show('string control', "x\x01y");
show('string null byte', "a\0b");
show('utf-8 ascii', 'café');
show('utf-8 emoji', '😀');

echo "\n=== array vs object encoding ===\n";
show('empty array', []);
show('list', [1, 2, 3]);
show('list with strings', ['a', 'b', 'c']);
show('hash', ['name' => 'ada', 'age' => 30]);
show('mixed keys (becomes obj)', [0 => 'a', 'k' => 'b']);
show('non-zero start (becomes obj)', [1 => 'a', 2 => 'b']);
show('non-sequential int keys', [0 => 'a', 2 => 'b']);
show('nested', ['users' => [['n' => 'a'], ['n' => 'b']]]);
show('deeply nested', [[[[[[[[[[42]]]]]]]]]]);

echo "\n=== flags ===\n";
echo "  pretty print:\n";
echo json_encode(['a' => 1, 'b' => [2, 3]], JSON_PRETTY_PRINT) . "\n";
echo "  unescaped slashes: " . json_encode('a/b/c', JSON_UNESCAPED_SLASHES) . "\n";
echo "  default escaping:  " . json_encode('a/b/c') . "\n";
echo "  unescaped unicode: " . json_encode('café', JSON_UNESCAPED_UNICODE) . "\n";
echo "  default unicode:   " . json_encode('café') . "\n";
echo "  force object on []: " . json_encode([], JSON_FORCE_OBJECT) . "\n";
echo "  force object on list: " . json_encode([1, 2], JSON_FORCE_OBJECT) . "\n";
echo "  preserve zero fraction: " . json_encode(1.0, JSON_PRESERVE_ZERO_FRACTION) . "\n";
echo "  default zero fraction:  " . json_encode(1.0) . "\n";

echo "\n=== decoding ===\n";
function decode_show(string $label, string $json, bool $assoc = true): void {
    $v = json_decode($json, $assoc);
    $err = json_last_error();
    if ($err !== JSON_ERROR_NONE) {
        echo "  $label: ERROR " . json_last_error_msg() . "\n";
        return;
    }
    $type = gettype($v);
    echo sprintf("  %-30s type=%-8s value=%s\n", $label, $type, var_export($v, true));
}
decode_show('null', 'null');
decode_show('true', 'true');
decode_show('false', 'false');
decode_show('zero', '0');
decode_show('neg int', '-7');
decode_show('float', '3.14');
decode_show('exponent', '1e2');
decode_show('string', '"hello"');
decode_show('escaped', '"a\\nb"');
decode_show('unicode escape', '"caf\\u00e9"');
decode_show('empty array', '[]');
decode_show('empty object (assoc)', '{}', true);
decode_show('list', '[1,2,3]');
decode_show('hash', '{"a":1,"b":2}');

echo "\n=== assoc vs object decode ===\n";
$json = '{"name":"x","age":30}';
$assoc = json_decode($json, true);
$obj = json_decode($json, false);
echo "  assoc is array: " . (is_array($assoc) ? 'yes' : 'no') . "\n";
echo "  obj is object: " . (is_object($obj) ? 'yes' : 'no') . "\n";
echo "  obj is stdClass: " . (get_class($obj)) . "\n";
echo "  obj->name: " . $obj->name . "\n";
echo "  assoc[name]: " . $assoc['name'] . "\n";

echo "\n=== roundtrip ===\n";
$cases = [
    null,
    true,
    false,
    0,
    -1,
    42,
    3.14,
    'hello',
    '',
    "a\nb\tc",
    [],
    [1, 2, 3],
    ['k' => 'v'],
    ['nested' => ['deep' => ['deeper' => 'leaf']]],
    [1, 'two', 3.0, null, true, [4, 5]],
];
foreach ($cases as $i => $v) {
    $encoded = json_encode($v);
    $decoded = json_decode($encoded, true);
    $re_encoded = json_encode($decoded);
    $ok = $encoded === $re_encoded ? 'ok' : 'FAIL';
    echo sprintf("  case %2d: %s (%s)\n", $i, $ok, $encoded);
}

echo "\n=== invalid json ===\n";
$bad = ['', '{', '}', '[', ']', '{,}', '{"a":}', 'undefined', "'single'", '+1', '.5'];
foreach ($bad as $b) {
    $v = json_decode($b);
    $err = json_last_error();
    echo sprintf("  [%-10s] -> %s err=%s\n",
        $b === '' ? '(empty)' : $b,
        var_export($v, true),
        $err === JSON_ERROR_NONE ? 'none' : 'set');
}

echo "\n=== JSON_THROW_ON_ERROR ===\n";
try {
    json_decode('{bad', false, 512, JSON_THROW_ON_ERROR);
    echo "  no exception (FAIL)\n";
} catch (JsonException $e) {
    echo "  caught JsonException\n";
}
try {
    json_encode("\xb1\x31", JSON_THROW_ON_ERROR);
    echo "  encode no exception\n";
} catch (JsonException $e) {
    echo "  caught encode JsonException\n";
}

echo "\n=== large nesting ===\n";
$deep = 'x';
$wrap = $deep;
for ($i = 0; $i < 50; $i++) $wrap = [$wrap];
$enc = json_encode($wrap);
echo "  encoded length: " . strlen($enc) . "\n";
echo "  starts with [: " . (substr($enc, 0, 1) === '[' ? 'yes' : 'no') . "\n";
$dec = json_decode($enc, true);
$cur = $dec;
$depth = 0;
while (is_array($cur) && isset($cur[0])) {
    $cur = $cur[0];
    $depth++;
}
echo "  decoded depth: $depth\n";
echo "  bottom value: " . var_export($cur, true) . "\n";

echo "\n=== large key count ===\n";
$big = [];
for ($i = 0; $i < 200; $i++) $big["key$i"] = $i;
$enc = json_encode($big);
$dec = json_decode($enc, true);
echo "  keys preserved: " . (count($dec) === 200 ? 'yes' : 'no') . "\n";
echo "  k_5 = " . ($dec['key5'] ?? 'missing') . "\n";
echo "  k_199 = " . ($dec['key199'] ?? 'missing') . "\n";

echo "\n=== numeric edge cases ===\n";
show('int 0 vs float 0.0', 0);
show('float 0.0', 0.0);
show('float .5', 0.5);
show('huge int', 9007199254740993);
show('negative zero float', -0.0);
show('very small float', 1e-300);
show('very large float', 1e300);

echo "\n=== string escape coverage ===\n";
$tricky = "\x00\x01\x02\b\t\n\f\r\"\\";
$enc = json_encode($tricky);
echo "  encoded: $enc\n";
$dec = json_decode($enc);
echo "  roundtrip equal: " . ($dec === $tricky ? 'yes' : 'no') . "\n";
echo "  decoded length: " . strlen($dec) . "\n";

echo "\n=== unicode escape decode ===\n";
$inputs = [
    '"\\u0041"',           // A
    '"\\u00e9"',           // é
    '"\\u4e2d"',           // 中
    '"\\ud83d\\ude00"',    // 😀 (surrogate pair)
];
foreach ($inputs as $s) {
    $v = json_decode($s);
    echo sprintf("  %-25s -> [%s] len=%d\n", $s, $v, strlen($v));
}

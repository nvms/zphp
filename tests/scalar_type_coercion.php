<?php
// php's rules for scalar parameter and return types: which values pass,
// which coerce in weak mode, and what strict mode allows

function attempt(callable $f, ...$args): void
{
    try {
        var_dump($f(...$args));
    } catch (TypeError $e) {
        echo preg_replace('/, called in .*/', '', $e->getMessage()), "\n";
    }
}

class Text { public function __toString(): string { return "text"; } }

function to_int(int $v) { return $v; }
function to_float(float $v) { return $v; }
function to_bool(bool $v) { return $v; }
function to_string(string $v) { return $v; }
function to_number(int|float $v) { return $v; }
function to_int_or_string(int|string $v) { return $v; }
function to_array_or_true(array|true $v) { return $v; }
function returns_int($v): int { return $v; }
function returns_array_or_false($v): array|false { return $v; }

foreach (['to_int', 'to_float', 'to_bool', 'to_string', 'to_number', 'to_int_or_string', 'to_array_or_true'] as $f) {
    echo "-- $f\n";
    foreach ([1, 1.0, 1.5, "1", "1.5", "1e2", " 7 ", "7x", "", true, null, [], new Text, NAN, PHP_INT_MAX] as $v) {
        attempt($f, $v);
    }
}

echo "-- returns\n";
attempt('returns_int', "12");
attempt('returns_int', 3.0);
attempt('returns_int', "abc");
attempt('returns_array_or_false', 0);
attempt('returns_array_or_false', false);

echo "-- strict mode\n";
$code = '<?php ' . 'declare' . '(strict_types=1); return function () {
    foreach (["to_int" => "1", "to_float" => 1, "to_bool" => 1, "to_string" => new Text, "to_number" => "5"] as $f => $v) {
        try { var_dump($f($v)); } catch (TypeError $e) { echo preg_replace("/, called in .*/", "", $e->getMessage()), "\n"; }
    }
};';
$file = tempnam(sys_get_temp_dir(), 'stc');
file_put_contents($file, $code);
$fn = require $file;
unlink($file);
$fn();

echo "-- named arguments skipping defaults\n";
class Defaults
{
    public static function make(string $a, string $b = 'b', bool $c = true, ?bool $d = false) { var_dump($b, $c, $d); }
}
Defaults::make('a', d: true);
Defaults::make('a', 'x', d: null);

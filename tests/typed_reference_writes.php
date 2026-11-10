<?php
// a reference bound to a typed property checks and coerces every write made
// through any of its aliases

class Box
{
    public int $count = 1;
    public ?string $label = null;
    public float $ratio = 1.5;
    public $loose;
    public static int $shared = 3;
}

function attempt(callable $write): void
{
    try {
        $write();
    } catch (TypeError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

$box = new Box;
$ref = &$box->count;

echo "-- assignment\n";
$ref = "5";
var_dump($box->count);
attempt(function () use (&$ref) { $ref = "five"; });
var_dump($box->count, $ref);

echo "-- compound assignment\n";
$ref += 1.0;
var_dump($box->count);
$ref .= "1";
var_dump($box->count);
attempt(function () use (&$ref) { $ref .= "e50"; });
var_dump($box->count);

echo "-- increment and decrement\n";
$ref = PHP_INT_MAX;
attempt(function () use (&$ref) { $ref++; });
attempt(function () use (&$ref) { ++$ref; });
var_dump($ref);
$ref = PHP_INT_MIN;
attempt(function () use (&$ref) { $ref--; });
attempt(function () use (&$ref) { --$ref; });
var_dump($ref);
$ref = 10;
$ref++;
--$ref;
var_dump($box->count);

echo "-- by-reference argument\n";
function assign(&$target, $value) { $target = $value; }
attempt(function () use ($box) { assign($box->count, "abc"); });
assign($box->count, "12");
var_dump($box->count);

echo "-- array element holding the reference\n";
$list = [&$box->count];
attempt(function () use (&$list) { $list[0] = null; });
$list[0] = 2.0;
var_dump($box->count);
$list[0]++;
var_dump($box->count);

echo "-- property holding the reference\n";
$box->loose = &$box->count;
attempt(function () use ($box) { $box->loose = []; });
$box->loose = "7";
var_dump($box->count, $box->loose);

echo "-- static property\n";
$static = &Box::$shared;
attempt(function () use (&$static) { $static = "q"; });
$static = "9";
var_dump(Box::$shared);

echo "-- foreach by reference over an object\n";
foreach ($box as $name => &$value) {
    if ($name === 'ratio') {
        attempt(function () use (&$value) { $value = "nope"; });
        $value = 3;
    }
}
unset($value);
var_dump($box->ratio);

echo "-- destructuring into a reference\n";
$source = [1];
[&$box->count] = $source;
attempt(function () use (&$source) { $source[0] = "w"; });
$source[0] = "40";
var_dump($box->count);

echo "-- internal function writing a by-reference argument\n";
attempt(function () use ($box) { preg_match('/a/', 'a', $box->count); });
var_dump($box->count);

echo "-- strict types\n";
$strict = '<?php ' . 'declare' . '(strict_types=1); return function (&$r) { try { $r = "1"; } catch (TypeError $e) { echo $e->getMessage(), "\n"; } $r = 2; };';
$file = tempnam(sys_get_temp_dir(), 'tref');
file_put_contents($file, $strict);
$fn = require $file;
unlink($file);
$float = &$box->ratio;
$fn($float);
var_dump($box->ratio);

echo "-- unset leaves the reference untyped\n";
unset($ref, $list, $static, $float);
$plain = &$box->label;
unset($box->label);
$plain = [1];
var_dump($plain);

echo "-- stepping a property that holds a typed reference\n";
class Pair { public int $a = 0; public int|bool $b = 0; }
$pair = new Pair;
$alias = &$pair->a;
$pair->a = PHP_INT_MAX;
attempt(function () use ($pair) { $pair->a++; });
attempt(function () use ($pair) { --$pair->b; $pair->b = PHP_INT_MIN; $pair->b--; });
$other = &$pair->b;
attempt(function () use ($pair) { $pair->b--; });
var_dump($pair->a, $pair->b);

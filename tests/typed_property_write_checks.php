<?php
// writes to typed properties: php's coercion rules, ++/-- past the int
// range, and static properties

class Counter
{
    public int $n = 0;
    public int|bool $flag = 0;
    public bool $bool = false;
    public float $float = 0.0;
    public string $string = "";
    public ?Counter $next = null;
    public self|int $selfish = 0;
    public static int $total = 0;
    public static ?string $name = null;
}

function check(callable $f): void
{
    try {
        $f();
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}

$c = new Counter;
$c->n = PHP_INT_MAX;
check(function () use ($c) { $c->n++; });
check(function () use ($c) { ++$c->n; });
var_dump($c->n);
$c->n = PHP_INT_MIN;
check(function () use ($c) { $c->n--; });
check(function () use ($c) { --$c->n; });
var_dump($c->n);
$c->flag = PHP_INT_MAX;
check(function () use ($c) { $c->flag++; });
$c->float = PHP_INT_MAX;
$c->float++;
var_dump($c->float);

$c->bool = 5;
$c->string = 1.5;
$c->float = "2";
var_dump($c->bool, $c->string, $c->float);
check(function () use ($c) { $c->next = new stdClass; });
$c->selfish = new Counter;
var_dump($c->selfish instanceof Counter);
check(function () use ($c) { $c->selfish = new stdClass; });

Counter::$total = "5";
var_dump(Counter::$total);
check(function () { Counter::$total = "five"; });
check(function () { Counter::$total = []; });
Counter::$total = PHP_INT_MAX;
check(function () { Counter::$total++; });
var_dump(Counter::$total);
Counter::$total = 1;
Counter::$total += 2;
var_dump(Counter::$total);
check(function () { Counter::$total .= "x"; });
Counter::$name = 12;
var_dump(Counter::$name);
$prop = 'total';
check(function () use ($prop) { Counter::$$prop = "nope"; });
var_dump(Counter::$total);

$code = '<?php ' . 'declare' . '(strict_types=1); return function (Counter $c) {
    foreach (["bool" => 1, "string" => 1, "float" => 1, "n" => 1.0, "n" => "1"] as $p => $v) {
        try { $c->$p = $v; echo "$p ok\n"; } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
    }
    var_dump($c->float);
};';
$file = tempnam(sys_get_temp_dir(), 'tpw');
file_put_contents($file, $code);
$fn = require $file;
unlink($file);
$fn(new Counter);

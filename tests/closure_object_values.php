<?php
// a closure is a Closure object everywhere a value goes: conversions,
// comparisons, array keys, serialization, identity and cloning
$x = 5;
$f = function ($a) use ($x) { return $a + $x; };
$g = fn ($y) => $y * $x;

function attempt(callable $body): void
{
    try {
        $body();
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

attempt(fn () => print("x" . $f . "\n"));
attempt(fn () => print((string) $f));
attempt(fn () => strlen($f));
attempt(fn () => str_repeat($f, 2));
attempt(fn () => strval($f));
attempt(function () use ($f) { $a = []; $a[$f] = 1; });
attempt(function () use ($f) { $a = [1]; echo $a[$f]; });
attempt(fn () => array_key_exists($f, []));
attempt(fn () => serialize($f));
attempt(fn () => serialize([1, $f]));
echo json_encode($f), " ", json_encode(['cb' => $f]), "\n";
var_export($f);
echo "\n";
var_dump($f == $f, $f == $g, $f === $f, $f == "abc", $f != null);
attempt(fn () => var_dump($f < $g));
var_dump(gettype($f), get_debug_type($f), is_object($f), is_string($f), is_scalar($f), is_callable($f));
var_dump($f instanceof Closure, $f instanceof stdClass, $f::class, get_class($f));
$copy = $f;
settype($copy, "array");
var_dump(count($copy), $copy[0] === $f);
$copy = $f;
attempt(function () use (&$copy) { settype($copy, "string"); });
var_dump((array) $g === [$g]);
$items = [1, 2, 3];
array_splice($items, 1, 1, $f);
var_dump($items[1] === $f, count($items));
var_dump(spl_object_id($f) !== spl_object_id($g), spl_object_hash($f) === spl_object_hash($f));
$c = clone $f;
var_dump($c(1), $c === $f, $c == $f, spl_object_id($c) !== spl_object_id($f));
$s = new SplObjectStorage();
$s[$f] = "first";
$s[$g] = "second";
var_dump(count($s), $s[$f]);
$w = new WeakMap();
$w[$f] = 1;
var_dump(count($w));
$tmp = function () {};
$w[$tmp] = 2;
var_dump(count($w));
unset($tmp);
var_dump(count($w));
attempt(fn () => $f->prop = 1);
attempt(fn () => new Closure());
var_dump(method_exists($f, '__invoke'), method_exists($f, 'bindTo'), method_exists('Closure', 'call'));
var_dump(array_map(fn ($c) => $c(1), [$f, $g]));
var_dump(in_array($g, [$f, $g], true), array_search($g, [$f, $g], true));
echo implode(",", array_map('gettype', [$f, $g, 'strlen'])), "\n";
var_dump(sprintf("%d", spl_object_id($f)) === (string) spl_object_id($f));
match (true) { default => print("matched\n") };
attempt(fn () => match ($f) { 1 => 1 });
$n = 0;
$byRef = function (&$v) { $v++; };
$byRef->__INVOKE($n);
$byRef->__invoke($n);
var_dump($n);

<?php
// range, array_column and count/sizeof as php's array.c does them, and the
// internal pointer after array_pop and array_shift
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });
function t(callable $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

t(fn() => range(1, 2, 0.5));
t(fn() => range(1, 5, 2.0));
t(fn() => range(1.5, 0, 0.5));
t(fn() => range("a", "e", 2));
t(fn() => range("z", "w"));
t(fn() => range("1", "3"));
t(fn() => range("1", "2", 0.5));
t(fn() => range("A", "B", 0.5));
t(fn() => range("ab", "cd"));
t(fn() => range("", "c"));
t(fn() => range("a", 5));
t(fn() => range(null, 2));
t(fn() => range(0, 10, -2));
t(fn() => range(10, 0, -3));
t(fn() => range(1, 2, 0));
t(fn() => range(1, 2, 5));
t(fn() => range(1, INF));
t(fn() => range(NAN, 1));
t(fn() => range(0, PHP_INT_MAX));
t(fn() => range(0.0, 1e12, 0.1));
t(fn() => range([], 1));
t(fn() => range(1, 2, "x"));
t(fn() => count(range(1, 3, 1.0)));

class Row {
    public $id;
    public $name = "pub";
    private $secret = "s";
    function __construct($id) { $this->id = $id; }
}
class Magic {
    private $hidden = "h";
    function __isset($n) { return $n === "hidden" || $n === "virt"; }
    function __get($n) { return "__get($n)"; }
}
$rows = [["id" => 3, "v" => null, "x" => "a"], ["id" => 4, "x" => "b"], new Row(5), "scalar", [1 => "one"]];
t(fn() => array_column($rows, "v"));
t(fn() => array_column($rows, "x", "id"));
t(fn() => array_column($rows, null, "id"));
t(fn() => array_column($rows, 1));
t(fn() => array_column([new Row(1)], "secret"));
t(fn() => array_column([new Magic, new Magic], "hidden"));
t(fn() => array_column([new Magic], "virt"));
t(fn() => array_column($rows, []));
t(fn() => array_column($rows, "id", false));
t(fn() => array_column([["a" => 1, "k" => [1]]], "a", "k"));

$nested = [1, [2, [3, 4]], 5];
t(fn() => count($nested, COUNT_RECURSIVE));
t(fn() => sizeof($nested, 1));
t(fn() => count($nested, 5));
t(fn() => sizeof(new Row(1)));
class Cnt implements Countable { function count(): int { return 7; } }
t(fn() => sizeof(new Cnt));

$a = [1, 2, 3, 4];
next($a); next($a);
array_pop($a);
var_dump(current($a));
next($a);
array_shift($a);
var_dump(current($a));

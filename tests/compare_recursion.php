<?php
// comparing values that contain themselves: php protects the first operand
// while it compares it and throws "Nesting level too deep" on meeting it again

class Test
{
    public $x = 5;
}

$a = new Test();
$b = new Test();
$a->x = $a;
$b->x = $b;

function attempt(string $label, callable $fn)
{
    try {
        var_dump($fn());
    } catch (Error $e) {
        echo $label, ": ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}

attempt("objects ==", fn() => $a == $b);
attempt("objects !=", fn() => $a != $b);
attempt("objects <", fn() => $a < $b);
attempt("objects <=>", fn() => $a <=> $b);
// the same object compares equal without looking inside
attempt("same object", fn() => $a == $a);

$x = [1];
$x[] = &$x;
$y = [1];
$y[] = &$y;
attempt("arrays ==", fn() => $x == $y);
attempt("arrays ===", fn() => $x === $y);
attempt("arrays <", fn() => $x < $y);
attempt("same array", fn() => $x == $x);
attempt("in_array", fn() => in_array($y, [$x]));

// after an error comparisons work again
$c = new Test();
$d = new Test();
var_dump($c == $d, [1, [2]] == [1, [2]], [1, [2]] === [1, [3]]);

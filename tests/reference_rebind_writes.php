<?php
// a property, static property or array element bound to a reference, written
// directly (plain and compound assignment, ++/--), then rebound to another
// reference: every name keeps its own value and nothing is freed twice

class C {
    public $p;
    public string $s = "";
    public int $i = 0;
    public ?array $a = null;
    public static $sp;
    public static string $ss = "";
}

function show(string $label, ...$values) {
    echo $label, ": ";
    foreach ($values as $v) echo json_encode($v), " ";
    echo "\n";
}

// untyped property
unset($c, $x, $y);
$c = new C;
$x = str_repeat("a", 2);
$y = str_repeat("b", 2);
$c->p = &$x;
$c->p .= "!";
$c->p = &$y;
$c->p .= "?";
show("concat", $c->p, $x, $y);

unset($c, $x, $y);
$c = new C;
$x = str_repeat("a", 2);
$y = 1;
$c->p = &$x;
$c->p = str_repeat("z", 3);
$c->p = &$y;
$c->p += 5;
show("assign", $c->p, $x, $y);

unset($c, $x, $y);
$c = new C;
$x = str_repeat("4", 2);
$y = 9;
$c->p = &$x;
$c->p++;
$c->p = &$y;
$c->p--;
show("incdec", $c->p, $x, $y);

unset($c, $x, $y);
$c = new C;
$x = null;
$y = [1];
$c->p = &$x;
$c->p ??= str_repeat("n", 2);
$c->p = &$y;
$c->p[] = str_repeat("e", 2);
show("coalesce", $c->p, $x, $y);

// a property holding an owned value, then bound
unset($c, $x, $y);
$c = new C;
$c->p = str_repeat("o", 4);
$y = "b";
$c->p = &$y;
show("owned", $c->p, $y);

unset($c, $x, $y);
$c = new C;
$c->p = [str_repeat("o", 4)];
$y = "b";
$c->p = &$y;
show("owned array", $c->p, $y);

unset($c, $x, $y);
$c = new C;
$c->p = new stdClass;
$y = "b";
$c->p = &$y;
show("owned object", $c->p, $y);

// rebinding to the same reference
unset($c, $x, $y);
$c = new C;
$x = str_repeat("s", 2);
$c->p = &$x;
$c->p .= "!";
$c->p = &$x;
$c->p .= "?";
show("same", $c->p, $x);

// typed properties
unset($c, $x, $y);
$c = new C;
$x = str_repeat("t", 2);
$y = str_repeat("u", 2);
$c->s = &$x;
$c->s .= 5;
$c->s = &$y;
$c->s .= "!";
show("typed string", $c->s, $x, $y);

unset($c, $x, $y);
$c = new C;
$x = 1;
$y = 2;
$c->i = &$x;
$c->i *= 10;
$c->i = &$y;
$c->i++;
show("typed int", $c->i, $x, $y);

unset($c, $x, $y);
$c = new C;
$x = [str_repeat("v", 2)];
$y = [];
$c->a = &$x;
$c->a[] = str_repeat("w", 2);
$c->a = &$y;
$c->a[] = 1;
show("typed array", $c->a, $x, $y);

// static properties
unset($c, $x, $y);
$x = str_repeat("a", 2);
$y = str_repeat("b", 2);
C::$sp = &$x;
C::$sp .= "!";
C::$sp = &$y;
C::$sp .= "?";
show("static", C::$sp, $x, $y);

$x = str_repeat("c", 2);
$y = str_repeat("d", 2);
C::$ss = &$x;
C::$ss .= "!";
C::$ss = &$y;
C::$ss = str_repeat("e", 3);
show("typed static", C::$ss, $x, $y);

// array elements
unset($x, $y);
$a = [];
$x = str_repeat("a", 2);
$y = str_repeat("b", 2);
$a["k"] = &$x;
$a["k"] .= "!";
$a["k"] = &$y;
$a["k"] .= "?";
show("element", $a, $x, $y);

$a = ["k" => str_repeat("o", 3)];
$y = str_repeat("7", 2);
$a["k"] = &$y;
$a["k"]++;
show("owned element", $a, $y);

// a property of an object held in an array, and an element of a property
unset($x, $y);
$list = [new C];
$x = str_repeat("a", 2);
$y = str_repeat("b", 2);
$list[0]->p = &$x;
$list[0]->p .= "!";
$list[0]->p = &$y;
show("nested object", $list[0]->p, $x, $y);

unset($c, $x, $y);
$c = new C;
$c->p = [];
$x = str_repeat("a", 2);
$y = str_repeat("b", 2);
$c->p["k"] = &$x;
$c->p["k"] .= "!";
$c->p["k"] = &$y;
$c->p["k"] .= "?";
show("nested element", $c->p, $x, $y);

// inside a function, where the bindings die with the frame
function inner() {
    $c = new C;
    $x = str_repeat("a", 2);
    $y = str_repeat("b", 2);
    $c->p = &$x;
    $c->p .= "!";
    $c->p = &$y;
    $c->p .= "?";
    return $c;
}
$r = inner();
show("returned", $r->p);
unset($r);
echo "done\n";

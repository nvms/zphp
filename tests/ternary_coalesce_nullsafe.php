<?php
echo (true ? "y" : "n"), "\n";
echo (false ? "y" : "n"), "\n";

// short ternary (Elvis)
echo "a" ?: "fallback", "\n";  // a
echo "" ?: "fallback", "\n";    // fallback
echo 0 ?: "z", "\n";            // z
echo null ?? "default", "\n";

// null coalesce chain
echo (null ?? null ?? "found"), "\n";  // found
echo (null ?? 0 ?? "x"), "\n";          // 0 (not null)
echo (false ?? "x"), "\n";              // false (not null)
echo (null ?? false ?? 0), "\n";        // false

// null coalesce assignment
$a = null;
$a ??= "first";
echo $a, "\n";
$a ??= "second";
echo $a, "\n"; // first

$b = 0;
$b ??= "x";
echo $b, "\n"; // 0

$c = false;
$c ??= "x";
var_dump($c); // false (kept)

// ?? with arrays
$arr = ["a" => 1];
echo $arr["a"] ?? "none", "\n";
echo $arr["b"] ?? "none", "\n";

// nullsafe -> chain
class A {
    public ?B $b = null;
    public function getB(): ?B { return $this->b; }
}
class B {
    public string $name = "b-name";
    public function getName(): string { return $this->name; }
}

$a = new A;
$r = $a?->b?->name;
echo $r ?? "null", "\n"; // null

$a->b = new B;
$r = $a?->b?->name;
echo $r, "\n"; // b-name

$r = $a?->getB()?->getName();
echo $r ?? "null", "\n"; // b-name

$a->b = null;
$r = $a?->getB()?->getName();
echo $r ?? "null", "\n"; // null

// nullsafe + array
$o = new stdClass;
$o->arr = ["x" => 1];
echo $o?->arr["x"] ?? "n", "\n"; // 1

$o = null;
echo $o?->arr["x"] ?? "n", "\n"; // n

// nested ternary - PHP 8 requires parens
echo (true ? 1 : (false ? 2 : 3)), "\n"; // 1
echo (false ? 1 : (true ? 2 : 3)), "\n"; // 2
echo (false ? 1 : (false ? 2 : 3)), "\n"; // 3

// short ternary chain
echo (null ?: "" ?: 0 ?: "last"), "\n"; // last

// ternary with assignments
$x = true ? 1 : 2;
echo $x, "\n";
$x = (true ? 1 : 2) + 10;
echo $x, "\n";

// ternary with array access
$arr = ["a" => 1, "b" => null];
echo $arr["a"] ?? "n", "\n"; // 1
echo $arr["b"] ?? "n", "\n"; // n (b is null)
echo $arr["c"] ?? "n", "\n"; // n (missing)

// nested null coalesce
$a = null;
$b = null;
$c = "found";
echo ($a ?? $b ?? $c), "\n"; // found

// null coalesce on nested array
$config = [
    "db" => [
        "host" => "localhost",
    ],
];
echo $config["db"]["host"] ?? "default", "\n";
echo $config["db"]["port"] ?? 5432, "\n";
echo $config["cache"]["host"] ?? "no-cache", "\n";

// nullsafe with method then array
class C {
    public function getArr(): array { return ["a" => 1]; }
}
$c = new C;
echo $c?->getArr()["a"] ?? "n", "\n"; // 1

$c = null;
echo $c?->getArr()["a"] ?? "n", "\n"; // n

// short-circuit doesn't evaluate right side
$called = 0;
$f = function () use (&$called) {
    $called++;
    return "from-fn";
};
$x = "yes" ?? $f();
echo $x, " called=", $called, "\n"; // yes called=0

$x = null ?? $f();
echo $x, " called=", $called, "\n"; // from-fn called=1

// ternary doesn't evaluate untaken branch
$called2 = 0;
$g = function () use (&$called2) {
    $called2++;
    return "g";
};
$y = true ? "x" : $g();
echo $y, " ", $called2, "\n";

$y = false ? $g() : "y";
echo $y, " ", $called2, "\n";

// nullsafe with non-existent prop returns null without warning
$obj = new stdClass;
$obj->name = "x";
echo $obj?->missing ?? "absent", "\n";

// nullsafe on null var
$nope = null;
$r = $nope?->anything()?->chain;
var_dump($r);

// short ternary with assignment chain
$arr = [];
$arr["k"] = "value";
echo ($arr["k"] ?: "fallback"), "\n";

// ?? on undefined var (no notice)
echo $never_defined_var ?? "undef", "\n";

// nested nullsafe with ?? mixing
$config = (object)["db" => null];
echo $config?->db?->host ?? "no-host", "\n";

$config = (object)["db" => (object)["host" => "h1"]];
echo $config?->db?->host ?? "no-host", "\n";

// chained method calls with null at any point
class D {
    public ?E $e = null;
    public function getE(): ?E { return $this->e; }
}
class E {
    public ?F $f = null;
    public function getF(): ?F { return $this->f; }
}
class F {
    public string $val = "F-val";
}
$d = new D;
$d->e = new E;
$d->e->f = new F;
echo $d?->getE()?->getF()?->val, "\n"; // F-val

$d->e->f = null;
echo $d?->getE()?->getF()?->val ?? "n", "\n"; // n

$d->e = null;
echo $d?->getE()?->getF()?->val ?? "n", "\n"; // n

$d = null;
echo $d?->getE()?->getF()?->val ?? "n", "\n"; // n

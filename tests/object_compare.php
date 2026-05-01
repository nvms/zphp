<?php

// DateTime comparison by timestamp
$a = new DateTime('2024-01-01');
$b = new DateTime('2024-06-01');
echo ($a < $b ? "<" : ">=") . "\n";
echo ($b > $a ? ">" : "<=") . "\n";
echo ($a == new DateTime('2024-01-01') ? "==" : "!=") . "\n";
echo ($a === new DateTime('2024-01-01') ? "id" : "not-id") . "\n";

// same-class objects with same props are equal
class Point { public function __construct(public int $x, public int $y) {} }
$p1 = new Point(1, 2);
$p2 = new Point(1, 2);
$p3 = new Point(1, 3);
echo ($p1 == $p2 ? "eq" : "ne") . "\n";
echo ($p1 == $p3 ? "eq" : "ne") . "\n";
echo ($p1 === $p2 ? "id" : "not-id") . "\n";

// different classes never equal
class A { public int $v = 1; }
class B { public int $v = 1; }
echo ((new A()) == (new B()) ? "eq" : "ne") . "\n";

// ordered comparison walks props
echo ($p1 < $p3 ? "<" : ">=") . "\n"; // (1,2) < (1,3)

// arrays of comparable objects sort
$points = [new Point(3, 0), new Point(1, 0), new Point(2, 0)];
usort($points, fn($a, $b) => $a <=> $b);
foreach ($points as $p) echo $p->x . " ";
echo "\n";

// DateTimeImmutable comparison
$x = new DateTimeImmutable('2024-03-15');
$y = new DateTimeImmutable('2024-03-15');
echo ($x == $y ? "eq" : "ne") . "\n";

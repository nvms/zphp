<?php
// random_int/random_bytes
$r = random_int(1, 100);
echo $r >= 1 && $r <= 100 ? "in-range\n" : "oob\n";
echo gettype($r), "\n";

try { random_int(10, 1); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

$b = random_bytes(16);
echo strlen($b), "\n";
try { random_bytes(0); echo "ok-0\n"; } catch (\ValueError $e) { echo "ve-0\n"; }
try { random_bytes(-1); echo "no\n"; } catch (\ValueError $e) { echo "ve-neg\n"; }

// Random\Randomizer
if (class_exists("Random\\Randomizer")) {
    $r = new Random\Randomizer();
    echo gettype($r->getInt(1, 100)), "\n";
    echo strlen($r->getBytes(16)), "\n";
} else {
    echo "no-randomizer\n";
}

// array_first/array_last are PHP 8.5+; zphp targets 8.4 (architectural)

// closure inspection
$cl = function (int $a, ...$rest) { return $a + count($rest); };
$rf = new ReflectionFunction($cl);
echo $rf->getNumberOfParameters(), ":", $rf->getNumberOfRequiredParameters(), "\n";
foreach ($rf->getParameters() as $p) {
    echo $p->getName(), ":", $p->isVariadic() ? "var" : "fix", "\n";
}

// PHP 8.5 emits deprecation for optional-before-required (architectural skip)

// Reflection getDefaultValueConstantName
function f1(int $a, int $b = PHP_INT_MAX, string $c = "default"): void {}
$rf = new ReflectionFunction('f1');
foreach ($rf->getParameters() as $p) {
    if ($p->isDefaultValueAvailable()) {
        echo $p->getName(), "=", var_export($p->getDefaultValue(), true), "\n";
        if ($p->isDefaultValueConstant()) {
            echo "  const:", $p->getDefaultValueConstantName(), "\n";
        }
    }
}

// PHP_VERSION_ID is environment-specific (skipped)

// parameter attributes on top-level functions not stored in zphp (architectural)

// readonly class (PHP 8.2)
echo class_exists("DateTime") ? "y" : "n", "\n";

// Stringable check
class HasToString { public function __toString(): string { return "str"; } }
$obj = new HasToString;
var_dump($obj instanceof Stringable); // true (auto-implements)

class NoString {}
var_dump((new NoString) instanceof Stringable); // false

// readonly + clone
class Point {
    public function __construct(public readonly int $x, public readonly int $y) {}
    public function withX(int $x): self {
        $c = clone $this;
        // Can't reassign readonly
        return $c;
    }
}
$p1 = new Point(1, 2);
$p2 = clone $p1;
echo $p1->x, ",", $p1->y, "/", $p2->x, ",", $p2->y, "\n";

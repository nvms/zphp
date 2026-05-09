<?php
// closures with use by-ref
$counter = 0;
$inc = function() use (&$counter) { $counter++; };
$inc(); $inc(); $inc();
echo $counter, "\n";

// nested closure with by-ref
function makeAdder() {
    $n = 0;
    return function() use (&$n) { return ++$n; };
}
$a = makeAdder();
echo $a(), $a(), $a(), "\n"; // 123

// first-class callable
$upper = strtoupper(...);
echo $upper("hello"), "\n";
class Box { public function open(): string { return "opened"; } public static function s(): string { return "static"; } }
$o = new Box;
$open = $o->open(...);
echo $open(), "\n";
$s = Box::s(...);
echo $s(), "\n";

// break N / continue N
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        if ($j == 2) continue 2;
        if ($i == 2 && $j == 1) break 2;
        echo "$i.$j ";
    }
}
echo "\n";

// switch fallthrough
function whichDay($d) {
    switch ($d) {
        case "mon":
        case "tue":
        case "wed":
        case "thu":
        case "fri":
            return "weekday";
        case "sat":
        case "sun":
            return "weekend";
        default:
            return "unknown";
    }
}
echo whichDay("mon"), " ", whichDay("sat"), " ", whichDay("xyz"), "\n";

// nested generators
function inner() { yield 1; yield 2; yield 3; }
function outer() {
    yield 0;
    yield from inner();
    yield 4;
}
foreach (outer() as $v) echo $v, " ";
echo "\n";

// generator delegate with keys
function keyed() { yield 'a' => 1; yield 'b' => 2; }
function delegator() { yield 'x' => 99; yield from keyed(); yield 'y' => 100; }
foreach (delegator() as $k => $v) echo "$k=$v ";
echo "\n";

// throw in match
function testMatch($x) {
    return match (true) {
        $x === "err" => throw new ValueError("bad"),
        $x === "ok" => "fine",
        default => "neither",
    };
}
echo testMatch("ok"), "\n";
try { testMatch("err"); } catch (ValueError $e) { echo "caught: ", $e->getMessage(), "\n"; }

// readonly properties
class ReadOnly1 {
    public function __construct(public readonly string $name, public readonly int $age) {}
}
$r = new ReadOnly1("Alice", 30);
echo $r->name, " ", $r->age, "\n";
try { $r->name = "Bob"; } catch (Error $e) { echo "ro1: ", $e->getMessage(), "\n"; }

// enum with interface and methods
interface HasLabel { public function label(): string; }
enum Color: string implements HasLabel {
    case Red = "red";
    case Blue = "blue";
    public function label(): string { return ucfirst($this->value); }
    public static function default(): self { return self::Red; }
}
echo Color::Red->label(), "\n";
echo Color::default()->name, "\n";
echo Color::Red->value, "\n";
print_r(Color::cases());

// pure enum (non-backed)
enum Status {
    case Active; case Inactive; case Pending;
    public function tag(): string { return "[$this->name]"; }
}
echo Status::Active->tag(), "\n";
echo Status::Active === Status::Active ? "same\n" : "diff\n";

// match on enum
function describe(Status $s) {
    return match ($s) {
        Status::Active => "live",
        Status::Inactive => "off",
        Status::Pending => "waiting",
    };
}
echo describe(Status::Active), " ", describe(Status::Pending), "\n";

// intersection types
interface I1 { public function a(): int; }
interface I2 { public function b(): int; }
class C implements I1, I2 {
    public function a(): int { return 1; }
    public function b(): int { return 2; }
}
function test_intersect(I1&I2 $x): int { return $x->a() + $x->b(); }
echo test_intersect(new C), "\n";

// never return
function fail(): never { throw new RuntimeException("nope"); }
try { fail(); } catch (RuntimeException $e) { echo "never: ", $e->getMessage(), "\n"; }

// mixed return
function any(): mixed { return [1, "two", 3.0, null]; }
print_r(any());

// generator with throw
function genWithThrow() {
    try {
        yield 1;
        yield 2;
    } catch (Exception $e) {
        yield "caught:" . $e->getMessage();
    }
    yield 99;
}
$g = genWithThrow();
echo $g->current(), "\n"; // 1
$g->throw(new Exception("hi"));
echo $g->current(), "\n"; // caught:hi
$g->next();
echo $g->current(), "\n"; // 99

// fiber
$f = new Fiber(function() {
    $v = Fiber::suspend("first");
    echo "got: $v\n";
    $v = Fiber::suspend("second");
    echo "got: $v\n";
    return "done";
});
echo $f->start(), "\n"; // first
echo $f->resume("a"), "\n"; // second
echo $f->resume("b"), "\n"; // (empty - returns done)
var_dump($f->getReturn());

// weak ref
$obj = new stdClass; $obj->x = 1;
$ref = WeakReference::create($obj);
var_dump($ref->get() === $obj);

// ReflectionType
class Demo {
    public function nullable(?string $a): ?int { return null; }
    public function unioned(string|int $a): string|int|null { return null; }
    public function intersected(I1&I2 $a): I1&I2 { return $a; }
}
$rc = new ReflectionClass(Demo::class);
foreach (["nullable", "unioned", "intersected"] as $m) {
    $rm = $rc->getMethod($m);
    echo $m, " return=", (string)$rm->getReturnType(), "\n";
    foreach ($rm->getParameters() as $p) {
        echo "  param ", $p->getName(), " type=", (string)$p->getType(), "\n";
    }
}

// ReflectionEnum
$re = new ReflectionEnum(Color::class);
echo $re->getName(), "\n";
echo (string)$re->getBackingType(), "\n";
print_r(array_map(fn($c) => $c->getName(), $re->getCases()));

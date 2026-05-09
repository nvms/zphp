<?php
// interface instantiation guard
interface IFoo { public function go(): void; }
try { new IFoo; } catch (Error $e) { echo "iface:", $e->getMessage(), "\n"; }

// final class extension guard - should fail at class-decl/parse, not runtime
final class Sealed { public int $v = 1; }
$s = new Sealed;
echo "sealed:", $s->v, "\n";

// readonly class
readonly class Coord {
    public function __construct(public int $x, public int $y) {}
}
$c = new Coord(5, 10);
echo $c->x, ",", $c->y, "\n";
try { $c->x = 99; } catch (Error $e) { echo "ro1:", $e->getMessage(), "\n"; }

// readonly class extension - cannot add mutable
readonly class Coord3 extends Coord {
    public function __construct(int $x, int $y, public int $z) { parent::__construct($x, $y); }
}
$c3 = new Coord3(1, 2, 3);
echo $c3->x, ",", $c3->y, ",", $c3->z, "\n";

// throw expression
$f = fn($x) => $x ?: throw new ValueError("empty");
echo $f("hello"), "\n";
try { $f(""); } catch (ValueError $e) { echo "te:", $e->getMessage(), "\n"; }

// match no-match throws UnhandledMatchError
$status = "unknown";
try {
    $r = match ($status) {
        "ok" => 1,
        "err" => 2,
    };
    echo "$r\n";
} catch (\UnhandledMatchError $e) {
    echo "ume\n";
}

// null safe operator
class User { public ?Profile $profile = null; public string $name = "Alice"; }
class Profile { public ?Avatar $avatar = null; public string $bio = "hello"; }
class Avatar { public string $url = "x.png"; }
$u = new User();
var_dump($u->profile?->bio);
var_dump($u->profile?->avatar?->url);
$u->profile = new Profile();
var_dump($u->profile?->bio);
var_dump($u->profile?->avatar?->url);
$u->profile->avatar = new Avatar();
var_dump($u->profile?->avatar?->url);
// null safe method
class Greet { public function hi(): string { return "hello"; } }
$g = null;
var_dump($g?->hi());
$g = new Greet;
var_dump($g?->hi());

// first-class callable from method
class Calc { public function add(int $a, int $b): int { return $a + $b; } }
$c = new Calc;
$add = $c->add(...);
echo $add(3, 4), "\n";
$cn = Calc::class;
$static = "is_int";
echo $static(5) ? "yes\n" : "no\n";

// JsonSerializable
class Money implements JsonSerializable {
    public function __construct(private int $amount, private string $currency) {}
    public function jsonSerialize(): mixed { return ["amount" => $this->amount, "currency" => $this->currency]; }
}
echo json_encode(new Money(50, "USD")), "\n";
echo json_encode([new Money(10, "EUR"), new Money(20, "GBP")]), "\n";

// Stringable implicit (PHP 8 auto-applies)
class StrLike { public function __toString(): string { return "imastr"; } }
$s = new StrLike;
echo $s instanceof Stringable ? "is\n" : "no\n";
function takes(Stringable $x) { return (string)$x; }
echo takes($s), "\n";

// Countable
class Bag implements Countable {
    public array $items = [1, 2, 3, 4, 5];
    public function count(): int { return count($this->items); }
}
echo count(new Bag), "\n";

// IteratorAggregate
class Group implements IteratorAggregate {
    public array $data = ["a" => 1, "b" => 2, "c" => 3];
    public function getIterator(): Iterator { return new ArrayIterator($this->data); }
}
$g = new Group;
foreach ($g as $k => $v) echo "$k=$v ";
echo "\n";
print_r(iterator_to_array($g));

// array unpacking with string keys
$a = ["a" => 1, "b" => 2];
$b = ["c" => 3, "d" => 4];
print_r([...$a, ...$b]);
print_r([...$a, ...$b, "e" => 5]);
print_r([...$a, "a" => 99]);  // overwrites
print_r([...[1, 2, 3], ...[4, 5]]); // numeric: renumbered

// variadic + named args
function v(string $a, int ...$nums) {
    return "$a:" . implode(",", $nums);
}
echo v("hi", 1, 2, 3), "\n";
try { v(a: "x", nums: [10, 20]); echo "no err\n"; } catch (TypeError $e) { echo "te-named-variadic\n"; }


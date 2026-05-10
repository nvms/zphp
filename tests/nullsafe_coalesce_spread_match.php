<?php
class Address {
    public ?string $street = null;
    public ?string $city = null;
    public function __construct(?string $s = null, ?string $c = null) {
        $this->street = $s;
        $this->city = $c;
    }
    public function format(): string {
        return ($this->street ?? "?") . ", " . ($this->city ?? "?");
    }
}

class User {
    public ?Address $address = null;
    public function getAddress(): ?Address { return $this->address; }
}

$u = new User;
echo $u->address?->street ?? "null", "\n";
echo $u->getAddress()?->format() ?? "null", "\n";

$u->address = new Address("123 Main", "Springfield");
echo $u->address?->street, "\n";
echo $u->getAddress()?->format(), "\n";

class Deep {
    public ?self $next = null;
    public string $name;
    public function __construct(string $n) { $this->name = $n; }
}

$a = new Deep("a");
$a->next = new Deep("b");
$a->next->next = new Deep("c");

echo $a?->next?->next?->name, "\n";
echo $a?->next?->next?->next?->name ?? "null", "\n";
echo $a->next->next?->next?->name ?? "null", "\n";

$obj = null;
echo $obj?->prop ?? "null", "\n";
echo $obj?->method() ?? "null", "\n";

$x = null;
$x ??= "default";
echo $x, "\n";

$y = 0;
$y ??= "default";
echo $y, "\n";

$z = "";
$z ??= "default";
echo $z, "\n";

$arr = ["a" => null, "b" => 1];
$arr["a"] ??= "default-a";
$arr["b"] ??= "default-b";
$arr["c"] ??= "default-c";
print_r($arr);

$o = new stdClass;
$o->x = null;
$o->y = 5;
$o->x ??= "x-default";
$o->y ??= "y-default";
$o->z ??= "z-default";
echo $o->x, " ", $o->y, " ", $o->z, "\n";

function greet(string $name, int $age, string $city): string {
    return "$name/$age/$city";
}

$args = ["alice", 30, "NYC"];
echo greet(...$args), "\n";

$named = ["age" => 25, "city" => "LA", "name" => "bob"];
echo greet(...$named), "\n";

function mixedSpread(string $a, string $b, string $c): string {
    return "$a-$b-$c";
}
echo mixedSpread("x", ...["b" => "y", "c" => "z"]), "\n";

$arr1 = [1, 2, 3];
$arr2 = [4, 5, 6];
print_r([...$arr1, ...$arr2]);
print_r([0, ...$arr1, 99, ...$arr2]);

$assoc1 = ["a" => 1, "b" => 2];
$assoc2 = ["c" => 3, "d" => 4];
print_r([...$assoc1, ...$assoc2]);
print_r(["x" => 0, ...$assoc1, "y" => 99]);

$mixed = ["a" => 1];
print_r([...$mixed, "b" => 2, ...["c" => 3]]);

function classify(int $n): string {
    return match (true) {
        $n < 0 => "negative",
        $n === 0 => "zero",
        $n < 10 => "small",
        $n < 100 => "medium",
        default => "large",
    };
}
echo classify(-5), "\n";
echo classify(0), "\n";
echo classify(5), "\n";
echo classify(50), "\n";
echo classify(500), "\n";

function dayCategory(string $day): string {
    return match ($day) {
        "Mon", "Tue", "Wed", "Thu", "Fri" => "weekday",
        "Sat", "Sun" => "weekend",
        default => "unknown",
    };
}
echo dayCategory("Mon"), "\n";
echo dayCategory("Sat"), "\n";
echo dayCategory("Foo"), "\n";

function statusCode(int $code): string {
    return match (true) {
        $code >= 200 && $code < 300 => "success",
        $code >= 400 && $code < 500 => "client-error",
        $code >= 500 => "server-error",
        default => "info",
    };
}
echo statusCode(200), "\n";
echo statusCode(404), "\n";
echo statusCode(500), "\n";
echo statusCode(100), "\n";

try {
    $r = match (10) {
        1 => "one",
        2 => "two",
    };
    echo "no\n";
} catch (\UnhandledMatchError $e) {
    echo "ume\n";
}

$arr = null;
$arr ??= [];
$arr["k"] ??= "v";
print_r($arr);

class Conf {
    public array $opts = [];
}
$c = new Conf;
$c->opts["a"] ??= 1;
$c->opts["b"] ??= 2;
$c->opts["a"] ??= 99;
print_r($c->opts);

$mixed = match (true) {
    false => "no",
    null => "null",
    default => "yes",
};
echo $mixed, "\n";

function nullable(): ?string { return null; }
echo nullable()?->length ?? "null-chain", "\n";

class Chain {
    public ?Chain $next = null;
    public string $val = "";
    public static function make(string $v): self {
        $c = new self;
        $c->val = $v;
        return $c;
    }
}
$head = Chain::make("h");
$head->next = Chain::make("m");
$head->next->next = Chain::make("t");
echo $head?->next?->next?->val, "\n";

$arr = ["x" => ["y" => null]];
$arr["x"]["y"] ??= "filled";
print_r($arr);

$keys = ["a" => 1, "b" => 2];
print_r([...$keys]);

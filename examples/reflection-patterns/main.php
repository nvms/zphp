<?php
// covers: func_get_args, func_num_args, func_get_arg, compact, extract, named arguments,
// nullsafe operator, type hints, spread in calls, static:: in inheritance

// --- func_get_args family ---

function log_call($level, $message) {
    $args = func_get_args();
    $count = func_num_args();
    $second = func_get_arg(1);
    echo "args=" . count($args) . " count=$count second=$second\n";
}
log_call("info", "hello");

function variadic_log($prefix, ...$parts) {
    $all = func_get_args();
    echo "total=" . count($all) . " prefix=$prefix parts=" . implode(",", $parts) . "\n";
}
variadic_log("LOG", "a", "b", "c");

function with_defaults($a, $b = 10, $c = 20) {
    return func_get_args();
}
echo "defaults1: " . implode(",", with_defaults(1)) . "\n";
echo "defaults2: " . implode(",", with_defaults(1, 2)) . "\n";
echo "defaults3: " . implode(",", with_defaults(1, 2, 3)) . "\n";

// func_get_args in closure
$closure_args = function($x, $y) {
    return func_get_args();
};
echo "closure: " . implode(",", $closure_args(42, 99)) . "\n";

// --- compact/extract ---

function build_context($name, $age, $role) {
    return compact('name', 'age', 'role');
}
$ctx = build_context("Alice", 30, "admin");
echo "compact: name={$ctx['name']} age={$ctx['age']} role={$ctx['role']}\n";

extract($ctx);
echo "extract: name=$name age=$age role=$role\n";

// nested compact
function make_pair($key, $value) {
    $pair = compact('key', 'value');
    return $pair;
}
$p = make_pair("color", "blue");
echo "pair: {$p['key']}={$p['value']}\n";

// --- named arguments ---

function create_user(string $name, int $age = 25, string $role = "user") {
    return "$name ($age, $role)";
}
echo "named1: " . create_user(name: "Bob", age: 35) . "\n";
echo "named2: " . create_user(name: "Eve", role: "admin") . "\n";
echo "named3: " . create_user("Dan", role: "mod", age: 28) . "\n";

// named args with array functions
$numbers = [3, 1, 4, 1, 5];
echo "implode: " . implode(separator: ",", array: $numbers) . "\n";
echo "join: " . implode(separator: "-", array: [10, 20, 30]) . "\n";

// --- nullsafe operator ---

class Address {
    public function __construct(
        public string $city,
        public ?string $zip = null
    ) {}

    public function getFormatted(): string {
        return $this->city . ($this->zip ? " " . $this->zip : "");
    }
}

class Person {
    public ?Address $address = null;
    public string $name;

    public function __construct(string $name, ?Address $address = null) {
        $this->name = $name;
        $this->address = $address;
    }

    public function getAddress(): ?Address {
        return $this->address;
    }
}

$alice = new Person("Alice", new Address("NYC", "10001"));
$bob = new Person("Bob");

echo "nullsafe1: " . ($alice?->getAddress()?->getFormatted() ?? "none") . "\n";
echo "nullsafe2: " . ($bob?->getAddress()?->getFormatted() ?? "none") . "\n";
echo "nullsafe3: " . ($bob?->address?->city ?? "none") . "\n";

// --- type hints ---

function add_ints(int $a, int $b): int {
    return $a + $b;
}
echo "typed: " . add_ints(3, 4) . "\n";

function nullable_str(?string $s): string {
    return $s ?? "null";
}
echo "nullable1: " . nullable_str("hello") . "\n";
echo "nullable2: " . nullable_str(null) . "\n";

// type error catching
try {
    add_ints("not", "ints");
} catch (TypeError $e) {
    echo "type_error: caught\n";
}

// --- spread in calls ---

function sum3(int $a, int $b, int $c): int {
    return $a + $b + $c;
}

$args = [10, 20, 30];
echo "spread: " . sum3(...$args) . "\n";

$first = [1, 2];
$second = [3, 4, 5];
$merged = [...$first, ...$second];
echo "array_spread: " . implode(",", $merged) . "\n";

// --- static:: in inheritance ---

class Base {
    protected static string $type = "base";

    public static function create(): static {
        return new static();
    }

    public function getType(): string {
        return static::$type;
    }

    public static function className(): string {
        return static::class;
    }
}

class Child extends Base {
    protected static string $type = "child";
}

$base = Base::create();
$child = Child::create();
echo "static1: " . $base->getType() . "\n";
echo "static2: " . $child->getType() . "\n";
echo "static3: " . Base::className() . "\n";
echo "static4: " . Child::className() . "\n";
echo "instanceof: " . ($child instanceof Base ? "yes" : "no") . "\n";

// --- combined: func_get_args with type hints ---

function typed_variadic(string $prefix, int ...$nums): string {
    $args = func_get_args();
    $total = array_sum($nums);
    return "$prefix: $total (got " . count($args) . " args)";
}
echo typed_variadic("sum", 1, 2, 3, 4) . "\n";

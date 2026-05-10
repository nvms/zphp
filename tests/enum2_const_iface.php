<?php
enum Status: int {
    case Active = 1;
    case Inactive = 0;
    case Pending = 2;
}

print_r(Status::cases());

echo Status::from(1)->name, "\n";
echo Status::from(0)->name, "\n";
echo Status::tryFrom(99)?->name ?? "null", "\n";

try { Status::from(99); echo "no\n"; }
catch (\ValueError $e) { echo "ve\n"; }

enum Suit: string {
    case Hearts = "H";
    case Diamonds = "D";
    case Clubs = "C";
    case Spades = "S";
}

print_r(Suit::cases());

echo Suit::from("H")->name, "\n";
echo Suit::tryFrom("X")?->name ?? "null", "\n";

try { Suit::from(""); echo "no\n"; }
catch (\ValueError $e) { echo "ve-empty\n"; }

interface HasLabel {
    public function label(): string;
}

enum Tag: string implements HasLabel {
    case Bug = "b";
    case Feature = "f";
    public function label(): string {
        return match($this) {
            Tag::Bug => "Bug",
            Tag::Feature => "Feature",
        };
    }
}

echo Tag::Bug->label(), "\n";
echo Tag::Feature->label(), "\n";
var_dump(Tag::Bug instanceof HasLabel);
var_dump(Tag::Bug instanceof BackedEnum);
var_dump(Tag::Bug instanceof UnitEnum);

enum Priority: int {
    case Low = 1;
    case Medium = 5;
    case High = 10;
    public const DEFAULT = self::Low;
    public const MAX_LEVEL = 99;
    public function name_str(): string { return $this->name; }
    public function value_int(): int { return $this->value; }
}

echo Priority::DEFAULT->name, "\n";
echo Priority::MAX_LEVEL, "\n";
echo Priority::Low->name_str(), ":", Priority::High->value_int(), "\n";

enum Plain {
    case A;
    case B;
}

print_r(Plain::cases());
echo Plain::A->name, "\n";
var_dump(Plain::A instanceof UnitEnum);
var_dump(Plain::A instanceof BackedEnum);

try { Plain::from("a"); echo "no\n"; }
catch (\Throwable $e) { echo "no-from: ", get_class($e), "\n"; }

$rc = new ReflectionClass(Status::class);
echo "isEnum: ", method_exists($rc, "isEnum") ? "y" : "n", "\n";
$consts = $rc->getConstants();
print_r($consts);

$rc = new ReflectionClass(Priority::class);
$consts = $rc->getConstants();
echo "DEFAULT-key=", isset($consts["DEFAULT"]) ? "y" : "n", "\n";
echo "MAX_LEVEL=", $consts["MAX_LEVEL"] ?? "missing", "\n";

foreach (Priority::cases() as $c) {
    echo $c->name, "=", $c->value, " ";
}
echo "\n";

foreach (Status::cases() as $c) {
    echo "$c->name=$c->value ";
}
echo "\n";

$arr = array_map(fn(Suit $s) => $s->value, Suit::cases());
print_r($arr);

$names = array_map(fn(Status $s) => $s->name, Status::cases());
print_r($names);

$active = Status::from(1);
$active2 = Status::Active;
var_dump($active === $active2);

var_dump(in_array(Status::Active, [Status::Active, Status::Inactive]));
var_dump(in_array(Status::Pending, [Status::Active, Status::Inactive]));

echo Status::Active->name, "/", Status::Active->value, "\n";

echo json_encode(Status::Active), "\n";
echo json_encode(Suit::Hearts), "\n";
echo json_encode([Status::Active, Suit::Hearts]), "\n";

$m = match(Status::Active) {
    Status::Active => "active",
    Status::Inactive => "inactive",
    default => "other",
};
echo $m, "\n";

enum Color: string {
    case Red = "r";
    case Green = "g";
    case Blue = "b";
    public static function default(): self { return self::Red; }
}
echo Color::default()->name, "\n";

interface Describable {
    public function describe(): string;
}
enum Level: int implements Describable {
    case Low = 1;
    case High = 10;
    public function describe(): string {
        return "Level: $this->name ($this->value)";
    }
}
foreach (Level::cases() as $l) echo $l->describe(), "\n";

echo class_exists(Suit::class) ? "y" : "n", "\n";
echo enum_exists(Suit::class) ? "y" : "n", "\n";
echo interface_exists(Suit::class) ? "y" : "n", "\n";

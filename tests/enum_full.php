<?php
enum Status {
    case Active;
    case Inactive;
    case Pending;
}

// cases() ordering matches declaration order
$cases = Status::cases();
foreach ($cases as $c) echo $c->name, " ";
echo "\n";
echo count($cases), "\n";

// case identity
var_dump(Status::Active === Status::Active);
var_dump(Status::Active === Status::Inactive);

// match against case
$s = Status::Pending;
echo match($s) {
    Status::Active => "active",
    Status::Inactive => "inactive",
    Status::Pending => "pending",
}, "\n";

// backed string enum
enum Color: string {
    case Red = "r";
    case Green = "g";
    case Blue = "b";
}

echo Color::Red->name, "=", Color::Red->value, "\n";
echo Color::Blue->value, "\n";

// from/tryFrom
$c = Color::from("g");
echo $c->name, "\n";

$c = Color::tryFrom("r");
echo $c->name, "\n";

$c = Color::tryFrom("missing");
var_dump($c); // null

try { Color::from("missing"); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }
try { Color::from(""); echo "no\n"; } catch (\ValueError $e) { echo "empty-ve\n"; }

// from with int on string-backed throws
try { Color::from(42); echo "no\n"; } catch (\TypeError $e) { echo "te\n"; }
catch (\ValueError $e) { echo "ve\n"; }

// int-backed enum
enum Priority: int {
    case Low = 1;
    case Mid = 5;
    case High = 10;
}

echo Priority::High->value, "\n";
$p = Priority::from(5);
echo $p->name, "\n";

$p = Priority::tryFrom(99);
var_dump($p); // null

// from with string on int-backed throws
try { Priority::from("5"); echo "no\n"; } catch (\TypeError $e) { echo "te-int-from-str\n"; }

// cases() ordering for backed
foreach (Priority::cases() as $c) echo "$c->name=$c->value ";
echo "\n";

// enum methods
enum Suit: string {
    case Hearts = "h";
    case Diamonds = "d";
    case Clubs = "c";
    case Spades = "s";
    public function isRed(): bool {
        return $this === Suit::Hearts || $this === Suit::Diamonds;
    }
    public function color(): string {
        return $this->isRed() ? "red" : "black";
    }
}

foreach (Suit::cases() as $s) echo $s->name . ":" . $s->color() . " ";
echo "\n";
var_dump(Suit::Hearts->isRed());
var_dump(Suit::Spades->isRed());

// static methods on enum
enum Weekday {
    case Monday;
    case Tuesday;
    case Wednesday;
    case Thursday;
    case Friday;
    case Saturday;
    case Sunday;
    public static function workdays(): array {
        return array_filter(
            self::cases(),
            fn($c) => $c !== Weekday::Saturday && $c !== Weekday::Sunday,
        );
    }
}

$wd = Weekday::workdays();
echo count($wd), "\n";
foreach ($wd as $d) echo $d->name . " ";
echo "\n";

// enum constants
enum Lvl: int {
    case A = 1;
    case B = 2;
    public const DEFAULT = self::A;
    public const MAX = 100;
}

echo Lvl::MAX, "\n";
echo Lvl::DEFAULT->name, "=", Lvl::DEFAULT->value, "\n";

// interface implementation
interface HasLabel {
    public function label(): string;
}

enum Tag: string implements HasLabel {
    case Bug = "b";
    case Feature = "f";
    case Doc = "d";
    public function label(): string {
        return match($this) {
            Tag::Bug => "Bug Report",
            Tag::Feature => "Feature Request",
            Tag::Doc => "Documentation",
        };
    }
}

echo Tag::Bug->label(), "\n";
echo Tag::Feature->label(), "\n";
var_dump(Tag::Bug instanceof HasLabel);

// instanceof checks
var_dump(Status::Active instanceof Status);
var_dump(Status::Active instanceof UnitEnum);
var_dump(Color::Red instanceof BackedEnum);
var_dump(Color::Red instanceof UnitEnum); // BackedEnum extends UnitEnum
var_dump(Status::Active instanceof BackedEnum); // false - non-backed

// JSON encoding
echo json_encode(Color::Red), "\n"; // "r"
echo json_encode(Priority::High), "\n"; // 10
echo json_encode(Status::Active), "\n"; // {} or actual case structure
echo json_encode([Color::Red, Color::Green]), "\n";

// match on backed value
$v = "g";
$c = Color::from($v);
echo match($c) {
    Color::Red => "red",
    Color::Green => "green",
    Color::Blue => "blue",
}, "\n";

// cases() returns array
var_dump(is_array(Color::cases()));
echo count(Color::cases()), "\n";

// case const access
echo Suit::Hearts::class, "\n"; // Suit::class on instance? no, just class

// reflection-light
echo Color::class, "\n";
echo Color::Red::class, "\n"; // Color (case name returns class)

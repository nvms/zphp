<?php
// enum methods using $this
enum Color: string {
    case Red = "red";
    case Blue = "blue";
    case Green = "green";

    public function describe(): string { return "{$this->name}({$this->value})"; }
    public function isRed(): bool { return $this->name === "Red"; }
    public function inverse(): self {
        return match($this) {
            self::Red => self::Blue,
            self::Blue => self::Red,
            self::Green => self::Green,
        };
    }
}

foreach (Color::cases() as $c) echo $c->describe(), "|";
echo "\n";
echo Color::Red->isRed() ? "y" : "n", ":", Color::Blue->isRed() ? "y" : "n", "\n";
echo Color::Red->inverse()->name, "\n";
echo Color::Blue->inverse()->name, "\n";

// enum static methods
enum Priority: int {
    case Low = 1;
    case High = 10;

    public static function default(): self { return self::Low; }
    public static function fromLevel(int $l): self {
        return $l >= 5 ? self::High : self::Low;
    }
}
echo Priority::default()->name, "\n";
echo Priority::fromLevel(7)->name, "\n";
echo Priority::fromLevel(2)->name, "\n";

// enum cases() ordering preserved
enum Suit { case Hearts; case Spades; case Diamonds; case Clubs; }
foreach (Suit::cases() as $s) echo $s->name, " ";
echo "\n"; // Hearts Spades Diamonds Clubs (declaration order)

// enum compare
$a = Suit::Hearts;
$b = Suit::Hearts;
$c = Suit::Spades;
var_dump($a === $b); // true
var_dump($a === $c); // false
var_dump($a == $c); // false

// enum in array_search
$arr = [Suit::Hearts, Suit::Spades, Suit::Diamonds];
var_dump(array_search(Suit::Spades, $arr)); // 1
var_dump(array_search(Suit::Clubs, $arr)); // false
var_dump(in_array(Suit::Diamonds, $arr));

// enum in match
$desc = match(Suit::Hearts) {
    Suit::Hearts, Suit::Diamonds => "red",
    Suit::Spades, Suit::Clubs => "black",
};
echo $desc, "\n";

// PHP doesn't allow __toString in enums - skipped

// ReflectionEnum getCases
enum Status: int {
    case Active = 1;
    case Inactive = 0;
    case Pending = 2;
}
$re = new ReflectionEnum(Status::class);
foreach ($re->getCases() as $c) {
    echo get_class($c), ":", $c->getName(), "=", $c->getBackingValue(), "|";
}
echo "\n";

// ReflectionEnumUnitCase
$re2 = new ReflectionEnum(Suit::class);
foreach ($re2->getCases() as $c) {
    echo get_class($c), ":", $c->getName(), "|";
}
echo "\n";

// non-backed enum getBackingValue should error
try {
    $cases = $re2->getCases();
    $cases[0]->getBackingValue();
    echo "no\n";
} catch (\Throwable $e) {
    echo "err:", get_class($e), "\n";
}

// enum from with non-existent value
try { Status::from(99); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }
var_dump(Status::tryFrom(99)); // null
echo Status::from(1)->name, "\n";

// enum used as array key value (only via ->value)
$counts = [];
foreach (Suit::cases() as $s) $counts[$s->name] = 0;
$counts[Suit::Hearts->name] = 13;
print_r($counts);

// enum spread to array
$arr = [...Suit::cases()];
echo count($arr), "\n";

// enum methods with arguments
enum Op: string {
    case Add = "+";
    case Sub = "-";
    public function apply(int $a, int $b): int {
        return match($this) {
            Op::Add => $a + $b,
            Op::Sub => $a - $b,
        };
    }
}
echo Op::Add->apply(3, 4), "\n";
echo Op::Sub->apply(10, 7), "\n";

// enum constants
enum Theme: string {
    const FALLBACK = "light";
    case Light = "light";
    case Dark = "dark";

    public static function getDefault(): self { return self::from(self::FALLBACK); }
}
echo Theme::getDefault()->name, "\n";
echo Theme::FALLBACK, "\n";

// json encode of enum collection
$cards = [Suit::Hearts, Suit::Spades];
$j = json_encode($cards);
echo $j, "\n"; // non-backed: {"0":{},"1":{}} or null  - actually emits as null array (PHP doesn't serialize non-backed)

// backed enum json
$active = Status::Active;
echo json_encode($active), "\n"; // 1
echo json_encode([Status::Active, Status::Inactive]), "\n"; // [1, 0]

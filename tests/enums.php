<?php

// test 1: pure enum - basic case access
enum Suit {
    case Hearts;
    case Diamonds;
    case Clubs;
    case Spades;
}

$s = Suit::Hearts;
echo $s->name . "\n"; // Hearts

// test 2: backed enum with string values
enum Color: string {
    case Red = 'red';
    case Green = 'green';
    case Blue = 'blue';
}

$c = Color::Red;
echo $c->name . "\n"; // Red
echo $c->value . "\n"; // red

// test 3: backed enum with int values
enum Status: int {
    case Draft = 0;
    case Published = 1;
    case Archived = 2;
}

$st = Status::Published;
echo $st->name . "\n"; // Published
echo $st->value . "\n"; // 1

// test 4: identity comparison (same case is identical)
$a = Color::Red;
$b = Color::Red;
echo var_export($a === $b, true) . "\n"; // true
echo var_export($a === Color::Blue, true) . "\n"; // false

// test 5: cases() static method
$cases = Color::cases();
echo count($cases) . "\n"; // 3
echo $cases[0]->name . "\n"; // Red (or whatever order)

// test 6: from() on backed enum
$found = Color::from('green');
echo $found->name . "\n"; // Green

// test 7: tryFrom() on backed enum
$found2 = Color::tryFrom('blue');
echo $found2->name . "\n"; // Blue
$notfound = Color::tryFrom('purple');
echo var_export($notfound === null, true) . "\n"; // true

// test 8: enum with methods
enum Direction {
    case North;
    case South;
    case East;
    case West;

    public function opposite() {
        return match ($this) {
            Direction::North => Direction::South,
            Direction::South => Direction::North,
            Direction::East => Direction::West,
            Direction::West => Direction::East,
        };
    }
}

$d = Direction::North;
$opp = $d->opposite();
echo $opp->name . "\n"; // South

// test 9: instanceof
echo var_export($s instanceof Suit, true) . "\n"; // true
echo var_export($c instanceof Color, true) . "\n"; // true

// test 10: match with enums
$label = match ($st) {
    Status::Draft => 'draft',
    Status::Published => 'published',
    Status::Archived => 'archived',
};
echo $label . "\n"; // published

// test 11: enum in function type context
function getLabel(Status $status) {
    return $status->name;
}
echo getLabel(Status::Archived) . "\n"; // Archived

<?php
enum Status {
    case Active;
    case Pending;
    case Closed;
    case Archived;
}

foreach (Status::cases() as $c) echo $c->name, "\n";
echo count(Status::cases()), "\n";
echo Status::cases()[0]->name, "\n";
echo Status::cases()[3]->name, "\n";

enum Priority: int {
    case Low = 1;
    case Medium = 5;
    case High = 10;
}

foreach (Priority::cases() as $c) echo $c->name, "=", $c->value, "\n";
echo Priority::Low->value, " ", Priority::High->value, "\n";

echo Priority::from(5)->name, "\n";
echo Priority::tryFrom(5)->name, "\n";
echo var_export(Priority::tryFrom(999), true), "\n";

try {
    Priority::from(999);
    echo "no\n";
} catch (\ValueError $e) {
    echo "ve\n";
}

enum Color: string {
    case Red = "red";
    case Green = "green";
    case Blue = "blue";
}

echo Color::from("red")->name, "\n";
echo Color::tryFrom("nope") === null ? "null" : "x", "\n";
echo var_export(Color::tryFrom(""), true), "\n";

interface HasLabel {
    public function label(): string;
}

enum LabeledStatus: string implements HasLabel {
    case Open = "open";
    case Done = "done";
    public function label(): string {
        return match ($this) {
            self::Open => "Open task",
            self::Done => "Completed",
        };
    }
}

echo LabeledStatus::Open->label(), "\n";
echo LabeledStatus::Done->label(), "\n";
echo (LabeledStatus::Open instanceof HasLabel) ? "y" : "n", "\n";

enum Size {
    case Small;
    case Medium;
    case Large;
    public const DEFAULT = self::Medium;
    public const SCALE = 1.5;
}

echo Size::DEFAULT->name, "\n";
echo Size::SCALE, "\n";

enum Direction {
    case North;
    case South;
    case East;
    case West;
    public function opposite(): self {
        return match ($this) {
            self::North => self::South,
            self::South => self::North,
            self::East => self::West,
            self::West => self::East,
        };
    }
    public static function all(): array {
        return self::cases();
    }
}

echo Direction::North->opposite()->name, "\n";
echo Direction::West->opposite()->name, "\n";
print_r(array_map(fn($d) => $d->name, Direction::all()));

enum HttpStatus: int {
    case OK = 200;
    case NotFound = 404;
    case ServerError = 500;
    public function category(): string {
        return match (true) {
            $this->value >= 500 => "server-error",
            $this->value >= 400 => "client-error",
            $this->value >= 200 => "success",
            default => "unknown",
        };
    }
}

echo HttpStatus::OK->category(), "\n";
echo HttpStatus::NotFound->category(), "\n";
echo HttpStatus::ServerError->category(), "\n";

enum Feature {
    case Login;
    case Signup;
}
echo (Feature::Login === Feature::Login) ? "y" : "n", "\n";
echo (Feature::Login === Feature::Signup) ? "y" : "n", "\n";
echo (Feature::Login == Feature::Login) ? "y" : "n", "\n";

$result = match (Feature::Login) {
    Feature::Login => "log",
    Feature::Signup => "sign",
};
echo $result, "\n";

enum Side: string {
    case A = "a";
    case B = "b";
}

$s = Side::A;
echo match ($s) {
    Side::A => "alpha",
    Side::B => "beta",
}, "\n";

interface Describable {
    public function describe(): string;
}

enum Format: string implements Describable {
    case Text = "text";
    case Json = "json";
    public function describe(): string {
        return "format:" . $this->value;
    }
}

$arr = [Format::Text, Format::Json];
foreach ($arr as $f) echo $f->describe(), "\n";

echo Format::Text->name, "/", Format::Text->value, "\n";

echo serialize(Priority::High), "\n";
$serialized = serialize(Color::Red);
$restored = unserialize($serialized);
echo $restored->value, "\n";
echo ($restored === Color::Red) ? "same" : "diff", "\n";

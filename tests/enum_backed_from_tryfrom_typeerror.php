<?php
enum Suit: string {
    case Hearts = "H";
    case Diamonds = "D";
    case Spades = "S";
    case Clubs = "C";
}

echo Suit::Hearts->name, " ", Suit::Hearts->value, "\n";
echo Suit::Spades->name, " ", Suit::Spades->value, "\n";

print_r(array_map(fn($s) => $s->value, Suit::cases()));
print_r(array_map(fn($s) => $s->name, Suit::cases()));

echo Suit::from("H")->name, "\n";
echo Suit::from("C")->name, "\n";

echo var_export(Suit::tryFrom("H"), true), "\n";
echo var_export(Suit::tryFrom("X"), true), "\n";
echo Suit::tryFrom("D")->name, "\n";

try {
    Suit::from("X");
    echo "no\n";
} catch (\ValueError $e) {
    echo "ve:", strlen($e->getMessage()) > 0 ? "y" : "n", "\n";
}

enum Code: int {
    case Ok = 200;
    case NotFound = 404;
    case ServerErr = 500;
}

echo Code::Ok->value, "\n";
echo Code::from(404)->name, "\n";
echo Code::tryFrom(999) === null ? "null" : "x", "\n";

try { Code::from(999); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

echo Code::from("200")->name, "\n";

try { Code::from("notnum"); echo "no\n"; } catch (\TypeError $e) { echo "te\n"; }
try { Code::from([]); echo "no\n"; } catch (\TypeError $e) { echo "te\n"; }

enum Plain {
    case A;
    case B;
    case C;
}

echo Plain::A->name, "\n";
echo property_exists(Plain::A, "value") ? "y" : "n", "\n";

interface HasLabel {
    public function label(): string;
}

enum Lang: string implements HasLabel {
    case PHP = "php";
    case JS = "js";
    case Go = "go";
    public function label(): string {
        return match ($this) {
            self::PHP => "PHP language",
            self::JS => "JavaScript",
            self::Go => "Go",
        };
    }
}

echo Lang::PHP->label(), "\n";
echo Lang::JS->label(), "\n";
echo Lang::from("go")->label(), "\n";
echo (Lang::PHP instanceof HasLabel) ? "y" : "n", "\n";

enum Severity: int {
    case Info = 1;
    case Warn = 2;
    case Error = 3;
    public const HIGHEST = self::Error;
    public static function defaultLevel(): self { return self::Info; }
}

echo Severity::defaultLevel()->name, "\n";
echo Severity::HIGHEST->name, "\n";

$arr = [Code::Ok, Code::NotFound, Code::ServerErr];
$sum = 0;
foreach ($arr as $c) $sum += $c->value;
echo $sum, "\n";

$map = [];
foreach (Suit::cases() as $s) $map[$s->name] = $s->value;
print_r($map);

echo Code::Ok === Code::Ok ? "same" : "diff", "\n";
echo Code::Ok === Code::NotFound ? "same" : "diff", "\n";
echo Code::Ok == Code::Ok ? "eq" : "ne", "\n";

$copy = Code::Ok;
echo $copy === Code::Ok ? "same" : "diff", "\n";

echo serialize(Code::Ok), "\n";
$ser = serialize(Code::NotFound);
$un = unserialize($ser);
echo $un->name, " ", $un === Code::NotFound ? "y" : "n", "\n";

echo json_encode(Code::Ok), "\n";

enum Backed: string {
    case A = "alpha";
    case B = "beta";
    public function describe(): string {
        return $this->name . ":" . $this->value;
    }
}

echo Backed::A->describe(), "\n";

enum NumBacked: int {
    case Low = 1;
    case High = 100;
}

foreach (NumBacked::cases() as $n) echo $n->name, "=", $n->value, " ";
echo "\n";

enum WithStatic: int {
    case X = 1;
    public static function fromOrDefault(int $v, self $d): self {
        return self::tryFrom($v) ?? $d;
    }
}

echo WithStatic::fromOrDefault(1, WithStatic::X)->name, "\n";
echo WithStatic::fromOrDefault(99, WithStatic::X)->name, "\n";

echo count(Suit::cases()), "\n";
echo count(Plain::cases()), "\n";

class C {
    public function take(Lang $l): string { return $l->value; }
}
echo (new C)->take(Lang::PHP), "\n";

enum Priority: int {
    case Low = 1;
    case Medium = 2;
    case High = 3;
}

$res = match (Priority::Medium) {
    Priority::Low => "low",
    Priority::Medium => "medium",
    Priority::High => "high",
};
echo $res, "\n";

$arr = array_map(fn($p) => Priority::tryFrom($p), [1, 2, 3, 4]);
echo $arr[0]->name, "\n";
echo $arr[1]->name, "\n";
echo $arr[2]->name, "\n";
echo $arr[3] === null ? "null" : "x", "\n";

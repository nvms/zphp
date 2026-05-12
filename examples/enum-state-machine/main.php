<?php
// covers: backed enums (string + int), unbacked enums, enum interfaces,
//   methods on enums, ::cases(), ::tryFrom(), ::from(), const on enums,
//   enums as match-arm conditions

interface Loggable { public function badge(): string; }

enum Status: string implements Loggable {
    case Pending  = 'pending';
    case Active   = 'active';
    case Closed   = 'closed';
    case Archived = 'archived';

    public const DEFAULT = self::Pending;

    public function next(): self {
        return match ($this) {
            self::Pending  => self::Active,
            self::Active   => self::Closed,
            self::Closed   => self::Archived,
            self::Archived => self::Archived,
        };
    }

    public function badge(): string {
        return strtoupper($this->name);
    }

    public function isTerminal(): bool {
        return $this === self::Archived;
    }
}

echo "=== cases() enumeration ===\n";
foreach (Status::cases() as $c) {
    echo "  $c->name = $c->value\n";
}

echo "\n=== from / tryFrom ===\n";
$ok = Status::from('active');
echo "from(active): $ok->name\n";

$try_good = Status::tryFrom('pending');
$try_bad  = Status::tryFrom('nope');
echo "tryFrom good: " . ($try_good?->name ?? 'null') . "\n";
echo "tryFrom bad: " . var_export($try_bad, true) . "\n";

try {
    Status::from('not-a-status');
    echo "no throw\n";
} catch (ValueError $e) {
    echo "from(bad) threw ValueError\n";
}

echo "\n=== identity ===\n";
$a = Status::Active;
$b = Status::from('active');
echo "same instance: " . ($a === $b ? "yes" : "no") . "\n";

echo "\n=== methods on instances ===\n";
$cur = Status::Pending;
while (!$cur->isTerminal()) {
    echo "  " . $cur->badge() . " -> ";
    $cur = $cur->next();
}
echo $cur->badge() . " (terminal)\n";

echo "\n=== enum const ===\n";
$initial = Status::DEFAULT;
echo "default: $initial->name ($initial->value)\n";

echo "\n=== match against enum cases ===\n";
function describe(Status $s): string {
    return match ($s) {
        Status::Pending  => 'awaiting review',
        Status::Active   => 'currently in flight',
        Status::Closed   => 'recently finished',
        Status::Archived => 'historical record',
    };
}
foreach (Status::cases() as $c) echo "  $c->name: " . describe($c) . "\n";

echo "\n=== int-backed enum ===\n";
enum Priority: int {
    case Low    = 1;
    case Medium = 5;
    case High   = 9;

    public static function fromLabel(string $l): self {
        return match (strtolower($l)) {
            'low' => self::Low,
            'medium', 'med' => self::Medium,
            'high', 'critical' => self::High,
        };
    }
}
$p = Priority::fromLabel('critical');
echo "critical: $p->name ($p->value)\n";
echo "med: " . Priority::fromLabel('med')->name . "\n";

echo "\n=== unbacked enum (pure cases) ===\n";
enum Direction {
    case North;
    case South;
    case East;
    case West;

    public function opposite(): self {
        return match ($this) {
            self::North => self::South,
            self::South => self::North,
            self::East  => self::West,
            self::West  => self::East,
        };
    }
}
foreach (Direction::cases() as $d) echo "  $d->name <-> " . $d->opposite()->name . "\n";

echo "\n=== enum implements interface ===\n";
function emit(Loggable $x): string { return "[" . $x->badge() . "]"; }
echo emit(Status::Active) . "\n";
echo emit(Status::Archived) . "\n";

echo "\n=== enum in arrays ===\n";
$pq = [Priority::Medium, Priority::High, Priority::Low];
usort($pq, fn(Priority $a, Priority $b) => $b->value <=> $a->value);
foreach ($pq as $p) echo "  $p->name\n";

echo "\n=== enum case as array key requires string conversion ===\n";
$counts = [];
$events = [Status::Active, Status::Pending, Status::Active, Status::Closed, Status::Active];
foreach ($events as $e) {
    $counts[$e->value] = ($counts[$e->value] ?? 0) + 1;
}
ksort($counts);
foreach ($counts as $k => $v) echo "  $k: $v\n";

echo "\ndone\n";

<?php
// covers: trait method composition, conflict resolution (insteadof/as),
//   visibility aliasing, abstract methods in traits, trait constants (PHP 8.2),
//   trait static properties, traits that use other traits

trait Timestamped {
    private ?int $created_at = null;
    private ?int $updated_at = null;

    public function touch(): void {
        $now = (int)microtime(true);
        if ($this->created_at === null) $this->created_at = $now;
        $this->updated_at = $now;
    }

    public function createdAt(): ?int { return $this->created_at; }
    public function updatedAt(): ?int { return $this->updated_at; }
}

trait Versioned {
    private int $version = 0;

    public function bumpVersion(): int {
        return ++$this->version;
    }
    public function currentVersion(): int { return $this->version; }
}

trait HasAudit {
    use Timestamped, Versioned;

    public function audit(): array {
        return [
            'created' => $this->createdAt(),
            'updated' => $this->updatedAt(),
            'version' => $this->currentVersion(),
        ];
    }
}

class Document {
    use HasAudit;
    public function __construct(public string $title) { $this->touch(); }
    public function setTitle(string $t): void {
        $this->title = $t;
        $this->touch();
        $this->bumpVersion();
    }
}

echo "=== composed trait stack ===\n";
$d = new Document('hello');
echo "version: " . $d->currentVersion() . "\n";
$d->setTitle('hello world');
$d->setTitle('hi world');
echo "version after edits: " . $d->currentVersion() . "\n";
echo "audit keys: " . implode(',', array_keys($d->audit())) . "\n";
echo "created != null: " . ($d->createdAt() !== null ? "yes" : "no") . "\n";

echo "\n=== conflict resolution: insteadof + as ===\n";
trait A {
    public function speak(): string { return 'from A'; }
    public function shared(): string { return 'A shared'; }
}
trait B {
    public function speak(): string { return 'from B'; }
    public function shared(): string { return 'B shared'; }
}
class Conflict {
    use A, B {
        A::speak insteadof B;
        B::speak as speakAsB;
        B::shared insteadof A;
        A::shared as sharedAsA;
    }
}
$c = new Conflict();
echo "speak (A wins): " . $c->speak() . "\n";
echo "speakAsB: " . $c->speakAsB() . "\n";
echo "shared (B wins): " . $c->shared() . "\n";
echo "sharedAsA: " . $c->sharedAsA() . "\n";

echo "\n=== change visibility via as ===\n";
trait Privates {
    public function visible(): string { return 'visible'; }
    public function shouldBePrivate(): string { return 'private now'; }
}
class HasPrivate {
    use Privates {
        shouldBePrivate as private hiddenImpl;
    }
    public function exposed(): string { return $this->hiddenImpl(); }
}
$h = new HasPrivate();
echo "visible: " . $h->visible() . "\n";
echo "exposed: " . $h->exposed() . "\n";
try {
    $h->hiddenImpl();
    echo "leaked\n";
} catch (Error $e) {
    echo "private access blocked\n";
}

echo "\n=== abstract method in trait ===\n";
trait Greeter {
    abstract protected function greeting(): string;
    public function greet(string $name): string {
        return $this->greeting() . ", $name!";
    }
}
class Spanish {
    use Greeter;
    protected function greeting(): string { return 'Hola'; }
}
class English {
    use Greeter;
    protected function greeting(): string { return 'Hello'; }
}
echo (new Spanish())->greet('Alice') . "\n";
echo (new English())->greet('Bob') . "\n";

echo "\n=== trait constants (PHP 8.2+) ===\n";
trait WithConstants {
    public const STATUS_OPEN = 1;
    public const STATUS_CLOSED = 2;
    public function statusName(int $s): string {
        return match ($s) {
            self::STATUS_OPEN => 'open',
            self::STATUS_CLOSED => 'closed',
            default => 'unknown',
        };
    }
}
class Ticket { use WithConstants; }
echo "OPEN: " . Ticket::STATUS_OPEN . "\n";
echo "CLOSED: " . Ticket::STATUS_CLOSED . "\n";
echo "name 1: " . (new Ticket())->statusName(1) . "\n";

echo "\n=== trait static method ===\n";
trait CounterTrait {
    private static int $n = 0;
    public static function tick(): int { return ++self::$n; }
}
class CA { use CounterTrait; }
class CB { use CounterTrait; }
echo "CA tick: " . CA::tick() . ", " . CA::tick() . "\n";
echo "CB tick: " . CB::tick() . "\n";  // independent static, starts fresh
echo "CA still: " . CA::tick() . "\n";

echo "\n=== trait_exists ===\n";
echo "Timestamped exists: " . (trait_exists('Timestamped') ? "yes" : "no") . "\n";
echo "NotATrait exists: " . (trait_exists('NotATrait') ? "yes" : "no") . "\n";

echo "\n=== class_uses ===\n";
$used = class_uses(Document::class);
echo "Document uses: " . implode(',', array_keys($used)) . "\n";

echo "\ndone\n";

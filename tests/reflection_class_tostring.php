<?php
// ReflectionClass, ReflectionObject and ReflectionEnum string forms for a
// small domain model: interfaces, an abstract base, a final subclass, enums,
// a trait and an object with a dynamic property

interface Identifiable
{
    const PREFIX = 'id-';
    public function id(): string;
}

interface Entity extends Identifiable, Countable, JsonSerializable
{
    public function touch(int $at = 0): static;
}

/**
 * The base every stored record extends.
 */
abstract class Record implements Entity
{
    const TABLE = 'records';
    protected const PAGE_SIZE = 25;
    private const SECRET = [1, 2, 3];
    final public const RATIO = 1.5;

    public static int $instances = 0;
    protected static ?array $cache = null;

    public $meta;
    /** When the record was last saved. */
    protected ?int $savedAt = null;
    private array $dirty = [];
    public readonly string $uuid;

    public function __construct(protected int $key = 0, public string $label = "new")
    {
        $this->uuid = self::PREFIX . $key;
    }

    public function id(): string { return $this->uuid; }
    public function touch(int $at = 0): static { $this->savedAt = $at; return $this; }
    public function count(): int { return count($this->dirty); }
    public function jsonSerialize(): mixed { return ['id' => $this->id()]; }
    abstract protected function validate(array $rules = [], bool $strict = true): bool;
    public static function table(): string { return static::TABLE; }
    private function reset(): void { $this->dirty = []; }
    protected function &field(string $name, mixed ...$fallbacks): mixed { return $this->dirty[$name]; }
}

final class User extends Record implements Stringable
{
    const TABLE = 'users';
    public ?string $email = null;
    public float $score = 0.0;

    protected function validate(array $rules = [], bool $strict = true): bool { return true; }
    public function count(): int { return 1; }
    public function __toString(): string { return $this->label; }
    public static function make(string $email, ?string $label = null): self { return new self(1, $label ?? $email); }
}

enum Suit: string implements JsonSerializable
{
    case Hearts = 'H';
    case Spades = 'S';
    const Wild = self::Spades;

    public function color(): string { return $this === self::Hearts ? 'Red' : 'Black'; }
    public function jsonSerialize(): mixed { return $this->value; }
    public static function fromChar(string $c): self { return self::from($c); }
}

enum Status
{
    case Active;
    case Archived;
}

enum Priority: int
{
    case Low = 1;
    case High = 10;
}

trait Greets
{
    public function greet(string $who = 'world'): string { return "hello $who"; }
    protected static function shout(string $s): string { return strtoupper($s); }
}

class Greeter
{
    use Greets;
    public string $name = 'greeter';
}

echo new ReflectionClass('Identifiable');
echo new ReflectionClass('Entity');
echo new ReflectionClass('Record');
echo new ReflectionClass('User');
echo new ReflectionEnum('Suit');
echo new ReflectionClass('Status');
echo new ReflectionEnum(Priority::class);
echo new ReflectionClass('Greets');
echo new ReflectionClass('Greeter');

$user = User::make('a@example.com');
echo new ReflectionObject($user);

$plain = new stdClass;
$plain->color = 'blue';
$plain->size = 3;
echo new ReflectionObject($plain);

// the string form is what (string) and string interpolation give too
$r = new ReflectionClass('Status');
var_dump((string) $r === $r->__toString());
echo strlen("$r") > 0 ? "interpolates\n" : "empty\n";

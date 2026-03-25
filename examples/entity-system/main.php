<?php
// covers: magic methods (__get, __set, __isset, __unset, __invoke, __toString),
//   ArrayAccess + Countable on user classes, late static binding (static::,
//   static::class), trait conflict resolution (insteadof, as), multiple catch
//   clauses, nested try/catch with re-throw, abstract method enforcement,
//   bitwise operations (flags), do-while, break N / continue N, for loops,
//   multiple interfaces per class, clone with deep copy

// --- interfaces ---

interface Identifiable
{
    public function getId(): int;
}

interface Validatable
{
    public function validate(): bool;
    public function getErrors(): array;
}

// --- traits with conflict ---

trait HasTimestamps
{
    private string $createdAt = "";
    private string $updatedAt = "";

    public function touch(): void
    {
        $this->updatedAt = date("Y-m-d H:i:s");
    }

    public function getInfo(): string
    {
        return "updated: {$this->updatedAt}";
    }
}

trait HasMetadata
{
    private array $metadata = [];

    public function setMeta(string $key, mixed $value): void
    {
        $this->metadata[$key] = $value;
    }

    public function getMeta(string $key): mixed
    {
        return $this->metadata[$key] ?? null;
    }

    public function getInfo(): string
    {
        return "meta keys: " . implode(", ", array_keys($this->metadata));
    }
}

// --- abstract entity with magic methods ---

abstract class Entity implements Identifiable, Validatable
{
    use HasTimestamps, HasMetadata {
        HasTimestamps::getInfo as getTimestampInfo;
        HasMetadata::getInfo insteadof HasTimestamps;
    }

    private static int $nextId = 1;
    protected int $id;
    protected array $attributes = [];
    protected array $errors = [];
    private array $dirty = [];

    public function __construct(array $attributes = [])
    {
        $this->id = self::$nextId++;
        $this->createdAt = date("Y-m-d");
        foreach ($attributes as $k => $v) {
            $this->attributes[$k] = $v;
        }
    }

    public function getId(): int
    {
        return $this->id;
    }

    public function __get(string $name): mixed
    {
        return $this->attributes[$name] ?? null;
    }

    public function __set(string $name, mixed $value): void
    {
        $this->dirty[$name] = true;
        $this->attributes[$name] = $value;
    }

    public function __isset(string $name): bool
    {
        return isset($this->attributes[$name]);
    }

    public function __unset(string $name): void
    {
        unset($this->attributes[$name]);
        unset($this->dirty[$name]);
    }

    public function isDirty(): bool
    {
        return count($this->dirty) > 0;
    }

    public function getDirtyFields(): array
    {
        return array_keys($this->dirty);
    }

    public function toArray(): array
    {
        return ["id" => $this->id, ...$this->attributes];
    }

    public function getErrors(): array
    {
        return $this->errors;
    }

    abstract public function validate(): bool;
    abstract public function getType(): string;

    public function __toString(): string
    {
        return static::class . "#" . $this->id;
    }

    // late static binding for factory
    public static function create(array $attrs = []): static
    {
        return new static($attrs);
    }
}

// --- concrete entities ---

class User extends Entity
{
    public function validate(): bool
    {
        $this->errors = [];
        if (!isset($this->attributes["name"]) || $this->attributes["name"] === "") {
            $this->errors[] = "name is required";
        }
        if (isset($this->attributes["email"]) && strpos($this->attributes["email"], "@") === false) {
            $this->errors[] = "invalid email";
        }
        return count($this->errors) === 0;
    }

    public function getType(): string
    {
        return "user";
    }
}

class Product extends Entity
{
    public function validate(): bool
    {
        $this->errors = [];
        if (!isset($this->attributes["title"]) || $this->attributes["title"] === "") {
            $this->errors[] = "title is required";
        }
        if (isset($this->attributes["price"]) && $this->attributes["price"] < 0) {
            $this->errors[] = "price must be non-negative";
        }
        return count($this->errors) === 0;
    }

    public function getType(): string
    {
        return "product";
    }
}

// --- collection with ArrayAccess + Countable + __invoke ---

class Collection implements ArrayAccess, Countable
{
    private array $items = [];

    public function __construct(array $items = [])
    {
        $this->items = $items;
    }

    public function offsetExists(mixed $offset): bool
    {
        return isset($this->items[$offset]);
    }

    public function offsetGet(mixed $offset): mixed
    {
        return $this->items[$offset] ?? null;
    }

    public function offsetSet(mixed $offset, mixed $value): void
    {
        if ($offset === null) {
            $this->items[] = $value;
        } else {
            $this->items[$offset] = $value;
        }
    }

    public function offsetUnset(mixed $offset): void
    {
        unset($this->items[$offset]);
    }

    public function count(): int
    {
        return count($this->items);
    }

    // __invoke: filter collection when called as function
    public function __invoke(callable $predicate): Collection
    {
        $result = [];
        foreach ($this->items as $item) {
            if ($predicate($item)) $result[] = $item;
        }
        return new Collection($result);
    }

    public function map(callable $fn): Collection
    {
        return new Collection(array_map($fn, $this->items));
    }

    public function each(callable $fn): void
    {
        foreach ($this->items as $k => $v) {
            $fn($v, $k);
        }
    }

    public function first(): mixed
    {
        return $this->items[0] ?? null;
    }

    public function toArray(): array
    {
        return $this->items;
    }

    public function pluck(string $key): Collection
    {
        $result = [];
        foreach ($this->items as $item) {
            if (is_array($item)) {
                $result[] = $item[$key] ?? null;
            } elseif (is_object($item)) {
                $result[] = $item->$key;
            }
        }
        return new Collection($result);
    }
}

// --- bitwise flags ---

const PERM_READ    = 1;
const PERM_WRITE   = 2;
const PERM_DELETE   = 4;
const PERM_ADMIN   = 8;
const PERM_ALL     = 15;

function hasPermission(int $userPerms, int $required): bool
{
    return ($userPerms & $required) === $required;
}

function describePermissions(int $perms): string
{
    $names = [];
    if ($perms & PERM_READ) $names[] = "read";
    if ($perms & PERM_WRITE) $names[] = "write";
    if ($perms & PERM_DELETE) $names[] = "delete";
    if ($perms & PERM_ADMIN) $names[] = "admin";
    return implode(", ", $names);
}

// --- custom exceptions ---

class ValidationException extends RuntimeException
{
    private array $errors;

    public function __construct(array $errors)
    {
        parent::__construct("Validation failed");
        $this->errors = $errors;
    }

    public function getErrors(): array
    {
        return $this->errors;
    }
}

class NotFoundException extends RuntimeException {}
class PermissionException extends RuntimeException {}

function saveEntity(Entity $entity, int $permissions): void
{
    if (!hasPermission($permissions, PERM_WRITE)) {
        throw new PermissionException("write permission required");
    }
    if (!$entity->validate()) {
        throw new ValidationException($entity->getErrors());
    }
}

// ============================================================
// tests
// ============================================================

// === test: entity creation with late static binding ===

$user = User::create(["name" => "Alice", "email" => "alice@example.com"]);
echo "created: " . $user . "\n";
echo "type: " . $user->getType() . "\n";

$product = Product::create(["title" => "Widget", "price" => 9.99]);
echo "created: " . $product . "\n";
echo "type: " . $product->getType() . "\n";

// === test: magic __get, __set, __isset, __unset ===

echo "name: " . $user->name . "\n";
$user->role = "admin";
echo "role: " . $user->role . "\n";
echo "has role: " . (isset($user->role) ? "yes" : "no") . "\n";
echo "dirty: " . implode(", ", $user->getDirtyFields()) . "\n";
unset($user->role);
echo "after unset: " . (isset($user->role) ? "yes" : "no") . "\n";

// === test: trait conflict resolution ===

$user->setMeta("source", "api");
$user->touch();
echo $user->getInfo() . "\n";
echo $user->getTimestampInfo() . "\n";

// === test: ArrayAccess + Countable ===

$coll = new Collection(["a", "b", "c"]);
echo "count: " . count($coll) . "\n";
echo "coll[1]: " . $coll[1] . "\n";
$coll[] = "d";
echo "after push: " . count($coll) . "\n";
$coll[1] = "B";
echo "after set: " . $coll[1] . "\n";
echo "isset[5]: " . (isset($coll[5]) ? "yes" : "no") . "\n";

// === test: __invoke (collection as callable filter) ===

$numbers = new Collection([1, 2, 3, 4, 5, 6, 7, 8]);
$evens = $numbers(function ($n) { return $n % 2 === 0; });
echo "evens: " . implode(", ", $evens->toArray()) . "\n";

// === test: collection methods ===

$users = new Collection([
    ["name" => "Alice", "age" => 30],
    ["name" => "Bob", "age" => 25],
    ["name" => "Charlie", "age" => 35],
]);
$names = $users->pluck("name");
echo "names: " . implode(", ", $names->toArray()) . "\n";

// === test: bitwise operations ===

$perms = PERM_READ | PERM_WRITE;
echo "perms: " . describePermissions($perms) . "\n";
echo "has read: " . (hasPermission($perms, PERM_READ) ? "yes" : "no") . "\n";
echo "has delete: " . (hasPermission($perms, PERM_DELETE) ? "yes" : "no") . "\n";
echo "has r+w: " . (hasPermission($perms, PERM_READ | PERM_WRITE) ? "yes" : "no") . "\n";

$allPerms = PERM_ALL;
echo "all: " . describePermissions($allPerms) . "\n";
echo "xor: " . describePermissions($allPerms ^ PERM_ADMIN) . "\n";
echo "not admin: " . describePermissions($allPerms & ~PERM_ADMIN) . "\n";

// === test: multiple catch clauses ===

$invalidUser = User::create(["name" => "", "email" => "bad"]);
try {
    saveEntity($invalidUser, PERM_READ | PERM_WRITE);
} catch (PermissionException $e) {
    echo "perm error: " . $e->getMessage() . "\n";
} catch (ValidationException $e) {
    echo "validation: " . implode("; ", $e->getErrors()) . "\n";
}

try {
    saveEntity($user, PERM_READ);
} catch (PermissionException $e) {
    echo "perm: " . $e->getMessage() . "\n";
} catch (ValidationException $e) {
    echo "validation: " . implode("; ", $e->getErrors()) . "\n";
}

// === test: nested try/catch with re-throw ===

function riskyOperation(): void
{
    try {
        try {
            throw new RuntimeException("inner error");
        } catch (RuntimeException $e) {
            throw new NotFoundException("not found: " . $e->getMessage());
        }
    } catch (NotFoundException $e) {
        echo "caught nested: " . $e->getMessage() . "\n";
    }
}
riskyOperation();

// === test: do-while ===

$i = 1;
$sum = 0;
do {
    $sum += $i;
    $i++;
} while ($i <= 5);
echo "do-while sum: $sum\n";

// === test: break 2 / continue 2 ===

$found = "";
for ($r = 0; $r < 3; $r++) {
    for ($c = 0; $c < 3; $c++) {
        if ($r === 1 && $c === 1) {
            $found = "$r,$c";
            break 2;
        }
    }
}
echo "break 2: $found\n";

$result = [];
for ($i = 0; $i < 3; $i++) {
    for ($j = 0; $j < 3; $j++) {
        if ($j === 1) continue 2;
        $result[] = "$i:$j";
    }
}
echo "continue 2: " . implode(" ", $result) . "\n";

// === test: __clone magic ===

$original = User::create(["name" => "CloneMe", "email" => "clone@test.com"]);
$original->setMeta("source", "original");
$cloned = clone $original;
$cloned->name = "Cloned";
echo "original name: " . $original->name . "\n";
echo "cloned name: " . $cloned->name . "\n";

// === test: validate interface contract ===

echo "user valid: " . ($user->validate() ? "yes" : "no") . "\n";
echo "user instanceof Identifiable: " . ($user instanceof Identifiable ? "yes" : "no") . "\n";
echo "user instanceof Validatable: " . ($user instanceof Validatable ? "yes" : "no") . "\n";

// === test: toArray with spread ===

$data = $user->toArray();
echo "keys: " . implode(", ", array_keys($data)) . "\n";

echo "done\n";

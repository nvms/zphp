<?php
// covers: abstract classes (abstract + concrete methods), interfaces,
//   multiple interface implementation, traits with methods and properties,
//   trait conflict resolution (insteadof, as), abstract class using traits,
//   constructor promotion (public readonly), readonly properties,
//   union types (int|string), named arguments, static methods and properties,
//   class constants with visibility, late static binding (static:: vs self::),
//   instanceof with interfaces and abstract classes, get_class(), is_a()

// --- interfaces ---

interface Identifiable {
    public function getId(): int;
}

interface Describable {
    public function describe(): string;
}

// --- traits ---

trait Timestamped {
    private string $createdAt = '2024-01-01';
    public function getCreatedAt(): string {
        return $this->createdAt;
    }
    public function setCreatedAt(string $date): void {
        $this->createdAt = $date;
    }
}

trait Labeled {
    private string $label = 'unlabeled';
    public function getLabel(): string {
        return $this->label;
    }
    public function setLabel(string $label): void {
        $this->label = $label;
    }
    public function info(): string {
        return "Label: " . $this->label;
    }
}

trait Tagged {
    public function info(): string {
        return "Tagged item";
    }
    public function tagInfo(): string {
        return "tag-info";
    }
}

// --- abstract class implementing interfaces and using traits ---

abstract class Entity implements Identifiable, Describable {
    use Timestamped;
    use Labeled, Tagged {
        Labeled::info insteadof Tagged;
        Tagged::info as taggedInfo;
    }

    abstract public function getType(): string;

    public function summary(): string {
        return $this->getType() . '#' . $this->getId() . ': ' . $this->describe();
    }
}

// --- class constants with visibility ---

class Status {
    public const ACTIVE = 'active';
    protected const INACTIVE = 'inactive';
    private const DELETED = 'deleted';

    public static function getActive(): string {
        return self::ACTIVE;
    }

    public static function getInactive(): string {
        return self::INACTIVE;
    }

    public static function getDeleted(): string {
        return self::DELETED;
    }
}

// --- late static binding ---

class ParentFactory {
    protected static string $type = 'parent';

    public static function getTypeSelf(): string {
        return self::$type;
    }

    public static function getTypeStatic(): string {
        return static::$type;
    }

    public static function create(): string {
        return 'Created: ' . static::$type;
    }
}

class ChildFactory extends ParentFactory {
    protected static string $type = 'child';
}

// --- concrete class with constructor promotion, readonly, union types, named args ---

class Product extends Entity {
    private static int $counter = 0;
    private static array $registry = [];

    public function __construct(
        public readonly int $id,
        public readonly string $name,
        private int|string $sku = 0
    ) {
        self::$counter++;
        self::$registry[] = $this->name;
    }

    public function getId(): int {
        return $this->id;
    }

    public function describe(): string {
        return $this->name . ' (SKU: ' . $this->sku . ')';
    }

    public function getType(): string {
        return 'Product';
    }

    public function getSku(): int|string {
        return $this->sku;
    }

    public static function getCount(): int {
        return self::$counter;
    }

    public static function getRegistry(): array {
        return self::$registry;
    }
}

// --- another concrete class for instanceof and is_a testing ---

class DigitalProduct extends Product {
    public function __construct(
        int $id,
        string $name,
        public readonly string $format = 'pdf'
    ) {
        parent::__construct($id, $name, 'digital-' . $id);
    }

    public function getType(): string {
        return 'DigitalProduct';
    }

    public function describe(): string {
        return $this->name . ' [' . $this->format . ']';
    }
}

// --- function with union type parameter ---

function formatValue(int|string $value): string {
    if (is_int($value)) {
        return 'int(' . $value . ')';
    }
    return 'string(' . $value . ')';
}

// ====== TESTS ======

echo "=== Test 1: Abstract Class + Interfaces + Traits ===\n";
$p = new Product(id: 1, name: 'Widget', sku: 'W-100');
echo $p->summary() . "\n";
echo $p->getCreatedAt() . "\n";
$p->setLabel('premium');
echo $p->info() . "\n";
echo $p->taggedInfo() . "\n";
echo $p->tagInfo() . "\n";

echo "\n=== Test 2: Constructor Promotion + Readonly ===\n";
$p2 = new Product(2, 'Gadget');
echo "id: " . $p2->id . "\n";
echo "name: " . $p2->name . "\n";
echo "sku: " . $p2->getSku() . "\n";

echo "\n=== Test 3: Named Arguments ===\n";
$p3 = new Product(name: 'Doohickey', id: 3, sku: 'D-300');
echo $p3->describe() . "\n";

echo "\n=== Test 4: Union Types ===\n";
echo formatValue(42) . "\n";
echo formatValue('hello') . "\n";
$p4 = new Product(4, 'Thing', 999);
echo "int sku: " . $p4->getSku() . "\n";
$p5 = new Product(5, 'Other', 'STR-5');
echo "string sku: " . $p5->getSku() . "\n";

echo "\n=== Test 5: Static Methods + Properties ===\n";
echo "Count: " . Product::getCount() . "\n";
$reg = Product::getRegistry();
echo "Registry: " . implode(', ', $reg) . "\n";

echo "\n=== Test 6: Class Constants with Visibility ===\n";
echo "Active: " . Status::ACTIVE . "\n";
echo "Via method active: " . Status::getActive() . "\n";
echo "Via method inactive: " . Status::getInactive() . "\n";
echo "Via method deleted: " . Status::getDeleted() . "\n";

echo "\n=== Test 7: Late Static Binding ===\n";
echo "Parent self: " . ParentFactory::getTypeSelf() . "\n";
echo "Parent static: " . ParentFactory::getTypeStatic() . "\n";
echo "Child self: " . ChildFactory::getTypeSelf() . "\n";
echo "Child static: " . ChildFactory::getTypeStatic() . "\n";
echo "Parent create: " . ParentFactory::create() . "\n";
echo "Child create: " . ChildFactory::create() . "\n";

echo "\n=== Test 8: Inheritance + Override ===\n";
$dp = new DigitalProduct(id: 10, name: 'Ebook');
echo $dp->getType() . "\n";
echo $dp->describe() . "\n";
echo $dp->summary() . "\n";
echo "format: " . $dp->format . "\n";
echo "sku: " . $dp->getSku() . "\n";

echo "\n=== Test 9: instanceof Checks ===\n";
echo ($dp instanceof DigitalProduct ? 'true' : 'false') . "\n";
echo ($dp instanceof Product ? 'true' : 'false') . "\n";
echo ($dp instanceof Entity ? 'true' : 'false') . "\n";
echo ($dp instanceof Identifiable ? 'true' : 'false') . "\n";
echo ($dp instanceof Describable ? 'true' : 'false') . "\n";
echo ($p instanceof DigitalProduct ? 'true' : 'false') . "\n";

echo "\n=== Test 10: get_class and is_a ===\n";
echo get_class($dp) . "\n";
echo get_class($p) . "\n";
echo (is_a($dp, 'Product') ? 'true' : 'false') . "\n";
echo (is_a($dp, 'Entity') ? 'true' : 'false') . "\n";
echo (is_a($dp, 'Identifiable') ? 'true' : 'false') . "\n";
echo (is_a($p, 'DigitalProduct') ? 'true' : 'false') . "\n";

echo "\n=== Test 11: Trait Conflict Resolution ===\n";
echo $p->info() . "\n";
echo $p->taggedInfo() . "\n";

echo "\n=== Test 12: Timestamp Trait State ===\n";
$dp->setCreatedAt('2025-06-15');
echo $dp->getCreatedAt() . "\n";
echo $p->getCreatedAt() . "\n";

echo "\nAll tests passed!\n";

<?php
// covers: attributes on enums, attributes on interfaces, attributes on traits,
//   method attributes on enums/interfaces/traits, property attributes on traits,
//   ReflectionClass::getAttributes for enums/interfaces/traits,
//   ReflectionMethod::getAttributes for enum/trait methods,
//   ReflectionAttribute::getName, ReflectionAttribute::getArguments,
//   ReflectionAttribute::newInstance, attribute filtering by class name

#[Attribute]
class Description {
    public function __construct(public string $text = '') {}
}

#[Attribute]
class Version {
    public function __construct(public int $major = 1, public int $minor = 0) {}
}

#[Attribute]
class DeprecatedNote {
    public function __construct(public string $reason = '') {}
}

#[Attribute]
class PropertyMeta {
    public function __construct(public string $label = '') {}
}

// --- Enum with attributes ---

#[Description('HTTP status codes')]
#[Version(major: 2, minor: 1)]
enum Status: int {
    case OK = 200;
    case NotFound = 404;
    case Error = 500;

    #[DeprecatedNote(reason: 'use statusLine instead')]
    public function label(): string {
        return match($this) {
            self::OK => 'OK',
            self::NotFound => 'Not Found',
            self::Error => 'Error',
        };
    }

    #[Description('full status line')]
    public function statusLine(): string {
        return $this->value . ' ' . $this->label();
    }
}

// --- Interface with attributes ---

#[Description('cacheable resource')]
#[Version(major: 1, minor: 0)]
interface Cacheable {
    #[Description('cache key for this resource')]
    public function cacheKey(): string;

    #[Description('time to live in seconds')]
    public function ttl(): int;
}

// --- Trait with attributes ---

#[Description('adds timestamp tracking')]
trait Timestamped {
    #[PropertyMeta(label: 'creation timestamp')]
    public string $createdAt = '';

    #[PropertyMeta(label: 'last update timestamp')]
    public string $updatedAt = '';

    #[Description('mark as just created')]
    public function touch(): void {
        $this->createdAt = '2025-01-01';
        $this->updatedAt = '2025-01-01';
    }
}

// --- Enum attributes ---

echo "=== Enum Attributes ===\n";

$rc = new ReflectionClass('Status');
$attrs = $rc->getAttributes();
echo "enum attr count: " . count($attrs) . "\n";
echo "attr 0 name: " . $attrs[0]->getName() . "\n";
echo "attr 0 args: " . $attrs[0]->getArguments()[0] . "\n";
echo "attr 1 name: " . $attrs[1]->getName() . "\n";

$filtered = $rc->getAttributes('Description');
echo "filtered count: " . count($filtered) . "\n";
echo "filtered 0 name: " . $filtered[0]->getName() . "\n";

$versionAttr = $rc->getAttributes('Version')[0];
$versionArgs = $versionAttr->getArguments();
echo "version major: " . $versionArgs['major'] . "\n";
echo "version minor: " . $versionArgs['minor'] . "\n";

$versionInst = $versionAttr->newInstance();
echo "version instance class: " . get_class($versionInst) . "\n";
echo "version instance major: " . $versionInst->major . "\n";
echo "version instance minor: " . $versionInst->minor . "\n";

$labelMethod = $rc->getMethod('label');
$labelAttrs = $labelMethod->getAttributes();
echo "label attr count: " . count($labelAttrs) . "\n";
echo "label attr name: " . $labelAttrs[0]->getName() . "\n";
echo "label attr reason: " . $labelAttrs[0]->getArguments()['reason'] . "\n";

$statusLineMethod = $rc->getMethod('statusLine');
$slAttrs = $statusLineMethod->getAttributes();
echo "statusLine attr count: " . count($slAttrs) . "\n";
echo "statusLine attr name: " . $slAttrs[0]->getName() . "\n";

// --- Interface attributes ---

echo "\n=== Interface Attributes ===\n";

$rc2 = new ReflectionClass('Cacheable');
$iAttrs = $rc2->getAttributes();
echo "interface attr count: " . count($iAttrs) . "\n";
echo "attr 0 name: " . $iAttrs[0]->getName() . "\n";
echo "attr 0 args: " . $iAttrs[0]->getArguments()[0] . "\n";
echo "attr 1 name: " . $iAttrs[1]->getName() . "\n";

$descInst = $iAttrs[0]->newInstance();
echo "desc instance class: " . get_class($descInst) . "\n";
echo "desc instance text: " . $descInst->text . "\n";

// note: getMethod on interfaces requires interface methods in ClassDef.methods
// which is tracked separately - test class-level attrs here

// --- Trait attributes ---

echo "\n=== Trait Attributes ===\n";

$rc3 = new ReflectionClass('Timestamped');
$tAttrs = $rc3->getAttributes();
echo "trait attr count: " . count($tAttrs) . "\n";
echo "attr 0 name: " . $tAttrs[0]->getName() . "\n";
echo "attr 0 args: " . $tAttrs[0]->getArguments()[0] . "\n";

$touchMethod = $rc3->getMethod('touch');
$touchAttrs = $touchMethod->getAttributes();
echo "touch attr count: " . count($touchAttrs) . "\n";
echo "touch attr name: " . $touchAttrs[0]->getName() . "\n";

echo "\nDone.\n";

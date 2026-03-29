<?php
// covers: ReflectionClass getProperties/getProperty/hasProperty/newInstanceWithoutConstructor/getShortName/isTrait/getTraitNames/isEnum/getConstants
// covers: ReflectionProperty getName/isPublic/isProtected/isPrivate/getDefaultValue/hasDefaultValue/isInitialized/getDeclaringClass/isReadOnly
// covers: ReflectionMethod invokeArgs/isAbstract/getAttributes
// covers: ReflectionParameter isPromoted/getClass

trait Timestampable {
    public function getTimestamp(): int { return time(); }
}

class Base {
    public string $name = 'default';
    protected int $age = 0;
    private $secret = 'hidden';

    public function __construct(string $name = 'default') {
        $this->name = $name;
    }
}

class Child extends Base {
    use Timestampable;

    public readonly string $tag;

    public function __construct(string $name = 'default', string $tag = 'none') {
        parent::__construct($name);
        $this->tag = $tag;
    }

    public function greet(): string {
        return "Hello, " . $this->name;
    }
}

interface Renderable {
    public function render(): string;
}

enum Color {
    case Red;
    case Green;
    case Blue;
}

enum Suit: string {
    case Hearts = 'H';
    case Diamonds = 'D';
    const WILD = 'joker';
}

// --- ReflectionClass::getProperties ---
$rc = new ReflectionClass('Child');
$props = $rc->getProperties();
$names = array_map(fn($p) => $p->getName(), $props);
sort($names);
echo implode(',', $names) . "\n";

// --- ReflectionClass::getProperty ---
$prop = $rc->getProperty('name');
echo $prop->getName() . "\n";
echo $prop->isPublic() ? 'public' : 'not-public';
echo "\n";

// --- ReflectionClass::hasProperty ---
echo $rc->hasProperty('name') ? 'yes' : 'no';
echo "\n";
echo $rc->hasProperty('nonexistent') ? 'yes' : 'no';
echo "\n";

// --- ReflectionClass::newInstanceWithoutConstructor ---
$obj = $rc->newInstanceWithoutConstructor();
echo $obj->name . "\n";

// --- ReflectionClass::getShortName ---
echo $rc->getShortName() . "\n";

// --- ReflectionClass::isTrait ---
$rcTrait = new ReflectionClass('Timestampable');
echo $rcTrait->isTrait() ? 'yes' : 'no';
echo "\n";
echo $rc->isTrait() ? 'yes' : 'no';
echo "\n";

// --- ReflectionClass::getTraitNames ---
$traits = $rc->getTraitNames();
echo implode(',', $traits) . "\n";

// --- ReflectionClass::isEnum ---
$rcEnum = new ReflectionClass('Color');
echo $rcEnum->isEnum() ? 'yes' : 'no';
echo "\n";
echo $rc->isEnum() ? 'yes' : 'no';
echo "\n";

// --- ReflectionClass::getConstants ---
$rcSuit = new ReflectionClass('Suit');
$consts = $rcSuit->getConstants();
echo isset($consts['WILD']) ? $consts['WILD'] : 'missing';
echo "\n";

// --- ReflectionProperty visibility ---
$rcBase = new ReflectionClass('Base');
$pubProp = $rcBase->getProperty('name');
$protProp = $rcBase->getProperty('age');
$privProp = $rcBase->getProperty('secret');
echo $pubProp->isPublic() ? 'yes' : 'no';
echo "\n";
echo $protProp->isProtected() ? 'yes' : 'no';
echo "\n";
echo $privProp->isPrivate() ? 'yes' : 'no';
echo "\n";

// --- ReflectionProperty::hasDefaultValue/getDefaultValue ---
echo $pubProp->hasDefaultValue() ? 'yes' : 'no';
echo "\n";
echo $pubProp->getDefaultValue() . "\n";
echo $protProp->getDefaultValue() . "\n";

// --- ReflectionProperty::isInitialized ---
$child = new Child('test', 'mytag');
$tagProp = $rc->getProperty('tag');
echo $tagProp->isInitialized($child) ? 'yes' : 'no';
echo "\n";

// --- ReflectionProperty::getDeclaringClass ---
$nameProp = $rc->getProperty('name');
echo $nameProp->getDeclaringClass()->getName() . "\n";

// --- ReflectionProperty::isReadOnly ---
echo $tagProp->isReadOnly() ? 'yes' : 'no';
echo "\n";
echo $pubProp->isReadOnly() ? 'yes' : 'no';
echo "\n";

// --- ReflectionMethod::invokeArgs ---
$rm = new ReflectionMethod('Child', 'greet');
$result = $rm->invokeArgs($child, []);
echo $result . "\n";

// --- ReflectionMethod::isAbstract ---
echo $rm->isAbstract() ? 'yes' : 'no';
echo "\n";
$rmIface = new ReflectionMethod('Renderable', 'render');
echo $rmIface->isAbstract() ? 'yes' : 'no';
echo "\n";

// --- ReflectionMethod::getAttributes ---
$attrs = $rm->getAttributes();
echo count($attrs) . "\n";

// --- ReflectionParameter::isPromoted ---
$ctor = $rc->getConstructor();
$params = $ctor->getParameters();
echo $params[0]->isPromoted() ? 'yes' : 'no';
echo "\n";

// --- ReflectionParameter::getClass (via getType for non-builtin) ---
class TypedParam {
    public function take(Base $b): void {}
}
$rmTyped = new ReflectionMethod('TypedParam', 'take');
$typedParams = $rmTyped->getParameters();
$type = $typedParams[0]->getType();
echo $type !== null ? $type->getName() : 'null';
echo "\n";

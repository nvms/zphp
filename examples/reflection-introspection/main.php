<?php
// covers: ReflectionClass methods, ReflectionMethod parameter/type inspection,
//   ReflectionProperty default values + types, ReflectionFunction,
//   isInternal/isUserDefined, class hierarchy walks

interface Shape {
    public function area(): float;
    public function describe(): string;
}

abstract class AbstractShape implements Shape {
    public function __construct(protected string $name) {}
    public function describe(): string { return "{$this->name}: " . round($this->area(), 2); }
    abstract public function area(): float;
}

class Circle extends AbstractShape {
    public function __construct(string $name, public readonly float $radius) {
        parent::__construct($name);
    }
    public function area(): float { return pi() * $this->radius ** 2; }
}

class Rectangle extends AbstractShape {
    public function __construct(
        string $name,
        public readonly float $width,
        public readonly float $height = 1.0,
    ) {
        parent::__construct($name);
    }
    public function area(): float { return $this->width * $this->height; }
    public function isSquare(): bool { return abs($this->width - $this->height) < 1e-9; }
}

echo "=== class metadata ===\n";
$r = new ReflectionClass(Circle::class);
echo "name: " . $r->getName() . "\n";
echo "is abstract: " . ($r->isAbstract() ? "yes" : "no") . "\n";
echo "is interface: " . ($r->isInterface() ? "yes" : "no") . "\n";
echo "is user-defined: " . ($r->isUserDefined() ? "yes" : "no") . "\n";
$parent = $r->getParentClass();
echo "parent: " . ($parent ? $parent->getName() : "none") . "\n";
$ifaces = $r->getInterfaceNames();
echo "interfaces: " . implode(',', $ifaces) . "\n";

echo "\n=== walk up hierarchy ===\n";
$cur = $r;
while ($cur) {
    echo "  " . $cur->getName() . " (abstract: " . ($cur->isAbstract() ? "y" : "n") . ")\n";
    $cur = $cur->getParentClass();
}

echo "\n=== methods on class ===\n";
foreach ($r->getMethods() as $m) {
    $params = [];
    foreach ($m->getParameters() as $p) {
        $type = $p->getType();
        $tname = $type instanceof ReflectionNamedType ? $type->getName() : 'mixed';
        $opt = $p->isOptional() ? '?' : '';
        $params[] = "$opt$tname \$" . $p->getName();
    }
    $rt = $m->getReturnType();
    $rtname = $rt instanceof ReflectionNamedType ? $rt->getName() : 'void';
    echo "  " . $m->getName() . "(" . implode(', ', $params) . "): " . $rtname . "\n";
}

echo "\n=== properties (non-promoted decl) ===\n";
class Box {
    public string $label = 'box';
    protected int $count = 0;
    public readonly float $weight;
    public function __construct(float $w = 1.0) { $this->weight = $w; }
}
$rb = new ReflectionClass(Box::class);
foreach ($rb->getProperties() as $p) {
    $vis = $p->isPublic() ? 'public' : ($p->isProtected() ? 'protected' : 'private');
    $ro = $p->isReadOnly() ? ' readonly' : '';
    $default = $p->hasDefaultValue() ? " = " . var_export($p->getDefaultValue(), true) : '';
    echo "  $vis$ro \$" . $p->getName() . "$default\n";
}

echo "\n=== Rectangle promoted properties (type preserved) ===\n";
$rr = new ReflectionClass(Rectangle::class);
foreach ($rr->getProperties() as $p) {
    $t = $p->getType();
    $tname = $t instanceof ReflectionNamedType ? $t->getName() : 'no-type';
    $vis = $p->isPublic() ? 'public' : ($p->isProtected() ? 'protected' : 'private');
    $ro = $p->isReadOnly() ? ' readonly' : '';
    echo "  $vis$ro $tname \$" . $p->getName() . "\n";
}

echo "\n=== constructor inspection ===\n";
$ctor = $rr->getConstructor();
echo "params: " . $ctor->getNumberOfParameters() . " (required: " . $ctor->getNumberOfRequiredParameters() . ")\n";
foreach ($ctor->getParameters() as $p) {
    $promo = $p->isPromoted() ? ' [promoted]' : '';
    echo "  \$" . $p->getName() . $promo;
    if ($p->isDefaultValueAvailable()) {
        echo " = " . var_export($p->getDefaultValue(), true);
    }
    echo "\n";
}

echo "\n=== instantiate via reflection ===\n";
$shape = $rr->newInstance('mySquare', 3.0, 3.0);
echo "type: " . get_class($shape) . "\n";
echo "describe: " . $shape->describe() . "\n";
echo "isSquare: " . ($shape->isSquare() ? "yes" : "no") . "\n";

echo "\n=== set property via reflection ===\n";
$c = new Circle('test', 2.0);
echo "before: " . $c->describe() . "\n";
$radius_prop = new ReflectionProperty(Circle::class, 'radius');
echo "isReadonly: " . ($radius_prop->isReadonly() ? "yes" : "no") . "\n";
$weight_prop = new ReflectionProperty(Box::class, 'weight');
echo "Box::weight isReadonly: " . ($weight_prop->isReadonly() ? "yes" : "no") . "\n";

echo "\n=== ReflectionFunction for closures and named ===\n";
function pure_func(int $x, string $name = 'default'): string { return "$name=$x"; }
$rf = new ReflectionFunction('pure_func');
echo "params: " . $rf->getNumberOfParameters() . "\n";
echo "required: " . $rf->getNumberOfRequiredParameters() . "\n";
echo "return: " . $rf->getReturnType()->getName() . "\n";

$rc = new ReflectionFunction(fn(int $a, int $b) => $a + $b);
echo "closure params: " . $rc->getNumberOfParameters() . "\n";

echo "\n=== user-defined check ===\n";
$user = new ReflectionClass(Circle::class);
echo "Circle user-defined: " . ($user->isUserDefined() ? "yes" : "no") . "\n";

echo "\n=== implementsInterface / isSubclassOf ===\n";
echo "Circle implements Shape: " . ($r->implementsInterface(Shape::class) ? "yes" : "no") . "\n";
echo "Circle isSubclassOf AbstractShape: " . ($r->isSubclassOf(AbstractShape::class) ? "yes" : "no") . "\n";
echo "Circle isSubclassOf Rectangle: " . ($r->isSubclassOf(Rectangle::class) ? "yes" : "no") . "\n";

echo "\ndone\n";

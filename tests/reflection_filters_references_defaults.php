<?php
// getProperties/getConstants filters, ReflectionEnum::getCase errors,
// ReflectionReference, private and uncloneable reflectors, property
// defaults and settable types

class C {
    public $pub;
    protected $prot;
    private $priv;
    public static $stat;
    public readonly int $ro;
    public const A = 1;
    protected const B = 2;
    final public const F = 3;
    public int $typed;
    public ?int $nullable = null;
    public $virt { get => 1; }
    public int $wide { get => $this->wide; set(int|string $value) => (int) $value; }
    public function __construct(public $promoted = 5) {}
}
enum Suit { case Hearts; const Alias = self::Hearts; }

$rc = new ReflectionClass('C');
$names = fn($list) => array_map(fn($p) => $p->name, $list);
var_dump($names($rc->getProperties(0)));
var_dump($names($rc->getProperties(ReflectionProperty::IS_PRIVATE | ReflectionProperty::IS_PROTECTED)));
var_dump($names($rc->getProperties(ReflectionProperty::IS_READONLY)));
var_dump($names($rc->getProperties(ReflectionProperty::IS_VIRTUAL)));
var_dump(count($rc->getProperties(null)) === count($rc->getProperties()));
var_dump($rc->getConstants(ReflectionClassConstant::IS_PROTECTED), $rc->getConstants(ReflectionClassConstant::IS_FINAL));
var_dump(count($rc->getReflectionConstants(ReflectionClassConstant::IS_PUBLIC)));

$re = new ReflectionEnum('Suit');
try {
    $re->getCase('Alias');
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}
try {
    $re->getCase('Nope');
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}

$ary = [0, 1, 2];
$ref1 = &$ary[1];
unset($ref1);
$ref2 = &$ary[2];
var_dump(ReflectionReference::fromArrayElement($ary, 0), ReflectionReference::fromArrayElement($ary, 1));
$r2 = ReflectionReference::fromArrayElement($ary, 2);
$copy = [&$ary[2]];
var_dump($r2 instanceof ReflectionReference, strlen($r2->getId()), $r2->getId() === ReflectionReference::fromArrayElement($ary, 2)->getId());
try {
    ReflectionReference::fromArrayElement($ary, 9);
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}
try {
    ReflectionReference::fromArrayElement($ary, []);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    clone $rc;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

foreach (['pub', 'stat', 'typed', 'nullable', 'promoted', 'virt'] as $p) {
    $rp = new ReflectionProperty('C', $p);
    echo $p, " "; var_dump($rp->hasDefaultValue(), @$rp->getDefaultValue());
}
foreach (['pub', 'typed', 'virt', 'wide'] as $p) {
    echo (new ReflectionProperty('C', $p))->getSettableType() ?? 'none', "\n";
}

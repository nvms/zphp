<?php
// covers: ReflectionClassConstant getName getValue getDeclaringClass getAttributes isPublic isEnumCase ReflectionClass::getReflectionConstants getReflectionConstant hasConstant getConstant

#[Attribute]
class MyConstAttr {
    public function __construct(public string $desc = '') {}
}

class Foo {
    const BAR = 42;
    const BAZ = 'hello';

    #[MyConstAttr('important')]
    const ANNOTATED = true;

    public static $notConst = 'nope';
}

class Child extends Foo {
    const CHILD_CONST = 99;
}

// --- getConstants only returns constants, not static props ---
$rc = new ReflectionClass('Foo');
$consts = $rc->getConstants();
echo isset($consts['BAR']) ? 'yes' : 'no';
echo "\n";
echo isset($consts['notConst']) ? 'yes' : 'no';
echo "\n";
echo $consts['BAR'] . "\n";
echo $consts['BAZ'] . "\n";

// --- hasConstant ---
echo $rc->hasConstant('BAR') ? 'yes' : 'no';
echo "\n";
echo $rc->hasConstant('notConst') ? 'yes' : 'no';
echo "\n";

// --- getConstant ---
echo $rc->getConstant('BAR') . "\n";
echo !$rc->hasConstant('NOPE') ? 'false' : 'other';
echo "\n";

// --- getReflectionConstants ---
$rcs = $rc->getReflectionConstants();
echo count($rcs) . "\n";
$names = [];
foreach ($rcs as $rcc) {
    $names[] = $rcc->getName();
}
sort($names);
echo implode(',', $names) . "\n";

// --- ReflectionClassConstant methods ---
$rcc = $rc->getReflectionConstant('BAR');
echo $rcc->getName() . "\n";
echo $rcc->getValue() . "\n";
echo $rcc->isPublic() ? 'yes' : 'no';
echo "\n";
echo $rcc->isProtected() ? 'yes' : 'no';
echo "\n";
echo $rcc->isPrivate() ? 'yes' : 'no';
echo "\n";
echo $rcc->getDeclaringClass()->getName() . "\n";

// --- attributes on constants ---
$rcc2 = $rc->getReflectionConstant('ANNOTATED');
$attrs = $rcc2->getAttributes();
echo count($attrs) . "\n";
echo $attrs[0]->getName() . "\n";
$inst = $attrs[0]->newInstance();
echo $inst->desc . "\n";

// --- inherited constants ---
$rcChild = new ReflectionClass('Child');
echo $rcChild->hasConstant('CHILD_CONST') ? 'yes' : 'no';
echo "\n";
echo $rcChild->hasConstant('BAR') ? 'yes' : 'no';
echo "\n";
echo $rcChild->getConstant('BAR') . "\n";

// --- enum constants ---
enum Color {
    case Red;
    case Green;
    const DEFAULT_NAME = 'Red';
}

$rcEnum = new ReflectionClass('Color');
echo $rcEnum->hasConstant('Red') ? 'yes' : 'no';
echo "\n";
echo $rcEnum->hasConstant('DEFAULT_NAME') ? 'yes' : 'no';
echo "\n";

$enumRcc = $rcEnum->getReflectionConstant('Red');
echo $enumRcc->isEnumCase() ? 'yes' : 'no';
echo "\n";

$nonCaseRcc = $rcEnum->getReflectionConstant('DEFAULT_NAME');
echo $nonCaseRcc->isEnumCase() ? 'yes' : 'no';
echo "\n";

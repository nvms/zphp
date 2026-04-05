<?php
// covers: closure attributes, arrow function attributes, ReflectionFunction::getAttributes on closures

#[Attribute]
class Tag {
    public function __construct(public string $label = '') {}
}

// basic closure with attribute
$fn = #[Tag('hello')] function() { return 42; };
echo $fn() . "\n";

$rf = new ReflectionFunction($fn);
$attrs = $rf->getAttributes();
echo count($attrs) . "\n";
echo $attrs[0]->getName() . "\n";
$inst = $attrs[0]->newInstance();
echo $inst->label . "\n";

// closure without attributes
$fn2 = function() { return 99; };
$rf2 = new ReflectionFunction($fn2);
echo count($rf2->getAttributes()) . "\n";

// arrow function with attribute
$fn3 = #[Tag('arrow')] fn() => 7;
echo $fn3() . "\n";
$rf3 = new ReflectionFunction($fn3);
$attrs3 = $rf3->getAttributes();
echo count($attrs3) . "\n";
echo $attrs3[0]->getName() . "\n";
$inst3 = $attrs3[0]->newInstance();
echo $inst3->label . "\n";

// multiple attributes on closure
$fn4 = #[Tag('first')] #[Tag('second')] function() { return 1; };
$rf4 = new ReflectionFunction($fn4);
echo count($rf4->getAttributes()) . "\n";

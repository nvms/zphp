<?php
// attributes before a group of constants or properties belong to every
// member of the group, and members of an anonymous class take attributes
#[Attribute(Attribute::TARGET_ALL)]
class Tag { function __construct(public $v = null) {} }
class Grouped {
    #[Tag(1)] public const A = 1, B = 2;
    #[Tag(2)] public $x, $y = 3;
}
foreach (['A', 'B'] as $c) var_dump((new ReflectionClassConstant('Grouped', $c))->getAttributes()[0]->getArguments());
foreach (['x', 'y'] as $p) var_dump((new ReflectionProperty('Grouped', $p))->getAttributes()[0]->getArguments());
$o = new class {
    #[Tag] public $p = 1;
    #[Tag] const C = 2;
    #[Tag] function m() { return 3; }
};
echo $o->p, $o::C, $o->m(), "\n";

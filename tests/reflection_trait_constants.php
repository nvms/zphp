<?php
// a trait's reflector sees the constants the trait declares

trait T {
    /** the answer */
    public const ANSWER = 42;
    final protected const NAME = 'T';
}

class C {
    use T;
}

$rt = new ReflectionClass(T::class);
var_dump($rt->getConstant('ANSWER'));
var_dump($rt->hasConstant('NAME'));
$c = $rt->getReflectionConstant('ANSWER');
var_dump($c->getDeclaringClass()->getName());
var_dump($c->getValue());
var_dump($c->getDocComment());
var_dump($rt->getReflectionConstant('NAME')->getValue());
var_dump($rt->getReflectionConstant('MISSING'));

$rc = new ReflectionClass(C::class);
var_dump($rc->getConstant('ANSWER'));
var_dump($rc->getReflectionConstant('ANSWER')->getDeclaringClass()->getName());
var_dump($rc->getReflectionConstant('ANSWER')->getDocComment());

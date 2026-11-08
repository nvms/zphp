<?php
// php evaluates attribute arguments only when reflection asks for them, so
// declaring a class with arguments it can't resolve yet creates nothing
class Base { const KIND = 'base'; }
#[Attribute(Attribute::TARGET_ALL)]
class Marker extends Base { function __construct(public $v = null) {} }
#[Marker(Marker::KIND)]
class Marked extends Base {}
#[Marker(Later::X)] #[Marker(Missing::X)] #[Marker(Deferred::LATE)]
class Target {}
class Deferred { const LATE = LATE_VALUE; }
var_dump(new stdClass);
class Later { const X = 'later'; }
define('LATE_VALUE', 'late');
echo "reflecting\n";
foreach (['Marked', 'Target'] as $c) {
    foreach ((new ReflectionClass($c))->getAttributes() as $a) {
        try { var_dump($a->getArguments()[0]); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
    }
}

<?php
// what ReflectionAttribute and getAttributes() check: the target flags an
// attribute class declares, the filter arguments, the constructor
#[Attribute("all")] class BadFlagsType {}
#[Attribute(-1)] class BadFlagsValue {}
#[Attribute(Attribute::TARGET_CONSTANT)] class ConstOnly {}
#[Attribute] class PrivateCtor { private function __construct() {} }
#[Attribute] class NeedsArg { function __construct(string $name) {} }

#[BadFlagsType] #[BadFlagsValue] #[ConstOnly] #[PrivateCtor] #[NeedsArg]
class Target {}

foreach ((new ReflectionClass('Target'))->getAttributes() as $a) {
    // the message's "passed in" part names the attribute's line in php
    try { $a->newInstance(); echo "built\n"; } catch (Error $e) { echo get_class($e), ': ', strtok($e->getMessage(), ','), "\n"; }
}
foreach ([[Target::class, 3], ['NoSuchClass', ReflectionAttribute::IS_INSTANCEOF]] as [$filter, $flags]) {
    try { (new ReflectionClass('Target'))->getAttributes($filter, $flags); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
    try { (new ReflectionFunction('strlen'))->getAttributes($filter, $flags); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
}
var_dump((new ReflectionClass('Target'))->getAttributes()[0]);

// a trait's property, reflected on the trait and on a class using it
#[Attribute] class Tag {}
trait HasTagged { #[Tag] public $tagged; }
class UsesTagged { use HasTagged; }
class RedeclaresTagged { use HasTagged; public $tagged; }
foreach (['HasTagged', 'UsesTagged', 'RedeclaresTagged'] as $c) {
    var_dump(count((new ReflectionProperty($c, 'tagged'))->getAttributes()));
}

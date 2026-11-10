<?php
// a readonly property a class takes from a trait, in a class declared by
// eval, is initialized once through ReflectionProperty::setValue (phpunit's
// mock objects)
class State {}
trait StubApi {
    private readonly State $__phpunit_state;
    public function state() { return $this->__phpunit_state ?? null; }
}
interface StubInternal {}
class FixtureService { public function __construct(private string $x = 'a') {} function fetch($k) {} }
eval('declare(strict_types=1); class Mock extends FixtureService implements StubInternal { use StubApi; public function fetch($k) { return 1; } }');
$o = (new ReflectionClass('Mock'))->newInstanceWithoutConstructor();
$r = new ReflectionObject($o);
$r->getProperty('__phpunit_state')->setValue($o, new State);
var_dump($o->state());
try {
    $r->getProperty('__phpunit_state')->setValue($o, new State);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

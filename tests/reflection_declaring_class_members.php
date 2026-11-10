<?php
// ReflectionMethod::$class and ReflectionProperty::$class name the declaring
// class; an ancestor's private property is invisible; dynamic properties are
// reflected from objects; getValue/setValue read and write like code in the
// reflected class's scope (hooks, __get, uninitialized typed properties)

class A {
    public $pubA = 'pubA in A';
    protected $protA = 'protA in A';
    private $privA = 'privA in A';
    function f() { return __METHOD__; }
    function G() {}
}
#[AllowDynamicProperties]
class B extends A {
    public $pubB = 'pubB in B';
}

$m = new ReflectionMethod('B', 'f');
var_dump($m->class, $m->name);
var_dump((array) $m);
$c = new ReflectionClass('B');
var_dump($c->getMethod('g')->name, $c->getMethod('g')->class);
foreach ($c->getMethods() as $method) echo $method->class, '::', $method->name, "\n";
foreach ($c->getProperties() as $prop) echo $prop->class, '::$', $prop->name, "\n";
var_dump($c->hasProperty('privA'), $c->hasProperty('pubA'));
try {
    $c->getProperty('privA');
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}
try {
    new ReflectionProperty('B', 'privA');
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}
try {
    new ReflectionProperty('NoSuchClass', 'p');
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}
try {
    new ReflectionProperty([], 'p');
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
var_dump($c->getProperty('A::pubA')->class);
try {
    $c->getProperty('stdClass::x');
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}

$b = new B;
$b->dyn = 5;
$p = new ReflectionProperty($b, 'dyn');
var_dump($p, $p->isDefault(), $p->isDynamic(), $p->getValue($b), $p->getDeclaringClass()->name);
$o = new ReflectionObject($b);
var_dump($o->hasProperty('dyn'), $o->getProperty('dyn')->class, count($o->getProperties()));
var_dump((new ReflectionClass('B'))->hasProperty('dyn'));
$prot = new ReflectionProperty('B', 'protA');
var_dump($prot->class, $prot->getValue($b), $prot->getMangledName(), (new ReflectionProperty('A', 'privA'))->getMangledName());
$prot->setValue($b, 'changed');
var_dump($prot->getValue($b));
try {
    $prot->getValue();
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    $prot->getValue(new stdClass);
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}

class Hooked {
    public string $name { get => strtoupper($this->name); set => $this->name = $value . '!'; }
    public int $typed;
    public function __get($n) { return strlen($n); }
}
$h = new Hooked;
$rp = new ReflectionProperty('Hooked', 'name');
$rp->setValue($h, 'abc');
var_dump($rp->getValue($h));
$typed = new ReflectionProperty('Hooked', 'typed');
var_dump($typed->isInitialized($h));
try {
    $typed->getValue($h);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
unset($h->typed);
var_dump($typed->getValue($h));

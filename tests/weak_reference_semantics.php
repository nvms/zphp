<?php
// a WeakReference doesn't keep its object alive: get() returns null once the
// object is freed, php hands out one WeakReference per object, and inside the
// destructor the object can still be reached
class Session {
    public function __construct(public string $id) {}
    public function __destruct() {
        global $ref;
        echo "destruct {$this->id}, reachable: ", var_export($ref?->get() === $this, true), "\n";
    }
}
$ref = WeakReference::create(new Session('temp'));
var_dump($ref->get());
$s = new Session('kept');
$ref = WeakReference::create($s);
var_dump($ref === WeakReference::create($s));
var_dump($ref->get()->id);
var_dump($ref);
unset($s);
var_dump($ref->get());
$cache = [];
foreach (['a', 'b'] as $key) {
    $obj = new stdClass;
    $cache[$key] = WeakReference::create($obj);
}
var_dump($cache['a']->get(), $cache['b']->get() instanceof stdClass);
unset($obj);
var_dump($cache['b']->get());
try { clone $ref; } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { serialize($ref); } catch (Exception $e) { echo $e->getMessage(), "\n"; }
$cycle = new stdClass;
$cycle->self = $cycle;
$weak = WeakReference::create($cycle);
unset($cycle);
var_dump($weak->get() !== null);
gc_collect_cycles();
var_dump($weak->get());

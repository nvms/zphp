<?php
class ProxyEdge {
    public int $value = 3;
    public mixed $link = null;
}
$r = new ReflectionClass(ProxyEdge::class);
$b = new ProxyEdge();
$p = $r->newLazyProxy(fn () => $b);
$rp = $r->getProperty('value');
var_dump($rp->isLazy($p));
$rp->setValue($p, 9);
var_dump($rp->isLazy($p), $b->value);
$ref =& $p->value;
$ref = 21;
echo $b->value, ':', $p->value, "\n";
$b->value = 22;
echo $ref, "\n";
echo json_encode($p), "\n";
echo json_encode(get_object_vars($p)), "\n";
$c = clone $p;
var_dump($r->initializeLazyObject($c) !== $c);
$c->value = 80;
echo $p->value, ':', $c->value, "\n";
$skip = $r->newLazyProxy(fn () => $b, ReflectionClass::SKIP_INITIALIZATION_ON_SERIALIZE);
echo serialize($skip), "\n";
var_dump($r->isUninitializedLazyObject($skip));
foreach ([null, 123, new stdClass()] as $bad) {
    $invalid = $r->newLazyProxy(fn () => $bad);
    try { $r->initializeLazyObject($invalid); } catch (Throwable $e) { echo get_class($e), ':', $e->getMessage(), "\n"; }
    var_dump($r->isUninitializedLazyObject($invalid));
}
$self = $r->newLazyProxy(fn ($proxy) => $proxy);
try { $self->value; } catch (Throwable $e) { echo get_class($e), ':', $e->getMessage(), "\n"; }
class ProxyCycle {
    public mixed $link = null;
    public function __destruct() { echo "cycle released\n"; }
}
function proxyCycle() {
    $r = new ReflectionClass(ProxyCycle::class);
    $b = new ProxyCycle();
    $p = $r->newLazyProxy(fn () => $b);
    $p->link = $p;
}
proxyCycle();
gc_collect_cycles();
echo "collected\n";
class ProxyParent { public int $x = 1; }
class ProxyChild extends ProxyParent {}
class ProxyOverride extends ProxyParent { public function __clone() {} }
class ProxyExtra extends ProxyParent { public int $extra = 2; }
foreach ([ProxyChild::class, ProxyOverride::class, ProxyExtra::class] as $class) {
    $rc = new ReflectionClass($class);
    $proxy = $rc->newLazyProxy(fn () => new ProxyParent());
    try { echo $proxy->x, "\n"; }
    catch (Throwable $e) { echo get_class($e), "\n"; }
}
$rollback = $r->newLazyProxy(function ($proxy) { $proxy->value = 99; throw new RuntimeException('rollback'); });
try { $rollback->value; } catch (Throwable $e) {}
$r->markLazyObjectAsInitialized($rollback);
echo $rollback->value, "\n";

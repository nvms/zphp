<?php
class ProxyService {
    public int $value = 1;
    private string $label = 'default';
    public array $items = [];
    public function configure(string $label): void { $this->label = $label; }
    public function read(): string { return $this->label . ':' . $this->value; }
    public function identity(): object { return $this; }
}
$r = new ReflectionClass(ProxyService::class);
$backing = new ProxyService();
$backing->value = 42;
$backing->configure('factory');
$calls = 0;
$p = $r->newLazyProxy(function ($proxy) use (&$calls, $backing) { ++$calls; return $backing; });
$alias = $p;
var_dump($p->identity() === $p, $r->isUninitializedLazyObject($p), $calls);
echo $p->read(), "\n";
var_dump($p === $alias, $p !== $backing, $calls, $r->initializeLazyObject($p) === $backing);
$p->value = 73;
echo $backing->value, "\n";
$backing->value = 91;
echo $p->value, "\n";
$p->items[] = 'shared';
echo implode(',', $backing->items), "\n";
var_dump(isset($p->value));
unset($p->value);
var_dump(isset($backing->value));
$backing->value = 12;
echo (new ReflectionProperty(ProxyService::class, 'value'))->getValue($p), "\n";
var_dump($r->markLazyObjectAsInitialized($p) === $backing);

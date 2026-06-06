<?php
// covers: nested `??=` must not warn on an absent INTERMEDIATE array key.
// php suppresses undefined-key warnings across the whole `??=` read chain;
// the result and the (lack of) warnings must match. run with E_ALL so any
// spurious "Undefined array key" warning shows as a diff.

error_reporting(E_ALL);

$cache = [];
$cache['Widget']['Calc'] ??= 'value';
$cache['Widget']['Calc'] ??= 'ignored';
print_r($cache);

// three levels deep, all intermediate keys absent
$deep = [];
$deep['a']['b']['c'] ??= 1;
print_r($deep);

// single level still fine
$flat = [];
$flat['x'] ??= 'first';
$flat['x'] ??= 'second';
echo $flat['x'], "\n";

// intermediate key present, leaf absent
$mix = ['k' => ['present' => 1]];
$mix['k']['leaf'] ??= 2;
echo $mix['k']['present'], ' ', $mix['k']['leaf'], "\n";

// property-backed nested ??= (the symfony/type-info cache pattern)
class Cache {
    public array $store = [];
    public function get(string $a, string $b): string {
        return $this->store[$a][$b] ??= "$a:$b";
    }
}
$c = new Cache();
echo $c->get('Foo', 'Bar'), "\n";
echo $c->get('Foo', 'Bar'), "\n"; // cached, same result
print_r($c->store);

// numeric intermediate keys
$n = [];
$n[5][10] ??= 'ten';
print_r($n);

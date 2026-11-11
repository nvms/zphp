<?php
// SplFixedArray and the InternalIterator its getIterator() returns, as php's
// spl_fixedarray has them

function show($label, $f) {
    try {
        $r = $f();
        echo $label, ': ';
        var_dump($r);
    } catch (Throwable $e) {
        echo $label, ': ', get_class($e), ': ', $e->getMessage(), "\n";
    }
}

$a = new SplFixedArray(3);
$a[0] = 'zero';
$a['1'] = 'one';
$a[true] = 'one again';
show('get 0', fn() => $a[0]);
show('get "01"', fn() => $a['01']);
show('get "x"', fn() => $a['x']);
show('get []', fn() => $a[[]]);
show('get 3', fn() => $a[3]);
show('get -1', fn() => $a[-1]);
show('append', function () use ($a) { $a[] = 1; });
show('offsetSet null', fn() => $a->offsetSet(null, 1));
show('offsetGet null', fn() => $a->offsetGet(null));
show('isset 2', fn() => isset($a[2]));
show('isset 0', fn() => isset($a[0]));
show('isset 9', fn() => isset($a[9]));
show('offsetExists "1"', fn() => $a->offsetExists('1'));
show('unset 9', function () use ($a) { unset($a[9]); });
unset($a[1]);
print_r($a);
var_dump($a->toArray(), count($a), $a->getSize());

echo "-- iteration\n";
foreach ($a as $k => $v) {
    foreach ($a as $k2 => $v2) echo "$k:$k2 ";
}
echo "\n";
$it = $a->getIterator();
var_dump(get_class($it), $it->valid(), $it->key(), $it->current());
$it->next();
$it->next();
$it->next();
var_dump($it->valid());
show('current past end', fn() => $it->current());
show('construct InternalIterator', fn() => new InternalIterator());
show('clone InternalIterator', fn() => clone $it);

echo "-- size\n";
$a->setSize(5);
var_dump($a->getSize());
$a->setSize(1);
var_dump($a->toArray());
show('negative size', fn() => $a->setSize(-1));
show('negative construct', fn() => new SplFixedArray(-1));
$a->__construct(10);
var_dump($a->getSize());

echo "-- fromArray\n";
var_dump(SplFixedArray::fromArray([1 => 'b', 3 => 'd'])->toArray());
var_dump(SplFixedArray::fromArray([1 => 'b', 3 => 'd'], false)->toArray());
show('string key', fn() => SplFixedArray::fromArray(['a' => 1]));
show('negative key', fn() => SplFixedArray::fromArray([-1 => 1]));

echo "-- serialization\n";
$s = new SplFixedArray(2);
$s[0] = [1, 2];
$s->prop = 'p';
echo serialize($s), "\n";
var_dump(unserialize(serialize($s)));
echo json_encode($s), "\n";
var_dump((array) $s);
$c = clone $s;
$c[1] = 'changed';
var_dump($s[1], $c[1]);

class MyFixed extends SplFixedArray {
    public $x = 1;
    public function count(): int { return 99; }
}
$m = new MyFixed(2);
var_dump(count($m), $m->getSize(), get_mangled_object_vars($m));
var_dump($m);

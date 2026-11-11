<?php
// SplObjectStorage and MultipleIterator as php's spl_observer has them

function show($label, $f) {
    try {
        $r = $f();
        echo $label, ': ';
        var_dump($r);
    } catch (Throwable $e) {
        echo $label, ': ', get_class($e), ': ', $e->getMessage(), "\n";
    }
}

class Item {
    public function __construct(public $n) {}
}

$a = new Item(1);
$b = new Item(2);
$c = new Item(3);
$s = new SplObjectStorage();
$s[$a] = 'a';
$s[$b] = null;
$s->offsetSet($c, ['c']);
show('count', fn() => count($s));
show('get a', fn() => $s[$a]);
show('get missing', fn() => $s[new Item(9)]);
show('coalesce missing', fn() => $s[new Item(9)] ?? 'none');
show('isset b', fn() => isset($s[$b]));
show('empty b', fn() => empty($s[$b]));
show('exists c', fn() => $s->offsetExists($c));
show('offsetGet string', fn() => $s->offsetGet('x'));
show('append', function () use ($s) { $s[] = 1; });
$s[$a] = 'a again';
foreach ($s as $i => $o) {
    echo $i, ' ', $o->n, ' ', json_encode($s->getInfo()), "\n";
    $s->setInfo("info $i");
}
var_dump($s);

echo "-- seek and position\n";
$s->rewind();
$s->seek(2);
var_dump($s->key(), $s->current()->n);
show('seek out', fn() => $s->seek(3));
$s->rewind();
$s->next();
unset($s[$a]);
var_dump($s->key(), $s->valid(), $s->current()->n);
$s->offsetUnset($b);
var_dump($s->key(), count($s));
show('current empty', fn() => (new SplObjectStorage)->current());

echo "-- set operations\n";
$x = new SplObjectStorage();
$y = new SplObjectStorage();
$x[$a] = 1;
$x[$b] = 2;
$y[$b] = 'y';
$y[$c] = 'y';
var_dump($x->addAll($y), $x[$b]);
var_dump($x->removeAll($y), count($x));
$x->addAll($y);
var_dump($x->removeAllExcept($y), count($x));
$x->removeAll($x);
var_dump(count($x));

echo "-- getHash\n";
class ByN extends SplObjectStorage {
    public function getHash($o): string { return (string) $o->n; }
}
$h = new ByN();
$h[new Item(1)] = 'first';
$h[new Item(1)] = 'second';
var_dump(count($h), $h[new Item(1)]);
class BadHash extends SplObjectStorage {
    public function getHash($o): string { return 1; }
}
show('int hash', function () { $b = new BadHash; $b[new Item(1)] = 1; return count($b); });
show('getHash', fn() => strlen((new SplObjectStorage)->getHash($a)));

echo "-- serialization\n";
$t = new SplObjectStorage();
$t[$a] = 'x';
$t[$b] = [1];
$t->prop = 1;
$ser = serialize($t);
echo $ser, "\n";
var_dump(unserialize($ser));
echo $t->serialize(), "\n";
$u = new SplObjectStorage();
$u->unserialize('x:i:1;O:8:"stdClass":0:{},s:1:"v";;m:a:0:{}');
print_r($u);
show('unserialize bad', fn() => (new SplObjectStorage)->unserialize('x:i:2;i:0;,i:1;;i:0;,i:2;;m:a:0:{}'));
show('__unserialize odd', fn() => (new SplObjectStorage)->__unserialize([[1], []]));
show('__unserialize key', fn() => (new SplObjectStorage)->__unserialize([[1, 2], []]));
$cl = clone $t;
$cl[$c] = 'c';
var_dump(count($t), count($cl));

echo "-- MultipleIterator\n";
$m = new MultipleIterator();
show('valid empty', fn() => $m->valid());
show('current empty', fn() => $m->current());
$m->attachIterator(new ArrayIterator([1, 2, 3]), 'nums');
$m->attachIterator(new ArrayIterator(['a', 'b']), 'letters');
show('duplicate', fn() => $m->attachIterator(new ArrayIterator([]), 'nums'));
var_dump($m->countIterators(), $m->getFlags());
foreach ($m as $k => $v) echo json_encode($k), ' ', json_encode($v), "\n";
$m->setFlags(MultipleIterator::MIT_NEED_ANY | MultipleIterator::MIT_KEYS_ASSOC);
foreach ($m as $k => $v) echo json_encode($k), ' ', json_encode($v), "\n";
$m->rewind();
$m->next();
$m->next();
show('need all', function () use ($m) { $m->setFlags(MultipleIterator::MIT_NEED_ALL); return $m->current(); });
$n = new MultipleIterator(MultipleIterator::MIT_KEYS_ASSOC);
$n->attachIterator(new ArrayIterator([1]));
show('assoc null', fn() => $n->current());
var_dump($m);

<?php
// an ArrayObject that is its own storage holds no reference to itself, so
// unset() frees it at once, and its handle is reused

class SelfArray extends ArrayObject
{
    public function __construct()
    {
        parent::__construct($this);
    }

    public function __destruct()
    {
        echo "destruct\n";
    }
}

$a = new SelfArray();
$a['foo'] = 'bar';
var_dump($a, count($a), $a->getArrayCopy());
unset($a);
echo "after unset\n";
var_dump(new stdClass());

$b = new SelfArray();
$b['x'] = 1;
$s = serialize($b);
var_dump($s);
unset($b);
echo "after unset\n";
$c = unserialize($s);
var_dump($c, $c['x']);
$d = clone $c;
$d['y'] = 2;
var_dump($d, $c);
foreach ($d as $k => $v) {
    echo "$k => $v\n";
}
$d->exchangeArray(['z' => 3]);
var_dump($d, serialize($d));
unset($c, $d);
echo "done\n";

// getIterator() copies the IS_SELF flag: the iterator walks its own
// (empty) properties, while an ArrayIterator built on the object sees them
$e = new SelfArray();
$e['x'] = 1;
$it = $e->getIterator();
var_dump($it->valid(), $it->count());
$i2 = new ArrayIterator($e);
var_dump($i2->valid(), $i2->key());
unset($it, $i2, $e);

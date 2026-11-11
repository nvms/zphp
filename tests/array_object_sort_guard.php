<?php
// ArrayObject's sort methods parse their arguments before sorting, and
// nothing may change the storage while a sort runs; the constructor and
// setIteratorClass() take only ArrayIterator and its subclasses
function attempt(string $what, callable $f) {
    try {
        $f();
        echo "$what: ok\n";
    } catch (Throwable $e) {
        echo "$what: ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}

$ao = new ArrayObject(['b' => 2, 'a' => 4, 'c' => 3]);
attempt('asort string', fn() => $ao->asort('x'));
attempt('ksort extra', fn() => $ao->ksort(0, 1));
attempt('natsort arg', fn() => $ao->natsort(1));
attempt('uasort none', fn() => $ao->uasort());
var_dump($ao->getArrayCopy());
$it = new ArrayIterator([3, 1, 2]);
attempt('iterator ksort', fn() => $it->ksort([]));
var_dump($it->asort(SORT_NUMERIC), $it->getArrayCopy());

$ao = new ArrayObject([3, 1, 2]);
$first = true;
$ao->uasort(function ($a, $b) use ($ao, &$first) {
    if ($first) {
        $first = false;
        attempt('write', function () use ($ao) { $ao[0] = 9; });
        attempt('append', function () use ($ao) { $ao[] = 9; });
        attempt('unset', function () use ($ao) { unset($ao[0]); });
        attempt('nested', function () use ($ao) { $ao['x']['y'] = 1; });
        attempt('exchange', fn() => $ao->exchangeArray([]));
        attempt('read', fn() => $ao[0]);
        attempt('isset', fn() => isset($ao[0]));
    }
    return $a <=> $b;
});
var_dump($ao->getArrayCopy());
$ao[] = 4;
var_dump(count($ao));

class MyIterator extends ArrayIterator {}
attempt('class Exception', fn() => new ArrayObject([], 0, 'Exception'));
attempt('class missing', fn() => new ArrayObject([], 0, 'NoSuchClass'));
attempt('class subclass', fn() => new ArrayObject([], 0, 'MyIterator'));
$o = new ArrayObject([1]);
attempt('set Exception', fn() => $o->setIteratorClass('stdClass'));
attempt('set subclass', fn() => $o->setIteratorClass('myiterator'));
var_dump($o->getIteratorClass(), get_class($o->getIterator()));
attempt('flags string', fn() => new ArrayObject([], 'x'));
attempt('too many', fn() => new ArrayObject([], 0, 'ArrayIterator', 1));

// unserialize() is a modification too, an empty payload aside
$it = new ArrayIterator([2, 1]);
$it->uksort(function ($a, $b) use ($it) {
    attempt('unserialize', fn() => $it->unserialize($it->serialize()));
    attempt('unserialize empty', fn() => $it->unserialize(''));
    return $a <=> $b;
});

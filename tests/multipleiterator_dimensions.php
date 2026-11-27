<?php
// MultipleIterator answers `$it[$object]` through SplObjectStorage's
// dimension handlers without being ArrayAccess: an object offset reads,
// writes (iterators only), tests and removes entries of its storage. the
// two classes share php's flags field, so MIT_NEED_ALL (the default) sends
// reads, and MIT_KEYS_ASSOC writes, to the standard handler, which refuses

function attempt(string $what, callable $f)
{
    try {
        $r = $f();
        echo "$what: ", var_export($r, true), "\n";
    } catch (Throwable $e) {
        echo "$what: ", $e::class, ': ', $e->getMessage(), "\n";
    }
}

$a = new ArrayIterator([1, 2]);
$b = new ArrayIterator([3, 4]);
$mi = new MultipleIterator(MultipleIterator::MIT_NEED_ANY);
$mi[$a] = 'first';
$mi[$b] = 'second';
var_dump($mi instanceof ArrayAccess, $mi->countIterators());
var_dump($mi[$a], isset($mi[$b]), isset($mi[new ArrayIterator([])]), empty($mi[$a]));
var_dump($mi[new ArrayIterator([])] ?? 'missing');
foreach ($mi as $key => $value) {
    var_dump($key, $value);
}
unset($mi[$a]);
var_dump($mi->countIterators(), $mi->containsIterator($a));

attempt('stdClass offset', fn() => $mi[new stdClass()] = 1);
attempt('missing read', fn() => $mi[new ArrayIterator([])]);
attempt('string offset write', fn() => $mi['key'] = 1);
attempt('int offset read', fn() => $mi[0]);
attempt('string isset', fn() => isset($mi['key']));

$all = new MultipleIterator();
$all[$a] = 1;
var_dump($all->countIterators());
attempt('read with MIT_NEED_ALL', fn() => $all[$a]);
attempt('isset with MIT_NEED_ALL', fn() => isset($all[$a]));
attempt('coalesce with MIT_NEED_ALL', fn() => $all[$a] ?? 'none');

$assoc = new MultipleIterator(MultipleIterator::MIT_KEYS_ASSOC);
attempt('write with MIT_KEYS_ASSOC', fn() => $assoc[$a] = 'k');
$assoc->setFlags(MultipleIterator::MIT_NEED_ANY);
$assoc[$a] = 'k';
var_dump($assoc[$a]);

class Empty1 implements Iterator
{
    public function valid(): bool { return false; }
    public function current(): mixed { return null; }
    public function key(): mixed { return ''; }
    public function next(): void {}
    public function rewind(): void {}
}
$m2 = new MultipleIterator();
$m2[new Empty1()] = 1;
attempt('key', fn() => $m2->key());

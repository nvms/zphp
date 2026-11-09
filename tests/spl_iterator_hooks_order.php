<?php
// the order in which the spl iterators call user-overridden methods: the
// inner iterator's methods, RecursiveIteratorIterator's hooks, and foreach's
// own calls (current() before key(), key() only when the loop names it)

class Trace
{
    public static array $log = [];

    public static function flush(string $label): void
    {
        echo $label, ': ', implode(' ', self::$log), "\n";
        self::$log = [];
    }
}

class Rows implements Iterator
{
    private int $i = 0;

    public function __construct(private array $rows) {}
    public function rewind(): void { Trace::$log[] = 'rewind'; $this->i = 0; }
    public function valid(): bool { Trace::$log[] = 'valid'; return $this->i < count($this->rows); }
    public function current(): mixed { Trace::$log[] = 'current'; return $this->rows[$this->i]; }
    public function key(): mixed { Trace::$log[] = 'key'; return $this->i; }
    public function next(): void { Trace::$log[] = 'next'; $this->i++; }
}

foreach (new Rows(['a', 'b']) as $row) {
    Trace::$log[] = "body($row)";
}
Trace::flush('foreach values');
foreach (new Rows(['a', 'b']) as $k => $row) {
    Trace::$log[] = "body($k)";
}
Trace::flush('foreach keys');

$wrappers = [
    'IteratorIterator' => fn($it) => new IteratorIterator($it),
    'LimitIterator' => fn($it) => new LimitIterator($it, 1, 2),
    'CachingIterator' => fn($it) => new CachingIterator($it),
    'NoRewindIterator' => fn($it) => new NoRewindIterator($it),
    'CallbackFilterIterator' => fn($it) => new CallbackFilterIterator($it, function ($v, $k) {
        Trace::$log[] = "accept($k)";
        return $k !== 1;
    }),
];
foreach ($wrappers as $name => $make) {
    foreach ($make(new Rows(['x', 'y', 'z'])) as $k => $v) {
        Trace::$log[] = "<$k:$v>";
    }
    Trace::flush($name);
}

$append = new AppendIterator();
$append->append(new Rows(['p']));
$append->append(new Rows([]));
$append->append(new Rows(['q']));
Trace::flush('AppendIterator::append');
foreach ($append as $k => $v) {
    Trace::$log[] = "<$k:$v@" . $append->getIteratorIndex() . ">";
}
Trace::flush('AppendIterator');

var_dump(iterator_to_array(new Rows(['m', 'n'])));
Trace::flush('iterator_to_array');
var_dump(iterator_to_array(new Rows(['m', 'n']), false));
Trace::flush('iterator_to_array values');
var_dump(iterator_count(new Rows(['m', 'n'])));
Trace::flush('iterator_count');
$rows = new Rows(['m', 'n', 'o']);
var_dump(iterator_apply($rows, function (Iterator $it) {
    Trace::$log[] = 'apply(' . $it->current() . ')';
    return $it->current() !== 'n';
}, [$rows]));
Trace::flush('iterator_apply');

class Tree extends RecursiveArrayIterator
{
    public function rewind(): void { Trace::$log[] = 'rewind'; parent::rewind(); }
    public function valid(): bool { Trace::$log[] = 'valid'; return parent::valid(); }
    public function current(): mixed { Trace::$log[] = 'current'; return parent::current(); }
    public function key(): string|int|null { Trace::$log[] = 'key'; return parent::key(); }
    public function next(): void { Trace::$log[] = 'next'; parent::next(); }
    public function hasChildren(): bool { Trace::$log[] = 'hasChildren'; return parent::hasChildren(); }
    public function getChildren(): ?RecursiveArrayIterator { Trace::$log[] = 'getChildren'; return parent::getChildren(); }
}

class Walker extends RecursiveIteratorIterator
{
    public function beginIteration(): void { Trace::$log[] = 'BEGIN'; }
    public function endIteration(): void { Trace::$log[] = 'END'; }
    public function beginChildren(): void { Trace::$log[] = 'beginChildren'; }
    public function endChildren(): void { Trace::$log[] = 'endChildren'; }
    public function callHasChildren(): bool { Trace::$log[] = 'callHasChildren'; return parent::callHasChildren(); }
    public function callGetChildren(): RecursiveIterator { Trace::$log[] = 'callGetChildren'; return parent::callGetChildren(); }
    public function nextElement(): void { Trace::$log[] = 'nextElement'; }
}

$data = ['a' => 1, 'b' => ['c' => 2, 'd' => []], 'e' => 3];
foreach ([RecursiveIteratorIterator::LEAVES_ONLY, RecursiveIteratorIterator::SELF_FIRST, RecursiveIteratorIterator::CHILD_FIRST] as $mode) {
    $walker = new Walker(new Tree($data), $mode);
    foreach ($walker as $k => $v) {
        Trace::$log[] = "<$k>";
    }
    Trace::flush("Walker mode $mode");
    $walker->setMaxDepth(0);
    foreach ($walker as $v) {
        Trace::$log[] = '<' . (is_array($v) ? 'array' : $v) . '>';
    }
    Trace::flush("Walker mode $mode depth 0");
}

// stepping by hand, and valid() past the end
$walker = new Walker(new Tree(['x' => ['y' => 1]]));
$walker->rewind();
while ($walker->valid()) {
    Trace::$log[] = '<' . $walker->key() . '>';
    $walker->next();
}
var_dump($walker->valid());
Trace::flush('manual');

// a filter over a recursive tree
class EvenOnly extends RecursiveFilterIterator
{
    public function accept(): bool
    {
        Trace::$log[] = 'accept(' . $this->key() . ')';
        return $this->hasChildren() || $this->current() % 2 === 0;
    }
}
foreach (new RecursiveIteratorIterator(new EvenOnly(new Tree(['a' => 1, 'b' => 2, 'c' => [3, 4]]))) as $k => $v) {
    Trace::$log[] = "<$k:$v>";
}
Trace::flush('RecursiveFilterIterator');

// a hook that throws ends the walk
class Fails extends RecursiveIteratorIterator
{
    public function nextElement(): void
    {
        if ($this->current() === 2) {
            throw new LogicException('stop at 2');
        }
    }
}
try {
    foreach (new Fails(new RecursiveArrayIterator([1, [2, 3]])) as $v) {
        echo "got $v\n";
    }
} catch (LogicException $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}

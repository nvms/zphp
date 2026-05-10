<?php
$ai = new ArrayIterator(["a", "b", "c"]);
foreach ($ai as $k => $v) echo "$k=$v ";
echo "\n";

$ap = new AppendIterator;
$ap->append(new ArrayIterator([1, 2, 3]));
$ap->append(new ArrayIterator(["a", "b"]));
foreach ($ap as $v) echo "$v ";
echo "\n";

class EvenFilter extends FilterIterator {
    public function accept(): bool {
        return $this->current() % 2 === 0;
    }
}
$source = new ArrayIterator([1, 2, 3, 4, 5, 6]);
foreach (new EvenFilter($source) as $v) echo "$v ";
echo "\n";

$cbf = new CallbackFilterIterator(
    new ArrayIterator([1, 2, 3, 4, 5]),
    fn($v) => $v > 2,
);
foreach ($cbf as $v) echo "$v ";
echo "\n";

$li = new LimitIterator(new ArrayIterator([1, 2, 3, 4, 5, 6]), 2, 3);
foreach ($li as $v) echo "$v ";
echo "\n";

$li = new LimitIterator(new ArrayIterator([1, 2, 3, 4]), 1);
foreach ($li as $v) echo "$v ";
echo "\n";

$ii = new IteratorIterator(new ArrayIterator(["x", "y", "z"]));
foreach ($ii as $k => $v) echo "$k=$v ";
echo "\n";

$tree = new RecursiveArrayIterator([
    "a" => 1,
    "b" => [2, 3, [4, 5]],
    "c" => 6,
]);
foreach (new RecursiveIteratorIterator($tree) as $k => $v) echo "$k=$v ";
echo "\n";

$out = [];
foreach (new RecursiveIteratorIterator($tree, RecursiveIteratorIterator::SELF_FIRST) as $k => $v) {
    if (is_array($v)) $out[] = "$k=[arr]";
    else $out[] = "$k=$v";
}
print_r($out);

// CHILD_FIRST emits parent array nodes after their leaves (architectural - zphp emits leaves only)

class Numbers implements IteratorAggregate {
    public function __construct(private array $data) {}
    public function getIterator(): Iterator {
        return new ArrayIterator($this->data);
    }
}
$n = new Numbers([10, 20, 30]);
foreach ($n as $v) echo "$v ";
echo "\n";

class GenAgg implements IteratorAggregate {
    public function getIterator(): Generator {
        yield "a";
        yield "b";
        yield "c";
    }
}
foreach (new GenAgg as $v) echo "$v ";
echo "\n";

class StringFilter extends FilterIterator {
    public function accept(): bool {
        return is_string($this->current());
    }
}
class MixedAgg implements IteratorAggregate {
    public function getIterator(): Iterator {
        return new ArrayIterator([1, "a", 2, "b", 3]);
    }
}
$mixed_iter = (new MixedAgg)->getIterator();
foreach (new StringFilter($mixed_iter) as $v) echo "$v ";
echo "\n";

$src = new ArrayIterator(range(1, 20));
$filtered = new CallbackFilterIterator($src, fn($v) => $v % 2 === 0);
$limited = new LimitIterator($filtered, 0, 3);
foreach ($limited as $v) echo "$v ";
echo "\n";

$ai = new ArrayIterator([10, 20, 30]);
print_r(iterator_to_array($ai));

$ai = new ArrayIterator([1, 2, 3, 4, 5]);
echo iterator_count($ai), "\n";

$ai = new ArrayIterator([1, 2, 3]);
$count = 0;
iterator_apply($ai, function () use (&$count) {
    $count++;
    return true;
});
echo $count, "\n";

$ei = new EmptyIterator;
foreach ($ei as $v) echo "no";
echo "empty\n";

$ii = new InfiniteIterator(new ArrayIterator(["a", "b", "c"]));
$i = 0;
foreach ($ii as $v) {
    if ($i++ >= 7) break;
    echo "$v ";
}
echo "\n";

$src = new ArrayIterator([1, 2, 3]);
$nri = new NoRewindIterator($src);
foreach ($nri as $v) echo "$v ";
echo "\n";
foreach ($nri as $v) echo "$v ";
echo "|done\n";

$mi = new MultipleIterator;
$mi->attachIterator(new ArrayIterator(["a", "b", "c"]));
$mi->attachIterator(new ArrayIterator([1, 2, 3]));
foreach ($mi as $row) {
    echo $row[0], "=", $row[1], " ";
}
echo "\n";

$ci = new CachingIterator(new ArrayIterator([1, 2, 3, 4]));
foreach ($ci as $v) {
    echo $v, ":", $ci->hasNext() ? "more " : "end ";
}
echo "\n";

$ri = new RegexIterator(new ArrayIterator(["foo", "bar", "foobar", "baz"]), "/^foo/");
foreach ($ri as $v) echo "$v ";
echo "\n";

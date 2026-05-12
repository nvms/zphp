<?php
// covers: SPL iterators - LimitIterator, FilterIterator, RegexIterator,
//   AppendIterator, CachingIterator, IteratorIterator, RecursiveIteratorIterator,
//   ArrayIterator + nested arrays

echo "=== LimitIterator slice ===\n";
$data = new ArrayIterator(range(1, 20));
$lim = new LimitIterator($data, 5, 8);
$out = [];
foreach ($lim as $v) $out[] = $v;
echo "got: " . implode(',', $out) . "\n";

echo "\n=== CallbackFilterIterator ===\n";
$src = new ArrayIterator([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
$even = new CallbackFilterIterator($src, fn($v) => $v % 2 === 0);
$out = [];
foreach ($even as $v) $out[] = $v;
echo "even: " . implode(',', $out) . "\n";

echo "\n=== RegexIterator matching ===\n";
$lines = new ArrayIterator(['error: 1', 'info: 2', 'error: 3', 'debug: 4', 'error: 5']);
$errors = new RegexIterator($lines, '/^error/', RegexIterator::MATCH);
$out = [];
foreach ($errors as $line) $out[] = $line;
echo "errors: " . count($out) . " lines\n";

echo "\n=== RegexIterator GET_MATCH ===\n";
$logs = new ArrayIterator(['order #100', 'request #200', 'ticket #300']);
$ids = new RegexIterator($logs, '/#(\d+)/', RegexIterator::GET_MATCH);
foreach ($ids as $m) echo "  matched id: $m[1]\n";

echo "\n=== AppendIterator combining sources ===\n";
$combined = new AppendIterator();
$combined->append(new ArrayIterator([1, 2, 3]));
$combined->append(new ArrayIterator([10, 20, 30]));
$combined->append(new ArrayIterator(['a', 'b']));
$out = [];
foreach ($combined as $v) $out[] = $v;
echo "combined: " . implode(',', $out) . "\n";

echo "\n=== CachingIterator with hasNext ===\n";
$src = new ArrayIterator(['a', 'b', 'c', 'd']);
$cache = new CachingIterator($src);
foreach ($cache as $v) {
    $sep = $cache->hasNext() ? ', ' : '';
    echo $v . $sep;
}
echo "\n";

echo "\n=== RecursiveIteratorIterator over nested ===\n";
$tree = new RecursiveArrayIterator([
    'level1' => [
        'a' => 1,
        'level2' => ['b' => 2, 'level3' => ['c' => 3, 'd' => 4]],
        'e' => 5,
    ],
    'f' => 6,
]);
$rii = new RecursiveIteratorIterator($tree, RecursiveIteratorIterator::LEAVES_ONLY);
foreach ($rii as $k => $v) echo "  $k => $v\n";

echo "\n=== SELF_FIRST mode visits internal nodes ===\n";
$rii = new RecursiveIteratorIterator(
    new RecursiveArrayIterator(['a' => 1, 'b' => ['c' => 2, 'd' => 3], 'e' => 4]),
    RecursiveIteratorIterator::SELF_FIRST,
);
foreach ($rii as $k => $v) {
    if (is_array($v)) {
        echo "  $k => (subtree)\n";
    } else {
        echo "  $k => $v (depth " . $rii->getDepth() . ")\n";
    }
}

echo "\n=== chain LimitIterator + FilterIterator ===\n";
$src = new ArrayIterator(range(1, 50));
$even = new CallbackFilterIterator($src, fn($v) => $v % 3 === 0);
$slice = new LimitIterator($even, 2, 4);
$out = [];
foreach ($slice as $v) $out[] = $v;
echo "every-3rd then skip 2 take 4: " . implode(',', $out) . "\n";

echo "\n=== IteratorIterator wraps any Traversable ===\n";
function gen(): Generator { yield 'x' => 1; yield 'y' => 2; yield 'z' => 3; }
$it = new IteratorIterator(gen());
foreach ($it as $k => $v) echo "  $k => $v\n";

echo "\n=== iterator_to_array preserves keys ===\n";
$dup_keys = new ArrayIterator(['a' => 1, 'b' => 2]);
print_r(iterator_to_array($dup_keys));

echo "\n=== iterator_count ===\n";
$count = iterator_count(new ArrayIterator(range(1, 7)));
echo "count: $count\n";

echo "\n=== iterator_apply ===\n";
$sum = 0;
$it = new ArrayIterator([10, 20, 30]);
iterator_apply($it, function () use ($it, &$sum) {
    $sum += $it->current();
    return true;
});
echo "sum: $sum\n";

echo "\ndone\n";

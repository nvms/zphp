<?php
// covers: IteratorIterator, LimitIterator, CallbackFilterIterator, RegexIterator, AppendIterator, EmptyIterator, NoRewindIterator, InfiniteIterator, CachingIterator, MultipleIterator, RecursiveCallbackFilterIterator, RecursiveArrayIterator, RecursiveRegexIterator

echo "=== IteratorIterator ===\n";
$src = new ArrayIterator(['alpha', 'beta', 'gamma']);
$ii = new IteratorIterator($src);
foreach ($ii as $k => $v) echo "$k => $v\n";

echo "\n=== LimitIterator ===\n";
$nums = new ArrayIterator(range(1, 10));
$page = new LimitIterator($nums, 3, 4);
foreach ($page as $v) echo "$v ";
echo "\nposition after iter: " . $page->getPosition() . "\n";
$page->rewind();
$page->seek(5);
echo "after seek(5) current: " . $page->current() . "\n";

echo "\n=== CallbackFilterIterator ===\n";
$even = new CallbackFilterIterator(
    new ArrayIterator(range(1, 10)),
    fn($v) => $v % 2 === 0
);
foreach ($even as $v) echo "$v ";
echo "\n";

echo "\n=== RegexIterator (MATCH) ===\n";
$words = new ArrayIterator(['cat', 'cab', 'dog', 'crow', 'fish']);
$cwords = new RegexIterator($words, '/^c/');
foreach ($cwords as $w) echo "$w ";
echo "\n";

echo "\n=== RegexIterator (USE_KEY + INVERT_MATCH) ===\n";
$assoc = new ArrayIterator(['admin' => 1, 'user' => 2, 'guest' => 3, 'admin_old' => 4]);
$nonAdmin = new RegexIterator($assoc, '/^admin/', RegexIterator::MATCH, RegexIterator::USE_KEY | RegexIterator::INVERT_MATCH);
foreach ($nonAdmin as $k => $v) echo "$k=$v\n";

echo "\n=== RegexIterator (GET_MATCH) ===\n";
$lines = new ArrayIterator(['error: 404 not found', 'info: 200 ok', 'error: 500 broken']);
$errs = new RegexIterator($lines, '/^error: (\d+) (.+)$/', RegexIterator::GET_MATCH);
foreach ($errs as $m) echo "code=" . $m[1] . " msg=" . $m[2] . "\n";

echo "\n=== AppendIterator ===\n";
$ap = new AppendIterator();
$ap->append(new ArrayIterator(['x', 'y']));
$ap->append(new ArrayIterator(['z']));
$ap->append(new ArrayIterator(['w', 'v', 'u']));
foreach ($ap as $v) echo "$v ";
echo "\n";

echo "\n=== EmptyIterator ===\n";
$empty = new EmptyIterator();
$count = 0;
foreach ($empty as $v) $count++;
echo "iterations: $count\n";

echo "\n=== NoRewindIterator ===\n";
$nri = new NoRewindIterator(new ArrayIterator([10, 20, 30]));
foreach ($nri as $v) echo "$v ";
echo "\n";
foreach ($nri as $v) echo "second: $v ";
echo "(no second pass)\n";

echo "\n=== InfiniteIterator ===\n";
$inf = new InfiniteIterator(new ArrayIterator(['rock', 'paper', 'scissors']));
$inf->rewind();
$out = [];
for ($i = 0; $i < 7; $i++) {
    $out[] = $inf->current();
    $inf->next();
}
echo implode(',', $out) . "\n";

echo "\n=== CachingIterator (hasNext + cache) ===\n";
$ci = new CachingIterator(new ArrayIterator(['a', 'b', 'c']), CachingIterator::FULL_CACHE);
$out = [];
foreach ($ci as $v) {
    $out[] = $v . ($ci->hasNext() ? ',' : '.');
}
echo implode('', $out) . "\n";
$cache = $ci->getCache();
echo "cached entries: " . count($cache) . "\n";

echo "\n=== MultipleIterator (assoc keys) ===\n";
$mi = new MultipleIterator(MultipleIterator::MIT_NEED_ALL | MultipleIterator::MIT_KEYS_ASSOC);
$mi->attachIterator(new ArrayIterator(['hello', 'world', 'foo']), 'word');
$mi->attachIterator(new ArrayIterator([5, 5, 3]), 'len');
foreach ($mi as $row) {
    echo $row['word'] . '(' . $row['len'] . ") ";
}
echo "\n";

echo "\n=== RecursiveCallbackFilterIterator ===\n";
$tree = new RecursiveArrayIterator([
    'src' => ['main.zig', 'main.zig.bak', 'README.md'],
    'tests' => ['test.zig', 'fixtures' => ['data.json', 'old.json.bak']],
    'logo.png',
]);
$filter = new RecursiveCallbackFilterIterator($tree, function ($val, $key, $iter) {
    if ($iter->hasChildren()) return true;
    return is_string($val) && !str_ends_with($val, '.bak');
});
$flat = new RecursiveIteratorIterator($filter);
foreach ($flat as $f) echo "$f\n";

echo "\n=== RecursiveRegexIterator ===\n";
$nested = new RecursiveArrayIterator(['cat', 'dog', ['bird', 'cow', ['cricket']], 'eel']);
$only_c = new RecursiveRegexIterator($nested, '/^c/');
$flat2 = new RecursiveIteratorIterator($only_c);
foreach ($flat2 as $w) echo "$w ";
echo "\n";

echo "\nall done\n";

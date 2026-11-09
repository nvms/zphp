<?php
// paginating with LimitIterator, rendering lists with CachingIterator's
// look-ahead, chaining sources with AppendIterator, and the errors each
// iterator raises

$articles = new ArrayIterator(array_map(fn($i) => "Article $i", range(1, 11)));

function page(Iterator $source, int $page, int $perPage): array
{
    return iterator_to_array(new LimitIterator($source, ($page - 1) * $perPage, $perPage), false);
}

for ($page = 1; $page <= 4; $page++) {
    try {
        echo "page $page: ", implode(', ', page($articles, $page, 4)), "\n";
    } catch (OutOfBoundsException $e) {
        // ArrayIterator::seek() refuses a position past its end
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
// an iterator that can't seek is stepped through, and runs out quietly
$unseekable = new IteratorIterator($articles);
echo "page 4: ", implode(', ', page($unseekable, 4, 4)) ?: '(empty)', "\n";

// LimitIterator seeks with the inner iterator's seek() when it has one
$limit = new LimitIterator($articles, 2, 5);
var_dump($limit->seek(4), $limit->current(), $limit->getPosition());
foreach ([1, 7] as $pos) {
    try {
        $limit->seek($pos);
    } catch (OutOfBoundsException $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
foreach ([[-1, 2], [0, -2]] as [$offset, $count]) {
    try {
        new LimitIterator($articles, $offset, $count);
    } catch (ValueError $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}

// a generator can be paged once
function lines(): Generator
{
    foreach (['alpha', 'beta', 'gamma', 'delta'] as $n => $line) {
        yield "line$n" => $line;
    }
}
var_dump(iterator_to_array(new LimitIterator(lines(), 1, 2)));

// a comma separated list with "and" before the last item
function sentence(array $items): string
{
    $out = '';
    $it = new CachingIterator(new ArrayIterator($items));
    foreach ($it as $item) {
        $out .= $item;
        if ($it->hasNext()) {
            $out .= count($items) > 2 ? ', ' : ' ';
        }
    }
    return $out;
}
echo sentence(['apples']), "\n", sentence(['apples', 'pears']), "\n", sentence(['apples', 'pears', 'plums']), "\n";

$cache = new CachingIterator(new ArrayIterator(['a' => 1, 'b' => 2, 'c' => 3]), CachingIterator::FULL_CACHE);
foreach ($cache as $k => $v) {
    echo "$k=$v cached=", count($cache), "\n";
}
var_dump($cache->getCache(), isset($cache['b']), $cache['c']);
$cache['z'] = 26;
unset($cache['a']);
var_dump($cache->getCache());

foreach ([CachingIterator::TOSTRING_USE_KEY, CachingIterator::TOSTRING_USE_CURRENT, CachingIterator::CALL_TOSTRING] as $flags) {
    $strings = [];
    $it = new CachingIterator(new ArrayIterator(['x' => 10, 'y' => 20]), $flags);
    foreach ($it as $v) {
        $strings[] = (string) $it;
    }
    echo "flags $flags: ", implode(',', $strings), "\n";
}

$plain = new CachingIterator(new ArrayIterator([1]), 0);
foreach (['__toString' => fn() => (string) $plain, 'getCache' => fn() => $plain->getCache(), 'offsetGet' => fn() => $plain['0']] as $what => $call) {
    try {
        $call();
    } catch (BadMethodCallException $e) {
        echo "$what: ", $e->getMessage(), "\n";
    }
}
try {
    $plain->setFlags(CachingIterator::TOSTRING_USE_KEY | CachingIterator::TOSTRING_USE_CURRENT);
} catch (ValueError $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
try {
    (new CachingIterator(new ArrayIterator([])))->setFlags(0);
} catch (InvalidArgumentException $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}

// feeds from several sources merged into one stream
$feed = new AppendIterator();
$feed->append(new ArrayIterator(['news-1' => 'Rates rise', 'news-2' => 'Markets calm']));
$feed->append(new ArrayIterator([]));
$feed->append(new LimitIterator(new ArrayIterator(['blog-1' => 'Hello', 'blog-2' => 'Again', 'blog-3' => 'Bye']), 0, 2));
foreach ($feed as $id => $title) {
    echo $feed->getIteratorIndex(), " $id: $title\n";
}
var_dump(iterator_count($feed), get_class($feed->getArrayIterator()), $feed->getInnerIterator());

// appending while iterating continues into the new source
$queue = new AppendIterator();
$queue->append(new ArrayIterator(['job1']));
foreach ($queue as $job) {
    echo "run $job\n";
    if ($job === 'job1') {
        $queue->append(new ArrayIterator(['job2', 'job3']));
    }
}

// round robin over a fixed list, and a cursor that keeps its place
$colors = new InfiniteIterator(new ArrayIterator(['red', 'green', 'blue']));
echo implode(' ', iterator_to_array(new LimitIterator($colors, 0, 7), false)), "\n";
$cursor = new NoRewindIterator(new ArrayIterator(['one', 'two', 'three', 'four']));
foreach ($cursor as $v) {
    echo "first loop $v\n";
    if ($v === 'two') {
        break;
    }
}
foreach ($cursor as $v) {
    echo "second loop $v\n";
}

// filtering file names, and the regex modes
$files = new ArrayIterator(['index.php', 'style.css', 'app.js', 'README', 'test.php']);
echo implode(' ', iterator_to_array(new RegexIterator($files, '/\.php$/'), false)), "\n";
echo implode(' ', iterator_to_array(new RegexIterator($files, '/\.php$/', RegexIterator::MATCH, RegexIterator::INVERT_MATCH), false)), "\n";
var_dump(iterator_to_array(new RegexIterator($files, '/^(\w+)\.(\w+)$/', RegexIterator::GET_MATCH)));
$replace = new RegexIterator($files, '/\.(\w+)$/', RegexIterator::REPLACE);
$replace->replacement = ' [$1]';
var_dump(iterator_to_array($replace));
try {
    new RegexIterator($files, 'no delimiters');
} catch (InvalidArgumentException $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}

$odd = new CallbackFilterIterator(new ArrayIterator(range(1, 6)), fn($v) => $v % 2 === 1);
var_dump(iterator_to_array($odd));

$empty = new EmptyIterator();
var_dump(iterator_to_array($empty), $empty->valid());
try {
    $empty->current();
} catch (BadMethodCallException $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}

// unknown methods go to the inner iterator, objects can't be cloned
$wrapped = new IteratorIterator(new ArrayIterator([3, 1, 2]));
var_dump($wrapped->count(), $wrapped->getArrayCopy());
try {
    $copy = clone $wrapped;
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}

class Lazy extends FilterIterator
{
    public function __construct() {}
    public function accept(): bool { return true; }
}
try {
    (new Lazy())->rewind();
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}

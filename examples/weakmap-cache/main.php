<?php
// covers: WeakMap as a per-object cache, WeakReference, count/iteration,
//   offset access via objects as keys. (zphp note: weak GC semantics are
//   approximated - dropping references doesn't auto-evict; tests against
//   PHP only cover the parts that don't depend on refcount-driven cleanup.)

class Article {
    public function __construct(public string $title) {}
}

class RenderCache {
    private WeakMap $store;

    public function __construct() {
        $this->store = new WeakMap();
    }

    public function render(Article $a): string {
        if (isset($this->store[$a])) {
            return "[cached] " . $this->store[$a];
        }
        $html = "<h1>" . htmlspecialchars($a->title) . "</h1>";
        $this->store[$a] = $html;
        return $html;
    }

    public function size(): int { return count($this->store); }
}

$cache = new RenderCache();

echo "=== first-render vs second-render ===\n";
$a1 = new Article("Welcome");
$a2 = new Article("News");
echo $cache->render($a1) . "\n";
echo $cache->render($a1) . "\n";  // cached
echo $cache->render($a2) . "\n";
echo "cache size: " . $cache->size() . "\n";

echo "\n=== WeakReference round-trip while object alive ===\n";
$strong = new Article("Strong");
$ref = WeakReference::create($strong);
$got = $ref->get();
echo "get returns same object: " . (($got !== null && $got === $strong) ? "yes" : "no") . "\n";
echo "title via ref: " . ($got?->title ?? "null") . "\n";

echo "\n=== explicit offsetUnset removes entry ===\n";
$tags = new WeakMap();
$objs = [new Article("a"), new Article("b"), new Article("c")];
foreach ($objs as $i => $o) $tags[$o] = "rank-$i";
echo "before unset: " . count($tags) . "\n";
unset($tags[$objs[1]]);
echo "after unset middle: " . count($tags) . "\n";
$remaining = [];
foreach ($tags as $k => $v) $remaining[] = $k->title;
sort($remaining);
echo "remaining: " . implode(',', $remaining) . "\n";

echo "\n=== iteration yields key as object, value as stored ===\n";
$wm = new WeakMap();
$x = new Article("x");
$y = new Article("y");
$wm[$x] = ['n' => 1];
$wm[$y] = ['n' => 2];

$collected = [];
foreach ($wm as $obj => $data) {
    $collected[$obj->title] = $data['n'];
}
ksort($collected);
foreach ($collected as $k => $v) echo "  $k => $v\n";

echo "\n=== isset / offsetExists ===\n";
$wm2 = new WeakMap();
$a = new Article("a");
$b = new Article("b");
$wm2[$a] = 'set';
echo "isset a: " . (isset($wm2[$a]) ? "yes" : "no") . "\n";
echo "isset b: " . (isset($wm2[$b]) ? "yes" : "no") . "\n";
echo "value a: " . $wm2[$a] . "\n";

echo "\n=== overwrite same key updates value, doesn't grow ===\n";
$wm3 = new WeakMap();
$key = new Article("only");
$wm3[$key] = 1;
$wm3[$key] = 2;
$wm3[$key] = 3;
echo "size: " . count($wm3) . "\n";
echo "value: " . $wm3[$key] . "\n";

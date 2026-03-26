<?php
// covers: ArrayAccess/Countable (custom collection), DateTime/strtotime (TTL expiry),
//   serialize/unserialize (value storage), named arguments, generators (yield iteration),
//   nullsafe operator (?->), foreach references (&$entry), first-class callable syntax,
//   compact(), constructor property promotion, enums (eviction policy),
//   array destructuring with keys, match expressions, spread operator,
//   pass-by-reference (&$stats), heredoc, static methods

enum EvictionPolicy: string {
    case LRU = 'lru';
    case FIFO = 'fifo';
    case LFU = 'lfu';

    public function label(): string {
        return match($this) {
            self::LRU => 'Least Recently Used',
            self::FIFO => 'First In First Out',
            self::LFU => 'Least Frequently Used',
        };
    }
}

class CacheEntry {
    public int $hits = 0;
    public int $lastAccess;

    public function __construct(
        public readonly string $key,
        public mixed $value,
        public int $expiresAt,
        public int $createdAt,
    ) {
        $this->lastAccess = $createdAt;
    }

    public function isExpired(int $now): bool {
        return $this->expiresAt > 0 && $now >= $this->expiresAt;
    }

    public function touch(int $now): void {
        $this->hits++;
        $this->lastAccess = $now;
    }
}

class Cache implements ArrayAccess, Countable {
    private array $entries = [];
    private int $hits = 0;
    private int $misses = 0;

    public function __construct(
        private int $maxSize = 10,
        private EvictionPolicy $policy = EvictionPolicy::LRU,
        private int $defaultTtl = 3600,
    ) {}

    public function set(string $key, mixed $value, int $ttl = -1): void {
        $now = 1750000000;
        if ($ttl < 0) $ttl = $this->defaultTtl;
        $expiresAt = $ttl > 0 ? $now + $ttl : 0;

        if (count($this->entries) >= $this->maxSize && !isset($this->entries[$key])) {
            $this->evict();
        }

        $serialized = serialize($value);
        $this->entries[$key] = new CacheEntry(
            key: $key,
            value: $serialized,
            expiresAt: $expiresAt,
            createdAt: $now,
        );
    }

    public function get(string $key, mixed $default = null): mixed {
        $entry = $this->entries[$key] ?? null;
        if ($entry === null) {
            $this->misses++;
            return $default;
        }

        $now = 1750000000;
        if ($entry->isExpired($now)) {
            unset($this->entries[$key]);
            $this->misses++;
            return $default;
        }

        $entry->touch($now);
        $this->hits++;
        return unserialize($entry->value);
    }

    public function has(string $key): bool {
        $entry = $this->entries[$key] ?? null;
        return $entry !== null && !$entry->isExpired(1750000000);
    }

    public function delete(string $key): bool {
        if (!isset($this->entries[$key])) return false;
        unset($this->entries[$key]);
        return true;
    }

    public function clear(): void {
        $this->entries = [];
    }

    private function evict(): void {
        if (empty($this->entries)) return;

        $victim = null;
        $victimKey = null;

        foreach ($this->entries as $key => &$entry) {
            if ($victim === null) {
                $victim = $entry;
                $victimKey = $key;
                continue;
            }

            $shouldEvict = match($this->policy) {
                EvictionPolicy::LRU => $entry->lastAccess < $victim->lastAccess,
                EvictionPolicy::FIFO => $entry->createdAt < $victim->createdAt,
                EvictionPolicy::LFU => $entry->hits < $victim->hits,
            };

            if ($shouldEvict) {
                $victim = $entry;
                $victimKey = $key;
            }
        }

        if ($victimKey !== null) {
            unset($this->entries[$victimKey]);
        }
    }

    // ArrayAccess
    public function offsetExists(mixed $offset): bool {
        return $this->has($offset);
    }

    public function offsetGet(mixed $offset): mixed {
        return $this->get($offset);
    }

    public function offsetSet(mixed $offset, mixed $value): void {
        $this->set($offset, $value);
    }

    public function offsetUnset(mixed $offset): void {
        $this->delete($offset);
    }

    // Countable
    public function count(): int {
        return count($this->entries);
    }

    public function keys(): array {
        return array_keys($this->entries);
    }

    public function stats(int &$totalHits, int &$totalMisses): array {
        $totalHits += $this->hits;
        $totalMisses += $this->misses;
        $ratio = ($this->hits + $this->misses) > 0
            ? round($this->hits / ($this->hits + $this->misses) * 100, 1)
            : 0.0;
        return compact('ratio');
    }

    public function entries(): Generator {
        foreach ($this->entries as $key => $entry) {
            yield $key => unserialize($entry->value);
        }
    }

    public function getPolicy(): EvictionPolicy {
        return $this->policy;
    }
}

class CacheGroup {
    private array $caches = [];

    public function add(string $name, Cache $cache): void {
        $this->caches[$name] = $cache;
    }

    public function find(string $name): ?Cache {
        return $this->caches[$name] ?? null;
    }

    public function collectStats(): array {
        $results = [];
        foreach ($this->caches as $name => $cache) {
            $hits = 0;
            $misses = 0;
            $stats = $cache->stats(totalHits: $hits, totalMisses: $misses);
            ['ratio' => $ratio] = $stats;
            $results[] = [
                'name' => $name,
                'count' => count($cache),
                'hits' => $hits,
                'misses' => $misses,
                'ratio' => $ratio,
                'policy' => $cache->getPolicy()->label(),
            ];
        }
        return $results;
    }
}

// --- basic set/get ---

$cache = new Cache(maxSize: 5, policy: EvictionPolicy::LRU, defaultTtl: 3600);

$cache->set('name', 'Alice');
$cache->set('age', 30);
$cache->set('scores', [95, 87, 92]);

echo $cache->get('name') . "\n";
echo $cache->get('age') . "\n";
echo implode(',', $cache->get('scores')) . "\n";
echo $cache->get('missing', 'default') . "\n";
echo "count: " . count($cache) . "\n";

// --- ArrayAccess ---

$cache['color'] = 'blue';
echo $cache['color'] . "\n";
echo "isset: " . (isset($cache['color']) ? 'yes' : 'no') . "\n";
unset($cache['color']);
echo "after unset: " . (isset($cache['color']) ? 'yes' : 'no') . "\n";
echo "count: " . count($cache) . "\n";

// --- serialize complex values ---

$data = ['nested' => ['a' => 1, 'b' => [2, 3]], 'flag' => true, 'nothing' => null];
$cache->set('complex', $data);
$retrieved = $cache->get('complex');
echo "nested.a: " . $retrieved['nested']['a'] . "\n";
echo "nested.b: " . implode(',', $retrieved['nested']['b']) . "\n";
echo "flag: " . ($retrieved['flag'] ? 'true' : 'false') . "\n";
echo "nothing: " . ($retrieved['nothing'] === null ? 'null' : 'other') . "\n";

// --- eviction (LRU) ---

$lru = new Cache(maxSize: 3, policy: EvictionPolicy::LRU);
$lru->set('a', 1);
$lru->set('b', 2);
$lru->set('c', 3);
$lru->get('a');
$lru->get('a');
$lru->set('d', 4);
echo "a survived: " . ($lru->has('a') ? 'yes' : 'no') . "\n";
echo "b evicted: " . ($lru->has('b') ? 'no' : 'yes') . "\n";
echo "d exists: " . ($lru->has('d') ? 'yes' : 'no') . "\n";

// --- eviction (FIFO) ---

$fifo = new Cache(maxSize: 3, policy: EvictionPolicy::FIFO);
$fifo->set('x', 10);
$fifo->set('y', 20);
$fifo->set('z', 30);
$fifo->get('x');
$fifo->get('x');
$fifo->set('w', 40);
echo "x evicted fifo: " . ($fifo->has('x') ? 'no' : 'yes') . "\n";
echo "z survived fifo: " . ($fifo->has('z') ? 'yes' : 'no') . "\n";

// --- generator iteration ---

$cache->set('g1', 'alpha');
$cache->set('g2', 'beta');
$items = [];
foreach ($cache->entries() as $k => $v) {
    if (is_string($v)) {
        $items[] = "$k=$v";
    }
}
sort($items);
echo "entries: " . implode(', ', $items) . "\n";

// --- pass-by-reference stats ---

$h = 0;
$m = 0;
$cache->stats($h, $m);
echo "hits: $h, misses: $m\n";

// --- nullsafe operator ---

$group = new CacheGroup();
$group->add('main', $cache);
echo "found: " . ($group->find('main') !== null ? 'yes' : 'no') . "\n";
$policy = $group->find('main')?->getPolicy();
echo "policy: " . $policy->value . "\n";
$nope = $group->find('nonexistent')?->getPolicy();
echo "null policy: " . ($nope === null ? 'null' : 'other') . "\n";

// --- enum features ---

echo EvictionPolicy::LRU->value . "\n";
echo EvictionPolicy::FIFO->label() . "\n";
echo EvictionPolicy::from('lfu')->label() . "\n";

// --- first-class callable + spread ---

$formatter = strtoupper(...);
echo $formatter('hello') . "\n";

$args = ['world'];
echo strtoupper(...$args) . "\n";

// --- array destructuring with keys ---

$stats = $group->collectStats();
foreach ($stats as $stat) {
    ['name' => $name, 'count' => $cnt, 'policy' => $pol] = $stat;
    echo "group $name: $cnt items, $pol\n";
}

// --- heredoc ---

$cacheName = 'main';
$cacheCount = count($cache);
$report = <<<REPORT
cache: $cacheName
items: $cacheCount
status: active
REPORT;
echo $report . "\n";

// --- DateTime/strtotime ---

$base = 1750000000;
$expiry = strtotime("+1 hour", $base);
echo "ttl check: " . ($expiry > $base ? 'valid' : 'invalid') . "\n";
echo "tomorrow: " . date('Y-m-d', strtotime('tomorrow', $base)) . "\n";

$dt = new DateTime('2025-06-15 12:00:00');
$dt->modify('+30 minutes');
echo "modified: " . $dt->format('H:i') . "\n";

// --- compact ---

$status = 'active';
$size = 5;
$engine = 'lru';
$info = compact('status', 'size', 'engine');
echo "compact: " . $info['status'] . "/" . $info['size'] . "/" . $info['engine'] . "\n";

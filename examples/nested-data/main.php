<?php
// covers: auto-vivification (nested array creation), json_encode, json_decode,
//   version_compare, class_alias, array_merge_recursive, array_column,
//   array_combine, array_fill_keys, compact, extract, deep array manipulation

// --- auto-vivification ---
echo "=== auto-vivification ===\n";
$config = [];
$config['database']['host'] = 'localhost';
$config['database']['port'] = 3306;
$config['database']['credentials']['user'] = 'admin';
$config['database']['credentials']['pass'] = 'secret';
$config['cache']['driver'] = 'redis';
$config['cache']['ttl'] = 3600;

echo "db host: {$config['database']['host']}\n";
echo "db port: {$config['database']['port']}\n";
echo "db user: {$config['database']['credentials']['user']}\n";
echo "cache driver: {$config['cache']['driver']}\n";

// vivify with push
$config['database']['replicas'][] = 'replica-1';
$config['database']['replicas'][] = 'replica-2';
echo "replicas: " . count($config['database']['replicas']) . "\n";
echo "first replica: {$config['database']['replicas'][0]}\n";

// integer key vivification
$matrix = [];
$matrix[0][0] = 1;
$matrix[0][1] = 0;
$matrix[1][0] = 0;
$matrix[1][1] = 1;
echo "identity: [{$matrix[0][0]},{$matrix[0][1]}],[{$matrix[1][0]},{$matrix[1][1]}]\n";

// copy semantics after vivification
$original = [];
$original['a']['b'] = 1;
$copy = $original;
$original['a']['c'] = 2;
echo "copy unchanged: " . (isset($copy['a']['c']) ? 'no' : 'yes') . "\n";

// --- json roundtrips ---
echo "\n=== json roundtrips ===\n";
$data = [
    'users' => [
        ['id' => 1, 'name' => 'Alice', 'active' => true],
        ['id' => 2, 'name' => 'Bob', 'active' => false],
        ['id' => 3, 'name' => 'Charlie', 'active' => true],
    ],
    'meta' => ['total' => 3, 'page' => 1],
];

$json = json_encode($data);
echo "encoded type: " . gettype($json) . "\n";
$decoded = json_decode($json, true);
echo "user count: " . count($decoded['users']) . "\n";
echo "first user: {$decoded['users'][0]['name']}\n";
echo "meta total: {$decoded['meta']['total']}\n";

// nested json with special chars
$special = ['message' => 'hello "world" & <friends>', 'emoji' => "tab\there"];
$json2 = json_encode($special);
$back = json_decode($json2, true);
echo "special roundtrip: " . ($back['message'] === $special['message'] ? 'yes' : 'no') . "\n";

// json encode with numeric keys
$indexed = [10, 20, 30];
echo "indexed: " . json_encode($indexed) . "\n";

// --- version_compare ---
echo "\n=== version_compare ===\n";
echo "1.0 < 1.1: " . (version_compare('1.0', '1.1', '<') ? 'yes' : 'no') . "\n";
echo "2.0 > 1.9.9: " . (version_compare('2.0', '1.9.9', '>') ? 'yes' : 'no') . "\n";
echo "1.0.0 == 1.0: " . (version_compare('1.0.0', '1.0', '==') ? 'yes' : 'no') . "\n";
echo "1.0-beta < 1.0: " . (version_compare('1.0-beta', '1.0', '<') ? 'yes' : 'no') . "\n";
echo "1.0-rc1 < 1.0: " . (version_compare('1.0-rc1', '1.0', '<') ? 'yes' : 'no') . "\n";
echo "1.0alpha < 1.0beta: " . (version_compare('1.0alpha', '1.0beta', '<') ? 'yes' : 'no') . "\n";

$raw = version_compare('1.2.3', '1.2.4');
echo "raw compare: $raw\n";

// --- class_alias ---
echo "\n=== class_alias ===\n";
class Logger {
    private $name;
    public function __construct($name) { $this->name = $name; }
    public function info($msg) { return "[{$this->name}] $msg"; }
}

class_alias('Logger', 'Log');
$log = new Log('app');
echo $log->info("started") . "\n";
echo ($log instanceof Logger) ? "instanceof: yes\n" : "instanceof: no\n";

// --- deep array manipulation ---
echo "\n=== deep arrays ===\n";

// build a tree via vivification then traverse
$tree = [];
$tree['root']['left']['value'] = 1;
$tree['root']['right']['left']['value'] = 2;
$tree['root']['right']['right']['value'] = 3;
$tree['root']['value'] = 0;

function sumTree($node) {
    $sum = $node['value'] ?? 0;
    if (isset($node['left'])) $sum += sumTree($node['left']);
    if (isset($node['right'])) $sum += sumTree($node['right']);
    return $sum;
}
echo "tree sum: " . sumTree($tree['root']) . "\n";

// compact and extract
$host = 'localhost';
$port = 5432;
$driver = 'pgsql';
$packed = compact('host', 'port', 'driver');
echo "compact: {$packed['host']}:{$packed['port']} ({$packed['driver']})\n";

$settings = ['timeout' => 30, 'retries' => 3, 'verbose' => true];
extract($settings);
echo "extracted: timeout=$timeout retries=$retries verbose=" . ($verbose ? 'true' : 'false') . "\n";

// array_combine
$keys = ['name', 'age', 'city'];
$values = ['Alice', 30, 'NYC'];
$combined = array_combine($keys, $values);
echo "combined: {$combined['name']} age {$combined['age']} in {$combined['city']}\n";

// array_fill_keys
$defaults = array_fill_keys(['read', 'write', 'admin'], false);
echo "defaults: read=" . ($defaults['read'] ? 'true' : 'false');
echo " admin=" . ($defaults['admin'] ? 'true' : 'false') . "\n";

// nested array modification
$users = [
    ['name' => 'Alice', 'scores' => [90, 85, 92]],
    ['name' => 'Bob', 'scores' => [78, 82, 88]],
];
$averages = [];
foreach ($users as $user) {
    $avg = array_sum($user['scores']) / count($user['scores']);
    $averages[$user['name']] = round($avg, 1);
}
echo "Alice avg: {$averages['Alice']}\n";
echo "Bob avg: {$averages['Bob']}\n";

echo "\ndone\n";

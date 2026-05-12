<?php
// covers: PHP serialize/unserialize for nested arrays/objects,
//   __serialize/__unserialize hooks, options whitelist, var_export round-trip,
//   json fallback comparison

class Address {
    public function __construct(public string $street, public string $city) {}
}

class User {
    public array $tags = [];
    public ?Address $home = null;
    public function __construct(public string $name, public int $age) {}
}

$alice = new User('Alice', 30);
$alice->tags = ['admin', 'editor'];
$alice->home = new Address('1 Main', 'Paris');

$bob = new User('Bob', 25);
$bob->tags = [];

echo "=== serialize a graph ===\n";
$data = ['alice' => $alice, 'bob' => $bob, 'flag' => true, 'count' => 42];
$s = serialize($data);
echo "ok bytes > 0: " . (strlen($s) > 0 ? "yes" : "no") . "\n";

echo "\n=== round-trip whole graph ===\n";
$back = unserialize($s);
echo "alice name: " . $back['alice']->name . "\n";
echo "alice city: " . $back['alice']->home->city . "\n";
echo "alice tags: " . implode(',', $back['alice']->tags) . "\n";
echo "flag: " . var_export($back['flag'], true) . "\n";

echo "\n=== unserialize with class whitelist (downgrade unknowns) ===\n";
// untyped containers so the downgraded __PHP_Incomplete_Class doesn't hit
// PHP's TypeError on typed-property assignment during reconstruction
$std1 = new stdClass();
$std1->kind = 'a';
$std2 = new stdClass();
$std2->kind = 'b';
$mixed = ['s1' => $std1, 's2' => $std2];

$kept = unserialize(serialize($mixed), ['allowed_classes' => [stdClass::class]]);
echo "s1 kept: " . get_class($kept['s1']) . "\n";
echo "s2 kept: " . get_class($kept['s2']) . "\n";

$none = unserialize(serialize($mixed), ['allowed_classes' => false]);
echo "all downgraded: " . get_class($none['s1']) . "\n";

echo "\n=== custom __serialize / __unserialize ===\n";
class Money {
    public function __construct(public int $cents, public string $currency = 'USD') {}
    public function __serialize(): array {
        return ['amount' => $this->cents / 100, 'cur' => $this->currency];
    }
    public function __unserialize(array $data): void {
        $this->cents = (int)round($data['amount'] * 100);
        $this->currency = $data['cur'];
    }
}
$price = new Money(12345, 'EUR');
$s = serialize($price);
echo "contains amount: " . (str_contains($s, 'amount') ? "yes" : "no") . "\n";
echo "round trip cents: " . unserialize($s)->cents . "\n";
echo "round trip currency: " . unserialize($s)->currency . "\n";

echo "\n=== arrays preserve mixed keys and order ===\n";
$mixed = [10 => 'ten', 'name' => 'bob', 0 => 'zero', 'sub' => [1, 2, 3]];
$out = unserialize(serialize($mixed));
echo "keys: " . implode(',', array_keys($out)) . "\n";
echo "sub: " . implode('|', $out['sub']) . "\n";

echo "\n=== floats round-trip with precision ===\n";
$f = [1.5, 0.1 + 0.2, 1e-9, 1.234567890123456];
$r = unserialize(serialize($f));
foreach ($f as $i => $orig) echo "  $orig == $r[$i]: " . ($orig === $r[$i] ? "yes" : "no") . "\n";

echo "\n=== invalid input returns false ===\n";
$cases = ['garbage', 'a:5:{i:0;', '', 'X:5:'];
foreach ($cases as $c) {
    $r = @unserialize($c);
    echo sprintf("  %-15s -> %s\n", $c === '' ? '(empty)' : $c, var_export($r, true));
}

echo "\n=== var_export string is valid PHP ===\n";
$payload = ['nums' => [1, 2, 3.5], 'name' => 'éclair', 'flag' => null];
$code = var_export($payload, true);
$tmp = tempnam(sys_get_temp_dir(), 've');
file_put_contents($tmp, "<?php return $code;\n");
$loaded = include $tmp;
echo "round-trip match: " . ($loaded == $payload ? "yes" : "no") . "\n";
echo "nested ok: " . (count($loaded['nums']) === 3 ? "yes" : "no") . "\n";
unlink($tmp);

echo "\n=== json compare for the same payload ===\n";
$payload = ['a' => 1, 'b' => [2, 3], 'c' => 'hi'];
echo "json: " . json_encode($payload) . "\n";
echo "serialized: " . serialize($payload) . "\n";
echo "json shorter: " . (strlen(json_encode($payload)) < strlen(serialize($payload)) ? "yes" : "no") . "\n";

echo "\ndone\n";

<?php
// covers: random_bytes, bin2hex, hex2bin, ord, chr, substr, sprintf,
//   md5, sha1, str_replace, str_pad, strtolower, preg_match, strlen,
//   pack, unpack, microtime, intdiv, usort, array_unique, count

const NS_DNS = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';
const NS_URL = '6ba7b811-9dad-11d1-80b4-00c04fd430c8';

function uuid_format(string $bytes): string {
    if (strlen($bytes) !== 16) {
        throw new RuntimeException('uuid bytes must be 16, got ' . strlen($bytes));
    }
    $hex = bin2hex($bytes);
    return substr($hex, 0, 8) . '-'
         . substr($hex, 8, 4) . '-'
         . substr($hex, 12, 4) . '-'
         . substr($hex, 16, 4) . '-'
         . substr($hex, 20, 12);
}

function uuid_parse(string $uuid): string {
    $hex = str_replace('-', '', strtolower($uuid));
    if (strlen($hex) !== 32 || !preg_match('/^[0-9a-f]{32}$/', $hex)) {
        throw new RuntimeException("invalid uuid: $uuid");
    }
    return hex2bin($hex);
}

function uuid_set_version(string $bytes, int $version): string {
    // octet 6 high nibble = version
    $bytes[6] = chr((ord($bytes[6]) & 0x0f) | ($version << 4));
    // octet 8 high two bits = 10 (RFC 4122 variant)
    $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
    return $bytes;
}

function uuid_v4(): string {
    return uuid_format(uuid_set_version(random_bytes(16), 4));
}

function uuid_v3(string $namespace, string $name): string {
    $bytes = substr(md5(uuid_parse($namespace) . $name, true), 0, 16);
    return uuid_format(uuid_set_version($bytes, 3));
}

function uuid_v5(string $namespace, string $name): string {
    $bytes = substr(sha1(uuid_parse($namespace) . $name, true), 0, 16);
    return uuid_format(uuid_set_version($bytes, 5));
}

function uuid_v7(): string {
    // 48-bit unix epoch milliseconds, then 4-bit version, 12-bit rand_a,
    // 2-bit variant, 62-bit rand_b
    $ms = intdiv((int)(microtime(true) * 1000000), 1000);
    $rand = random_bytes(10);
    // pack ms as 6 bytes big-endian using two ints
    $hi = ($ms >> 32) & 0xffff;
    $lo = $ms & 0xffffffff;
    $bytes = pack('nN', $hi, $lo) . $rand;
    return uuid_format(uuid_set_version($bytes, 7));
}

function uuid_version(string $uuid): int {
    $b = uuid_parse($uuid);
    return (ord($b[6]) >> 4) & 0x0f;
}

function uuid_variant_is_rfc4122(string $uuid): bool {
    $b = uuid_parse($uuid);
    return (ord($b[8]) & 0xc0) === 0x80;
}

echo "=== format and parse ===\n";
$canonical = '550e8400-e29b-41d4-a716-446655440000';
$bin = uuid_parse($canonical);
echo "  parse length: " . strlen($bin) . "\n";
echo "  format roundtrip: " . (uuid_format($bin) === $canonical ? 'ok' : 'FAIL') . "\n";
echo "  uppercase parse: " . (uuid_format(uuid_parse(strtoupper($canonical))) === $canonical ? 'ok' : 'FAIL') . "\n";

echo "\n=== v4 random ===\n";
$v4s = [];
for ($i = 0; $i < 5; $i++) $v4s[] = uuid_v4();
echo "  unique: " . (count(array_unique($v4s)) === 5 ? 'yes' : 'no') . "\n";
$all_v4 = true;
$all_rfc = true;
foreach ($v4s as $u) {
    if (uuid_version($u) !== 4) $all_v4 = false;
    if (!uuid_variant_is_rfc4122($u)) $all_rfc = false;
}
echo "  all version=4: " . ($all_v4 ? 'yes' : 'no') . "\n";
echo "  all rfc4122 variant: " . ($all_rfc ? 'yes' : 'no') . "\n";

echo "\n=== v3 deterministic (md5) ===\n";
$v3 = uuid_v3(NS_DNS, 'www.widgets.com');
echo "  v3(NS_DNS, www.widgets.com) = $v3\n";
echo "  version: " . uuid_version($v3) . "\n";
echo "  variant rfc4122: " . (uuid_variant_is_rfc4122($v3) ? 'yes' : 'no') . "\n";
echo "  deterministic: " . (uuid_v3(NS_DNS, 'www.widgets.com') === $v3 ? 'yes' : 'no') . "\n";
echo "  different name differs: " . (uuid_v3(NS_DNS, 'other') !== $v3 ? 'yes' : 'no') . "\n";

echo "\n=== v5 deterministic (sha1) ===\n";
$v5 = uuid_v5(NS_DNS, 'python.org');
echo "  v5(NS_DNS, python.org) = $v5\n";
echo "  version: " . uuid_version($v5) . "\n";
echo "  variant rfc4122: " . (uuid_variant_is_rfc4122($v5) ? 'yes' : 'no') . "\n";
echo "  deterministic: " . (uuid_v5(NS_DNS, 'python.org') === $v5 ? 'yes' : 'no') . "\n";
echo "  different ns differs: " . (uuid_v5(NS_URL, 'python.org') !== $v5 ? 'yes' : 'no') . "\n";

echo "\n=== v7 time-ordered ===\n";
$v7s = [];
for ($i = 0; $i < 5; $i++) {
    $v7s[] = uuid_v7();
    usleep(2000);
}
echo "  generated " . count($v7s) . "\n";
$all_v7 = true;
foreach ($v7s as $u) if (uuid_version($u) !== 7) $all_v7 = false;
echo "  all version=7: " . ($all_v7 ? 'yes' : 'no') . "\n";
echo "  all unique: " . (count(array_unique($v7s)) === 5 ? 'yes' : 'no') . "\n";

$sorted = $v7s;
sort($sorted);
echo "  lexically sorted equals generation order: " . ($sorted === $v7s ? 'yes' : 'no') . "\n";

echo "\n=== validation ===\n";
$cases = [
    ['550e8400-e29b-41d4-a716-446655440000', true],
    ['550E8400-E29B-41D4-A716-446655440000', true],
    ['550e8400e29b41d4a716446655440000', true],          // accept compact form
    ['550e8400-e29b-41d4-a716-44665544000', false],      // too short
    ['550e8400-e29b-41d4-a716-4466554400000', false],    // too long
    ['550e8400-e29b-41d4-a716-44665544000z', false],     // non-hex
    ['', false],
    ['not-a-uuid', false],
];
foreach ($cases as [$s, $valid]) {
    $got = true;
    try { uuid_parse($s); } catch (Throwable) { $got = false; }
    $ok = $got === $valid ? 'ok' : 'FAIL';
    echo sprintf("  %-40s expected=%-5s got=%-5s %s\n",
        $s === '' ? '(empty)' : $s,
        $valid ? 'true' : 'false',
        $got ? 'true' : 'false',
        $ok);
}

echo "\n=== bit-level inspection ===\n";
foreach ([3, 4, 5, 7] as $ver) {
    $u = match($ver) {
        3 => uuid_v3(NS_DNS, 'a'),
        4 => uuid_v4(),
        5 => uuid_v5(NS_DNS, 'a'),
        7 => uuid_v7(),
    };
    $b = uuid_parse($u);
    $v_nibble = (ord($b[6]) >> 4) & 0x0f;
    $variant_bits = (ord($b[8]) >> 6) & 0x03;
    echo "  v$ver: version=$v_nibble variant_bits=" . sprintf('%02b', $variant_bits) . "\n";
}

echo "\n=== usort lexical ===\n";
$ids = [uuid_v7(), uuid_v7(), uuid_v7()];
usort($ids, fn($a, $b) => strcmp($a, $b));
$is_sorted = true;
for ($i = 1; $i < count($ids); $i++) {
    if (strcmp($ids[$i - 1], $ids[$i]) > 0) { $is_sorted = false; break; }
}
echo "  count: " . count($ids) . "\n";
echo "  sorted ascending: " . ($is_sorted ? 'yes' : 'no') . "\n";

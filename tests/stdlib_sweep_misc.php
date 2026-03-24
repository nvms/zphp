<?php

// === json ===
$data = ["name" => "Alice", "age" => 30, "active" => true];
$json = json_encode($data);
echo $json . "\n";

$decoded = json_decode($json, true);
echo $decoded["name"] . " " . $decoded["age"] . "\n";

echo json_encode(null) . "\n";
echo json_encode([1, 2, 3]) . "\n";
echo json_encode(["a" => 1], JSON_PRETTY_PRINT) . "\n";

$nested = json_decode('{"users":[{"name":"Bob"},{"name":"Carol"}]}', true);
echo $nested["users"][0]["name"] . "\n";
echo $nested["users"][1]["name"] . "\n";

// === regex ===
echo var_export(preg_match('/^hello/', 'hello world'), true) . "\n";
echo var_export(preg_match('/^world/', 'hello world'), true) . "\n";

$m = [];
preg_match('/(\d{4})-(\d{2})-(\d{2})/', '2024-01-15', $m);
echo $m[0] . "\n";
echo $m[1] . " " . $m[2] . " " . $m[3] . "\n";

// named groups
$m2 = [];
preg_match('/(?P<year>\d{4})-(?P<month>\d{2})/', '2024-01-15', $m2);
echo $m2["year"] . " " . $m2["month"] . "\n";

// preg_match_all
$all = [];
preg_match_all('/\d+/', 'a1b22c333', $all);
echo implode(",", $all[0]) . "\n";

// preg_replace
echo preg_replace('/\d+/', 'X', 'abc123def456') . "\n";
echo preg_replace('/(\w+)@(\w+)/', '$2/$1', 'user@host') . "\n";

// preg_split
$parts = preg_split('/[\s,]+/', 'one, two, three four');
echo implode("|", $parts) . "\n";

// === datetime ===
echo strlen(date("Y-m-d")) . "\n"; // 10 chars
echo date("Y", mktime(0, 0, 0, 6, 15, 2024)) . "\n";
echo date("m", mktime(0, 0, 0, 6, 15, 2024)) . "\n";
echo date("d", mktime(0, 0, 0, 6, 15, 2024)) . "\n";

// time() returns current unix timestamp
echo var_export(is_int(time()), true) . "\n";
echo var_export(time() > 1000000000, true) . "\n";

// === serialize ===
echo serialize(42) . "\n";
echo serialize("hello") . "\n";
echo serialize([1, "two", true]) . "\n";
echo serialize(null) . "\n";

echo var_export(unserialize('i:42;'), true) . "\n";
echo unserialize('s:5:"hello";') . "\n";

// === crypto ===
echo strlen(md5("test")) . "\n"; // 32
echo strlen(sha1("test")) . "\n"; // 40
echo strlen(hash("sha256", "test")) . "\n"; // 64

$hashed = password_hash("secret", PASSWORD_DEFAULT);
echo var_export(password_verify("secret", $hashed), true) . "\n";
echo var_export(password_verify("wrong", $hashed), true) . "\n";

echo var_export(is_string(random_bytes(16)), true) . "\n";
$r = random_int(1, 100);
echo var_export($r >= 1 && $r <= 100, true) . "\n";

// === filesystem (basic) ===
$tmpfile = tempnam(sys_get_temp_dir(), "zphp_test_");
file_put_contents($tmpfile, "hello world");
echo file_get_contents($tmpfile) . "\n";
echo filesize($tmpfile) . "\n";
echo var_export(file_exists($tmpfile), true) . "\n";
echo var_export(is_file($tmpfile), true) . "\n";
echo var_export(is_dir($tmpfile), true) . "\n";

echo basename("/foo/bar/baz.txt") . "\n";
echo dirname("/foo/bar/baz.txt") . "\n";

$pi = pathinfo("/foo/bar/baz.txt");
echo $pi["dirname"] . "\n";
echo $pi["basename"] . "\n";
echo $pi["extension"] . "\n";
echo $pi["filename"] . "\n";

unlink($tmpfile);
echo var_export(file_exists($tmpfile), true) . "\n";

// === output buffering ===
ob_start();
echo "buffered";
$captured = ob_get_clean();
echo "got:$captured\n";

ob_start();
echo "level1";
ob_start();
echo "level2";
$inner = ob_get_clean();
$outer = ob_get_clean();
echo "inner:$inner outer:$outer\n";

// === misc ===
echo var_export(isset($data), true) . "\n";
echo var_export(empty(""), true) . "\n";
echo var_export(empty("x"), true) . "\n";

echo getcwd() !== "" ? "has_cwd" : "no_cwd";
echo "\n";

// php_uname differs between local and docker, just check it returns a string
echo var_export(strlen(php_uname("s")) > 0, true) . "\n";

echo "done\n";

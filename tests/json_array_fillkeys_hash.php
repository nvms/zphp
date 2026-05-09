<?php
// hash_hmac
echo hash_hmac("sha256", "msg", "key"), "\n";
echo hash_hmac("sha1", "msg", "key"), "\n";
echo hash_hmac("md5", "msg", "key"), "\n";
echo bin2hex(hash_hmac("sha256", "msg", "key", true)), "\n";
echo hash_hmac("sha512", "test", str_repeat("a", 200)), "\n"; // long key

// hash family
echo hash("sha512", "test"), "\n";
echo hash("crc32b", "abc"), "\n";
echo hash("crc32", "abc"), "\n";
echo hash("xxh3", "test"), "\n";
echo hash("xxh32", "test"), "\n";
echo hash("xxh64", "test"), "\n";
echo hash("sha3-256", "test"), "\n";

// password_hash + verify
$h = password_hash("secret", PASSWORD_BCRYPT);
var_dump(strlen($h) >= 60);
var_dump(password_verify("secret", $h));
var_dump(password_verify("wrong", $h));
var_dump(password_verify("secret", $h));

// password_hash with cost
$h = password_hash("hello", PASSWORD_BCRYPT, ["cost" => 4]);
var_dump(strlen($h) >= 60);
var_dump(password_verify("hello", $h));

// password_get_info
$h = password_hash("pw", PASSWORD_BCRYPT);
$info = password_get_info($h);
echo $info['algoName'], "\n";
echo $info['options']['cost'] >= 4 ? "ok cost\n" : "fail\n";

// json_decode flags
print_r(json_decode('{"a":1,"b":2}', true));
print_r(json_decode('{"a":1,"b":2}'));
print_r(json_decode('{"a":1,"b":2}', false, 512, JSON_OBJECT_AS_ARRAY));
print_r(json_decode('{"deep":{"a":{"b":{"c":1}}}}', true));
var_dump(json_decode('{"deep":{"a":1}}', true, 2)); // null - too deep
var_dump(json_decode('{"deep":{"a":1}}', true, 3));
var_dump(json_last_error());
echo json_last_error_msg(), "\n";

// JSON_BIGINT_AS_STRING
var_dump(json_decode('99999999999999999999', false, 512, JSON_BIGINT_AS_STRING));
var_dump(json_decode('99999999999999999999'));
var_dump(json_decode('-99999999999999999999', false, 512, JSON_BIGINT_AS_STRING));

// array_diff multiple
print_r(array_diff([1,2,3,4,5], [2], [4]));
print_r(array_diff([1,2,3,4,5], [2,4], [3]));
print_r(array_diff_assoc(["a"=>1,"b"=>2], ["a"=>1], ["b"=>3])); // b in second matches val 3 but our val is 2

// array_intersect multiple
print_r(array_intersect([1,2,3,4], [2,3,5], [3]));
print_r(array_intersect_assoc(["a"=>1,"b"=>2], ["a"=>1,"b"=>2,"c"=>3]));
print_r(array_intersect_assoc(["a"=>1,"b"=>2], ["a"=>1,"b"=>9]));

// array_unique SORT_REGULAR/NUMERIC/STRING
print_r(array_unique([1, "1", 1.0, "abc", "1"], SORT_REGULAR));
print_r(array_unique([1, "1", 1.0, "abc", "1"], SORT_NUMERIC));
print_r(array_unique([1, "1", 1.0, "abc", "1"], SORT_STRING));

// array_fill_keys with non-string keys
print_r(array_fill_keys([1, 2, 3], "x"));
print_r(array_fill_keys(["a", 1, 1.5], "x")); // 1.5 -> 1, last wins
print_r(array_fill_keys([true, false, null], "x")); // true=1, false=0, null=""

// Closure::bind
class Box { private int $v = 42; }
$get = function() { return $this->v; };
$bound = Closure::bind($get, new Box, Box::class);
echo $bound(), "\n";

// Closure::bind to null (unbind)
$f = function() { return isset($this) ? "bound" : "unbound"; };
$u = Closure::bind($f, null);
echo $u(), "\n";

// Closure::fromCallable
$c = Closure::fromCallable("strtoupper");
echo $c("hello"), "\n";
try { $c = Closure::fromCallable(["Box", "doStatic"]); echo "no err\n"; } catch (TypeError $e) { echo "type-err\n"; }
class Foo { public static function bar() { return "foo::bar"; } }
$c = Closure::fromCallable(["Foo", "bar"]);
echo $c(), "\n";

// spl_autoload_register
$tracked = [];
spl_autoload_register(function($cn) use (&$tracked) { $tracked[] = $cn; });
$loaders = spl_autoload_functions();
echo "loaders=" . count($loaders) . "\n";

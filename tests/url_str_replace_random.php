<?php
// strtolower/strtoupper byte-based with multibyte
echo strtolower("HELLO"), "\n";
echo strtolower("Café"), "\n"; // Caf\xc3\xa9 - byte lowercase: caf<bytes>
echo bin2hex(strtolower("Café")), "\n";
echo strtoupper("groß"), "\n";

// strpos with multibyte
echo strpos("héllo wörld", "wör"), "\n"; // byte offset
echo strpos("héllo", "é"), "\n"; // byte index of first é byte
echo strlen("héllo"), "\n"; // byte length

// preg_match with PREG_OFFSET_CAPTURE
preg_match('/world/', "hello world foo", $m, PREG_OFFSET_CAPTURE);
echo $m[0][0], "@", $m[0][1], "\n"; // world@6
preg_match('/(\d+)-(\w+)/', "abc 123-def", $m, PREG_OFFSET_CAPTURE);
print_r($m);

// preg_match with PREG_OFFSET_CAPTURE + offset arg
preg_match('/\w+/', "hello world", $m, PREG_OFFSET_CAPTURE, 5);
echo $m[0][0], "@", $m[0][1], "\n"; // world@6

// parse_url edge
print_r(parse_url("file:///path/to/file"));
print_r(parse_url("mailto:user@example.com"));
print_r(parse_url("ftp://ftp.example.com:21/path"));
print_r(parse_url("//proto-relative.com/path"));
print_r(parse_url("/just/a/path"));
print_r(parse_url("user:pass@host"));
print_r(parse_url("?a=1&b=2"));

// str_replace with arrays
echo str_replace(["a","b","c"], ["1","2","3"], "abc"), "\n"; // 123
echo str_replace(["a","b","c"], ["x"], "abc"), "\n"; // xxx? - one replacement for all
echo str_replace(["a","b","c"], "x", "abc"), "\n"; // xxx
try { str_replace("a", ["x","y","z"], "abc"); echo "no\n"; } catch (\TypeError $e) { echo "te\n"; }

// array_column with object source
class Row { public function __construct(public int $id, public string $name) {} }
$rows = [new Row(1, "alice"), new Row(2, "bob"), new Row(3, "carol")];
print_r(array_column($rows, 'name'));
print_r(array_column($rows, 'name', 'id'));
print_r(array_column($rows, null, 'id'));

// hash_equals
var_dump(hash_equals("secret", "secret"));
var_dump(hash_equals("secret", "secrec"));
var_dump(hash_equals("a", "ab")); // false
var_dump(hash_equals("", ""));

// password_hash custom cost
$h1 = password_hash("test", PASSWORD_BCRYPT, ["cost" => 4]);
$h2 = password_hash("test", PASSWORD_BCRYPT, ["cost" => 6]);
echo strpos($h1, "\$2y\$04\$") === 0 ? "h1-cost4\n" : "no\n";
echo strpos($h2, "\$2y\$06\$") === 0 ? "h2-cost6\n" : "no\n";
echo password_verify("test", $h1) ? "v1\n" : "no";
echo password_verify("test", $h2) ? "v2\n" : "no";
echo password_verify("wrong", $h1) ? "no\n" : "wrong-v1\n";

// random_int
$r1 = random_int(1, 100);
echo gettype($r1), ":", ($r1 >= 1 && $r1 <= 100 ? "in-range" : "oob"), "\n";
// random_int two-call uniqueness check is flaky (1% chance of collision); skipped

try { random_int(10, 1); echo "no err\n"; } catch (\ValueError $e) { echo "ve\n"; }

// random_bytes
$b = random_bytes(16);
echo strlen($b), ":", gettype($b), "\n";

try { random_bytes(0); echo "ok-0\n"; } catch (\ValueError $e) { echo "ve\n"; }
try { random_bytes(-1); echo "no err\n"; } catch (\ValueError $e) { echo "ve-neg\n"; }

// openssl_random_pseudo_bytes
$b = openssl_random_pseudo_bytes(16);
echo strlen($b), "\n";

// crypto_random
$b = openssl_random_pseudo_bytes(16, $strong);
echo strlen($b), ":", $strong ? "strong" : "weak", "\n";

// regex specials in str_replace
echo str_replace("$1", "X", "abc \$1 def"), "\n"; // abc X def
echo str_replace("\\n", "/", "a\\nb"), "\n"; // a/b? - depends

// stripslashes / addslashes
echo addslashes("it's \"quoted\" \\with\\ slashes"), "\n";
echo stripslashes("it\\'s \\\"quoted\\\""), "\n";

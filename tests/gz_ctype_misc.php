<?php
// ctype with int args (PHP 8.1+ semantic change)
var_dump(ctype_alpha("abc"));
var_dump(ctype_alpha("abc123"));
var_dump(ctype_alpha("ABC"));
var_dump(ctype_alpha(""));    // false in 8.1+
var_dump(ctype_alpha("a"));

// PHP 8.5 deprecates int-arg semantics (architectural skip)

// ctype_digit
var_dump(ctype_digit("123"));
var_dump(ctype_digit("12.3"));
var_dump(ctype_digit(""));
var_dump(ctype_digit("1"));
// int-arg ctype: deprecated in 8.5 (architectural skip)

// ctype_alnum
var_dump(ctype_alnum("abc123"));
var_dump(ctype_alnum("abc 123")); // false (space)
var_dump(ctype_alnum(""));
var_dump(ctype_alnum("abc-123"));

// ctype_xdigit
var_dump(ctype_xdigit("1234abcDEF"));
var_dump(ctype_xdigit("0x10"));   // false ('x')
var_dump(ctype_xdigit("ABC"));
var_dump(ctype_xdigit("xyz"));    // false

// ctype_space
var_dump(ctype_space("   "));
var_dump(ctype_space(" \t\n\r"));
var_dump(ctype_space("a "));
var_dump(ctype_space(""));
var_dump(ctype_space("\v\f")); // vertical tab, form feed (whitespace)

// ctype_upper / ctype_lower
var_dump(ctype_upper("ABC"));
var_dump(ctype_upper("AbC"));
var_dump(ctype_lower("abc"));
var_dump(ctype_lower("AbC"));

// ctype_punct
var_dump(ctype_punct("!?,.;"));
var_dump(ctype_punct("abc"));
var_dump(ctype_punct("123"));
var_dump(ctype_punct(""));

// ctype_print / ctype_graph
var_dump(ctype_print("abc 123"));
var_dump(ctype_print("abc\nx"));
var_dump(ctype_graph("abc"));
var_dump(ctype_graph("abc def")); // false (space)

// ctype_cntrl
var_dump(ctype_cntrl("\n\t\r"));
var_dump(ctype_cntrl("abc"));

// hash_init incremental
$ctx = hash_init("md5");
hash_update($ctx, "hello ");
hash_update($ctx, "world");
echo hash_final($ctx), "\n";
echo hash("md5", "hello world"), "\n";

$ctx = hash_init("sha256");
foreach (str_split("Hello, World!", 3) as $chunk) hash_update($ctx, $chunk);
echo hash_final($ctx), "\n";
echo hash("sha256", "Hello, World!"), "\n";

// hash_init with key (HMAC)
$ctx = hash_init("sha256", HASH_HMAC, "key");
hash_update($ctx, "data");
echo hash_final($ctx), "\n";
echo hash_hmac("sha256", "data", "key"), "\n";

// hash_copy
$c1 = hash_init("sha1");
hash_update($c1, "foo");
$c2 = hash_copy($c1);
hash_update($c1, "bar");
hash_update($c2, "baz");
echo hash_final($c1), "\n";
echo hash_final($c2), "\n";

// base64 with raw flag (URL-safe)
$bin = "\xff\xfe\xfd\xfc";
echo base64_encode($bin), "\n"; // "//79/A=="
$dec = base64_decode("//79/A==");
echo bin2hex($dec), "\n"; // "fffefdfc"

// strict mode rejects invalid chars
var_dump(base64_decode("AB!CD", true));   // false (! invalid)
var_dump(base64_decode("AB CD", true));   // false (space invalid in strict)
var_dump(base64_decode("ABCD", true));    // valid

// invalid char in non-strict — silently dropped
echo bin2hex(base64_decode("AB!CD")), "\n"; // ABCD decoded

// gzcompress / gzuncompress
$d = gzcompress("hello world hello world hello world");
$r = gzuncompress($d);
echo $r === "hello world hello world hello world" ? "rt-ok\n" : "no\n";

// gzdeflate / gzinflate
$d = gzdeflate("test data");
$r = gzinflate($d);
echo $r === "test data" ? "rt-deflate\n" : "no\n";

// gzencode / gzdecode (gzip format)
$d = gzencode("gzip me");
$r = gzdecode($d);
echo $r === "gzip me" ? "rt-gz\n" : "no\n";

<?php
// comprehensive string function sweep

// basic transforms
echo strtolower("HELLO") . "\n";
echo strtoupper("hello") . "\n";
echo ucfirst("hello world") . "\n";
echo lcfirst("Hello World") . "\n";
echo ucwords("hello world foo") . "\n";
echo str_repeat("ab", 3) . "\n";
echo strrev("hello") . "\n";

// trim variants
echo trim("  hello  ") . "\n";
echo ltrim("  hello  ") . "\n";
echo rtrim("  hello  ") . "\n";
echo trim("xxhelloxx", "x") . "\n";

// search/position
echo strpos("hello world", "world") . "\n";
echo stripos("Hello World", "world") . "\n";
echo strrpos("hello hello", "hello") . "\n";
echo substr_count("hello hello hello", "hello") . "\n";
echo var_export(strpos("hello", "xyz"), true) . "\n";

// contains/starts/ends
echo var_export(str_contains("hello world", "world"), true) . "\n";
echo var_export(str_starts_with("hello world", "hello"), true) . "\n";
echo var_export(str_ends_with("hello world", "world"), true) . "\n";
echo var_export(str_contains("hello", "xyz"), true) . "\n";
echo var_export(str_starts_with("hello", "xyz"), true) . "\n";
echo var_export(str_ends_with("hello", "xyz"), true) . "\n";

// substr
echo substr("hello world", 6) . "\n";
echo substr("hello world", 0, 5) . "\n";
echo substr("hello world", -5) . "\n";
echo substr("hello", 1, 3) . "\n";

// replace
echo str_replace("world", "PHP", "hello world") . "\n";
echo str_ireplace("WORLD", "PHP", "hello world") . "\n";
echo substr_replace("hello world", "PHP", 6, 5) . "\n";

// split/join
$parts = explode(",", "a,b,c");
echo count($parts) . "\n";
echo $parts[1] . "\n";
echo implode("-", ["x", "y", "z"]) . "\n";

$split = str_split("hello", 2);
echo count($split) . "\n";
echo $split[0] . " " . $split[1] . " " . $split[2] . "\n";

// pad
echo str_pad("hi", 10) . "|\n";
echo str_pad("hi", 10, "-") . "|\n";
echo str_pad("hi", 10, "-", STR_PAD_LEFT) . "|\n";
echo str_pad("hi", 10, "-+", STR_PAD_BOTH) . "|\n";

// formatting
echo number_format(1234567.891, 2, ".", ",") . "\n";
echo sprintf("Hello %s, you are %d", "World", 42) . "\n";
echo sprintf("%05d", 42) . "\n";
echo sprintf("%.2f", 3.14159) . "\n";
echo sprintf("%10s", "right") . "\n";

// encoding
echo htmlspecialchars("<p>Hello & 'World'</p>") . "\n";
echo htmlspecialchars_decode("&lt;p&gt;Hello&lt;/p&gt;") . "\n";
echo addslashes("He said \"hello\" and it's fine") . "\n";
echo stripslashes("He said \\\"hello\\\"") . "\n";

// url encoding
echo urlencode("hello world&foo=bar") . "\n";
echo urldecode("hello+world%26foo%3Dbar") . "\n";
echo rawurlencode("hello world") . "\n";
echo rawurldecode("hello%20world") . "\n";

// base64
echo base64_encode("Hello World") . "\n";
echo base64_decode("SGVsbG8gV29ybGQ=") . "\n";

// hex
echo bin2hex("AB") . "\n";
echo hex2bin("4142") . "\n";

// hashing
echo md5("hello") . "\n";
echo sha1("hello") . "\n";

// ord/chr
echo ord("A") . "\n";
echo chr(65) . "\n";

// comparison
echo strcmp("abc", "abc") . "\n";
echo strcmp("abc", "abd") . "\n";
echo strncmp("abcdef", "abcxyz", 3) . "\n";

// wordwrap
echo wordwrap("The quick brown fox jumps over the lazy dog", 15, "\n", true) . "\n";

// nl2br
echo nl2br("line1\nline2") . "\n";

// chunk_split
echo chunk_split("abcdefgh", 3, "-") . "\n";

// parse_url
$url = parse_url("https://example.com:8080/path?query=1#frag");
echo $url['scheme'] . "\n";
echo $url['host'] . "\n";
echo $url['port'] . "\n";
echo $url['path'] . "\n";
echo $url['query'] . "\n";
echo $url['fragment'] . "\n";

// strstr
echo strstr("user@example.com", "@") . "\n";

// str_getcsv
$csv = str_getcsv("one,two,three", ",", "\"", "\\");
echo count($csv) . " " . $csv[0] . " " . $csv[2] . "\n";

// crc32
echo crc32("hello") . "\n";

echo "done\n";

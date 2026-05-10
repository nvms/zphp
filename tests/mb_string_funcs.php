<?php
echo mb_strlen("hello"), "\n";
echo mb_strlen("héllo"), "\n";
echo mb_strlen("café"), "\n";
echo mb_strlen("日本語"), "\n";
echo mb_strlen(""), "\n";
echo mb_strlen("πr²"), "\n";

echo strlen("hello"), "\n";
echo strlen("héllo"), "\n";
echo strlen("café"), "\n";

echo mb_substr("hello", 0, 3), "\n";
echo mb_substr("héllo", 0, 3), "\n";
echo mb_substr("café", 1), "\n";
echo mb_substr("café", -2), "\n";
echo mb_substr("日本語テスト", 0, 3), "\n";
echo mb_substr("日本語テスト", -2), "\n";

echo mb_strtolower("Hello WORLD"), "\n";
echo mb_strtolower("CAFÉ"), "\n";

echo mb_strtoupper("hello world"), "\n";
echo mb_strtoupper("café"), "\n";

echo mb_strpos("hello world", "world"), "\n";
echo mb_strpos("héllo wörld", "wörld"), "\n";
echo mb_strpos("café au lait", "au"), "\n";
var_dump(mb_strpos("hello", "xyz"));

echo mb_strrpos("ababab", "ab"), "\n";
echo mb_strrpos("hello world hello", "hello"), "\n";

echo mb_str_split("hello")[0], mb_str_split("hello")[4], "\n";
print_r(mb_str_split("hello"));
print_r(mb_str_split("café"));
print_r(mb_str_split("hello", 2));

echo mb_convert_case("hello world", MB_CASE_UPPER), "\n";
echo mb_convert_case("HELLO WORLD", MB_CASE_LOWER), "\n";
echo mb_convert_case("hello world", MB_CASE_TITLE), "\n";

// mb_internal_encoding
$enc = mb_internal_encoding();
echo gettype($enc), " ", $enc !== "" ? "set" : "empty", "\n";

// mb_detect_encoding (basic)
$r = mb_detect_encoding("hello");
echo gettype($r), "\n";

// mb_check_encoding
var_dump(mb_check_encoding("hello", "UTF-8"));
var_dump(mb_check_encoding("héllo", "UTF-8"));

// strlen on non-ASCII
echo strlen("π"), "\n";       // 2 bytes
echo mb_strlen("π"), "\n";     // 1 char

// str_split (byte-wise)
print_r(str_split("café"));
print_r(str_split("café", 2));

// substr (byte-wise)
echo substr("hello", 0, 3), "\n";
echo substr("café", 0, 3), "\n"; // byte slice may produce broken UTF-8

// ucfirst / lcfirst (ASCII only)
echo ucfirst("hello world"), "\n";
echo lcfirst("HELLO WORLD"), "\n";

// ucwords
echo ucwords("hello world foo bar"), "\n";
echo ucwords("hello-world-foo", "-"), "\n";

// nl2br
echo nl2br("a\nb"), "\n";
echo nl2br("x\ny\nz", false), "\n"; // <br> not <br />

// wordwrap
echo wordwrap("a long sentence with many words", 10, "\n", false), "\n";

// chunk_split
echo chunk_split("abcdefghij", 3, "-"), "\n"; // abc-def-ghi-j-

// str_repeat
echo str_repeat("ab", 3), "\n";
echo str_repeat("-", 0), "\n"; // ""

// strrev
echo strrev("hello"), "\n";

// str_word_count
echo str_word_count("Hello World"), "\n";
print_r(str_word_count("hello world foo", 1));
print_r(str_word_count("hello world foo", 2));

// quotemeta
echo quotemeta(".+*?[^]\$()"), "\n";

// htmlspecialchars / htmlentities
echo htmlspecialchars("<a>&amp;<\"'>"), "\n";
echo htmlspecialchars_decode("&lt;a&gt;&amp;amp;"), "\n";
echo htmlentities("<a>&amp;<\"'>"), "\n";
echo html_entity_decode("&amp;&lt;&gt;"), "\n";

// strip_tags
echo strip_tags("<b>bold</b> <i>italic</i> text"), "\n";
echo strip_tags("<a href='x'>link</a>", "<a>"), "\n"; // keep <a>

// addslashes
echo addslashes("hello \"world\" 'quoted'"), "\n";
echo stripslashes("hello \\\"world\\\" \\'q\\'"), "\n";

// base64
echo base64_encode("hello"), "\n";
echo base64_decode("aGVsbG8="), "\n";
echo bin2hex("abc"), "\n";
echo hex2bin("616263"), "\n";

// utf-8 decoding chain
$enc = base64_encode("café");
echo $enc, "\n";
echo base64_decode($enc), "\n";

// soundex / metaphone
echo soundex("Robert"), "\n";
echo soundex("Rupert"), "\n";
echo metaphone("Thompson"), "\n";

// similar_text
similar_text("hello", "world", $pct);
echo round($pct, 2), "\n";
echo similar_text("abc", "abd"), "\n";

// levenshtein
echo levenshtein("kitten", "sitting"), "\n";
echo levenshtein("", "abc"), "\n";
echo levenshtein("abc", "abc"), "\n";

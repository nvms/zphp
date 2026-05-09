<?php
// array_search strict
var_dump(array_search(0, ["a", "b", "c"]));         // PHP 8: false ("a" != 0 strictly)
var_dump(array_search(0, ["a", "b", "c"], true));   // false
var_dump(array_search("a", ["a", "b", "c"]));        // 0
var_dump(array_search(2, [1, 2, 3]));               // 1
var_dump(array_search("2", [1, 2, 3]));             // 1 (loose)
var_dump(array_search("2", [1, 2, 3], true));       // false
var_dump(array_search(null, [0, "", false, null])); // 3 (loose) — PHP 8 too
var_dump(array_search(null, [0, "", false, null], true)); // 3

// str_repeat
echo str_repeat("ab", 3), "\n";
echo str_repeat("x", 0), "|\n";
echo str_repeat("", 5), "|\n";
try { str_repeat("x", -1); echo "no err\n"; } catch (\ValueError $e) { echo "ve\n"; }

// substr edge
echo substr("hello", 1, -1), "\n"; // ell
echo substr("hello", 0, -3), "\n"; // he
echo substr("hello", 0, -10), "\n"; // empty
echo substr("hello", -3, -1), "\n"; // ll
echo substr("hello", -10), "\n"; // hello

// strncmp length 0
var_dump(strncmp("a", "b", 0));
var_dump(strncasecmp("X", "y", 0));

// strpos with oversize offset
try { var_dump(strpos("abc", "a", 100)); } catch (\ValueError $e) { echo "ve\n"; }
var_dump(strpos("abc", "a", 3));
var_dump(strpos("abc", "a", -1));

// mb_strpos
echo mb_strpos("héllo wörld", "wörld"), "\n";
echo mb_strpos("héllo wörld", "ö"), "\n";
echo mb_strpos("héllo wörld", "é"), "\n";
var_dump(mb_strpos("abc", "x"));

// mb_substr
echo mb_substr("héllo", 1, 2), "\n";
echo mb_substr("héllo", -2), "\n";
echo mb_substr("世界你好", 1, 2), "\n";

// ctype_space
var_dump(ctype_space("   \t\n"));
var_dump(ctype_space(" a "));
var_dump(ctype_space(""));
var_dump(ctype_space("\x0b\x0c\x0d")); // VT FF CR — all true

// heredoc escape
echo <<<EOT
line1\nliteral
tab\tliteral
EOT, "\n";

echo <<<EOT
\$dollar
\\\backslash
\nactual newline:
EOT, "|\n";

// nowdoc
echo <<<'EOT'
\n\t\$noescape
EOT, "|\n";

// preg_replace /e removed
$r = @preg_replace('/(\d+)/e', '$1*2', "abc 5 def");
var_dump($r);
echo preg_last_error(), "\n";

// var_export nested
var_export([1, ["a" => 2, "b" => [3, 4]], "x"]);
echo "\n";
var_export([10 => "a", "k" => "v", 11 => "b"]);
echo "\n";
var_export(null);
echo "\n";

// print_r return=true
$s = print_r([1,2,3], true);
echo strlen($s), "\n"; // returns string
echo strpos($s, "Array") === 0 ? "starts-Array\n" : "no\n";

$s = print_r("x", true);
echo $s, "\n";

// var_dump array has consistent indent?
ob_start();
var_dump(["a" => 1, "b" => [2, 3]]);
$out = ob_get_clean();
echo strlen($out), "\n";

// PHP emits "Array to string conversion" warning here; zphp does not (architectural gap)

// json edge: trailing comma
var_dump(json_decode('[1,2,3,]')); // PHP: returns null (not allowed)
var_dump(json_decode('{"a":1,}'));

// json_decode max_depth
$j = '[[[[[[[1]]]]]]]';
var_dump(json_decode($j, true, 3));
echo json_last_error(), "|", json_last_error_msg(), "\n";
var_dump(json_decode($j, true, 10));

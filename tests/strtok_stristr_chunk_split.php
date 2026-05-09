<?php
// substr negative/out-of-bounds
echo substr("hello", -3), "|\n"; // "llo"
echo substr("hello", -3, 2), "|\n"; // "ll"
echo substr("hello", -3, -1), "|\n"; // "ll"
echo substr("hello", 10), "|\n"; // ""
echo substr("hello", 0, 0), "|\n"; // ""
echo substr("hello", 0, 100), "|\n"; // "hello"
echo substr("hello", -100, 2), "|\n"; // "he"
echo substr("hello", 2, -10), "|\n"; // ""

// substr_count with offset and length
echo substr_count("abcabcabc", "abc"), "\n"; // 3
echo substr_count("abcabcabc", "abc", 1), "\n"; // 2
echo substr_count("abcabcabc", "abc", 0, 6), "\n"; // 2
echo substr_count("abcabcabc", "abc", 1, 5), "\n"; // 1
echo substr_count("aaa", "aa"), "\n"; // 1 - non-overlapping
try { substr_count("abc", ""); echo "no err\n"; } catch (\ValueError $e) { echo "v-empty\n"; }

// strstr/stristr/strrchr
echo strstr("hello world", "world"), "|\n";
echo strstr("hello world", "WORLD"), "|\n"; // false
var_dump(strstr("hello world", "WORLD"));
echo stristr("hello world", "WORLD"), "|\n"; // case-insens
echo strstr("hello world", "world", true), "|\n"; // before-needle
echo strstr("hello@example.com", "@"), "|\n";
echo strrchr("a/b/c/d.txt", "/"), "|\n"; // /d.txt
echo strrchr("no/separator", "x"), "|\n"; // false
var_dump(strrchr("no/separator", "x"));

// strtok
$tok = strtok("a,b;c|d", ",");
echo $tok, "\n";
$tok = strtok(";"); // continue with new sep
echo $tok, "\n";
$tok = strtok("|");
echo $tok, "\n";
$tok = strtok("|");
echo $tok === false ? "end" : "[$tok]", "\n";

// strtok new string resets
strtok("aa,bb,cc", ",");
echo strtok(","), "\n"; // bb
strtok("xx-yy-zz", "-"); // resets
echo strtok("-"), "\n"; // yy

// str_split with size <= 0
try { str_split("abc", 0); echo "no err\n"; } catch (\ValueError $e) { echo "v0\n"; }
try { str_split("abc", -1); echo "no err\n"; } catch (\ValueError $e) { echo "vneg\n"; }

// chunk_split
echo chunk_split("abcdefghij", 3, "-"), "|\n";
echo chunk_split("abc", 5, "-"), "|\n"; // shorter than chunk size
echo chunk_split("abcdef", 2), "|\n"; // default sep \r\n
echo chunk_split("", 3, "-"), "|\n";

// wordwrap edge cases
echo wordwrap("hello world", 0, "\n"), "|\n"; // wrap at 0 = each char? PHP: error or special
echo wordwrap("hello", 5, "\n"), "|\n"; // exact fit
echo wordwrap("ab", 5, "/"), "|\n"; // shorter than width

// nl2br
echo nl2br("line1\nline2\nline3"), "|\n";
echo nl2br("a\r\nb\nc\rd"), "|\n";
echo nl2br("a\nb", false), "|\n"; // not XHTML
echo nl2br("plain text"), "|\n";

// ucwords with multibyte
echo ucwords("hello world"), "\n";
echo ucwords("café résumé"), "\n"; // PHP: byte-based, doesn't capitalize multibyte

// ucfirst/lcfirst on already cased
echo ucfirst("Hello"), "\n";
echo ucfirst(""), "|\n";
echo lcfirst("hello"), "\n";
echo ucfirst("hELLO"), "\n";  // only first char changed

// addcslashes range edge cases
echo addcslashes("ABCDEF", "B..D"), "\n"; // \B\C\D
echo addcslashes("123abc", "0..9"), "\n";
echo addcslashes("hi", ""), "\n"; // empty range -> no changes
echo addcslashes("a\nb\tc", "\n\t"), "\n";


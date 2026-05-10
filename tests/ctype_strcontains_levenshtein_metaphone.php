<?php
foreach (["alpha", "Hello", "abc123", "", " ", "a", "A1", "?!"] as $s) {
    echo $s, ": ";
    echo ctype_alpha($s)?"A":"-";
    echo ctype_alnum($s)?"N":"-";
    echo ctype_digit($s)?"D":"-";
    echo ctype_upper($s)?"U":"-";
    echo ctype_lower($s)?"L":"-";
    echo ctype_space($s)?"S":"-";
    echo ctype_punct($s)?"P":"-";
    echo ctype_print($s)?"R":"-";
    echo ctype_xdigit($s)?"X":"-";
    echo ctype_cntrl($s)?"C":"-";
    echo "\n";
}

echo var_export(ctype_alpha(""), true), "\n";
echo var_export(ctype_digit(""), true), "\n";
echo var_export(ctype_space(""), true), "\n";

echo ctype_digit("0")?"y":"n", "\n";
echo ctype_digit("00000")?"y":"n", "\n";
echo ctype_digit("-1")?"y":"n", "\n";
echo ctype_digit("3.14")?"y":"n", "\n";
echo ctype_digit("1e3")?"y":"n", "\n";

echo ctype_xdigit("DEAD")?"y":"n", "\n";
echo ctype_xdigit("dead")?"y":"n", "\n";
echo ctype_xdigit("DeAd")?"y":"n", "\n";
echo ctype_xdigit("g")?"y":"n", "\n";

echo ctype_space(" \t\n\r\v")?"y":"n", "\n";
echo ctype_space(" x")?"y":"n", "\n";

echo ctype_print("Hello!")?"y":"n", "\n";
echo ctype_print("\t")?"y":"n", "\n";
echo ctype_cntrl("\t\n")?"y":"n", "\n";
echo ctype_cntrl("a")?"y":"n", "\n";

echo var_export(ctype_alpha(65), true), "\n";
echo var_export(ctype_alpha(97), true), "\n";
echo var_export(ctype_digit(48), true), "\n";

echo str_contains("hello world", "world") ? "y" : "n", "\n";
echo str_contains("hello", "") ? "y" : "n", "\n";
echo str_contains("", "") ? "y" : "n", "\n";
echo str_contains("", "x") ? "y" : "n", "\n";
echo str_contains("hello", "Hello") ? "y" : "n", "\n";
echo str_contains("hello", "h") ? "y" : "n", "\n";
echo str_contains("hello", "o") ? "y" : "n", "\n";
echo str_contains("a", "ab") ? "y" : "n", "\n";

echo str_starts_with("hello world", "hello") ? "y" : "n", "\n";
echo str_starts_with("hello", "") ? "y" : "n", "\n";
echo str_starts_with("", "") ? "y" : "n", "\n";
echo str_starts_with("hello", "Hello") ? "y" : "n", "\n";
echo str_starts_with("a", "ab") ? "y" : "n", "\n";

echo str_ends_with("hello world", "world") ? "y" : "n", "\n";
echo str_ends_with("hello", "") ? "y" : "n", "\n";
echo str_ends_with("", "") ? "y" : "n", "\n";
echo str_ends_with("hello", "World") ? "y" : "n", "\n";
echo str_ends_with("a", "ba") ? "y" : "n", "\n";

echo levenshtein("kitten", "sitting"), "\n";
echo levenshtein("hello", "hello"), "\n";
echo levenshtein("", ""), "\n";
echo levenshtein("abc", ""), "\n";
echo levenshtein("", "xyz"), "\n";
echo levenshtein("rosettacode", "raisethysword"), "\n";

echo levenshtein("kitten", "sitting", 1, 1, 1), "\n";
echo levenshtein("kitten", "sitting", 2, 1, 1), "\n";
echo levenshtein("kitten", "sitting", 1, 1, 2), "\n";

similar_text("hello", "world", $pct);
echo round($pct, 2), "\n";
similar_text("hello", "hello", $pct);
echo $pct, "\n";
similar_text("", "", $pct);
echo $pct, "\n";
similar_text("abcdef", "abcxyz", $pct);
echo round($pct, 2), "\n";
echo similar_text("hello", "world"), "\n";
echo similar_text("php", "PHP"), "\n";

echo soundex("Robert"), "\n";
echo soundex("Rupert"), "\n";
echo soundex("Rubin"), "\n";
echo soundex("Ashcraft"), "\n";
echo soundex("Tymczak"), "\n";
echo soundex(""), "\n";
echo soundex("a"), "\n";
echo soundex("ABC"), "\n";

echo metaphone("Thompson"), "\n";
echo metaphone("Fleischman"), "\n";
echo metaphone("Knight"), "\n";
echo metaphone("Phone"), "\n";
echo metaphone(""), "\n";
echo metaphone("Programming"), "\n";
echo metaphone("Hello", 4), "\n";
echo metaphone("Programming", 5), "\n";

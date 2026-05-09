<?php
// trim with .. range syntax
echo "[", trim("123abc456", "0..9"), "]\n";
echo "[", trim("aabbccDDee", "a..z"), "]\n";
echo "[", ltrim("xy09abc", "a..z"), "]\n";
echo "[", rtrim("abcXYZ", "A..Z"), "]\n";
echo "[", trim("##xx##", "#"), "]\n";
echo "[", trim("aZbcd9", "a..cZ"), "]\n";

// substr_replace with array input
print_r(substr_replace(["abc", "def", "ghi"], "X", 1, 1));
print_r(substr_replace(["abc", "def"], ["X", "Y"], 0, 1));
print_r(substr_replace(["aaaaa", "bbbbb"], "ZZ", [1, 2], [3, 1]));

// version_compare with "=" operator
var_dump(version_compare("1.0", "1.0", "="));
var_dump(version_compare("2.0", "1.0", "="));
var_dump(version_compare("1.0", "1.0", "=="));
var_dump(version_compare("1.0", "1.0", "eq"));

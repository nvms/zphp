<?php
// numeric_prefix
echo http_build_query([1, 2, 3], 'item_'), "\n";
echo http_build_query(['x' => 1, 5, 6], 'p_'), "\n";

// nested arrays
echo http_build_query(['user' => ['name' => 'alice', 'age' => 30]]), "\n";
echo http_build_query(['list' => [1, 2, 3]]), "\n";
echo http_build_query(['deep' => ['a' => ['b' => ['c' => 'x']]]]), "\n";

// PHP_QUERY_RFC3986 spaces as %20, RFC1738 as +
echo http_build_query(['a' => 'hello world'], '', '&', PHP_QUERY_RFC3986), "\n";
echo http_build_query(['a' => 'hello world'], '', '&', PHP_QUERY_RFC1738), "\n";

// custom separator
echo http_build_query(['a' => 1, 'b' => 2], '', ';'), "\n";

// null values omitted
echo "[", http_build_query(['a' => null, 'b' => 1, 'c' => null]), "]\n";

// bool values: true → 1, false → 0
echo "[", http_build_query(['t' => true, 'f' => false]), "]\n";

// htmlspecialchars double_encode parameter
echo htmlspecialchars("<b>&amp;</b>"), "\n"; // double-encodes
echo htmlspecialchars("<b>&amp;</b>", ENT_QUOTES, 'UTF-8', false), "\n"; // preserves
echo htmlspecialchars("&#039;test&#039;", ENT_QUOTES, 'UTF-8', false), "\n";
echo htmlspecialchars("&#x27;&amp;&lt;&gt;", ENT_QUOTES, 'UTF-8', false), "\n";

// unknown ampersand sequence: encoded
echo htmlspecialchars("foo & bar", ENT_QUOTES, 'UTF-8', false), "\n";

// constants exposed
echo PHP_QUERY_RFC1738, " ", PHP_QUERY_RFC3986, "\n";

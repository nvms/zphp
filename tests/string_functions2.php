<?php
echo strcmp("abc", "abc");
echo "\n";
echo strcmp("abc", "def") < 0 ? "neg" : "pos";
echo "\n";
echo strcmp("def", "abc") > 0 ? "pos" : "neg";
echo "\n";

echo ord("A");
echo "\n";
echo chr(65);
echo "\n";

echo substr_count("hello world hello", "hello");
echo "\n";

echo str_word_count("Hello beautiful world");
echo "\n";

echo nl2br("line1\nline2");
echo "\n";

echo addslashes("He said \"hi\" and it's fine");
echo "\n";
echo stripslashes("He said \\\"hi\\\"");
echo "\n";

echo htmlspecialchars("<p>Hello & 'world'</p>");
echo "\n";
echo htmlspecialchars_decode("&lt;p&gt;Hello&lt;/p&gt;");
echo "\n";

echo bin2hex("AB");
echo "\n";
echo hex2bin("4142");
echo "\n";

echo number_format(1234567.891, 2);
echo "\n";
echo number_format(1234.5, 2, ',', '.');
echo "\n";

$parts = str_split("Hello", 2);
echo implode('|', $parts);
echo "\n";

echo substr_replace("hello world", "PHP", 6, 5);
echo "\n";

echo chunk_split("abcdef", 2, "-");
echo "\n";

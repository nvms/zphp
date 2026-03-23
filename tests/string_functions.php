<?php
echo substr('Hello World', 6);
echo "\n";
echo substr('Hello World', 0, 5);
echo "\n";
echo substr('Hello', -3);
echo "\n";

echo strpos('Hello World', 'World');
echo "\n";
echo strpos('abcabc', 'bc', 3);
echo "\n";

echo str_replace('World', 'PHP', 'Hello World');
echo "\n";
echo str_replace('o', '0', 'foo bar boo');
echo "\n";

echo strtolower('Hello World');
echo "\n";
echo strtoupper('Hello World');
echo "\n";

echo trim('  hello  ');
echo "\n";
echo ltrim('  hello  ');
echo "\n";
echo rtrim('  hello  ');
echo "\n";

echo str_contains('Hello World', 'World') ? 'true' : 'false';
echo "\n";
echo str_contains('Hello World', 'xyz') ? 'true' : 'false';
echo "\n";

echo str_starts_with('Hello World', 'Hello') ? 'true' : 'false';
echo "\n";
echo str_ends_with('Hello World', 'World') ? 'true' : 'false';
echo "\n";

echo str_repeat('ab', 3);
echo "\n";
echo ucfirst('hello');
echo "\n";
echo lcfirst('Hello');
echo "\n";

echo str_pad('42', 5, '0', 0);
echo "\n";
echo str_pad('hi', 10, '-');
echo "\n";

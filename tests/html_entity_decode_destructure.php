<?php
// html_entity_decode with named Latin-1 entities
echo html_entity_decode("caf&eacute;"), "\n";
echo html_entity_decode("&pound;100"), "\n";
echo html_entity_decode("&copy; 2024"), "\n";
echo html_entity_decode("&Auml;rger"), "\n";
echo html_entity_decode("r&eacute;sum&eacute;"), "\n";
echo html_entity_decode("&Aring;ngstr&ouml;m"), "\n";

// HTML special chars still decoded
echo html_entity_decode("&lt;b&gt;hello&lt;/b&gt;"), "\n";
echo html_entity_decode("&amp;lt;"), "\n";

// numeric entities
echo html_entity_decode("&#233;"), "\n";
echo html_entity_decode("&#xE9;"), "\n";

// unknown entity passes through
echo html_entity_decode("&unknown;"), "\n";

// htmlspecialchars_decode does NOT handle Latin-1 named
echo htmlspecialchars_decode("&lt;b&gt;"), "\n";
echo htmlspecialchars_decode("caf&eacute;"), "\n";  // unchanged

// list / destructuring basics
[$a, $b, $c] = [1, 2, 3];
echo "$a $b $c\n";

// nested
[[$a, $b], $c] = [[1, 2], 3];
echo "$a $b $c\n";

// associative
['name' => $n, 'age' => $g] = ['name' => 'alice', 'age' => 30];
echo "$n $g\n";

// nested associative
['user' => ['name' => $n, 'age' => $g]] = ['user' => ['name' => 'bob', 'age' => 25]];
echo "$n $g\n";

// skipped slots
[, $b, , $d] = [1, 2, 3, 4];
echo "$b $d\n";

// foreach with destructuring
$rows = [['x' => 1, 'y' => 2], ['x' => 3, 'y' => 4]];
foreach ($rows as ['x' => $x, 'y' => $y]) echo "$x,$y ";
echo "\n";

// nested in foreach
foreach ([[1, 'one'], [2, 'two'], [3, 'three']] as [$n, $w]) echo "$n:$w ";
echo "\n";

// list( ... ) syntax
list($a, $b) = [10, 20];
echo "$a $b\n";

// ArrayObject ArrayAccess
$ao = new ArrayObject(['a' => 1, 'b' => 2]);
echo $ao['a'], "\n";
$ao['c'] = 3;
echo isset($ao['c']) ? "set\n" : "miss\n";
unset($ao['a']);
echo isset($ao['a']) ? "still\n" : "gone\n";

// asort/ksort
$ao = new ArrayObject([3, 1, 2]);
$ao->asort();
print_r($ao->getArrayCopy());

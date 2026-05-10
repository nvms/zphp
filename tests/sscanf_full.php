<?php
print_r(sscanf("42", "%d"));
print_r(sscanf("hello", "%s"));
print_r(sscanf("3.14", "%f"));

print_r(sscanf("name=alice age=30", "name=%s age=%d"));

print_r(sscanf("2025-01-15", "%d-%d-%d"));

print_r(sscanf("0xff", "%x"));
print_r(sscanf("777", "%o"));
print_r(sscanf("11", "%d"));
try { sscanf("1010", "%b"); echo "no\n"; } catch (\ValueError $e) { echo "ve-b\n"; }

print_r(sscanf("12 34 56 78", "%d %d %d %d"));

print_r(sscanf("foo bar baz", "%s %s %s"));

print_r(sscanf("abc", "%c%c%c"));

print_r(sscanf("hello world", "%5s"));
print_r(sscanf("12345", "%3d"));
print_r(sscanf("3.14159", "%5f"));

$count = sscanf("alice 30 1.85", "%s %d %f", $name, $age, $h);
echo "n=$count name=$name age=$age h=$h\n";

$count = sscanf("only-name", "%s %d", $name, $age);
echo "n=$count name=$name age=", $age ?? "null", "\n";

print_r(sscanf("abc 123", "%s %d %f"));

print_r(sscanf("abc def", "%d %d"));
print_r(sscanf("123 456", "%d %d"));

print_r(sscanf("alice30", "%[a-z]%d"));
print_r(sscanf("HELLO", "%[A-Z]"));
print_r(sscanf("foo123bar", "%[^0-9]%d%s"));

print_r(sscanf("abc1def", "%[abc]%d%[def]"));

print_r(sscanf("hello", "h%[a-z]"));

print_r(sscanf("first second third", "%s %s %s"));

print_r(sscanf("12+34", "%d+%d"));
print_r(sscanf("1*2*3", "%d*%d*%d"));

print_r(sscanf("ABC123XYZ", "%[A-Z]%d%[A-Z]"));

print_r(sscanf("100%50", "%d%%%d"));

$r = sscanf("123abc", "%d");
print_r($r);

$r = sscanf("abc123", "%d");
print_r($r);

// references
$count = sscanf("price=42.50", "price=%f", $price);
echo "n=$count price=$price\n";

$count = sscanf("1,2,3,4,5", "%d,%d,%d,%d,%d", $a, $b, $c, $d, $e);
echo "n=$count a=$a b=$b c=$c d=$d e=$e\n";

// fewer args
$count = sscanf("1 2 3", "%d %d %d %d", $a, $b, $c, $d);
echo "n=$count d=", $d ?? "null", "\n";

print_r(sscanf("1.5e3", "%e"));

print_r(sscanf("FF", "%x"));
print_r(sscanf("ff", "%x"));

print_r(sscanf("---hello---", "---%[^-]---"));

print_r(sscanf("aaa", "%[a]"));

print_r(sscanf("CSV,parse,test", "%[^,],%[^,],%[^,]"));

print_r(sscanf("Hello, World!", "%5s"));
print_r(sscanf("Hello, World!", "%[^,]"));

$kv = sscanf("name=alice", "%[a-z]=%[a-z]");
print_r($kv);

print_r(sscanf("12 34", "%d %d %d"));
print_r(sscanf("12", "%d %d %d"));
print_r(sscanf("", "%d"));

$r = sscanf("3.14", "%f", $f);
echo "n=$r f=$f\n";

$r = sscanf("abc", "%d", $n);
echo "n=$r v=", $n ?? "null", "\n";

// returns int when given references
$r = sscanf("1 2 3", "%d %d %d", $a, $b, $c);
echo gettype($r), "\n";
echo $a, " ", $b, " ", $c, "\n";

print_r(sscanf("name:alice age:30", "name:%s age:%d"));

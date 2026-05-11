<?php
print_r(sscanf("hello 42", "%s %d"));
print_r(sscanf("3.14", "%f"));
print_r(sscanf("0xff", "%x"));
print_r(sscanf("777", "%o"));

$x = 0; $y = 0;
$n = sscanf("hello 42", "%s %d", $x, $y);
echo "n=$n x=$x y=$y\n";

$a = ""; $b = 0; $c = 0.0;
sscanf("foo 42 3.14", "%s %d %f", $a, $b, $c);
echo "a=$a b=$b c=$c\n";

print_r(sscanf("only-string", "%s"));
print_r(sscanf("42 extra", "%d"));

print_r(sscanf("name=alice", "%[^=]=%s"));
print_r(sscanf("abc123def", "%[a-z]%d%[a-z]"));

print_r(sscanf("hello", "%2s"));
print_r(sscanf("12345", "%3d"));

print_r(sscanf("a b", "%c %c"));
print_r(sscanf("hi", "%c"));

print_r(sscanf("3.14e2", "%f"));
print_r(sscanf("-3.14", "%f"));
print_r(sscanf("+42", "%d"));

print_r(sscanf("hello world", "%s %s"));
print_r(sscanf("a:b:c", "%[^:]:%[^:]:%[^:]"));
print_r(sscanf("1, 2, 3", "%d, %d, %d"));

echo function_exists("sscanf") ? "y" : "n", "\n";
echo function_exists("fscanf") ? "y" : "n", "\n";

$tmp = tempnam(sys_get_temp_dir(), "ss_");
file_put_contents($tmp, "first 1\nsecond 2\n");
$f = fopen($tmp, "r");
print_r(fscanf($f, "%s %d"));
print_r(fscanf($f, "%s %d"));
fclose($f);
unlink($tmp);

print_r(sscanf("  42", "%d"));
print_r(sscanf("42abc", "%d"));
print_r(sscanf("abc", "%d"));

print_r(sscanf("a1b2c3", "%c%d%c%d%c%d"));

$r = sscanf("42 hello", "%d %s");
print_r($r);
echo count($r), "\n";

print_r(sscanf("0", "%d"));
print_r(sscanf("-0", "%d"));
print_r(sscanf("0.0", "%f"));
print_r(sscanf("3.14 2.71", "%f %f"));

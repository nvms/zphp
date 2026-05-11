<?php
echo implode(",", [1,2,3]), "\n";
echo implode("-", ["a","b","c"]), "\n";
echo implode("", ["x","y","z"]), "\n";
echo implode(",", []), "\n";
echo implode(",", ["only"]), "\n";

echo implode(",", ["a"=>1, "b"=>2, "c"=>3]), "\n";
echo implode("|", ["k1"=>"v1", "k2"=>"v2"]), "\n";

echo implode(",", [1, "two", 3.14, true, false, null]), "\n";

echo join(":", ["a", "b", "c"]), "\n";

print_r(explode(",", "a,b,c"));
print_r(explode(",", "a,b,c,d,e", 3));
print_r(explode(",", "a,b,c,d,e", -2));
print_r(explode(",", "a,b,c,d,e", 0));
print_r(explode(",", ""));
print_r(explode(",", "no-comma"));
print_r(explode(",", "a,b", 1));
print_r(explode(",", "a,b,c", -1));
print_r(explode(",", "a,b,c", -5));
print_r(explode("-", "a-b-c-d", 2));

print_r(explode(",,", "a,,b,,c"));
print_r(explode("xx", "axxbxxc"));

print_r(explode(",", "a,b,c,d,e", 10));
print_r(explode(",", "a,b,c,d,e", -10));

print_r(str_split("hello"));
print_r(str_split("hello", 2));
print_r(str_split("hello", 5));
print_r(str_split("hello", 100));
print_r(str_split(""));
print_r(str_split("héllo"));
print_r(str_split("日本", 1));

echo strlen("héllo"), "\n";
echo strlen("é"), "\n";

print_r(str_split("ab", 1));
try { str_split("abc", 0); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

try {
    str_split("test", -1);
    echo "no\n";
} catch (\ValueError $e) {
    echo "ve\n";
}

echo implode("\n", explode("\n", "line1\nline2\nline3")), "\n";

$result = explode(",", "a,b,c,d");
echo count($result), "\n";

$joined = implode("+", explode(",", "1,2,3,4,5"));
echo $joined, "\n";

$arr = ["hello", " ", "world"];
echo implode("", $arr), "\n";

echo implode("--", ["a", "", "b", "", "c"]), "\n";

print_r(explode(",", ",a,b,"));
print_r(explode(" ", "hello world", 1));



class Stringy {
    public function __toString(): string { return "S"; }
}
$obj = new Stringy;
echo implode(",", ["a", $obj, "b"]), "\n";

print_r(str_split("a"));
print_r(str_split("ab", 1));

echo implode(",", str_split("hello", 1)), "\n";

print_r(preg_split("//", "abc", -1, PREG_SPLIT_NO_EMPTY));

$big = str_repeat("x", 100);
print_r(str_split($big, 25));

$big = str_repeat("y", 50);
echo count(str_split($big, 5)), "\n";

$big = str_repeat("z", 100);
echo strlen(implode("|", str_split($big, 10))), "\n";

print_r(explode(",", "abc"));
try { explode("", "abc"); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

print_r(str_split("hello world", 3));
print_r(str_split("hello world", 6));
print_r(str_split("hello world", 11));

echo implode("/", explode("/", "a/b/c")), "\n";

$keys = ["k1", "k2", "k3"];
$vals = ["v1", "v2", "v3"];
$pairs = array_map(fn($k, $v) => "$k=$v", $keys, $vals);
echo implode("&", $pairs), "\n";

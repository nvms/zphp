<?php
// array_combine error - PHP 8.x ValueError on length mismatch
try { array_combine([1,2], [1,2,3]); echo "no err\n"; } catch (\ValueError $e) { echo "ve:", $e->getMessage(), "\n"; }
try { array_combine([], []); var_dump(array_combine([], [])); } catch (\Throwable $e) { echo "err\n"; }

// array_diff: returns original (re-keyed? no, preserves keys) when all unique
print_r(array_diff([1,2,3], [4,5,6]));
print_r(array_diff(["a"=>1,"b"=>2], [9,8])); // keeps string keys
print_r(array_diff([1,2,3,2,1], [2])); // 0=>1, 3=>3 (no key 1, no 4, no 2)

// array_intersect multiple arrays
print_r(array_intersect([1,2,3,4], [2,3,4,5], [3,4,5,6]));
print_r(array_intersect(["a"=>1,"b"=>2,"c"=>3], ["x"=>1,"y"=>2]));

// str_replace count by-ref
$count = 0;
$r = str_replace("a", "X", "banana", $count);
echo "$r|$count\n"; // bXnXnX|3
$r = str_replace(["a","n"], "_", "banana", $count);
echo "$r|$count\n";

// ctype_punct
var_dump(ctype_punct("!?.,;"));
var_dump(ctype_punct("abc"));
var_dump(ctype_punct("123"));
var_dump(ctype_punct(" !"));
var_dump(ctype_punct(""));
var_dump(ctype_punct("()[]"));

// htmlspecialchars chained
$s = "<a href='x' & \"y\">";
$enc = htmlspecialchars($s);
echo $enc, "\n";
$dec = htmlspecialchars_decode($enc);
echo ($dec === $s ? "round-trip\n" : "diff:$dec\n");

// http_build_query with Stringable
class S { public function __construct(public string $v) {} public function __toString(): string { return $this->v; } }
echo http_build_query(["a" => new S("hi"), "b" => [new S("x"), new S("y")]]), "\n";

// uasort stable-ish
$a = ["x"=>1,"y"=>1,"z"=>1,"a"=>0];
uasort($a, fn($l,$r) => $l <=> $r);
foreach ($a as $k=>$v) echo "$k=>$v ";
echo "\n";

// ArrayObject offsetSet
$ao = new ArrayObject(["a"=>1]);
$ao["b"] = 2;
$ao[] = 99;
var_dump($ao->getArrayCopy());
echo $ao->count(), "\n";
echo isset($ao["a"]) ? "has-a\n" : "no\n";
unset($ao["a"]);
echo isset($ao["a"]) ? "has-a\n" : "no\n";

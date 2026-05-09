<?php
// preg_match PREG_OFFSET_CAPTURE
preg_match('/world/', 'hello world hi', $m, PREG_OFFSET_CAPTURE);
print_r($m);

preg_match('/(\w+)\s+(\w+)/', 'hello world', $m, PREG_OFFSET_CAPTURE);
print_r($m);

// preg_match_all with PREG_OFFSET_CAPTURE
preg_match_all('/\d+/', 'a1 b22 c333', $m, PREG_OFFSET_CAPTURE);
print_r($m);

preg_match_all('/(\w+)=(\d+)/', 'a=1 b=22 c=333', $m, PREG_PATTERN_ORDER | PREG_OFFSET_CAPTURE);
print_r($m);

preg_match_all('/(\w+)=(\d+)/', 'a=1 b=22 c=333', $m, PREG_SET_ORDER | PREG_OFFSET_CAPTURE);
print_r($m);

// preg_match with named groups + offset
preg_match('/(?<word>\w+)\s+(?<num>\d+)/', 'hello 42', $m, PREG_OFFSET_CAPTURE);
print_r($m);

// preg_replace_callback with count by-ref (no PREG_OFFSET_CAPTURE - separate feature)
$out = preg_replace_callback(
    '/\d+/',
    fn($m) => "[" . $m[0] . "]",
    'a1 b22 c333',
    -1, $count
);
echo $out, " count=$count\n";

// regex backreferences in replacement
echo preg_replace('/(\w+) (\w+)/', '$2 $1', 'hello world'), "\n";
echo preg_replace('/(\w+) (\w+)/', '\2 \1', 'hello world'), "\n";
echo preg_replace('/(\w+) (\w+)/', '${2}-${1}', 'hello world'), "\n";
echo preg_replace('/\$(\d+)/', '[\1]', '$1 $99 $0'), "\n";

// preg_replace with named backreferences via numbered slots (PHP doesn't expand ${name})
echo preg_replace('/(?<adj>\w+) (?<noun>\w+)/', '$2 $1', 'big tree'), "\n";

// sprintf with object lacking __toString
class NoStr { public int $v = 1; }
try { echo sprintf("%s", new NoStr); } catch (\Error $e) { echo "err\n"; }
class HasStr { public function __toString(): string { return "yes"; } }
echo sprintf("%s", new HasStr), "\n";

// fopen with invalid mode
$f = @fopen("/tmp/zphp_test.dat", "qq");
var_dump($f); // false with warning

// realpath
echo realpath("/tmp"), "\n"; // /private/tmp on macOS, /tmp on linux
var_dump(realpath("/nonexistent_xyz_zzz"));
file_put_contents("/tmp/zphp_test.dat", "x");
echo realpath("/tmp/zphp_test.dat") !== false ? "real\n" : "false\n";
unlink("/tmp/zphp_test.dat");

// levenshtein with costs
echo levenshtein("kitten", "sitting"), "\n";
echo levenshtein("kitten", "sitting", 1, 1, 1), "\n";
echo levenshtein("kitten", "sitting", 2, 1, 1), "\n"; // higher ins cost
echo levenshtein("abc", "abxc", 5, 1, 1), "\n"; // 1 insert at cost 5
echo levenshtein("abc", "axc", 1, 5, 1), "\n"; // 1 replace at cost 5
echo levenshtein("abc", "ac", 1, 1, 5), "\n"; // 1 delete at cost 5
echo levenshtein("", ""), "\n";
echo levenshtein("a", ""), "\n";

// str_word_count format=2 with custom chars
print_r(str_word_count("hello-world is.cool", 2));
print_r(str_word_count("don't can't won't", 2));

// array_intersect reset_keys behavior
$a = [1 => "a", 5 => "b", 10 => "c"];
$b = ["a", "c"];
print_r(array_intersect($a, $b)); // PHP: keys preserved {1=>a, 10=>c}

// array_diff reset
$a = [10 => 1, 20 => 2, 30 => 3];
$b = [2];
print_r(array_diff($a, $b));

// array_keys preserving order
$a = ["c" => 3, "a" => 1, "b" => 2];
print_r(array_keys($a));

// array_merge over keyed arrays
$a = ["x" => 1, "y" => 2];
$b = ["y" => 99, "z" => 3];
print_r(array_merge($a, $b));
$a = [1, 2, 3];
$b = [4, 5];
print_r(array_merge($a, $b));

<?php
preg_match('/(?<name>\w+)/', "hello world", $m);
print_r($m);

preg_match('/(?<first>\w+) (?<second>\w+)/', "hello world", $m);
print_r($m);

preg_match('/(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/', "2025-06-15", $m);
print_r($m);
echo $m["year"], "-", $m["month"], "-", $m["day"], "\n";

preg_match_all('/(\w+)/', "one two three", $matches);
print_r($matches);

preg_match_all('/(\w+)/', "one two three", $matches, PREG_SET_ORDER);
print_r($matches);

preg_match_all('/(\w+)/', "one two three", $matches, PREG_OFFSET_CAPTURE);
print_r($matches);

preg_match_all('/(\w+)/', "one two three", $matches, PREG_SET_ORDER | PREG_OFFSET_CAPTURE);
print_r($matches);

preg_match_all('/(?<n>\d+)/', "a1 b22 c333", $m, PREG_SET_ORDER);
print_r($m);

echo preg_replace('/(\w+)@(\w+)/', '$1-AT-$2', "alice@example"), "\n";
echo preg_replace('/(\w+) (\w+)/', '$2 $1', "hello world"), "\n";
echo preg_replace('/(\d+)/', '[$1]', "a1 b22 c333"), "\n";
echo preg_replace('/(\w+)/', '${1}!', "hello"), "\n";
echo preg_replace('/(?<word>\w+)/', '${word}!', "hello"), "\n";

echo preg_replace('/(\w+)\.(\w+)/', '$2.$1', "first.second"), "\n";

echo preg_replace('/[aeiou]/i', '*', "Hello World"), "\n";

print_r(preg_replace(['/a/', '/b/'], ['X', 'Y'], "abc"));

print_r(preg_replace('/\d/', '*', ["abc1", "def2"]));

echo preg_replace('/\\\\/', '/', "a\\b\\c"), "\n";

echo preg_match('/(?P<digit>\d+)/', "abc123def", $m) ? "match" : "nope", "\n";
echo $m[0], " ", $m["digit"], " ", $m[1], "\n";

echo preg_match('/((a)(b))/', "ab", $m), "\n";
echo $m[0], " ", $m[1], " ", $m[2], " ", $m[3], "\n";

echo preg_match('/(a)?(b)?(c)/', "ac", $m), "\n";
print_r($m);

preg_match_all('/(?<year>\d{4})-(?<month>\d{2})/', "2025-01 2025-02 2026-03", $m, PREG_SET_ORDER);
foreach ($m as $match) echo $match["year"], "/", $match["month"], "\n";

preg_match_all('/(\d+)/', "a 100 b 200 c 300", $matches, PREG_OFFSET_CAPTURE);
foreach ($matches[1] as $cap) echo $cap[0], "@", $cap[1], "\n";

echo preg_replace('/^/', "> ", "line1\nline2"), "\n";

echo preg_replace('/(\w+)/', '\\0!', "hi"), "\n";
echo preg_replace('/(\w+)/', '\1!', "hi"), "\n";
echo preg_replace('/(\w+)/', '\\\\1!', "hi"), "\n";

echo preg_replace('/(\d+)/', '<$1>', "abc 100 def 200"), "\n";

class WithName {
    public function name(): string { return "WithName"; }
}

echo preg_replace('/(?<= )(\w+)(?= )/', '[$1]', "the quick brown fox"), "\n";

preg_match('/(?<=^)(\w+)/', "alpha beta", $m);
print_r($m);

preg_match('/abc(?!def)/', "abcxyz abcdef", $m);
echo isset($m[0]) ? $m[0] : "none", "\n";

preg_match('/abc(?=xyz)/', "abcxyz abcdef", $m);
echo $m[0], "\n";

preg_match('/^(\d+)/', "abc", $m);
echo isset($m[0]) ? "y" : "n", "\n";

echo preg_replace_callback('/(\w+)/', fn($m) => strtoupper($m[0]), "hello world"), "\n";

echo preg_replace_callback('/(\w+) (\w+)/', fn($m) => $m[2] . " " . $m[1], "hello world"), "\n";

preg_match_all('/<(\w+)>/', "<a><b><c>", $m);
print_r($m);

preg_match_all('/<(\w+)>/', "<a><b><c>", $m, PREG_SET_ORDER);
foreach ($m as $g) echo $g[1], " ";
echo "\n";

echo preg_replace_callback('/\d+/', function ($m) {
    return $m[0] * 2;
}, "1 2 3 4 5"), "\n";

echo preg_replace('/cat|dog|fish/', 'PET', "I have a cat and a dog and a fish"), "\n";

echo preg_replace('/[aeiou]/', '', "hello world"), "\n";

echo preg_replace('/(.)\1/', '$1', "aabbccdd"), "\n";

preg_match('/(?J)(?<n>\d+)|(?<n>\w+)/', "hello", $m);
echo isset($m["n"]) ? $m["n"] : "?", "\n";

preg_match('/(\w+)/', "", $m);
echo isset($m[0]) ? "y" : "n", "\n";

preg_match('/\d+/u', "héllo 42 wörld", $m);
echo $m[0], "\n";

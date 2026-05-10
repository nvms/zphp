<?php
print_r(explode(",", "a,b,c"));
print_r(explode(",", "a,b,c", 2));
print_r(explode(",", "a,b,c", -1));
print_r(explode(",", ""));
print_r(explode(",", "no-comma"));
print_r(explode("+", "a++b+c+"));

print_r(explode(", ", "a, b, c"));
print_r(explode(",,", "a,,b,,c"));
print_r(explode(":", "x:y:z", 0));

print_r(preg_split('/[\s,;]+/', "a, b ; c, d ;e"));
print_r(preg_split('/\s+/', "  hello   world  "));
print_r(preg_split('/[\.,]/', "a.b,c.d,e"));

print_r(preg_split('/[\s,]+/', "a, b ,c , d"));

print_r(preg_split('/,/', "a,,b,,c", -1, PREG_SPLIT_NO_EMPTY));

print_r(preg_split('/,/', "a,b,c,d", 2));

print_r(preg_split('//', "abc"));
print_r(preg_split('//', "abc", -1, PREG_SPLIT_NO_EMPTY));

echo str_word_count("Hello World Foo Bar"), "\n";
echo str_word_count(""), "\n";
echo str_word_count("hello-world"), "\n";

print_r(str_word_count("foo bar baz", 1));
print_r(str_word_count("foo bar baz", 2));

$tok = strtok("hello world foo bar", " ");
$tokens = [];
while ($tok !== false) {
    $tokens[] = $tok;
    $tok = strtok(" ");
}
print_r($tokens);

$str = "/path/to/file.ext";
$parts = [];
$t = strtok($str, "/.");
while ($t !== false) {
    $parts[] = $t;
    $t = strtok("/.");
}
print_r($parts);

$str = "a,,b,,,c";
$tokens = [];
$t = strtok($str, ",");
while ($t !== false) {
    $tokens[] = $t;
    $t = strtok(",");
}
print_r($tokens);

$str = "x:y";
$first = strtok($str, ":");
echo "first=$first\n";
$rest = strtok(":");
echo "rest=$rest\n";
$next = strtok(":");
var_dump($next);

echo strtok("first second", " "), "\n";
echo strtok(" "), "\n";
echo strtok("new sentence", " "), "\n";
echo strtok(" "), "\n";

print_r(explode(" ", trim("   hello world  ")));
print_r(preg_split('/\s+/', trim("   hello world  ")));

$csv = "name,age,city";
$tokens = explode(",", $csv);
print_r($tokens);

$tokens = explode(",", "");
print_r($tokens); // [""]
$tokens = explode(",", ",");
print_r($tokens); // ["", ""]

print_r(preg_split('/(\s+)/', "a b c", -1, PREG_SPLIT_DELIM_CAPTURE));
print_r(preg_split('/(\s+)/', "a b c", -1, PREG_SPLIT_DELIM_CAPTURE | PREG_SPLIT_NO_EMPTY));

echo str_word_count("hello-world", 0, "-"), "\n"; // 1 (with - as additional char)

$str = "1+2-3*4/5";
$ts = [];
$t = strtok($str, "+-*/");
while ($t !== false) {
    $ts[] = $t;
    $t = strtok("+-*/");
}
print_r($ts);

$first = strtok("foo;bar;baz", ";");
echo $first, "\n";
echo strtok(";"), "\n";
echo strtok(";"), "\n";

$bad = strtok(";");
var_dump($bad);

print_r(explode("|", "a|b|c|d|e", 3));
print_r(explode("|", "a|b|c|d|e", -2));
print_r(explode("|", "a|b|c|d|e", -10));

print_r(preg_split('/[!?]/', "Hello! How are you? Fine."));

echo str_word_count("Hello World", 0), "\n";

// explode with empty separator throws
try { explode("", "abc"); echo "no\n"; }
catch (\ValueError $e) { echo "ve-empty-sep\n"; }

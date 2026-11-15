<?php
// "\{" is text: its brace can't start "{$...}", and a "$" after it is a simple
// variable

$abc = "bar";
$arr = ['k' => 'v'];
echo "foo\{$abc}baz\n";
echo "foo\{ $abc}baz\n";
echo "foo\\{$abc}baz\n";
echo "x\{$arr[k]}y\n";
echo "\{\$abc}\n";
echo <<<TEST
foo{$abc}baz
foo\{$abc}baz
foo\{ $abc}baz
TEST;
echo "\n";
foreach (["$     \{    ", "      \{   $", "      \{$   ", "      $\{   ", "      \{\$  "] as $v) {
    echo "'$v'\n";
}

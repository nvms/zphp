<?php
// "$a[...]" takes a name, a number or a variable as its offset: a quoted
// key there is php's parse error

$arr = ['foo' => 'bar', 3 => 'three', 'k' => 'kay'];
$k = 'k';
$codes = [
    'echo "$arr[\'foo\']\n";',
    "echo <<<EOT\n\$arr['foo']\nEOT;\n",
    'echo "$arr[foo] $arr[3] $arr[$k] {$arr[\'foo\']} ${arr}[x]\n";',
    "echo <<<'EOT'\n\$arr['foo']\nEOT;\necho \"\\n\";",
    'echo \'$arr[\\\'foo\\\']\', "\n";',
    'echo "\$arr[\'foo\']\n";',
];
foreach ($codes as $code) {
    try {
        eval($code);
    } catch (ParseError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

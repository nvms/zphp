<?php
// php's parser words every syntax error: the token it stopped at, named by its
// kind and text, and the tokens it expected when there are at most four

$snippets = [
    '$x = 5 6;',
    '$x = "abc" "def";',
    "\$x = 'abc' 'def';",
    '$x = 1.5 2;',
    '$x = $a $b;',
    'echo Foo\Bar Baz;',
    'echo \Foo 1;',
    'echo namespace\Foo 1;',
    'function () {}',
    'class {}',
    '$x = "a $b" 1;',
    'echo 99999999999999999999 1;',
    'echo 1 (int) $x;',
    "if (\$x) {\n echo 1;\n",
    'echo __CLASS__ __LINE__;',
    'echo 1 ?> <?php echo 2;',
    'foo(1 2);',
    '$a = [1 2];',
    'function f($a $b) {}',
    'echo 1 die;',
    "\$x = <<<EOT\nabc\nEOT 5;",
    'echo 1 FUNCTION;',
    'echo 1 <> 2 3;',
    '$x = "abcdefghijklmnopqrstuvwxyzabcdefghijklmn" 1;',
    'echo `ls` 1;',
    '$x++ ++;',
    'class A { public function }',
    'class A { function f() { } public }',
    '$x = fn($a) => ;',
    'match($x) { 1 => 2 3 };',
    'foreach ($a as) {}',
    'for ($i = 0; $i < 3 $i++) {}',
    'while (1 {}',
    '$a = (1];',
    "\$a = (1,\n2];",
    '}',
    'echo 1 #[A] 1;',
    'echo 1 & 2 &$x 3;',
    'echo 1 \ 2;',
    "echo 1 \x01;",
    '$x = $y ?-> ;',
    '$x = 1 ?? ;',
    'echo "unterminated',
];

foreach ($snippets as $code) {
    try {
        eval($code);
        echo "no error\n";
    } catch (ParseError $e) {
        echo $e->getLine(), ': ', $e->getMessage(), "\n";
    }
}

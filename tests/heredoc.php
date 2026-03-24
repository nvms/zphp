<?php

// basic heredoc
$x = <<<EOT
Hello World
EOT;
echo $x . "\n";

// heredoc with variable interpolation
$name = "Alice";
$greeting = <<<EOT
Hello $name
EOT;
echo $greeting . "\n";

// heredoc with curly interpolation
$item = "widget";
echo <<<EOT
Item: {$item}
EOT;
echo "\n";

// nowdoc - no interpolation
$y = <<<'EOT'
Hello $name
EOT;
echo $y . "\n";

// heredoc with escape sequences
$esc = <<<EOT
tab:\there\nnewline above
EOT;
echo $esc . "\n";

// nowdoc preserves escapes literally
$raw = <<<'EOT'
tab:\there\nnewline
EOT;
echo $raw . "\n";

// heredoc in function argument
echo strlen(<<<EOT
abcdef
EOT) . "\n";

// heredoc with multiple variables
$a = "foo";
$b = "bar";
$multi = <<<EOT
$a and $b
EOT;
echo $multi . "\n";

// indented closing marker (PHP 7.3+)
$indented = <<<EOT
    line one
    line two
    EOT;
echo $indented . "\n";

// indented heredoc with interpolation
$who = "world";
$indented2 = <<<EOT
    hello $who
    goodbye $who
    EOT;
echo $indented2 . "\n";

// empty heredoc
$empty = <<<EOT
EOT;
echo "empty:" . $empty . ":\n";

// heredoc as array value
$arr = [
    'key' => <<<EOT
    value here
    EOT,
];
echo $arr['key'] . "\n";

// nowdoc with dollar signs preserved
$nd = <<<'END'
Price: $100
Variable: $undefined
END;
echo $nd . "\n";

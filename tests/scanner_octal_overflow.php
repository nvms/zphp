<?php
// the scanner's warning for an octal escape past \377, at the escape's own
// line; the value keeps its low byte

echo bin2hex("\141\542\143\777\400\1234\0\08"), "\n";
$v = 'x';
echo bin2hex("$v\477{$v}"), "\n";
echo bin2hex(<<<EOT
\600 $v
EOT), "\n";
echo bin2hex('\542'), "\n";
echo bin2hex("a
\400"), "\n";
eval('echo bin2hex("\\\\542 \\542"), "\n";');

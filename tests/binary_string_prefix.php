<?php
// the b prefix on a string literal is accepted and changes nothing
$x = 5;
var_dump(b"double $x", B'single', b<<<EOT
heredoc $x
EOT, b<<<'NOW'
nowdoc $x
NOW);
var_dump(b"" === "", strlen(b"\x00\x01"));

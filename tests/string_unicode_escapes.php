<?php
// \u{...} in double-quoted strings: any code point up to U+10FFFF is encoded,
// surrogates included; a \u without a brace stays as written; anything else
// between the braces is php's parse error
var_dump(bin2hex("\u{41}\u{00e9}\u{20AC}\u{1F602}\u{0000000041}"));
var_dump(bin2hex("\u{D801}\u{DC00}"), "‮", "\\u{41}", 'single \u{41}');
$cases = ['"\u{}"', '"\u{blah"', '"\u{110000}"', '"\u{+1F602}"', '"\u{-1F602}"', '"\u{1F602 }"', '"\u{10FFFF}"'];
foreach ($cases as $literal) {
    echo $literal, "\n";
    $command = escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 -r ' . escapeshellarg("var_dump(bin2hex($literal));");
    echo trim(shell_exec($command)), "\n";
}

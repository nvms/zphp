<?php
// covers: heredoc, nowdoc, string escapes, variable interpolation in strings,
//         double-quoted escapes (\n, \t, \r, \\, \$, \", \x, \0, \u),
//         multiline strings, sprintf, str_pad, number_format

// --- double-quoted escapes ---

echo "--- double-quoted ---\n";
echo "tab:\there\n";
echo "newline in string: [line1\nline2]\n";
echo "carriage return: [cr\rhere]\n";
echo "null byte: [before\0after]\n";
echo "backslash: [back\\slash]\n";
echo "dollar: [\$var]\n";
echo "quote: [say \"hello\"]\n";
echo "hex: [\x41\x42\x43]\n";
echo "octal: [\101\102\103]\n";
echo "unicode: [\u{0041}\u{0042}\u{0043}]\n";

// --- heredoc ---

echo "--- heredoc ---\n";
$name = "World";
$text = <<<EOT
Hello, $name!
This is a heredoc.
It supports variable interpolation.
EOT;
echo $text . "\n";

$html = <<<HTML
<div class="test">
    <p>Paragraph</p>
</div>
HTML;
echo $html . "\n";

// heredoc with escapes
$escaped = <<<EOT
tab:\there
newline:\nhere
hex:\x41\x42\x43
EOT;
echo $escaped . "\n";

// --- nowdoc (no interpolation) ---

echo "--- nowdoc ---\n";
$nowdoc = <<<'EOT'
Hello, $name!
No interpolation here.
Backslash: \n \t \x41
EOT;
echo $nowdoc . "\n";

// --- string interpolation patterns ---

echo "--- interpolation ---\n";
$a = "first";
$b = "second";
echo "simple: $a and $b\n";
echo "braces: {$a} and {$b}\n";

$arr = ['key' => 'value', 'num' => 42];
echo "array: {$arr['key']}\n";
echo "array num: {$arr['num']}\n";

$obj = new stdClass();
$obj->name = "test";
echo "object: {$obj->name}\n";

// --- multiline string operations ---

echo "--- multiline ---\n";
$multi = "line 1\nline 2\nline 3\nline 4\nline 5";
$lines = explode("\n", $multi);
echo "lines: " . count($lines) . "\n";
echo "first: {$lines[0]}\n";
echo "last: {$lines[4]}\n";

$joined = implode(" | ", $lines);
echo "joined: $joined\n";

// --- padding and formatting ---

echo "--- formatting ---\n";
echo str_pad("left", 10) . "|\n";
echo str_pad("right", 10, " ", STR_PAD_LEFT) . "|\n";
echo str_pad("both", 10, "-", STR_PAD_BOTH) . "|\n";
echo str_pad("dots", 10, ".") . "|\n";

echo sprintf("%05d", 42) . "\n";
echo sprintf("%-10s|", "left") . "\n";
echo sprintf("%10s|", "right") . "\n";
echo sprintf("%+d", 42) . "\n";
echo sprintf("%+d", -42) . "\n";

// --- edge cases ---

echo "--- edge cases ---\n";
echo "empty concat: " . "" . "" . "" . "end\n";
echo "nested quotes: " . 'it\'s "fine"' . "\n";
$empty = "";
echo "empty length: " . strlen($empty) . "\n";
echo "null coalesce: " . ($empty ?: "default") . "\n";

// single char operations
$ch = "A";
echo "ord: " . ord($ch) . "\n";
echo "chr: " . chr(65) . "\n";
echo "chr range: ";
for ($i = 65; $i <= 70; $i++) {
    echo chr($i);
}
echo "\n";

echo "done\n";

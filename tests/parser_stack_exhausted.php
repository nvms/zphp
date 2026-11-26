<?php
// php's parser holds at most 10000 states (bison's YYMAXDEPTH): source
// nested deeper is a ParseError "memory exhausted", source just inside the
// limit parses
$cases = [
    'arrays ok' => '$x = ' . str_repeat('[', 9993) . str_repeat(']', 9993) . '; return "parsed";',
    'arrays too deep' => '$x = ' . str_repeat('[', 9994) . str_repeat(']', 9994) . ';',
    'calls ok' => 'return 4996; ' . str_repeat('f(', 4996) . str_repeat(')', 4996) . ';',
    'calls too deep' => 'return 1; ' . str_repeat('f(', 5001) . str_repeat(')', 5001) . ';',
    'blocks too deep' => str_repeat('{', 5000) . str_repeat('}', 5000),
    'far too deep' => '$x = ' . str_repeat('(', 50000) . '1' . str_repeat(')', 50000) . ';',
    'deep on a later line' => "\n\n" . '$x = ' . str_repeat("[\n", 12000) . str_repeat(']', 12000) . ';',
];
foreach ($cases as $label => $code) {
    try {
        var_dump(eval($code));
    } catch (ParseError $e) {
        echo "$label: ", $e->getMessage(), " on line ", $e->getLine(), "\n";
    }
}

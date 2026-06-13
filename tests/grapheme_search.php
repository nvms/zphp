<?php
// covers: grapheme_strrpos / grapheme_strripos / grapheme_strstr /
// grapheme_stristr / grapheme_str_split, plus the offset argument of
// grapheme_strpos / grapheme_stripos (previously ignored). positions are in
// grapheme units, case-insensitive variants use real unicode folding

// strrpos: last occurrence
var_dump(grapheme_strrpos('a-b-c-d', '-'));
var_dump(grapheme_strrpos('héllo wörld hé', 'hé'));
var_dump(grapheme_strrpos('héllo', 'x'));
var_dump(grapheme_strrpos('👍a👍b👍', '👍'));

// strrpos offsets: positive = match must start at/after, negative = bound from end
var_dump(grapheme_strrpos('a-b-c-d', '-', 2));
var_dump(grapheme_strrpos('a-b-c-d', '-', -2));
var_dump(grapheme_strrpos('a-b-c-d', '-', -3));
var_dump(grapheme_strrpos('a-b-c-d', '-', -7));
var_dump(grapheme_strrpos('a-b-c-d', '-', 6));
var_dump(grapheme_strrpos('a-b-c-d', 'b-c', 2));
var_dump(grapheme_strrpos('a-b-c-d', 'b-c', 3));

// strripos: unicode case folding
var_dump(grapheme_strripos('a-B-c-D', 'b'));
var_dump(grapheme_strripos('HÉllo hÉ', 'hé'));

// strpos/stripos offset argument
var_dump(grapheme_strpos('a-b-c-d', '-', 2));
var_dump(grapheme_strpos('a-b-c-d', '-', -3));
var_dump(grapheme_strpos('abc', 'x', 3));
var_dump(grapheme_strpos('👍a👍b👍', '👍', 1));
var_dump(grapheme_stripos('HÉLLO wörld', 'wÖrld'));

// empty needle returns positional values
var_dump(grapheme_strpos('abc', ''));
var_dump(grapheme_strpos('abc', '', 2));
var_dump(grapheme_strrpos('abc', ''));
var_dump(grapheme_strrpos('abc', '', -1));

// out-of-range offset throws ValueError
try {
    grapheme_strpos('a-b-c-d', '-', 99);
} catch (ValueError $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
try {
    grapheme_strrpos('a-b-c-d', '-', -8);
} catch (ValueError $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

// strstr / stristr
var_dump(grapheme_strstr('a-b-c-d', '-'));
var_dump(grapheme_strstr('a-b-c-d', '-', true));
var_dump(grapheme_strstr('héllo wörld', 'wö'));
var_dump(grapheme_strstr('abc', 'x'));
var_dump(grapheme_strstr('abc', ''));
var_dump(grapheme_stristr('HÉllo World', 'wor'));
var_dump(grapheme_stristr('HÉllo World', 'wor', true));

// str_split: grapheme-cluster chunks
var_dump(grapheme_str_split('héllo'));
var_dump(grapheme_str_split('a👍b👍c', 2));
var_dump(grapheme_str_split(''));
var_dump(grapheme_str_split('👨‍👩‍👧‍👦ab'));
try {
    grapheme_str_split('abc', 0);
} catch (ValueError $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

// unicode case mapping fixes that back the folding (latin extended-a odd
// subranges, Y-diaeresis, dz/lj/nj digraphs)
echo mb_strtolower('ĹĻĽĿŃŅŇŹŻŽŸǄǅǇǊǱ'), "\n";
echo mb_strtoupper('ĺļľŀńņňźżžÿǆǉǌǳ'), "\n";

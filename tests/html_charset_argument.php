<?php
// the encoding argument of the html functions: php's charset names in any
// case, a warning for anything else, and a number read as its digits
$s = "<a href='x'>T\xe9st</a>";
foreach ([1, 12, 1252, 866, 8666, null, '', 'SJIS', 'sjis', 'utf8', 'UTF-8', 'latin1', 'ISO-8859-1', 'cp1251', 'MacRoman', str_repeat('a', 40), "utf-8\0junk"] as $cs) {
    var_dump(htmlspecialchars($s, ENT_QUOTES, $cs));
}
var_dump(htmlentities("<\xe9>", ENT_QUOTES, 'iso-8859-1'));
var_dump(htmlentities("<\xe9>", ENT_QUOTES, '123'));
var_dump(html_entity_decode("&lt;&eacute;", ENT_QUOTES, 12));
var_dump(count(get_html_translation_table(HTML_SPECIALCHARS, ENT_QUOTES, 'x')));

// multibyte charsets other than UTF-8: whole characters pass, ill-formed ones
// empty the result, are substituted, or are dropped
$cases = [
    'SJIS' => ["\x82\xa0<", "a\x81", "\x80x", "\xa5"],
    'BIG5' => ["\xa4\x40&", "\xa4", "\xa4\x30"],
    'BIG5-HKSCS' => ["\x88\x80", "\x88\x40"],
    'GB2312' => ["\xb0\xa1'", "\xb0\x41", "\x8e"],
    'EUC-JP' => ["\xa4\xa2\"", "\x8e\xb1", "\x8f\xb0\xa1", "\x8f\xb0", "\xa0", "\x8e\xa0"],
];
foreach ($cases as $cs => $inputs) {
    foreach ($inputs as $in) {
        echo $cs, ' ', bin2hex($in), ': ';
        var_dump(htmlspecialchars($in, ENT_QUOTES, $cs), htmlspecialchars($in, ENT_QUOTES | ENT_SUBSTITUTE, $cs), htmlspecialchars($in, ENT_QUOTES | ENT_IGNORE, $cs));
    }
}

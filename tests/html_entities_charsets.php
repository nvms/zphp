<?php
// html entity functions over php's single-byte and multibyte charsets

set_error_handler(function ($no, $msg) {
    echo "[$no] $msg\n";
    return true;
});

function show($label, $s) {
    echo str_pad($label, 34), bin2hex($s), "  ", preg_replace('/[^\x20-\x7e]/', '.', $s), "\n";
}

// a paragraph pasted from a word processor in windows-1252: smart quotes,
// an em dash, a euro sign and an ellipsis
$word = "\x93Caf\xe9 cr\xe8me\x94 \x96 only \x8019.99\x85 <b>tonight</b> & \x99";
show("cp1252 htmlentities", htmlentities($word, ENT_QUOTES, "Windows-1252"));
show("cp1252 htmlspecialchars", htmlspecialchars($word, ENT_QUOTES, "cp1252"));
show("cp1252 bytes without a code point", htmlentities("a\x81b\x8dc\x8fd\x90e\x9d", ENT_QUOTES, "1252"));
show("cp1252 decode", html_entity_decode("&ldquo;Caf&eacute;&rdquo; &euro;5 &hellip; &trade; &rarr;", ENT_QUOTES, "cp1252"));

// iso-8859-15 swaps a few latin-1 slots for the euro sign and oe ligatures
show("iso-8859-15 htmlentities", htmlentities("\xa4 \xbc\xbd\xbe \xa6\xa8 \xb4\xb8", ENT_QUOTES, "ISO-8859-15"));
show("iso-8859-15 decode", html_entity_decode("&euro; &OElig;&oelig; &Yuml; &curren; &frac12;", ENT_QUOTES, "ISO8859-15"));
show("iso-8859-1 htmlentities", htmlentities("Gr\xfc\xdfe aus K\xf6ln \xa9 2024 \xbd \xa0", ENT_QUOTES, "ISO-8859-1"));
show("iso-8859-1 decode", html_entity_decode("Gr&uuml;&szlig;e &euro; &#233; &#x20AC; &#256;", ENT_QUOTES, "iso-8859-1"));

// russian text in the cyrillic charsets
$privet_koi8 = "\xf0\xd2\xc9\xd7\xc5\xd4, \xcd\xc9\xd2!";
show("koi8-r htmlentities", htmlentities($privet_koi8, ENT_QUOTES, "KOI8-R"));
show("koi8-r decode", html_entity_decode("&#1055;&#1088;&#1080;&#1074;&#1077;&#1090; &mdash; &copy; &euro;", ENT_QUOTES, "koi8-ru"));
$privet_1251 = "\xcf\xf0\xe8\xe2\xe5\xf2 \x97 \x84\xec\xe8\xf0\x93 \xb9 5";
show("cp1251 htmlentities", htmlentities($privet_1251, ENT_QUOTES, "Windows-1251"));
show("cp1251 decode", html_entity_decode("&#1055;&#1088;&#1080; &bdquo;&laquo;&raquo;&ldquo; &#8470; &euro;", ENT_QUOTES, "win-1251"));
show("iso-8859-5 htmlentities", htmlentities("\xbf\xe0\xd8\xd2\xd5\xe2 \xf0 \xfd \xad", ENT_QUOTES, "iso-8859-5"));
show("iso-8859-5 decode", html_entity_decode("&#1055;&#1088; &#8470; &sect; &shy; &#1037; &#1104;", ENT_QUOTES, "iso8859-5"));
show("cp866 htmlentities", htmlentities("\x8f\xe0\xa8\xa2\xa5\xe2 \xc9\xcd\xbb \xfc \xb0\xb1\xb2", ENT_QUOTES, "cp866"));
show("cp866 decode", html_entity_decode("&#1055;&#1088; &boxDR; &radic; &deg; &nbsp;", ENT_QUOTES, "ibm866"));

// classic mac os text
show("macroman htmlentities", htmlentities("Caf\x8e \xa5 \xa9 \xaa \xd0 \xf0 \x7f", ENT_QUOTES, "MacRoman"));
show("macroman decode", html_entity_decode("Caf&eacute; &bull; &trade; &ndash; &#127; &#63743;", ENT_QUOTES, "macroman"));

// multibyte charsets only get the basic entities, and their ill-formed
// sequences follow each charset's own rules
$sjis = "\x93\xfa\x96\x7b\x8c\xea <a href='x'>\x83\x65\x83\x58\x83\x67</a> & \x5c";
show("shift_jis htmlspecialchars", htmlspecialchars($sjis, ENT_QUOTES, "Shift_JIS"));
show("shift_jis htmlentities", htmlentities($sjis, ENT_QUOTES, "SJIS"));
show("shift_jis broken trail", htmlspecialchars("ok\x81\x7f<end", ENT_QUOTES | ENT_SUBSTITUTE, "SJIS-win"));
show("shift_jis broken ignored", htmlspecialchars("ok\x81\x7f<end\x81", ENT_QUOTES | ENT_IGNORE, "CP932"));
show("shift_jis broken refused", htmlspecialchars("ok\x81\x7f<end", ENT_QUOTES, "932"));
show("euc-jp htmlspecialchars", htmlspecialchars("\xc6\xfc\xcb\xdc <\x8e\xb1> \x8f\xb0\xa1 \"q\"", ENT_QUOTES, "EUC-JP"));
show("euc-jp broken", htmlspecialchars("\xa1\x41 \x8e\xe0 \x8f\xa1\x41 \xff", ENT_QUOTES | ENT_SUBSTITUTE, "eucJP-win"));
show("big5 htmlspecialchars", htmlspecialchars("\xa4\xa4\xa4\xe5 <p> \xa5\x40", ENT_QUOTES, "BIG5"));
show("big5 broken", htmlspecialchars("\xa4\x30 \xa4\x80 \xa4", ENT_QUOTES | ENT_SUBSTITUTE, "950"));
show("big5-hkscs broken", htmlspecialchars("\xa4\x30 \xa4\x80 \xa4\xff", ENT_QUOTES | ENT_SUBSTITUTE, "BIG5-HKSCS"));
show("gb2312 htmlspecialchars", htmlspecialchars("\xd6\xd0\xce\xc4 <i>\xb2\xe2</i>", ENT_QUOTES, "GB2312"));
show("gb2312 broken", htmlspecialchars("\xd6\x41 \xd6\x8e \xa0 \xff", ENT_QUOTES | ENT_SUBSTITUTE, "936"));
show("multibyte decode ascii only", html_entity_decode("&lt;&amp;&#65;&#x5c;&yen;&#x4e2d;&quot;", ENT_QUOTES, "Shift_JIS"));
show("big5 decode", html_entity_decode("&lt;&#126;&#x7e;&#x7d;&copy;", ENT_QUOTES, "BIG5"));

// utf-8 ill-formed input
$broken = "ok \xc3\x28 \xe2\x82 \xf0\x9f\x98 \xed\xa0\x80 \xc0\xaf \xf4\x90\x80\x80 <end>";
show("utf-8 substitute", htmlspecialchars($broken, ENT_QUOTES | ENT_SUBSTITUTE));
show("utf-8 ignore", htmlentities($broken, ENT_QUOTES | ENT_IGNORE));
show("utf-8 refused", htmlspecialchars($broken, ENT_QUOTES));

// charset names are matched without regard to case, and unknown ones warn
show("lowercase charset name", htmlentities("\xe9", ENT_QUOTES, "iso-8859-1"));
show("unknown charset", htmlentities("\xc3\xa9", ENT_QUOTES, "latin9"));
show("charset name with a nul", htmlentities("\xc3\xa9", ENT_QUOTES, "utf-8\0junk"));
show("unknown charset, empty input", htmlentities("", ENT_QUOTES, "latin9"));
show("unknown charset, no &", html_entity_decode("plain", ENT_QUOTES, "latin9"));

// the default charset comes from default_charset when none is given
ini_set("default_charset", "cp1252");
show("default_charset cp1252", htmlentities("\x93quoted\x94 \x80"));
show("default_charset decode", html_entity_decode("&ldquo;&euro;&rdquo;"));
ini_set("default_charset", "");
show("empty default_charset", htmlentities("\xc3\xa9"));
ini_set("default_charset", "UTF-8");

// translation tables per charset
foreach (["cp1252", "KOI8-R", "cp866", "MacRoman", "ISO-8859-1", "BIG5", "EUC-JP"] as $cs) {
    $t = get_html_translation_table(HTML_ENTITIES, ENT_QUOTES | ENT_HTML401, $cs);
    echo $cs, ": ", count($t), " entries";
    $shown = 0;
    foreach ($t as $k => $v) {
        if (strlen($k) == 1 && ord($k) >= 0x80 && $shown < 6) {
            echo " ", bin2hex($k), "=", $v;
            $shown++;
        }
    }
    echo "\n";
}
$t = get_html_translation_table(HTML_ENTITIES, ENT_QUOTES | ENT_HTML5, "ISO-8859-1");
echo "latin-1 html5: ", count($t), "\n";
foreach (["<\xd2", "=\xe5", ">\xd2", "fj"] as $k) var_dump($t[$k] ?? null);
$t = get_html_translation_table(HTML_ENTITIES, ENT_QUOTES | ENT_HTML5, "cp1251");
echo "cp1251 html5: ", count($t), " ", $t["\xb9"], " ", $t["\xab"], "\n";

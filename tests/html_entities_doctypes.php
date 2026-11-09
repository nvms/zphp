<?php
// how the doctype flags (ENT_HTML401, ENT_XML1, ENT_XHTML, ENT_HTML5) and
// ENT_DISALLOWED, ENT_IGNORE, ENT_SUBSTITUTE and double_encode change escaping

$doctypes = ["html401" => ENT_HTML401, "xml1" => ENT_XML1, "xhtml" => ENT_XHTML, "html5" => ENT_HTML5];

function show($label, $s) {
    echo str_pad($label, 40), json_encode($s, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE), "\n";
}

// a comment form submission with quotes, markup and a few symbols
$comment = "It's \"great\" <script>alert('x')</script> caf\u{e9} \u{2264} 5 \u{2192} \u{2665} \u{1d538}";
foreach ($doctypes as $name => $dt) {
    show("htmlspecialchars $name", htmlspecialchars($comment, ENT_QUOTES | $dt));
    show("htmlentities $name", htmlentities($comment, ENT_QUOTES | $dt));
    show("compat $name", htmlspecialchars($comment, ENT_COMPAT | $dt));
    show("noquotes $name", htmlentities($comment, ENT_NOQUOTES | $dt));
}

// re-escaping text that already holds entities
$stored = "Tom &amp; Jerry &copy; &apos;quoted&apos; &hellip; &nGt; &#169; &#xA9; &#x0x41; &bogus; & &; &#; &#x; &#12a; &#9999999999999;";
foreach ($doctypes as $name => $dt) {
    show("no double encode $name", htmlspecialchars($stored, ENT_QUOTES | $dt, "UTF-8", false));
    show("no double encode entities $name", htmlentities($stored, ENT_QUOTES | $dt, "UTF-8", false));
    show("double encode $name", htmlspecialchars($stored, ENT_QUOTES | $dt, "UTF-8", true));
}

// numeric entities that a doctype does not allow are encoded again under
// ENT_DISALLOWED
$numeric = "&#0; &#1; &#9; &#11; &#12; &#13; &#127; &#128; &#159; &#xD800; &#xFFFE; &#xFDD0; &#x1FFFF; &#x10FFFF; &#x110000;";
foreach ($doctypes as $name => $dt) {
    show("disallowed numeric $name", htmlspecialchars($numeric, ENT_QUOTES | ENT_DISALLOWED | $dt, "UTF-8", false));
}

// control characters and noncharacters in the text itself
$controls = "a\x01b\x0bc\x0cd\re\x7ff\u{80}g\u{9f}h\u{fdd0}i\u{fffe}j\u{1fffe}k\u{e000}l";
foreach ($doctypes as $name => $dt) {
    show("disallowed text $name", htmlspecialchars($controls, ENT_QUOTES | ENT_DISALLOWED | $dt));
    show("disallowed entities $name", htmlentities($controls, ENT_QUOTES | ENT_DISALLOWED | $dt));
    show("allowed text $name", htmlspecialchars($controls, ENT_QUOTES | $dt));
}
show("disallowed in cp1252", bin2hex(htmlentities("a\x01b\x7f\x81\x93", ENT_QUOTES | ENT_DISALLOWED | ENT_XML1, "cp1252")));
show("disallowed cp1252 html5", bin2hex(htmlentities("a\x01b\x0c\x7f\x81\x93", ENT_QUOTES | ENT_DISALLOWED | ENT_HTML5, "cp1252")));
show("disallowed in sjis", bin2hex(htmlspecialchars("a\x01b\x7f\x0c", ENT_QUOTES | ENT_DISALLOWED | ENT_XHTML, "SJIS")));
show("disallowed in koi8-r", bin2hex(htmlspecialchars("a\x01b\x7f\x80", ENT_QUOTES | ENT_DISALLOWED | ENT_HTML401, "KOI8-R")));

// decoding follows the doctype too
$encoded = "&apos;&#39;&#039;&#x27;&quot;&#34; &lt;&gt;&amp; &copy;&euro;&hellip; &NewLine;&Tab;&excl; &#13;&#x0D;&#12;&#1;&#128;&#xFFFE;";
foreach ($doctypes as $name => $dt) {
    show("decode $name", html_entity_decode($encoded, ENT_QUOTES | $dt));
    show("decode compat $name", html_entity_decode($encoded, ENT_COMPAT | $dt));
    show("decode noquotes $name", html_entity_decode($encoded, ENT_NOQUOTES | $dt));
    show("specialchars decode $name", htmlspecialchars_decode($encoded, ENT_QUOTES | $dt));
    show("specialchars decode compat $name", htmlspecialchars_decode($encoded, ENT_COMPAT | $dt));
}

// the basic tables per doctype
foreach ($doctypes as $name => $dt) {
    echo "table $name: ", json_encode(get_html_translation_table(HTML_SPECIALCHARS, ENT_QUOTES | $dt)), "\n";
    echo "table noquotes $name: ", json_encode(get_html_translation_table(HTML_SPECIALCHARS, ENT_NOQUOTES | $dt)), "\n";
    echo "entities $name: ", count(get_html_translation_table(HTML_ENTITIES, ENT_QUOTES | $dt)), "\n";
}

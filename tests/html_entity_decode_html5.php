<?php
// the html 5 entity table: names beyond html 4.01, entities for two code
// points, and the limits on names and numeric references

function show($label, $s) {
    echo str_pad($label, 36), json_encode($s, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE), " ", bin2hex($s), "\n";
}

// a snippet of math markup scraped from a wiki page
$math = "&forall;x &isin; &Ropf;: x&sup2; &ge; 0 &NotEqualTilde; &nGt; &nLt; &nvlt; &bne; &fjlig; &ThickSpace;&MediumSpace; &acE; &race; &NewLine;&Tab;&lbrace;&rbrace;";
show("html5", html_entity_decode($math, ENT_QUOTES | ENT_HTML5));
show("html401", html_entity_decode($math, ENT_QUOTES | ENT_HTML401));
show("xhtml", html_entity_decode($math, ENT_QUOTES | ENT_XHTML));
show("xml1", html_entity_decode($math, ENT_QUOTES | ENT_XML1));
show("html5 into latin-1", html_entity_decode("&eacute; &nGt; &fjlig; &Ropf; &bne; &sup2;", ENT_QUOTES | ENT_HTML5, "ISO-8859-1"));
show("html5 into cp1252", html_entity_decode("&euro;&OElig;&fjlig;&lbrace;&nbsp;&amp;", ENT_QUOTES | ENT_HTML5, "cp1252"));

// names are case sensitive and end at the first ';' within 32 bytes
show("case", html_entity_decode("&AMP; &Amp; &amp; &COPY; &Copy; &copy; &eacute; &Eacute; &EACUTE;", ENT_QUOTES | ENT_HTML5));
$long = "&CounterClockwiseContourIntegral; &CounterClockwiseContourIntegralX; &" . str_repeat("a", 40) . "; &amp";
show("long names", html_entity_decode($long, ENT_QUOTES | ENT_HTML5));
show("no semicolon", html_entity_decode("&copy &amp &lt3 &#65 &#x41 a&b", ENT_QUOTES | ENT_HTML5));
show("short tail", html_entity_decode("x&lt; &lt &a; &#", ENT_QUOTES | ENT_HTML5));
show("odd bytes in names", html_entity_decode("&a b; &a-b; &;; &&amp;; &\u{e9};", ENT_QUOTES | ENT_HTML5));

// numeric references, including what strtol accepts
$nums = "&#65;&#x41;&#X41;&#0065;&#x0041;&#x0x41;&#x0X42;&#x0x;&#xx41; &#1114111;&#1114112;&#x110000;&#99999999999999999999; &#-65;&#+65;&# 65;&#x 41;";
show("numeric html5", html_entity_decode($nums, ENT_QUOTES | ENT_HTML5));
show("numeric html401", html_entity_decode($nums, ENT_QUOTES | ENT_HTML401));
$edge = "&#0;&#9;&#10;&#11;&#12;&#13;&#127;&#128;&#159;&#160;&#xD7FF;&#xD800;&#xDFFF;&#xE000;&#xFDD0;&#xFDEF;&#xFDF0;&#xFFFE;&#xFFFF;&#x1FFFE;&#x10FFFD;";
foreach (["html401" => ENT_HTML401, "xml1" => ENT_XML1, "xhtml" => ENT_XHTML, "html5" => ENT_HTML5] as $name => $dt) {
    show("edge $name", html_entity_decode($edge, ENT_QUOTES | $dt));
}
show("quotes kept", html_entity_decode("&#39;&#34;&apos;&quot;", ENT_NOQUOTES | ENT_HTML5));
show("specialchars decode", htmlspecialchars_decode("&#60;&#x3C;&#62;&#38;&#39;&#34;&#65;&lt;&apos;&copy;", ENT_QUOTES | ENT_HTML5));
show("specialchars decode 401", htmlspecialchars_decode("&#60;&#38;&#39;&apos;&#039;&quot;", ENT_QUOTES));

// encoding picks the two code point entities when the second one follows
$pairs = "<\u{20d2} >\u{20d2} =\u{20e5} fj f \u{205f}\u{200a} \u{205f} \u{2260}\u{fe00} \u{223e}\u{333} \u{2282}\u{20d2} \u{1d56b}";
show("htmlentities html5", htmlentities($pairs, ENT_QUOTES | ENT_HTML5));
show("htmlentities html401", htmlentities($pairs, ENT_QUOTES | ENT_HTML401));
show("pair at the end", htmlentities("<", ENT_QUOTES | ENT_HTML5));
show("pair before bad utf-8", htmlentities("<\xe2\x83 f\xff", ENT_QUOTES | ENT_HTML5 | ENT_SUBSTITUTE));
show("round trip", html_entity_decode(htmlentities($pairs, ENT_QUOTES | ENT_HTML5), ENT_QUOTES | ENT_HTML5));

// the html 5 translation table
$t = get_html_translation_table(HTML_ENTITIES, ENT_QUOTES | ENT_HTML5);
echo "html5 table: ", count($t), "\n";
foreach (["<", "<\u{20d2}", "f", "fj", "\u{205f}\u{200a}", "\u{2260}", "'", "&", "\u{1d56b}", "\u{a0}"] as $k) {
    echo bin2hex($k), " => ", var_export($t[$k] ?? null, true), "\n";
}
echo "first: ", json_encode(array_slice($t, 0, 8, true), JSON_UNESCAPED_UNICODE), "\n";
echo "last: ", json_encode(array_slice($t, -4, 4, true), JSON_UNESCAPED_UNICODE), "\n";
$t = get_html_translation_table(HTML_ENTITIES, ENT_COMPAT | ENT_HTML5);
echo "compat html5 table: ", count($t), " ", var_export(isset($t["'"]), true), "\n";
$t = get_html_translation_table(HTML_ENTITIES, ENT_QUOTES | ENT_HTML401);
echo "html401 table: ", count($t), " ", md5(serialize($t)), "\n";
$t = get_html_translation_table(HTML_ENTITIES, ENT_QUOTES | ENT_XML1);
echo "xml1 entities table: ", json_encode($t), "\n";

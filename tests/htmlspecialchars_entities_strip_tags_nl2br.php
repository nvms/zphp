<?php
echo htmlspecialchars("<script>alert('xss')</script>"), "\n";
echo htmlspecialchars("a&b<c>d"), "\n";
echo htmlspecialchars("'quote' \"double\""), "\n";
echo htmlspecialchars("'quote' \"double\"", ENT_QUOTES), "\n";
echo htmlspecialchars("'quote' \"double\"", ENT_NOQUOTES), "\n";
echo htmlspecialchars("plain text"), "\n";
echo htmlspecialchars(""), "\n";
echo htmlspecialchars("&amp;"), "\n";
echo htmlspecialchars("&amp;", ENT_QUOTES | ENT_HTML5), "\n";

echo htmlspecialchars_decode("&lt;p&gt;hello&lt;/p&gt;"), "\n";
echo htmlspecialchars_decode("&amp;"), "\n";
echo htmlspecialchars_decode("&quot;hi&quot;", ENT_QUOTES), "\n";
echo htmlspecialchars_decode("&#039;hi&#039;", ENT_QUOTES), "\n";
echo htmlspecialchars_decode("a&amp;b&lt;c&gt;d"), "\n";

echo htmlentities("a&b<c>d"), "\n";
echo htmlentities("café"), "\n";
echo htmlentities("naïve"), "\n";
echo htmlentities("'\"<>&"), "\n";
echo htmlentities("'\"<>&", ENT_QUOTES), "\n";

echo html_entity_decode("&amp;&lt;&gt;&quot;&#039;"), "\n";
echo html_entity_decode("&amp;", ENT_QUOTES), "\n";
echo html_entity_decode("&#039;hi&#039;", ENT_QUOTES), "\n";
echo html_entity_decode("&copy;"), "\n";
echo html_entity_decode("&pound;"), "\n";
echo html_entity_decode("&hellip;"), "\n";
echo html_entity_decode("&trade;"), "\n";

echo htmlentities("Hello&World"), "\n";

echo strip_tags("<p>hello</p>"), "\n";
echo strip_tags("<b>bold</b> normal <i>italic</i>"), "\n";
echo strip_tags("<a href='url'>link</a>"), "\n";
echo strip_tags("<script>bad()</script>safe"), "\n";
echo strip_tags("<p>keep</p><span>remove</span>", "<p>"), "\n";
echo strip_tags("<b>x</b><i>y</i><u>z</u>", "<b><u>"), "\n";
echo strip_tags("plain text"), "\n";
echo strip_tags(""), "\n";
echo strip_tags("<br/>line<br>break"), "\n";
echo strip_tags("<p class='c'>hello</p>"), "\n";

echo strip_tags("<!-- comment --> visible"), "\n";

echo strip_tags("<p>nested <b>tag</b></p>"), "\n";

echo strip_tags("<<<<unclosed"), "\n";

echo strip_tags("<a>x</a><b>y</b>", ["a"]), "\n";
echo strip_tags("<a>x</a><b>y</b>", ["a", "b"]), "\n";

echo strip_tags("multi
line<br>
break"), "\n";

echo htmlspecialchars(null, ENT_QUOTES, "UTF-8"), "\n";

echo htmlspecialchars("test<br>", ENT_QUOTES | ENT_SUBSTITUTE), "\n";

echo htmlspecialchars("<", ENT_HTML5), "\n";
echo htmlspecialchars("<", ENT_XHTML), "\n";

$decoded = htmlspecialchars_decode(htmlspecialchars("<>&\"'"));
echo $decoded, "\n";

$decoded = htmlspecialchars_decode(htmlspecialchars("<>&\"'", ENT_QUOTES), ENT_QUOTES);
echo $decoded === "<>&\"'" ? "y" : "n", "\n";

$roundtrip = htmlspecialchars("<p>hello & world</p>");
echo $roundtrip, "\n";
echo htmlspecialchars_decode($roundtrip), "\n";

echo htmlspecialchars(123), "\n";
echo htmlspecialchars(123.45), "\n";
echo htmlspecialchars(true), "\n";

echo strip_tags("<P>upper</P>"), "\n";

echo htmlspecialchars("<>", ENT_NOQUOTES), "\n";

echo nl2br("line1\nline2"), "\n";
echo nl2br("line1\nline2", false), "\n";

echo nl2br("line1\r\nline2"), "\n";

echo wordwrap("The quick brown fox", 10, "\n", true), "\n";
echo wordwrap("the quick brown fox", 10), "\n";
echo wordwrap("verylongwordhere", 5, "\n", true), "\n";

echo wordwrap("hello world", 5, "-"), "\n";

echo quoted_printable_encode("Café"), "\n";

echo strlen(htmlspecialchars("naïve")), "\n";
echo strlen(htmlentities("naïve")), "\n";

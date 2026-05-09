<?php
echo htmlspecialchars("<a href='x'>&\"y\"</a>"), "\n";
echo htmlspecialchars("<a href='x'>", ENT_QUOTES), "\n";
echo htmlspecialchars("<a href='x'>", ENT_NOQUOTES), "\n";
echo htmlspecialchars("<a href='x'>", ENT_HTML5), "\n";
echo htmlspecialchars("a&amp;b"), "\n"; // double encode default true: "a&amp;amp;b"
echo htmlspecialchars("a&amp;b", ENT_QUOTES, "UTF-8", false), "\n"; // no double
echo htmlspecialchars("a&copy;b", ENT_QUOTES, "UTF-8", false), "\n";
echo htmlspecialchars("a&#039;b", ENT_QUOTES, "UTF-8", false), "\n";
echo htmlspecialchars("a&#x27;b", ENT_QUOTES, "UTF-8", false), "\n";
echo htmlspecialchars("a&xyz;b", ENT_QUOTES, "UTF-8", false), "\n"; // not entity, encode &
echo htmlspecialchars_decode("&lt;a&gt;&amp;"), "\n";
echo htmlspecialchars_decode("&#039;hi&#039;"), "\n";
echo htmlspecialchars_decode("&#x27;hi&#x27;"), "\n";
echo htmlspecialchars_decode("&quot;x&quot;", ENT_NOQUOTES), "\n"; // keeps quotes
echo htmlentities("café <test>"), "\n";
echo htmlentities("café", ENT_QUOTES | ENT_HTML5), "\n";
echo html_entity_decode("&copy; &eacute; &amp;"), "\n";
echo html_entity_decode("&apos;"), "\n"; // no decode in HTML4 default
echo html_entity_decode("&apos;", ENT_QUOTES | ENT_HTML5), "\n"; // decodes
echo html_entity_decode("&trade; &euro; &rarr;", ENT_QUOTES | ENT_HTML5), "\n";
echo html_entity_decode("&#9731;"), "\n"; // snowman
echo html_entity_decode("&#x2603;"), "\n"; // hex snowman
// strip_tags
echo strip_tags("<p>hello <b>world</b></p>"), "\n";
echo strip_tags("<p>hello <b>world</b></p>", "<b>"), "\n";
echo strip_tags("<p>hello <b>world</b></p>", ["b", "i"]), "\n";
echo strip_tags("<script>bad</script><p>good</p>"), "\n";
echo strip_tags("self<closing/> tags <br/>"), "\n";
echo strip_tags("<!-- comment --> and <p>content</p>"), "\n";
echo strip_tags('<a href="x">link</a>'), "\n";

<?php
// Latin-1 chars get named entities
echo htmlentities("café"), "\n";          // caf&eacute;
echo htmlentities("résumé"), "\n";        // r&eacute;sum&eacute;
echo htmlentities("naïve"), "\n";         // na&iuml;ve
echo htmlentities("über"), "\n";          // &uuml;ber
echo htmlentities("año"), "\n";           // a&ntilde;o
echo htmlentities("£100"), "\n";          // &pound;100
echo htmlentities("¿qué?"), "\n";

// Latin Extended-A & beyond NOT in Latin-1: pass through
echo htmlentities("日本語"), "\n";

// HTML special chars still work
echo htmlentities("<b>café</b>"), "\n";   // &lt;b&gt;caf&eacute;&lt;/b&gt;
echo htmlentities("a & b"), "\n";
echo htmlentities("'quote'"), "\n";       // &#039;quote&#039; (default = ENT_QUOTES|HTML5)

// no escape single (ENT_NOQUOTES = 0)
echo htmlentities("'", ENT_NOQUOTES), "\n";
echo htmlentities("'", ENT_QUOTES), "\n";

// double_encode parameter
echo htmlentities("&amp;"), "\n";  // double-encodes by default
// (note: 4th arg is double_encode but htmlentities for Latin-1 doesn't know existing entities)

// htmlspecialchars (only basic 5 chars)
echo htmlspecialchars("café"), "\n";  // café (no entity)

// special markers like ©, ®
echo htmlentities("© 2024"), "\n";
echo htmlentities("®"), "\n";

// HTML5 entities beyond Latin-1
echo htmlentities("™"), "\n";          // &trade;
echo htmlentities("€100"), "\n";       // &euro;100
echo htmlentities("a→b"), "\n";        // a&rarr;b
echo htmlentities("a≤b"), "\n";        // a&le;b

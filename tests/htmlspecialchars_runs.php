<?php
// plain ascii runs between special characters, multibyte text and invalid
// bytes, under each quote and error flag
$inputs = ["plain text only", "a&b<c>d\"e'f", "café <naïve> & \"résumé\"", "bad \xC3\x28 byte & more", "&amp; already &lt;encoded&gt;", "\x00\x1f control", ""];
foreach ($inputs as $s) {
    foreach ([ENT_QUOTES, ENT_NOQUOTES, ENT_COMPAT | ENT_SUBSTITUTE, ENT_QUOTES | ENT_IGNORE, ENT_QUOTES | ENT_DISALLOWED | ENT_HTML5] as $flags) {
        var_dump(htmlspecialchars($s, $flags), htmlspecialchars($s, $flags, 'UTF-8', false));
    }
}

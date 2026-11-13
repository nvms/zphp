<?php
// the scanner's ParseError for a block comment that never ends

foreach (["y&/*", "y&/**", "\$a = 1;\n/* x\ny", "y&/* */", "y&#", "/**/ y&//"] as $code) {
    try {
        eval($code);
    } catch (ParseError $e) {
        var_dump($e->getMessage(), $e->getLine());
    }
}
var_dump(count(token_get_all("<?php /* open")));

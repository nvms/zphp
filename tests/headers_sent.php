<?php
// covers: headers_sent() with output buffering interaction

// before any output
var_dump(headers_sent()); // false

// after unbuffered output
echo "hello";
var_dump(headers_sent()); // true

// stays true even with no new output
var_dump(headers_sent()); // true

// stays true even inside ob_start
ob_start();
echo "buffered";
var_dump(headers_sent()); // true (was already sent before OB)
ob_end_clean();

// fresh test: OB before any direct output
// can't truly reset headers_sent in a single script,
// so just verify it stays true
var_dump(headers_sent()); // true

echo "\n";
echo "DONE\n";

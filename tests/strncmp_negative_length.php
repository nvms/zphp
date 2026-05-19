<?php
// regression: strncmp and strncasecmp throw ValueError when $length is
// negative ('must be greater than or equal to 0'). previously zphp
// silently clamped to 0 and returned 0 which masked caller bugs
try { strncmp('hello', 'help', -1); }
catch (\ValueError $e) { echo "nc: " . $e->getMessage() . "\n"; }

try { strncasecmp('hello', 'help', -5); }
catch (\ValueError $e) { echo "ncc: " . $e->getMessage() . "\n"; }

// zero length is valid (returns 0)
echo strncmp("hello", "world", 0) . "\n";
echo strncasecmp("hello", "world", 0) . "\n";

// normal positive length works
echo strncmp("hello", "help", 3) . "\n";
echo strncasecmp("HELLO", "help", 3) . "\n";

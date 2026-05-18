<?php
// regression: argument-type TypeError messages include the ', called in
// <file> on line N' suffix matching PHP exactly. previously the message
// stopped after 'given' which broke compat for any caller that pattern-
// matched on the trailing location text
function strict(int $x): int { return $x * 2; }
try { strict("abc"); }
catch (TypeError $e) { echo $e->getMessage() . "\n"; }

class A { public static function s(int $x): int { return $x; } }
try { A::s("z"); }
catch (TypeError $e) { echo $e->getMessage() . "\n"; }

// nullable type
function nb(?int $x): int { return $x ?? 0; }
try { nb("x"); }
catch (TypeError $e) { echo $e->getMessage() . "\n"; }

// nested call - line number should match the inner call site
function outer($v) {
    try { strict($v); }
    catch (TypeError $e) { return $e->getMessage(); }
    return "no-throw";
}
echo outer("bad") . "\n";

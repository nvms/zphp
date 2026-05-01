<?php

class A {}
interface I {}
interface J {}
class AI extends A implements I {}
class AIJ extends A implements I, J {}

// pure intersection
function needsAI(A&I $x): string { return "ok"; }
echo needsAI(new AI()) . "\n";
echo needsAI(new AIJ()) . "\n";

// union
function needsAOrI(A|I $x): string { return "ok"; }
echo needsAOrI(new A()) . "\n";

// DNF with parens: (A&I)|null
function dnf((A&I)|null $x): string { return $x === null ? "null" : "ok"; }
echo dnf(new AI()) . "\n";
echo dnf(null) . "\n";
echo dnf(new AIJ()) . "\n";

// reject mismatched
try { needsAI(new A()); echo "should not pass\n"; } catch (TypeError $e) { echo "rejected\n"; }

// triple intersection
function tri(A&I&J $x): string { return "tri-ok"; }
echo tri(new AIJ()) . "\n";
try { tri(new AI()); } catch (TypeError $e) { echo "tri-rejected\n"; }

// nullable shorthand still works
function nullable(?A $x): string { return $x === null ? "null" : "obj"; }
echo nullable(null) . "\n";
echo nullable(new A()) . "\n";

<?php
// PHP 8.5: resolving a by-reference parameter must use the evaluated lvalue,
// not replay the bytecode or guess its receiver from the caller's variables.
class ProvenanceBox {
    public private(set) int $number = 1;
    public protected(set) int $protectedNumber = 2;
    public private(set) array $items = [[1]];
    public private(set) object $inside;
    function __construct() { $this->inside = (object)['number' => 1]; }
    function legal() { provenanceChange($this->number); }
}
class ProvenanceChild extends ProvenanceBox {
    function legalChild() { provenanceChange($this->protectedNumber); }
    function deniedChild() { provenanceChange($this->number); }
}
$b = new ProvenanceBox;
$evaluations = 0;
$entries = 0;
function provenanceReceiver() { global $b, $evaluations; ++$evaluations; return $b; }
function provenanceField() { global $evaluations; ++$evaluations; return 'number'; }
function provenanceIndex() { global $evaluations; ++$evaluations; return 0; }
function provenanceChange(&$n) { global $entries; ++$entries; $n = 9; }
function provenanceRead($n) { echo "read=$n\n"; }
function provenanceAttempt($fn) {
    try { $fn(); }
    catch (Error $e) { echo $e->getMessage(), "\n"; }
}
provenanceAttempt(function () { provenanceChange(provenanceReceiver()->number); });
provenanceAttempt(function () { provenanceChange(provenanceReceiver()->{provenanceField()}); });
provenanceAttempt(function () { provenanceChange(provenanceReceiver()->items[provenanceIndex()][0]); });
provenanceAttempt(function () use ($b) { provenanceChange(n: $b->number); });
provenanceAttempt(function () use ($b) { provenanceChange(...[], n: $b->number); });
provenanceAttempt(function () { $fn = 'provenanceChange'; $fn(provenanceReceiver()->number); });
// Ordinary reads and mutation of an object's interior remain legal.
provenanceRead(provenanceReceiver()->number);
provenanceChange($b->inside->number);
echo "evaluations=$evaluations entries=$entries\n";
var_dump($b->number, $b->items, $b->inside->number);
$b->legal();
$child = new ProvenanceChild;
$child->legalChild();
provenanceAttempt(function () use ($child) { $child->deniedChild(); });
var_dump($b->number, $child->protectedNumber, $child->number);
// Native mutation is observable even where userland writeback is missing.
class ProvenanceNativeBox { public private(set) array $items = [3, 1, 2]; }
$nativeBox = new ProvenanceNativeBox;
function provenanceNativeReceiver() { global $nativeBox; return $nativeBox; }
provenanceAttempt(function () { $fn = 'sort'; $fn(provenanceNativeReceiver()->items); });
var_dump($nativeBox->items);
// Constructor binding must check evaluated property provenance before entry.
class ProvenanceConstructor {
    function __construct(&$n) { echo "unexpected constructor entry\n"; $n = 100; }
}
provenanceAttempt(function () use ($b) { new ProvenanceConstructor($b->number); });
provenanceAttempt(function () use ($b) { $class = 'ProvenanceConstructor'; new $class($b->number); });
provenanceAttempt(function () use ($b) { new ProvenanceConstructor(...[], n: $b->number); });

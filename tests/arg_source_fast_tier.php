<?php
function fastTierWrite(&$value) { $value = 99; }
function fastTierIdentity($value) { return $value; }
function fastTierPair(&$value, $unused) { $value = 42; }
function fastTierExercise() {
    $text = 'keep';
    $target = 1;
    // Native results are values, not the source variable of their arguments.
    strlen($text);
    echo $text, "\n";
    // A fast callee returning must not discard the caller's pending source.
    fastTierPair($target, fastTierIdentity($text));
    echo $target, "\n";
    $target = 2;
    // Fast-to-runtime bailout must preserve the recorded source.
    fastTierWrite($target);
    echo $target, "\n";
}
fastTierExercise();

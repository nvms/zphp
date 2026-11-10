<?php
// return type errors are raised inside the function: a function that falls
// off its end returns "none", a catch inside the function sees the error,
// and the trace lists the function

function missing(): ?iterable {}
function missing_mixed(): mixed { if (false) return 1; }
function never_returns(): never {}
function nothing(): void {}
function wrong(): int { return "x"; }
function caught(): int
{
    try {
        return [];
    } catch (TypeError $e) {
        echo "caught inside: ", $e->getMessage(), "\n";
        return 5;
    }
}
function gen(): iterable { yield 1; }
$closure = function (): string {};

foreach (['missing', 'missing_mixed', 'never_returns', 'wrong', $closure] as $f) {
    try {
        $f();
    } catch (TypeError $e) {
        echo get_class($e), ": ", $e->getMessage(), " @ ", $e->getLine(), "\n";
        echo $e->getTraceAsString(), "\n";
    }
}
var_dump(nothing(), caught(), iterator_to_array(gen()));

function typed(int $x) {}
try {
    typed("x");
} catch (TypeError $e) {
    echo preg_replace('~/\S+~', 'PATH', (string) $e), "\n";
}

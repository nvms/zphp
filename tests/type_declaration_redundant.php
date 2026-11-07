<?php
// php rejects declared types that repeat or subsume one another while
// compiling
echo "not reached\n";
class Ok { function m(int|string|null $a, ?Countable $b, (Countable&Traversable)|null $c, iterable|bool $d): static|null {} }
function broken(Countable|object $value) {}

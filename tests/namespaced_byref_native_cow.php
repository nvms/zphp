<?php

namespace App\Console\Support;

// by-ref array natives (array_shift, array_pop, array_unshift, array_splice,
// sort, ...) called UNQUALIFIED inside a namespace must still COW-separate a
// shared array before mutating it. the compiler resolves the unqualified name
// to a namespaced symbol (App\Console\Support\array_shift) that falls back to
// the global native at runtime; the by-ref separation must key off the
// basename, not the namespaced name. this regressed every namespaced file
// (i.e. all Composer/Symfony/Laravel code): `$copy = $prop; array_shift($copy)`
// mutated $prop in place. it broke Symfony Console's ArgvInput::getParameterOption
// (`$tokens = $this->tokens; array_shift($tokens)`), emptying the input tokens
// so no command name was parsed and every artisan command showed the help page.

class Box
{
    public array $items = ['a', 'b', 'c'];

    public function drainCopy(): array
    {
        $copy = $this->items;
        while (0 < count($copy)) {
            array_shift($copy);
        }
        return $this->items;
    }

    public function popCopy(): array
    {
        $copy = $this->items;
        array_pop($copy);
        return $this->items;
    }

    public function sortCopy(): array
    {
        $copy = $this->items;
        sort($copy);
        return $this->items;
    }

    public function spliceCopy(): array
    {
        $copy = $this->items;
        array_splice($copy, 0, 2);
        return $this->items;
    }
}

$b = new Box();
echo "after array_shift drain: ";
var_dump($b->drainCopy());
echo "after array_pop: ";
var_dump($b->popCopy());
echo "after sort: ";
var_dump($b->sortCopy());
echo "after array_splice: ";
var_dump($b->spliceCopy());

// the plain local-to-local copy form in a namespace
$src = ['x', 'y', 'z'];
$copy = $src;
array_shift($copy);
echo "src after local array_shift(copy): ";
var_dump($src);

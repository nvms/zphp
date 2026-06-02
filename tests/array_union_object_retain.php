<?php

// the array-union operator (+ / +=) copies the right operand's entries into
// the result. for object/array values the result holds a NEW reference, so it
// must bump the refcount - otherwise freeing the result over-releases a value
// still owned elsewhere (a static cache, another array, a property). this
// regressed Symfony VarDumper / Laravel error rendering, where per-class
// UninitializedStub markers cached in a static array were destructed when a
// local built via `$local += self::$cache` went out of scope.

class Box
{
    public int $tag = 1;
    public array $items = [];
}

class Registry
{
    public static array $cache = [];
}

Registry::$cache['a'] = new Box();
Registry::$cache['b'] = new Box();

// build a local via array union, mutate it, then free it
$local = [];
$local += Registry::$cache;
$local['c'] = new Box();
$local['a']->items[] = 'mutated through alias';
unset($local);

// the cached boxes must still be intact (not destructed / zeroed)
echo "a.items: ";
var_dump(Registry::$cache['a']->items);
echo "b.tag: ";
var_dump(Registry::$cache['b']->tag);

// the binary + form (not just +=) on a fresh array
$base = ['x' => new Box()];
$merged = $base + ['y' => new Box()];
unset($merged);
echo "base.x.tag after binary union + unset: ";
var_dump($base['x']->tag);

// union where the left operand wins for duplicate keys - the right's value is
// dropped, the left's survives and stays owned
$left = ['k' => new Box()];
$left['k']->tag = 42;
$right = ['k' => new Box()];
$u = $left + $right;
unset($u);
echo "left.k.tag (left wins): ";
var_dump($left['k']->tag);

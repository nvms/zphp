<?php

// passing a COW-shared array BY REFERENCE must separate it: a PHP reference is
// never COW-shared with a non-reference, so an in-place mutation through the
// ref param (unset / array_shift / array_splice / sort / direct write) must
// NOT corrupt another holder that copied the array before the call. at the
// same time the mutation MUST still be visible to the caller's variable (the
// whole point of by-ref) and non-shared by-ref must be untouched.

function unsetKey(array &$a): void
{
    unset($a['b']);
}

$shared = ['a' => 1, 'b' => 2, 'c' => 3];
$reader = $shared;                 // COW copy - shares storage
unsetKey($shared);
echo "shared after unsetKey: ";
var_dump(array_keys($shared));     // [a, c]  (by-ref unset visible)
echo "reader (must keep b): ";
var_dump(array_keys($reader));     // [a, b, c]  (COW holder untouched)

function shiftFirst(array &$a): void
{
    array_shift($a);
}

$s2 = ['x', 'y', 'z'];
$r2 = $s2;
shiftFirst($s2);
echo "s2 count / r2 count: ";
var_dump([count($s2), count($r2)]);  // [2, 3]

function spliceTwo(array &$a): void
{
    array_splice($a, 0, 2);
}

$s3 = ['p', 'q', 'r', 's'];
$r3 = $s3;
spliceTwo($s3);
echo "s3 count / r3 count: ";
var_dump([count($s3), count($r3)]);  // [2, 4]

function pushNew(array &$a): void
{
    $a['added'] = true;
}

$s4 = ['k' => 1];
$r4 = $s4;
pushNew($s4);
echo "s4 has added / r4 has added: ";
var_dump([isset($s4['added']), isset($r4['added'])]);  // [true, false]

// non-shared by-ref still mutates in place (no spurious extra copy)
function appendOne(array &$a): void
{
    $a[] = 99;
}

$solo = [1, 2];
appendOne($solo);
echo "solo after appendOne: ";
var_dump($solo);  // [1, 2, 99]

// chained: caller passes by-ref into a helper that passes it by-ref again
function inner(array &$a): void
{
    unset($a[0]);
}
function outer(array &$a): void
{
    inner($a);
    $a[] = 'tail';
}

$chain = ['first', 'second'];
$chainReader = $chain;
outer($chain);
echo "chain: ";
var_dump(array_values($chain));        // [second, tail]
echo "chainReader (untouched): ";
var_dump($chainReader);                // [first, second]

// a by-ref param bound to a COW-shared OBJECT PROPERTY array must also separate:
// the mutation must reach $obj->prop (an in-place unset doesn't fire the cell
// writeback, so the property is pointed at the private copy at bind time) and a
// reader that copied the property before the call must be protected. this is the
// shape config Repository uses: Arr::forget($this->items, $key).
class PropHolder
{
    public array $items = ['a' => 1, 'b' => 2, 'c' => 3];
}

function unsetProp(array &$a): void
{
    unset($a['b']);
}

$ph = new PropHolder();
$propReader = $ph->items;
unsetProp($ph->items);
echo "prop items after unset: ";
var_dump(array_keys($ph->items));        // [a, c] - mutation reached the property
echo "prop reader (untouched): ";
var_dump(array_keys($propReader));       // [a, b, c]

// non-shared object-prop by-ref still mutates the property in place
class PropHolder2
{
    public array $items = ['p' => 1];
}
function addProp(array &$a): void
{
    $a['q'] = 2;
}
$ph2 = new PropHolder2();
addProp($ph2->items);
echo "prop2 has q: ";
var_dump(isset($ph2->items['q']));       // true

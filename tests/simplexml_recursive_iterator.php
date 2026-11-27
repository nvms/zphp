<?php
// SimpleXMLElement is a RecursiveIterator, as php declares it (no
// IteratorAggregate, no ArrayAccess): the object is its own iterator. the
// elements a name selects walk those siblings, attributes() walks the
// attributes, and anything else (the document's element, children(), an
// element an iteration or an offset gave) walks its children

$x = new SimpleXMLElement('<r><a><b/><c/></a><a><d/></a></r>');
foreach ($x as $k => $a) {
    echo "[$k:";
    foreach ($a as $k2 => $v) {
        echo $k2;
    }
    echo "]";
}
echo "\n";
foreach ($x->a as $k => $a) {
    echo "[$k:";
    foreach ($a as $k2 => $v) {
        echo $k2;
    }
    echo "]";
}
echo "\n";
foreach ($x->a[0] as $k => $v) {
    echo $k;
}
echo "\n";
foreach ($x->a[0]->children() as $k => $v) {
    echo $k;
}
echo "\n";
$y = new SimpleXMLElement('<r p="1" q="2"><a/></r>');
foreach ($y->attributes() as $k => $v) {
    echo "$k=$v ";
}
echo "\n";

$it = new SimpleXMLIterator('<r><a><b/></a><c/></r>');
foreach ($it as $k => $v) {
    echo get_class($v), " $k ", var_export($it->hasChildren(), true), "\n";
}
foreach (new RecursiveIteratorIterator($it, RecursiveIteratorIterator::SELF_FIRST) as $k => $v) {
    echo "$k ";
}
echo "\n";
foreach (new RecursiveIteratorIterator($x, RecursiveIteratorIterator::SELF_FIRST) as $k => $v) {
    echo "$k ";
}
echo "\n";

var_dump($x instanceof RecursiveIterator, $x instanceof ArrayAccess, $x instanceof IteratorAggregate);
var_dump(method_exists($x, 'rewind'), method_exists($x, 'offsetGet'), method_exists($x, 'getIterator'));
print_r(class_implements($x));

$x->rewind();
var_dump($x->valid(), $x->key(), $x->current()->getName(), $x->current() === $x->current());
$x->next();
var_dump($x->key());
$x->next();
var_dump($x->valid(), $x->hasChildren(), $x->getChildren());
try {
    $x->key();
} catch (Error $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
try {
    $x->current();
} catch (Error $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
$x->rewind();
var_dump($x->hasChildren(), $x->getChildren()->getName());

var_dump(isset($y['p']), (string) $y['p'], (string) $y['q']);
$y['z'] = 'new';
unset($y['p']);
echo $y->asXML();

$mi = new MultipleIterator();
$mi->attachIterator(new SimpleXMLElement('<x><y/><z/></x>'));
foreach ($mi as $k => $v) {
    var_dump($k, $v[0]->getName());
}

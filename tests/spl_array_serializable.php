<?php
// PHP 8.5 legacy Serializable and modern state contracts share storage/members,
// but legacy streams deliberately omit the configured iterator class.
class SerializableArrayObject extends ArrayObject {
    public $label = 'member';
    protected $hidden = 'protected';
    private $secret = 'private';
}
class SerializableArrayIterator extends ArrayIterator {}
foreach (['ArrayObject', 'ArrayIterator', 'SerializableArrayObject', 'SerializableArrayIterator'] as $class) {
    $a = new $class(['name' => 'value', 7 => [false, null, 2.5]], 3);
    $wire = $a->serialize();
    echo $class, ':', bin2hex($wire), "\n";
    $b = new $class();
    var_dump($b->unserialize($wire));
    var_dump($b->getFlags(), $b->getArrayCopy());
    echo bin2hex($b->serialize()), "\n";
    echo bin2hex(serialize($a)), "\n";
    $c = unserialize(serialize($a));
    var_dump($c->getFlags(), $c->getArrayCopy());
}
$o = (object)['value' => 12];
$a = new ArrayObject([$o, $o]);
$a->member = $o;
$wire = $a->serialize();
echo $wire, "\n";
$b = new ArrayObject();
$b->unserialize($wire);
var_dump($b[0] === $b[1], $b[0] === $b->member);
$b[0]->value = 20;
var_dump($b[1]->value, $b->member->value);
foreach (['ArrayObject', 'ArrayIterator'] as $class) {
    $a = new $class((object)['key' => 'object storage'], 1);
    echo $a->serialize(), "\n";
    $b = new $class();
    $b->unserialize($a->serialize());
    echo $b->serialize(), "\n";
    $b->unserialize('');
    echo $b->serialize(), "\n";
    $b->unserialize('x:i:99;a:0:{};m:a:0:{}ignored');
    echo $b->serialize(), "\n";
}
foreach (['garbage', 'x:i:0;i:1;;m:a:0:{}', 'x:i:0;a:0:{}', 'x:i:0;a:0:{};m:i:1;', 'x:i:0;R:1;;m:a:0:{}'] as $wire) {
    try { (new ArrayObject())->unserialize($wire); }
    catch (UnexpectedValueException $e) { echo $e->getMessage(), "\n"; }
}
foreach ([[], ['0', [], [], null], [0, 1, [], null], [0, [], 1, null]] as $state) {
    try { (new ArrayObject())->__unserialize($state); }
    catch (Exception $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
}
$x = 1;
$a = new ArrayObject([&$x, &$x]);
echo $a->serialize(), "\n";
$b = new ArrayObject();
$b->unserialize($a->serialize());
echo $b->serialize(), "\n";
$b[0] = 7; // SPL replaces this bucket, unlike assignment into a PHP array.
echo $b->serialize(), "\n";
foreach (['x:i:0;a:0:{};m:a:0:{', 'x:i:0;a:1:{i:0;i:1;;m:a:0:{}'] as $wire) {
    try { (new ArrayObject())->unserialize($wire); }
    catch (UnexpectedValueException $e) { echo $e->getMessage(), "\n"; }
}
$a = new ArrayObject();
$a->unserialize('x:i:16777216;m:a:1:{s:1:"p";i:2;}');
echo $a->serialize(), "\n";
$a = new ArrayObject();
$a[] = $a;
echo $a->serialize(), "\n";
$b = new ArrayObject();
$b->unserialize($a->serialize());
echo $b->serialize(), "\n";
class SerializationCustomIterator extends ArrayIterator {}
$a = new ArrayObject([1], 0, SerializationCustomIterator::class);
echo serialize($a), "\n";
echo serialize(unserialize(serialize($a))), "\n";

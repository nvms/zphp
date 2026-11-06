<?php
// ArrayObject and ArrayIterator over an object read and write the object's
// property table: public and dynamic entries by name, private and protected
// ones by their mangled keys, past types and visibility
error_reporting(E_ALL);

class P { private $x = 'px'; protected $y = 'py'; public $z = 'pz'; public int $t; }
class C extends P { private $x = 'cx'; public $w = 'cw'; }

$o = new C;
$o->{'12'} = 'twelve';
$o->dyn = 'd';
$ao = new ArrayObject($o);
var_dump(count($ao));
foreach ($ao as $k => $v) var_dump($k, $v);
print_r(array_map('bin2hex', array_keys($ao->getArrayCopy())));
var_dump($ao['x'] ?? 'missing', isset($ao['z']), isset($ao["\0C\0x"]), $ao["\0C\0x"], $ao["\0P\0x"], $ao["\0*\0y"]);
var_dump($ao['t']);
$ao['t'] = 'not an int';
var_dump($o->t);
$ao['x'] = 'beside the privates';
unset($ao['z']);
print_r($o);
$ao['z'] = 'back';
print_r($o);
try { $ao->append(1); } catch (Error $e) { echo $e->getMessage(), "\n"; }

// another ArrayObject as storage works on that one's storage
$outer = new ArrayObject($ao);
$outer['through'] = 1;
var_dump($o->through, count($outer));
$it = new ArrayIterator($o);
$it->seek(1);
var_dump($it->key());
try { $it->seek(50); } catch (OutOfBoundsException $e) { echo $e->getMessage(), "\n"; }
print_r((array) $ao);

// numeric offsets name properties
$s = new stdClass;
$a = new ArrayObject($s);
$a[0] = 1;
$a[0] += 1;
var_dump($s->{'0'}, isset($a[0]), (array) $a);
unset($a[0]);
var_dump(count($a));

// writes never reach an array the storage was copied from
$arr = [1, 2];
$x = new ArrayObject($arr);
$x[] = 3;
$copy = clone $x;
$copy['k'] = 'v';
var_dump($arr, count($x), count($copy));
$i = $x->getIterator();
$x['late'] = 1;
var_dump(iterator_to_array($i));

// the storage keeps its flags, an iterator takes them, and getFlags masks
$f = new ArrayObject(new ArrayObject([], ArrayObject::ARRAY_AS_PROPS));
var_dump($f->getFlags());
$f->setFlags(0x7FFFFFFF);
var_dump($f->getFlags());

// a dynamic-only table sorts in place
$d = (object) ['b' => 2, 'a' => 1, 'c' => 3];
$sorted = new ArrayObject($d);
$sorted->asort();
print_r($d);
$sorted->ksort();
print_r($d);

// objects that build their properties are refused, as are enums
enum E { case A; }
foreach ([new DateTime('2020-01-01'), new SplFixedArray(1), E::A] as $bad) {
    try { new ArrayObject($bad); } catch (InvalidArgumentException $e) { echo $e->getMessage(), "\n"; }
}
try { new ArrayObject(null); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { (new ArrayIterator)->exchangeArray('x'); } catch (Error $e) { echo get_class($e), "\n"; }
try { (new ArrayObject)->exchangeArray('x'); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }

// an object as its own storage
$self = new ArrayObject();
$self->exchangeArray($self);
$self['foo'] = 'bar';
var_dump(serialize($self));
var_dump(unserialize(serialize($self))['foo']);

// ARRAY_AS_PROPS on an iterator, and RecursiveArrayIterator children
$it = (new ArrayObject(['a' => 1], ArrayObject::ARRAY_AS_PROPS))->getIterator();
var_dump(isset($it->a), $it->a);
$plain = new ArrayObject([]);
var_dump(@$plain->missing);
$r = new RecursiveArrayIterator(['o' => (object) ['p' => 1], 'arr' => [2]]);
var_dump($r->hasChildren(), $r->getChildren()->getArrayCopy());
$r = new RecursiveArrayIterator(['o' => (object) ['p' => 1]], RecursiveArrayIterator::CHILD_ARRAYS_ONLY);
var_dump($r->hasChildren(), $r->getChildren());
echo json_encode(new class(['x' => 1]) extends ArrayIterator implements JsonSerializable {
    public function jsonSerialize(): mixed { return $this; }
}), "\n";

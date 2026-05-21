<?php
// regression: writing to a typed property must coerce the value to the
// declared type (weak mode) or throw TypeError. zphp stored the raw value
// unchanged - `public int $n; $obj->n = "5"` kept the string "5".

class Model {
    public int $i = 0;
    public float $f = 0.0;
    public string $s = '';
    public bool $b = false;
    public ?int $ni = null;
    public array $arr = [];
    public int|string $u = 0;
}

$m = new Model;

// weak-mode scalar coercion on write
$m->i = "42";   var_dump($m->i);   // int(42)
$m->i = 3.0;    var_dump($m->i);   // int(3)
$m->i = true;   var_dump($m->i);   // int(1)
$m->f = 5;      var_dump($m->f);   // float(5)
$m->f = "2.5";  var_dump($m->f);   // float(2.5)
$m->s = 99;     var_dump($m->s);   // string "99"
$m->s = 1.5;    var_dump($m->s);   // string "1.5"
$m->b = 1;      var_dump($m->b);   // bool(true)
$m->b = 0;      var_dump($m->b);   // bool(false)
$m->ni = "7";   var_dump($m->ni);  // int(7)
$m->ni = null;  var_dump($m->ni);  // NULL

// a union type keeps a value that already matches a member - no coercion
$m->u = "hello"; var_dump($m->u);  // string "hello"
$m->u = 5;       var_dump($m->u);  // int(5)

// __toString into a string-typed property
class Labelled { public function __toString(): string { return "label"; } }
$m->s = new Labelled; var_dump($m->s); // string "label"

// uncoercible values throw TypeError
try { $m->i = "notnumeric"; } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { $m->i = []; }          catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { $m->i = null; }        catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { $m->arr = "x"; }       catch (TypeError $e) { echo $e->getMessage(), "\n"; }

// constructor-promoted typed property coerces too
class Promoted {
    public function __construct(public int $value) {}
}
$p = new Promoted("100");
var_dump($p->value); // int(100)

// typed property written via $this inside a method
class Setter {
    public float $rate = 0.0;
    public function apply($v): void { $this->rate = $v; }
}
$st = new Setter;
$st->apply("3.75");
var_dump($st->rate); // float(3.75)

// inherited typed property - the TypeError names the declaring class
class Base { public int $count = 0; }
class Derived extends Base {}
$d = new Derived;
$d->count = "8";
var_dump($d->count); // int(8)
try { $d->count = "bad"; } catch (TypeError $e) { echo $e->getMessage(), "\n"; }

// repeated writes exercise the inline-cache fast path
for ($k = 0; $k < 5; $k++) {
    $m->i = (string)($k * 10);
}
var_dump($m->i); // int(40)

// a Closure-typed property accepts a first-class callable
class Holder { public \Closure $fn; }
$h = new Holder;
$h->fn = fn() => 1;
$h->fn = 'strlen'(...);
echo "closure assigned\n";

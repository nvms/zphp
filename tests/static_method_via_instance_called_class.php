<?php
// a static method called through an object has the object's class as its
// called scope

class C {
    final static function s() {
        return get_called_class() . " " . static::class . " " . (isset($this) ? "this" : "no this");
    }
    static function v(...$args) {
        return get_called_class() . " " . count($args);
    }
}

class D extends C {
    public function m() {
        return $this->s();
    }
    static function n() {
        $o = new C;
        return $o->s();
    }
}

echo (new D)->m(), "\n";
$d = new D;
echo $d->s(), "\n";
echo D::n(), "\n";
echo $d->v(1, 2), "\n";
$name = 's';
echo $d->$name(), "\n";
echo call_user_func([$d, 's']), "\n";
function inside() {
    $d = new D;
    return $d->s();
}
echo inside(), "\n";

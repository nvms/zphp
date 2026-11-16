<?php
// self, parent and static are keywords php matches in any case
class P {
    const C = 'P::C';
    public static $s = 'P::$s';
    function __construct() { echo "P::__construct\n"; }
    static function who() { return 'P'; }
    function m() { return 'P::m'; }
}
class K extends P {
    const C = 'K::C';
    public static $s = 'K::$s';
    function __construct() { PARENT::__construct(); echo "K::__construct\n"; }
    static function who() { return 'K'; }
    function m() { return 'K::m'; }
    function run() {
        var_dump(SELF::C, Self::C, PARENT::C, Static::C);
        var_dump(SELF::$s, Parent::$s, STATIC::$s);
        var_dump(SELF::who(), Parent::who(), STATIC::who());
        var_dump(SELF::class, PARENT::class, STATIC::class);
        var_dump($this instanceof SELF, $this instanceof PARENT, $this instanceof STATIC);
        var_dump(get_class(new STATIC), get_class(new Self));
        var_dump(PARENT::m());
        $f = function () { return [SELF::C, STATIC::class, PARENT::who()]; };
        var_dump($f());
        $g = fn (): SELF => $this;
        var_dump(get_class($g()));
    }
    function typed(SELF $x): STATIC { return $this; }
}
class L extends K {}
(new K)->run();
(new L)->run();
var_dump(get_class((new K)->typed(new K)));

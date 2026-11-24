<?php
// php 8.6's reflection additions: parameter doc comments, namespace parts of
// attribute and constant names, and whether a property can be read or
// written from a scope

namespace App\Attr {
    #[\Attribute]
    class Marker {}
}

namespace {
    const PLAIN = 1;
    define('App\NESTED', 2);

    /** f */
    function f(
        /** first */ int $a,
        $b /** second */,
        /** not this */ /** third */ ?string $c = /** default */ null,
        #[\SensitiveParameter] /** fourth */ $d = 1,
        $e = 2,
    ) {}
    function g($x, $y) {}

    class P {
        public function __construct(
            /** promoted */ public int $p = 1,
            /** plain */ $q = 2,
        ) {}
        public function m(/** m doc */ (Countable&ArrayAccess)|null $r) {}
    }
    $fn = function (/** closure doc */ $z) {};

    foreach ((new ReflectionFunction('f'))->getParameters() as $p) var_dump($p->getDocComment());
    var_dump((new ReflectionFunction('g'))->getParameters()[0]->getDocComment());
    var_dump((new ReflectionFunction('strlen'))->getParameters()[0]->getDocComment());
    foreach ((new ReflectionMethod('P', '__construct'))->getParameters() as $p) var_dump($p->getDocComment());
    var_dump((new ReflectionProperty('P', 'p'))->getDocComment());
    var_dump((new ReflectionMethod('P', 'm'))->getParameters()[0]->getDocComment());
    var_dump((new ReflectionFunction($fn))->getParameters()[0]->getDocComment());
    var_dump((new ReflectionFunction('f'))->getDocComment());

    foreach ((new ReflectionClass(App\Attr\Marker::class))->getAttributes() as $a) {
        var_dump($a->getName(), $a->inNamespace(), $a->getNamespaceName(), $a->getShortName());
    }
    #[App\Attr\Marker] function marked() {}
    $a = (new ReflectionFunction('marked'))->getAttributes()[0];
    var_dump($a->inNamespace(), $a->getNamespaceName(), $a->getShortName());

    foreach (['PLAIN', 'App\NESTED', 'E_ALL'] as $c) {
        $r = new ReflectionConstant($c);
        var_dump($r->inNamespace(), $r->getNamespaceName(), $r->getShortName());
    }

    class Base {
        public $pub = 1;
        protected $prot = 2;
        private $priv = 3;
        public readonly int $ro;
        public private(set) int $ps = 4;
        public protected(set) string $pps = 'x';
        public int $typed;
        public static $st = 5;
        public static int $stTyped;
        private static $stPriv;
        public int $virt { get => 1; }
        public int $setOnly { set { } }
        public $hooked { get => $this->hooked; set { $this->hooked = $value; } }
        public function __construct() { $this->ro = 1; }
    }
    class Child extends Base {}
    class Other {}
    class Magic {
        private $hidden = 1;
        public function __get($n) { return 1; }
        public function __isset($n) { return $n === 'hidden'; }
        public function __set($n, $v) {}
    }

    $props = ['pub', 'prot', 'priv', 'ro', 'ps', 'pps', 'typed', 'st', 'stTyped', 'stPriv', 'virt', 'setOnly', 'hooked'];
    $b = new Base;
    foreach ($props as $name) {
        $r = new ReflectionProperty(Base::class, $name);
        $static = $r->isStatic();
        $o = $static ? null : $b;
        echo str_pad($name, 8);
        foreach ([null, 'Base', 'Child', 'Other'] as $scope) {
            echo ' ', $scope ?? 'global', ':', (int) $r->isReadable($scope), (int) $r->isWritable($scope);
            echo '/', (int) $r->isReadable($scope, $o), (int) $r->isWritable($scope, $o);
        }
        echo "\n";
    }
    $fresh = (new ReflectionClass(Base::class))->newInstanceWithoutConstructor();
    $r = new ReflectionProperty(Base::class, 'ro');
    var_dump($r->isWritable('Base', $fresh), $r->isReadable('Base', $fresh));
    unset($b->pub);
    var_dump((new ReflectionProperty(Base::class, 'pub'))->isReadable(null, $b));

    $m = new Magic;
    $r = new ReflectionProperty(Magic::class, 'hidden');
    var_dump($r->isReadable(null), $r->isReadable(null, $m), $r->isWritable(null, $m), $r->isReadable('Magic', $m));
    $o = new stdClass;
    $o->dyn = 1;
    $r = new ReflectionProperty($o, 'dyn');
    var_dump($r->isReadable(null, $o), $r->isWritable(null, $o), $r->isReadable(null, new stdClass), $r->isReadable('NoSuchClass'));

    try {
        (new ReflectionProperty(Base::class, 'pub'))->isReadable('NoSuchClass');
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
    try {
        (new ReflectionProperty(Base::class, 'st'))->isReadable(null, $b);
    } catch (ReflectionException $e) {
        echo $e->getMessage(), "\n";
    }
    try {
        (new ReflectionProperty(Base::class, 'pub'))->isWritable(null, new Other);
    } catch (ReflectionException $e) {
        echo $e->getMessage(), "\n";
    }
    try {
        (new ReflectionProperty(Base::class, 'pub'))->isReadable();
    } catch (ArgumentCountError $e) {
        echo $e->getMessage(), "\n";
    }
}

<?php
// doc comments as php's scanner takes them: "/**" followed by whitespace,
// the last one seen before the declaration (attributes included, their own
// arguments' comments excluded), static properties' and promoted ones' too

/**** Not a doc comment */
class A {}

/** A doc comment */
#[Attribute]
class B {
    /** static doc */
    public static $s = 1;
    /** var doc */
    var $v;
    public const int /** inner doc */ C = 1;
    /**no space */
    public $nospace;

    public function __construct(
        /** promoted doc */
        public int $p = 0,
    ) {}

    /** method doc */
    #[B(
        /** closure doc */
        static function () {},
    )]
    public function m() {}
}

/** closure assigned */
$f = function () {};
/** arrow assigned */
$g = fn() => 1;

var_dump((new ReflectionClass('A'))->getDocComment());
var_dump((new ReflectionClass('B'))->getDocComment());
var_dump((new ReflectionProperty('B', 's'))->getDocComment());
var_dump((new ReflectionProperty('B', 'v'))->getDocComment());
var_dump((new ReflectionProperty('B', 'nospace'))->getDocComment());
var_dump((new ReflectionProperty('B', 'p'))->getDocComment());
var_dump((new ReflectionClassConstant('B', 'C'))->getDocComment());
echo new ReflectionClassConstant('B', 'C');
$m = new ReflectionMethod('B', 'm');
var_dump($m->getDocComment());
var_dump((new ReflectionFunction($m->getAttributes()[0]->getArguments()[0]))->getDocComment());
var_dump((new ReflectionFunction($f))->getDocComment());
var_dump((new ReflectionFunction($g))->getDocComment());

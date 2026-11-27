<?php
// generated declarations with more members than a byte counts: classes,
// interfaces, traits and enums with hundreds of attributed members, many
// parents and traits, and a class and an enum with thousands of constants
// and cases

#[Attribute(Attribute::TARGET_ALL)]
class Tag { function __construct(public $n = 0) {} }

function each_of(int $n, callable $f): string
{
    $s = '';
    for ($i = 0; $i < $n; $i++) $s .= $f($i) . "\n";
    return $s;
}

$n = 300;
$code = [];
$code[] = "class Big {\n"
    . each_of($n, fn($i) => "#[Tag($i)] const C$i = $i;")
    . each_of($n, fn($i) => "#[Tag($i)] public \$p$i = $i;")
    . each_of($n, fn($i) => "#[Tag($i)] public static \$s$i = $i;")
    . each_of($n, fn($i) => "#[Tag($i)] function m$i(#[Tag] \$x = $i) { return \$x; }")
    . "}";
$code[] = "trait Wide {\n"
    . each_of($n, fn($i) => "#[Tag($i)] public \$tp$i = $i; #[Tag] public static \$ts$i = $i; #[Tag] const TC$i = $i;")
    . each_of($n, fn($i) => "#[Tag($i)] function tm$i() { return $i; }")
    . "}";
$code[] = "class UsesWide { use Wide; }";
$code[] = each_of(40, fn($i) => "interface I$i { const IC$i = $i; }");
$code[] = "interface Many extends " . implode(', ', array_map(fn($i) => "I$i", range(0, 39))) . " {\n"
    . each_of($n, fn($i) => "#[Tag($i)] const MC$i = $i; #[Tag] function im$i();")
    . "}";
$code[] = each_of(70, fn($i) => "trait U$i { function u$i() { return $i; } }");
$code[] = "class UsesMany implements Many { use " . implode(', ', array_map(fn($i) => "U$i", range(0, 69))) . " { U0::u0 insteadof " . implode(', ', array_map(fn($i) => "U$i", range(1, 20))) . "; u1 as alias1; }\n"
    . each_of($n, fn($i) => "function im$i() { return $i; }")
    . "}";
$code[] = "enum Suit: int implements Many { use " . implode(', ', array_map(fn($i) => "U$i", range(0, 19))) . ";\n"
    . each_of($n, fn($i) => "#[Tag($i)] case K$i = $i;")
    . each_of($n, fn($i) => "#[Tag($i)] const E$i = self::K$i;")
    . each_of($n, fn($i) => "#[Tag] function im$i() { return $i; }")
    . "}";
// more placeholders than a frame's operand headroom
$code[] = "class Constants {\n" . each_of(17000, fn($i) => "const X$i = 'x$i';") . "}";
$code[] = "enum Huge: string {\n" . each_of(2000, fn($i) => "case H$i = 'h$i';") . "}";
foreach ($code as $c) eval($c);
unset($code, $c);

$big = new Big();
$r = new ReflectionClass('Big');
echo count($r->getConstants()), ' ', count(get_object_vars($big)), ' ', count($r->getStaticProperties()), ' ', count(get_class_methods($big)), "\n";
echo Big::C299, ' ', $big->p299, ' ', Big::$s299, ' ', $big->m299(), "\n";
echo $r->getReflectionConstant('C299')->getAttributes()[0]->newInstance()->n, ' ';
echo $r->getProperty('p299')->getAttributes()[0]->newInstance()->n, ' ';
echo $r->getProperty('s150')->getAttributes()[0]->newInstance()->n, ' ';
echo $r->getMethod('m299')->getAttributes()[0]->newInstance()->n, ' ';
echo count($r->getMethod('m299')->getParameters()[0]->getAttributes()), "\n";

$u = new UsesWide();
$r = new ReflectionClass('UsesWide');
echo count(get_object_vars($u)), ' ', count($r->getStaticProperties()), ' ', count($r->getConstants()), ' ', $u->tp299, ' ', UsesWide::$ts299, ' ', UsesWide::TC299, ' ', $u->tm299(), "\n";
$t = new ReflectionClass('Wide');
echo $t->getProperty('tp299')->getAttributes()[0]->newInstance()->n, ' ', $t->getMethod('tm299')->getAttributes()[0]->newInstance()->n, ' ', count($t->getReflectionConstant('TC299')->getAttributes()), "\n";

$m = new ReflectionClass('Many');
echo count($m->getInterfaceNames()), ' ', count($m->getConstants()), ' ', count($m->getMethods()), ' ', Many::IC39, ' ', Many::MC299, ' ', $m->getReflectionConstant('MC299')->getAttributes()[0]->newInstance()->n, "\n";

$o = new UsesMany();
echo count(class_uses($o)), ' ', $o->u0(), ' ', $o->u20(), ' ', $o->u69(), ' ', $o->alias1(), ' ', $o->im299(), ' ', $o instanceof I39 ? 'I39' : '-', "\n";

$e = new ReflectionEnum('Suit');
echo count(Suit::cases()), ' ', Suit::K299->value, ' ', Suit::from(150)->name, ' ', Suit::E299->name, ' ', Suit::K5->u19(), ' ', Suit::K1->im299(), "\n";
echo $e->getCase('K299')->getAttributes()[0]->newInstance()->n, ' ', $e->getReflectionConstant('E299')->getAttributes()[0]->newInstance()->n, ' ', count($e->getMethod('im1')->getAttributes()), "\n";

echo Constants::X0, ' ', Constants::X16999, ' ', Constants::X12345, "\n";
echo count(Huge::cases()), ' ', Huge::H1999->value, ' ', Huge::from('h1234')->name, ' ', Huge::tryFrom('nope') === null ? 'null' : '?', "\n";

// static properties declared after more instance properties than a byte
// counts keep their place in the listings
$s = "class Ordered {\n" . each_of(200, fn($i) => "public \$p$i = $i;") . "public static \$st = 's';\n" . each_of(10, fn($i) => "public \$q$i = $i;") . "public static \$st2 = 's2'; }";
eval($s);
echo implode(',', array_slice(array_map(fn($p) => $p->name, (new ReflectionClass('Ordered'))->getProperties()), 197, 10)), "\n";
echo implode(',', array_slice(array_keys(get_class_vars('Ordered')), 205, 10)), "\n";

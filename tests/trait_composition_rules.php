<?php
// how traits compose into a class: php's insteadof and as rules, abstract
// trait methods checked against the method meeting them, and properties two
// sources declare differently. each case runs in its own process since most
// errors are fatal

function run(string $code): void
{
    $file = tempnam(sys_get_temp_dir(), 'tcr');
    file_put_contents($file, "<?php\n" . $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 ' . escapeshellarg($file) . ' 2>&1');
    unlink($file);
    echo trim(str_replace($file, 'FILE', $out)), "\n";
}

// rules naming methods or traits that aren't there
run('trait T { function a() {} } class C { use T { a as b; b as protected; } }');
run('trait T { function a() {} } class C { use T { nope as b; } }');
run('trait T { function a() {} } class C { use T { T::nope as b; } }');
run('trait T { function a() {} } trait U { function a() {} } class C { use T, U { T::nope insteadof U; } }');
run('trait T { function a() {} } class C { use T { Typo::a as b; } }');
run('trait T { function a() {} } trait U { function a() {} } class C { use T, U { T::a insteadof T; } }');
run('trait T { function a() { return 1; } } trait U { function a() { return 2; } } class C { use T, U { U::a insteadof T; } use T, U { U::a insteadof T; } }');
run('trait T { function a() {} } trait U { function a() {} } class C { use T, U { a as b; } }');
run('trait T { function a() {} } class C { use T { a as static; } }');
run('trait T { function a() {} } class C { use T { T::a as abstract; } }');
run('class C { use static; }');
run('trait T { function a() {} } class C { use T { T::a insteadof static; } }');

// modifiers an `as` rule changes
run('trait T { function a() {} protected function b() {} final function c() {} }
class C { use T { a as final; b as final; c as private; c as public d; } }
foreach (["a", "b", "c", "d"] as $m) { $r = new ReflectionMethod("C", $m); echo $m, " ", $r->isFinal() ? "final " : "", $r->isPublic() ? "public" : ($r->isProtected() ? "protected" : "private"), "\n"; }');
run('trait T { private function a() {} } class C { use T { a as final; } } echo "done\n";');
run('trait T { private final function a() {} } echo "done\n";');

// a trait using a trait: its own methods win, its rules apply to its traits
run('trait A { function f() { return "A"; } function g() { return "A::g"; } }
trait B { use A { f as protected fa; } function f() { return "B"; } function call() { return $this->fa(); } }
class C { use B; }
$c = new C; echo $c->f(), " ", $c->g(), " ", $c->call(), "\n";
echo (new ReflectionMethod("C", "fa"))->isProtected() ? "protected\n" : "public\n";');

// abstract trait methods
run('trait T { abstract function a(int $x); } class C { use T; function a(array $x) {} }');
run('trait T { abstract static function a(); } class C { use T; function a() {} }');
run('trait T { abstract private function a(self $x): self; } class C { use T; private function a(int $x): int {} }');
run('trait T { abstract protected function a(); } class C { use T; private function a() {} } echo "visibility not checked\n";');
run('trait T { abstract function a(); } class C { use T; }');
run('trait T { abstract function a(); function b() { return $this->c(); } } class C { use T { T::a as c; } function a() {} }');
run('trait T { abstract function a($x); } class P { function a() {} } class C extends P { use T; }');
run('trait T { abstract function a($x); } trait U { function a() {} } class C { use U, T; }');
// the parent an abstract trait method is met by may need autoloading
run('spl_autoload_register(function ($c) { if ($c === "P") eval("class P { function a() { echo \"P::a\\\\n\"; } }"); });
trait T { abstract function a(); } class C extends P { use T; } (new C)->a();');

// properties declared twice
run('trait T { public $p; } trait U { private $p; } class C { use T; use U; }');
run('trait T { public $p = true; } class C { use T; public $p = 2; }');
run('trait T { public $p = 2; } class C { use T; public $p = 2; } echo "same default\n";');
run('trait T { static $p = true; } class C { use T; public $p = true; }');
run('trait T { public int $p; } class C { use T; public ?int $p; }');
run('trait T { public int $p = 1; } trait U { public int $p = 1; } class C { use T, U; } var_dump(new C);');
run('trait T { public $p { get => 1; } } class C { use T; public $p; }');
run('trait T { public $p; } readonly class C { use T; }');

<?php
class Loader {
    public array $loaded = [];
    public function load(string $cls): void { $this->loaded[] = $cls; }
}

$l = new Loader;
spl_autoload_register([$l, "load"]);

class_exists("NonExistentX1", true);
print_r($l->loaded);

$f1 = function ($cls) use ($l) { $l->loaded[] = "f1:$cls"; };
$f2 = function ($cls) use ($l) { $l->loaded[] = "f2:$cls"; };
spl_autoload_register($f1);
spl_autoload_register($f2);

class_exists("Foo", true);
class_exists("Bar", true);
print_r($l->loaded);

$funcs = spl_autoload_functions();
echo count($funcs), "\n";

spl_autoload_unregister($f2);
$l->loaded = [];
class_exists("Baz", true);
print_r($l->loaded);

spl_autoload_unregister($f1);
spl_autoload_unregister([$l, "load"]);

echo count(spl_autoload_functions()), "\n";

class Existing {}
echo class_exists("Existing") ? "y" : "n", "\n";
echo class_exists("Existing", false) ? "y" : "n", "\n";

interface IFoo {}
echo interface_exists("IFoo") ? "y" : "n", "\n";
echo interface_exists("MissingInt") ? "y" : "n", "\n";

trait TFoo {}
echo trait_exists("TFoo") ? "y" : "n", "\n";

enum EFoo { case A; case B; }
echo enum_exists("EFoo") ? "y" : "n", "\n";
echo enum_exists("Existing") ? "y" : "n", "\n";

class P {}
class C_ extends P {}
echo is_subclass_of(new C_, P::class) ? "y" : "n", "\n";
echo is_subclass_of(C_::class, P::class) ? "y" : "n", "\n";
echo is_a(new C_, P::class) ? "y" : "n", "\n";
echo is_a(C_::class, P::class, true) ? "y" : "n", "\n";

print_r(class_parents(C_::class));

class Imp implements IFoo {}
print_r(class_implements(Imp::class));

class Tr1 { use TFoo; }
print_r(class_uses(Tr1::class));

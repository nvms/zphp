<?php
// spl_autoload_register and friends, spl_autoload with its extensions, and
// class_parents/class_implements/class_uses as php's php_spl.c has them

function show($label, $f) {
    try {
        $r = $f();
        echo $label, ': ';
        var_dump($r);
    } catch (Throwable $e) {
        echo $label, ': ', get_class($e), ': ', $e->getMessage(), "\n";
    }
}

class Loader {
    public static function load($c) { echo "Loader::load($c)\n"; }
    public function inst($c) { echo "inst($c)\n"; }
    public function __invoke($c) { echo "invoke($c)\n"; }
}
function fnload($c) { echo "fnload($c)\n"; }

$l = new Loader;
var_dump(spl_autoload_functions());
spl_autoload_register('FNLOAD');
spl_autoload_register(['Loader', 'load']);
spl_autoload_register('Loader::load');
spl_autoload_register([$l, 'inst']);
spl_autoload_register($l);
spl_autoload_register(fn($c) => print("closure($c)\n"), true, true);
var_dump(count(spl_autoload_functions()));
var_dump(spl_autoload_functions()[1], spl_autoload_functions()[2], spl_autoload_functions()[3]);
var_dump(class_exists('Missing1'));
var_dump(spl_autoload_unregister('fnload'), spl_autoload_unregister('fnload'));
var_dump(spl_autoload_unregister(['LOADER', 'LOAD']));
spl_autoload_call('Missing2');
show('register spl_autoload_call', fn() => spl_autoload_register('spl_autoload_call'));
show('register bad', fn() => spl_autoload_register('no_such_function'));
show('call array', fn() => spl_autoload_call([]));
spl_autoload_register('fnload', false);
var_dump(spl_autoload_unregister('spl_autoload_call'));
var_dump(spl_autoload_functions());

echo "-- autoloaders that change the stack\n";
function first($c) {
    echo "first($c)\n";
    spl_autoload_unregister('first');
    spl_autoload_register('third');
}
function second($c) { echo "second($c)\n"; }
function third($c) { echo "third($c)\n"; }
spl_autoload_register('first');
spl_autoload_register('second');
var_dump(class_exists('Missing3'));
foreach (spl_autoload_functions() as $f) spl_autoload_unregister($f);

echo "-- spl_autoload\n";
var_dump(spl_autoload_extensions());
$dir = sys_get_temp_dir() . '/zphp_spl_autoload_' . getmypid();
@mkdir($dir);
file_put_contents("$dir/autoloadedone.inc", "<?php echo 'loading one\n'; class AutoloadedOne {}");
file_put_contents("$dir/autoloadedtwo.php", "<?php echo 'loading two\n'; class AutoloadedTwo {}");
set_include_path($dir);
spl_autoload_register();
var_dump(spl_autoload_functions());
var_dump(class_exists('AutoloadedOne'), class_exists('AutoloadedTwo'), class_exists('AutoloadedNone'));
var_dump(spl_autoload_extensions('.php'));
spl_autoload('AutoloadedOne');
unlink("$dir/autoloadedone.inc");
unlink("$dir/autoloadedtwo.php");
rmdir($dir);

echo "-- class_parents, class_implements, class_uses\n";
interface I1 {}
interface I2 extends I1 {}
trait T1 {}
class A implements I2 { use T1; }
class B extends A implements Countable { public function count(): int { return 0; } }
var_dump(class_parents(new B), class_parents('B'), class_implements('B'), class_uses('A'), class_uses(new B));
var_dump(class_implements('I2'), class_parents('I2'));
show('parents int', fn() => class_parents(1));
show('implements missing', fn() => class_implements('NoSuchClass'));
show('uses missing no autoload', fn() => class_uses('NoSuchClass', false));
spl_autoload_register(function ($c) { echo "autoload($c)\n"; });
show('implements autoload', fn() => class_implements('\\NoSuchClass2'));

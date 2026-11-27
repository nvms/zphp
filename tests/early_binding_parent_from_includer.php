<?php
// php binds an included file's class while compiling the file when its
// parent (and the classes its method types need) already exist; otherwise
// the class is declared where it stands
$dir = sys_get_temp_dir() . '/zphp_early_bind_' . getmypid();
@mkdir($dir);
$write = function ($name, $code) use ($dir) {
    file_put_contents("$dir/$name", "<?php\n" . $code);
    return "$dir/$name";
};

class Base {
    public function name(): string { return static::class; }
}
interface Shape {}

// used before its declaration, past a return
$f = $write('unreachable.php', '
var_dump((new Early)->name());
if (true) { return; }
class Early extends Base {}
');
require $f;
var_dump(class_exists('Early', false));

// a chain: the second class's parent is bound just before it
$f = $write('chain.php', '
var_dump(class_exists("Second", false));
class First extends Base {}
class Second extends First {}
');
require $f;

// a parent declared later in the same file isn't there yet
$f = $write('later_parent.php', '
var_dump(class_exists("Child", false));
class Child extends Later {}
class Later extends Base {}
var_dump(class_exists("Child", false));
');
require $f;

// method types naming classes that exist, and one that doesn't yet
$f = $write('types.php', '
var_dump(class_exists("Typed", false), class_exists("Untyped", false));
class Typed extends Base {
    public function shape(Shape $s): ?Base { return null; }
}
class Untyped extends Base {
    public function other(NotYet $n): void {}
}
class NotYet {}
var_dump(class_exists("Untyped", false));
');
require $f;

// an override whose check needs a class that isn't there yet, and ones
// naming the same class as the parent's, which need nothing loaded
class Holder {
    public function take(Shape $s): ?Shape { return null; }
    public function same(Later2 $l): Later2 { return $l; }
    public ?Later2 $held = null;
}
$f = $write('override.php', '
var_dump(class_exists("Overrides", false), class_exists("Same", false), class_exists("Redeclares", false), class_exists("Plain", false));
interface Missing extends Shape {}
class Overrides extends Holder {
    public function take(Shape $s): ?Missing { return null; }
}
class Same extends Holder {
    public function same(Later2 $l): Later2 { return $l; }
}
class Redeclares extends Holder {
    public ?Later2 $held = null;
}
class Plain extends Holder {
    public ?Missing $other = null;
}
var_dump(class_exists("Overrides", false));
');
require $f;

// a parent that only autoloading finds is loaded where the class stands
spl_autoload_register(function ($class) {
    echo "autoload $class\n";
    if ($class === 'Loaded') {
        eval('class Loaded extends Base {}');
    }
});
$f = $write('autoloaded.php', '
echo "before\n";
var_dump(class_exists("FromLoaded", false));
class FromLoaded extends Loaded {}
var_dump(class_exists("FromLoaded", false));
');
require $f;

// eval compiles with the classes there are
eval('var_dump(class_exists("InEval", false)); class InEval extends Base {}');

// inside a namespace
$f = $write('ns.php', '
namespace Space;
var_dump((new Inner)->name());
return;
class Inner extends \Base {}
');
require $f;

// what php can't bind while compiling still runs where it stands
$f = $write('stringable.php', '
var_dump(class_exists("Str", false));
class Str extends Base { public function __toString(): string { return "s"; } }
var_dump(class_exists("Str", false));
');
require $f;

foreach (glob("$dir/*") as $file) unlink($file);
rmdir($dir);

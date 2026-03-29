<?php
// covers: nested trait resolution across autoloaded files, namespaced traits,
//   trait-uses-trait chains, method inheritance through trait hierarchies

spl_autoload_register(function ($class) {
    $file = __DIR__ . "/" . str_replace("\\", "/", str_replace("App\\", "", $class)) . ".php";
    if (file_exists($file)) {
        require $file;
    }
});

class Carbon {
    use App\Traits\Date;

    public $value;

    public function __construct($value) {
        $this->value = $value;
    }
}

$c = new Carbon("2024-01-01");

// method from Date trait (direct)
echo $c->format("Y-m-d") . "\n";

// method from Units trait (nested: Date uses Units)
echo ($c->isModifiableUnit("year") ? "yes" : "no") . "\n";
echo ($c->isModifiableUnit("week") ? "yes" : "no") . "\n";
echo $c->getUnitName() . "\n";

// method from Comparison trait (nested: Date uses Comparison)
$c2 = new Carbon("2024-01-01");
$c3 = new Carbon("2024-06-15");
echo ($c->isEqual($c2) ? "equal" : "not-equal") . "\n";
echo ($c->isEqual($c3) ? "equal" : "not-equal") . "\n";

// 4-level deep autoloaded trait chain
class DeepUser {
    use App\Traits\Deep\Top;
}

$du = new DeepUser();
echo $du->topMethod() . "\n";
echo $du->middleMethod() . "\n";
echo $du->coreMethod() . "\n";

echo "done\n";

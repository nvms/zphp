<?php
// a property magic method runs on the lazy object itself, before it is
// initialized, for a name its class doesn't declare; the access the magic
// method makes is what initializes it, and that access reaches the instance
// under the same guard

#[AllowDynamicProperties]
class C
{
    public $declared = 1;

    public function __isset($name)
    {
        echo __METHOD__, " $name\n";
        return isset($this->$name);
    }

    public function __get($name)
    {
        echo __METHOD__, " $name\n";
        return $this->$name ?? "default";
    }

    public function __unset($name)
    {
        echo __METHOD__, " $name\n";
        unset($this->$name);
    }
}

$rc = new ReflectionClass(C::class);
$makers = [
    'proxy' => fn() => $rc->newLazyProxy(function () {
        echo "init\n";
        return new C();
    }),
    'ghost' => fn() => $rc->newLazyGhost(function ($obj) {
        echo "init\n";
    }),
];
foreach ($makers as $kind => $make) {
    echo "# $kind isset\n";
    var_dump(isset($make()->prop));
    echo "# $kind get\n";
    var_dump($make()->prop);
    echo "# $kind coalesce\n";
    var_dump($make()->prop ?? "none");
    echo "# $kind unset\n";
    $o = $make();
    unset($o->prop);
    var_dump($rc->isUninitializedLazyObject($o));
    echo "# $kind declared\n";
    var_dump(isset($make()->declared));
}

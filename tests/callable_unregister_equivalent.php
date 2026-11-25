<?php
declare(ticks=1);
// unregistering an autoloader or a tick function matches a first-class
// callable against the callable it was made from, and methods of a class
// declared after declare(ticks) tick too

function load_string(string $class): void { echo "load_string $class\n"; }

class Loader {
    public int $ticks = 0;
    public function load(string $class): void { echo "load $class\n"; }
    public function __call(string $name, array $args): void { echo "__call $name\n"; }
    public function __invoke(string $class): void { echo "invoke $class\n"; }
    public function tick(): void { $this->ticks++; }

    public function run(): void {
        spl_autoload_register($this->load(...));
        var_dump(spl_autoload_unregister($this->load(...)));
        spl_autoload_register($this->load(...));
        var_dump(spl_autoload_unregister([$this, 'load']));
        spl_autoload_register($this->missing(...));
        var_dump(spl_autoload_unregister($this->missing(...)));
        spl_autoload_register($this(...));
        var_dump(spl_autoload_unregister($this));
        spl_autoload_register($this);
        var_dump(spl_autoload_unregister([$this, '__invoke']));
        var_dump(count(spl_autoload_functions()));
        class_exists('Missing1');

        register_tick_function($this->tick(...));
        unregister_tick_function([$this, 'tick']);
        echo "ticks: {$this->ticks}\n";
    }
}

spl_autoload_register(load_string(...));
var_dump(spl_autoload_functions()[0] instanceof Closure);
var_dump(spl_autoload_unregister('load_string'));
spl_autoload_register(strlen(...));
var_dump(spl_autoload_unregister('strlen'));
var_dump(spl_autoload_functions());
(new Loader)->run();

<?php
declare(ticks=1);
// a class php binds early still compiles under the file's declare(ticks)
class T {
    public int $n = 0;
    function kick() { $this->n++; }
    function run() {
        register_tick_function([$this, 'kick']);
        $x = 1;
        $x++;
        unregister_tick_function([$this, 'kick']);
        echo "n: {$this->n}\n";
    }
}
(new T)->run();

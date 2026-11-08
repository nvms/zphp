<?php
// only the property's own hook reaches its storage: a method the hook calls
// goes through the hook again, and so recurses, as in php
class Test {
    public $prop {
        get => $this->read();
        set { $this->write($value); }
    }
    private function read() { return $this->prop; }
    private function write($value) { $this->prop = $value; }
}
class Backed {
    public $name = 'init' {
        get { return strtoupper($this->name) . ' via ' . $this->via(); }
    }
    private function via() { return 'helper'; }
}
$t = new Test;
try { $t->prop = 1; } catch (Error $e) { echo get_class($e), ': ', substr($e->getMessage(), 0, 25), "\n"; }
try { $t->prop; } catch (Error $e) { echo get_class($e), ': ', substr($e->getMessage(), 0, 25), "\n"; }
var_dump((new Backed)->name);

<?php
// a destructor that fails ends its own call: the code that dropped the
// object carries on in its own frame
class D {
    public function __construct(public string $how) {}
    public function __destruct() {
        echo "destruct {$this->how}\n";
        if ($this->how === 'throw') throw new Exception("from destructor");
        if ($this->how === 'error') undefined_function();
        if ($this->how === 'constant') UNDEFINED_CONSTANT;
    }
}

function viaUnset(string $how) {
    $d = new D($how);
    try {
        unset($d);
    } catch (Throwable $e) {
    }
    return "after unset $how";
}

function viaForeach(string $how) {
    try {
        foreach ([new D($how)] as $d) {
            unset($d);
        }
    } catch (Throwable $e) {
    }
    return "after foreach $how";
}

function viaReassign(string $how) {
    $d = new D($how);
    try {
        $d = null;
    } catch (Throwable $e) {
    }
    return "after reassign $how";
}

foreach (['throw', 'error', 'constant'] as $how) {
    var_dump(viaUnset($how));
    var_dump(viaForeach($how));
    var_dump(viaReassign($how));
}
echo "done\n";

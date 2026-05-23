<?php
// Stage 2 overwrite-release for variable-variables (`$$name = ...`). before
// the fix, set_var_var did a bare locals[si] = val or vars.put without
// dropping the prior value's retain.
class T
{
    public $id;
    public function __construct($id) { $this->id = $id; }
    public function __destruct() { echo "destruct {$this->id}\n"; }
}

function go() {
    $name = 'x';
    $$name = new T('A');
    echo "before overwrite\n";
    $$name = new T('B');
    echo "after overwrite\n";
    $$name = 0;
    echo "done\n";
}

go();

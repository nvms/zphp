<?php
// parent::${0}::get() names property "0" as a literal, so inside $a's hook
// it is a compile error

class ParentC {}
class Child extends ParentC {
    public $a {
        get {
            return parent::${0}::get();
        }
    }
}

echo "not reached\n";

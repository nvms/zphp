<?php
// __debugInfo() returning null is deprecated (the dump shows no properties)

set_error_handler(function ($no, $msg) {
    echo "error $no: $msg\n";
    return true;
});

class Base {
    public $visible = 1;
    public function __debugInfo() {
        return null;
    }
}
class Child extends Base {}

var_dump(new Base());
var_dump(new Child());
print_r(new Child());
echo "\n";
debug_zval_dump(new Base());

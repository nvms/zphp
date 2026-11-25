<?php

const BACKING = new stdClass;

class C {
    const O = BACKING;
}

// Access via class name.
C::O->prop = 123;
var_dump(C::O->prop);

// Access via instance.
$c = new C;
$c::O->prop = 'overwritten';
var_dump(C::O->prop);

// Compound assignment, increment/decrement and concatenation.
C::O->counter = 0;
C::O->counter++;
C::O->counter++;
C::O->counter--;
var_dump(C::O->counter);

C::O->str = 'hello';
C::O->str .= ' world';
var_dump(C::O->str);

// Nested property chains.
C::O->inner = new stdClass;
C::O->inner->value = 999;
var_dump(C::O->inner->value);

// isset()/unset().
C::O->temp = 'remove me';
var_dump(isset(C::O->temp));
unset(C::O->temp);
var_dump(isset(C::O->temp));

// Passing by reference.
function incr(&$v) { $v++; }
C::O->reftest = 10;
incr(C::O->reftest);
var_dump(C::O->reftest);

// self:: from within a method.
class D {
    const O = BACKING;

    public static function set(): void {
        self::O->fromSelf = 'yes';
    }
}

D::set();
var_dump(D::O->fromSelf);
var_dump(BACKING->fromSelf);

<?php
// declaring a class, interface, trait or enum under a taken name is php's
// fatal error naming the earlier declaration; class_alias only warns
class Order {}
interface Payable {}
class_alias('Order', 'Purchase');
var_dump(class_alias('\Order', 'Payable'));
var_dump(class_alias('Order', 'stdClass'));
var_dump(class_alias('Order', 'PURCHASE'));
function declare_again() {
    eval('class Order {}');
}
echo "declaring\n";
declare_again();
echo "not reached\n";

<?php
// __wakeup turns the properties unserialize() set into elements and drops
// them in one pass, keeping internal state and handling many of them
$a = new SplFixedArray();
for ($i = 0; $i < 50000; $i++) {
    @$a->{$i} = $i * 2;
}
$a->{'name'} = 'kept?';
@$a->__wakeup();
var_dump($a->getSize(), $a[0], $a[49999], $a[50000], get_object_vars($a));
$b = unserialize('O:13:"SplFixedArray":3:{i:0;s:1:"x";i:1;s:1:"y";s:1:"k";i:5;}');
var_dump($b);

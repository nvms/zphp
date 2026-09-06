<?php
class B {public $a=[1];}
function readit($v){}
$b=new B;readit($b->a[0]);$c=$b->a;$c[0]=3;var_dump($b->a);
function change(&$v,$unused){$v=7;}
function later(){global $b;$b->a[0]=5;return 0;}
change($b->a[0],later());var_dump($b->a);

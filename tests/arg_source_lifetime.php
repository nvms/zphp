<?php
class Box { public $x=1; function __destruct(){echo "destroy\n";} }
function make(){return new Box;}
function later(){echo "later\n"; return 0;}
function change(&$x,$y){$x=9;echo "change=$x\n";}
change(make()->x,later());
$a=new Box;$b=$a;
function replace(){global $a;$a=new Box;return 0;}
change($a->x,replace());echo $b->x,':',$a->x,"\n";

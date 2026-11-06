<?php
// reading a property of something that isn't an object warns and reads null,
// except under isset, ?? and ?->
$nil = null;
echo $nil->x;
$i = 3;
$arr = [];
var_dump($i->y, $arr->p, "s"->len ?? 1);
var_dump($nil->x ?? "q", isset($nil->x), $nil?->x, @$nil->x);

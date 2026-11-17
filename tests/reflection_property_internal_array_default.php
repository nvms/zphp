<?php
class U { public $a = [1, 2, 3]; public $b = 'x'; }
for ($i = 0; $i < 1000; $i++) {
  $p = new ReflectionProperty('U', 'a'); $d = $p->getDefaultValue();
  $q = new ReflectionProperty('Exception', 'trace'); $q->getDefaultValue();
  if ($i == 5) $m = memory_get_usage();
}
var_dump(memory_get_usage() - $m, $d, (new U)->a, (new Exception)->getTrace());

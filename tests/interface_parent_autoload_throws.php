<?php
// an autoloader that throws while an interface loads its parent
spl_autoload_register(function ($c) { throw new Exception("no $c"); });
try { eval("interface B extends A {}"); } catch (Exception $e) { echo $e->getMessage(), "\n"; }
var_dump(interface_exists("B", false));
spl_autoload_register(function ($c) { if ($c === "A") { class X implements B {} } }, true, true);
try { eval("interface C extends A {}"); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }

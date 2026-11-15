<?php
// a class loads the interfaces it lists when it is declared
spl_autoload_register(function ($name) { echo "autoload $name\n"; if ($name === "Late") { eval("interface Late {}"); } });
try { eval("class C implements UndefI {}"); } catch (Error $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
var_dump(class_exists("C", false));
eval("class D implements Late {}");
var_dump(new D instanceof Late);
try { eval("interface J extends Missing {}"); } catch (Error $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }

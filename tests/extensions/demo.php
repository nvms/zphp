<?php
// exercised by tests/extensions/run against a dynamic build of demo.c and,
// with STATIC=1, against a zphp built with -Dextension=tests/extensions/demo.c
var_dump(extension_loaded("demo"), in_array("demo", get_loaded_extensions(), true));
var_dump(interface_exists("Demo\\Tally"), method_exists("Demo\\Counter", "increment"), class_exists("DemoException"), get_parent_class("DemoException"));
var_dump(demo_add(2, 3));
var_dump(demo_greet("world"));
var_dump(DEMO_VERSION, DEMO_ANSWER, DEMO_RATIO, DEMO_ENABLED);
var_dump(Demo\Counter::LIMIT, Demo\Counter::NAME);
$c = new Demo\Counter(4);
var_dump($c->increment()->increment(2)->value());
var_dump($c instanceof Demo\Tally);
var_dump(demo_describe($c));
var_dump(Demo\Counter::make(7)->value());
try { $c->increment(10); } catch (DemoException $e) { echo "caught: ", $e->getMessage(), "\n"; }
try { demo_throw("boom"); } catch (DemoException $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
var_dump(demo_stats([1, 2, 3, "name" => "x"]));
var_dump(demo_types(null, true, 1, 1.5, "s", [], $c));
var_dump(demo_apply("strtoupper", "abc"));
function twice($x) { return $x * 2; }
var_dump(demo_apply("twice", 21));
try { demo_apply("nope_missing", 1); } catch (Error $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
var_dump(demo_counter(), demo_counter(), demo_hits());
demo_echo("echoed\n");
var_dump(ini_get("demo.greeting"));
ini_set("demo.greeting", "hi");
var_dump(demo_greet("again"));
$b = demo_open(8);
var_dump(demo_write($b, "hello world"), demo_read($b));
var_dump(get_class($b));
var_dump(demo_freed());
unset($b);
var_dump(demo_freed());
function scoped() { $x = demo_open(4); demo_write($x, "zz"); }
scoped();
var_dump(demo_freed());
function throws() { $x = demo_open(4); throw new RuntimeException("mid"); }
try { throws(); } catch (RuntimeException $e) { echo "unwound\n"; }
var_dump(demo_freed());
try { demo_read("not a buffer"); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
$probe = demo_open(4);
var_dump(get_object_vars($probe), (new ReflectionClass($probe))->getProperties());
$probe->__ext_ptr = 0x41414141;
$probe->__ext_type = 99;
var_dump(demo_write($probe, "still mine"), demo_read($probe));
try { $copy = clone $probe; } catch (Error $e) { echo $e->getMessage(), "\n"; }
unset($probe);
var_dump(demo_freed());
$keep = demo_open(2);
register_shutdown_function(function () { echo "shutdown sees ", demo_add(1, 1), "\n"; });
echo "done\n";

<?php
// an exception a destructor throws while values are freed stays in flight
// when the next freed object's destructor runs statements of its own

class ThrowOnFree {
    public function __destruct() { throw new Exception('dtor'); }
}
class Value {
    public function __destruct() { $x = strlen('abc'); }
}

function f() { $local = new ThrowOnFree(); return new Value(); }
try { f(); echo "no exception 1\n"; } catch (Exception $e) { echo "1: ", $e->getMessage(), "\n"; }

class C {
    public $h {
        get {
            $local = new ThrowOnFree();
            return new Value();
        }
    }
}
try { (new C)->h; echo "no exception 2\n"; } catch (Exception $e) { echo "2: ", $e->getMessage(), "\n"; }
try { $x = (new C)->h; echo "no exception 3\n"; } catch (Exception $e) { echo "3: ", $e->getMessage(), "\n"; }
$c = new C;
try { $c->h; echo "no exception 4\n"; } catch (Exception $e) { echo "4: ", $e->getMessage(), "\n"; }

function g() {
    $a = new ThrowOnFree();
    $b = new Value();
    $c = new Value();
}
try { g(); echo "no exception 5\n"; } catch (Exception $e) { echo "5: ", $e->getMessage(), "\n"; }
echo "done\n";

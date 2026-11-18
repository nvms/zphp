<?php
// an increment or assign-op on an unset declared property warns, and reads
// the value an error handler wrote to it meanwhile

class C {
    public $a;
    public $n;

    public function handler($no, $msg) {
        echo "handler: $msg\n";
        if (str_contains($msg, '$a')) $this->a = new stdClass;
        if (str_contains($msg, '$n')) $this->n = 10;
        return true;
    }
}

$c = new C;
set_error_handler([$c, 'handler']);
unset($c->a, $c->n);
try {
    ++$c->a;
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
var_dump($c->a);
$c->n += 5;
var_dump($c->n);
unset($c->n);
$c->n++;
var_dump($c->n);

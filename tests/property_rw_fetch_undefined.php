<?php
// an assign-op or increment on a missing property fetches it for
// read-modify-write: the dynamic property deprecation comes first, then the
// undefined property warning, and the property exists from then on, so a
// handler that writes it meanwhile is read back

class Plain {}

#[AllowDynamicProperties]
class Open {
    public function handler($no, $msg) {
        echo "handler: $msg\n";
        $this->a = 12345;
        return true;
    }
}

set_error_handler(function ($no, $msg) {
    echo "[$no] $msg\n";
    return true;
});
$o = new Plain;
$o->sum += 2;
$o->sum += 2;
$o->count++;
++$o->count;
$o->text .= 'x';
$name = 'dyn';
$o->$name -= 1;
$o->$name--;
var_dump($o);

$open = new Open;
set_error_handler([$open, 'handler']);
$open->a %= 10;
var_dump($open->a);
$open2 = new Open;
set_error_handler(function ($no, $msg) use ($open2) {
    echo "[$no] $msg\n";
    $open2->b = 'set by the handler';
    return true;
});
$open2->b .= '!';
var_dump($open2->b);
$open2->c++;
var_dump($open2->c);

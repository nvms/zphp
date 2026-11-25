<?php
// an exception's message that isn't a string is converted where php reads
// it as one: getMessage(), __toString() and the uncaught error
class Lazy {
    function __toString(): string { echo "converting\n"; return "Foobar"; }
}
class E extends Exception {
    public $message;
    function __construct($m) { $this->message = $m; }
}
foreach ([new Lazy, 42, 1.5, null, true] as $m) {
    $e = new E($m);
    var_dump($e->getMessage());
    echo strtok((string) $e, "\n"), "\n";
}
throw new E(new Lazy);

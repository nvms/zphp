<?php
// an object whose constructor throws never has its destructor called, even
// when something still holds it

class Throws {
    public function __construct(public string $name, bool $keep = false) {
        if ($keep) $GLOBALS['kept'] = $this;
        throw new Exception("ctor {$name}");
    }
    public function __destruct() {
        echo "destruct {$this->name}\n";
    }
}

class Fine {
    public function __construct(public string $name) {}
    public function __destruct() {
        echo "destruct {$this->name}\n";
    }
}

class Child extends Throws {
    public function __construct() {
        parent::__construct('child');
    }
}

try {
    new Throws('plain');
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}

try {
    $x = new Throws('assigned');
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
var_dump(isset($x));

try {
    new Throws('kept', true);
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
echo "kept: ", $kept->name, "\n";
unset($kept);
echo "after unset\n";

try {
    new Child();
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}

$cls = 'Throws';
try {
    new $cls('dynamic');
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}

class Inner {
    public function __construct() {
        $this->fine = new Fine('inner');
        throw new Exception('inner ctor');
    }
    public $fine;
    public function __destruct() {
        echo "destruct Inner\n";
    }
}

try {
    new Inner();
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}

function make() {
    try {
        return new Throws('in function');
    } catch (Exception $e) {
        return $e->getMessage();
    }
}
echo make(), "\n";

$ok = new Fine('survivor');
echo "end\n";

<?php
// Exception::__construct writes $code through a subclass's set hook, and a
// hook that throws ends the constructor

class MyException extends Exception {
    private bool $modified = false;

    protected $code {
        set($value) {
            echo "set code $value\n";
            if ($this->modified) {
                throw new Exception("again");
            }
            $this->modified = true;
            $this->code = $value;
        }
    }
}

$e = new MyException("foo", 1, new Exception());
try {
    $e->__construct("bar", 2, null);
} catch (Exception $x) {
    echo $x->getMessage(), "\n";
}
var_dump($e->getMessage(), $e->getCode(), $e->getPrevious()::class);

class MyErrorException extends ErrorException {
    protected $code {
        set($value) {
            $this->code = $value * 10;
        }
    }
}
$e = new MyErrorException("m", 3, E_WARNING);
var_dump($e->getCode(), $e->getSeverity());

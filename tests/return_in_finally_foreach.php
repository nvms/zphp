<?php
// a return inside a finally that runs on the way out of another return
// from inside foreach loops: the loops are ended once, and the first
// return's value is dropped for the second

class D {
    public function __construct(public string $n) {}
    public function __destruct() { echo "destruct {$this->n}\n"; }
}

function plain() {
    foreach ([1, 2, 3] as $v) {
        try {
            echo "try $v\n";
            return;
        } finally {
            echo "finally $v\n";
            return;
        }
    }
}
plain();

function nested() {
    foreach ([0] as $_) {
        foreach ([1] as $v) {
            try {
                return "first";
            } finally {
                return "second";
            }
        }
    }
}
var_dump(nested());

function replaced($x) {
    foreach ($x as $v) {
        try {
            return str_repeat("a", 2);
        } finally {
            return 42;
        }
    }
}
var_dump(replaced([1]));

function objects() {
    foreach ([1] as $v) {
        try {
            return new D("first");
        } finally {
            echo "in finally\n";
            return new D("second");
        }
    }
}
$r = objects();
echo "got {$r->n}\n";
unset($r);

function gen() {
    try {
        yield 1;
        yield 2;
    } finally {
        echo "generator closed\n";
    }
}

function overGenerator() {
    foreach (gen() as $v) {
        try {
            return "try $v";
        } finally {
            foreach ([7, 8] as $w) {
                if ($w === 8) return "finally $v $w";
            }
        }
    }
}
var_dump(overGenerator());

function nestedFinally() {
    foreach ([1] as $v) {
        try {
            return "outer";
        } finally {
            try {
                return "middle";
            } finally {
                foreach ([2] as $w) {
                    return "inner $w";
                }
            }
        }
    }
}
var_dump(nestedFinally());

echo "done\n";

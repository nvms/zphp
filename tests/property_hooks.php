<?php

// short-form get hook
class Upper {
    public string $name = "alice";
    public string $shouty {
        get => strtoupper($this->name);
    }
}
$u = new Upper();
echo $u->shouty . "\n";

// short-form set hook with type
class Trimmed {
    public string $value {
        set(string $v) => trim($v);
    }
}
$t = new Trimmed();
$t->value = "  hello  ";
echo "[" . $t->value . "]\n";

// block-form get
class Counter {
    public int $count = 0;
    public int $double {
        get { return $this->count * 2; }
    }
}
$c = new Counter();
$c->count = 7;
echo $c->double . "\n";

// block-form set with raw write inside
class User {
    public string $name {
        get => strtoupper($this->name);
        set(string $v) {
            $this->name = trim($v);
        }
    }
}
$u = new User();
$u->name = "  bob  ";
echo $u->name . "\n";

// hook with logic
class Temperature {
    public float $celsius = 0.0;
    public float $fahrenheit {
        get => $this->celsius * 9 / 5 + 32;
        set(float $f) {
            $this->celsius = ($f - 32) * 5 / 9;
        }
    }
}
$temp = new Temperature();
$temp->celsius = 100;
echo $temp->fahrenheit . "\n";
$temp->fahrenheit = 32;
echo $temp->celsius . "\n";

// recursive raw access in set
class Validated {
    public int $age {
        set(int $v) {
            if ($v < 0) $v = 0;
            $this->age = $v;
        }
    }
}
$v = new Validated();
$v->age = -5;
echo $v->age . "\n";
$v->age = 25;
echo $v->age . "\n";

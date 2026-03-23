<?php

class Account {
    public $name;
    protected $balance;
    private $pin;

    public function __construct($name, $balance, $pin) {
        $this->name = $name;
        $this->balance = $balance;
        $this->pin = $pin;
    }

    public function getName() {
        return $this->name;
    }

    protected function getBalance() {
        return $this->balance;
    }

    private function getPin() {
        return $this->pin;
    }

    public function describe() {
        // can access all own members
        return $this->name . ":" . $this->getBalance() . ":" . $this->getPin();
    }
}

class SavingsAccount extends Account {
    public function showBalance() {
        // can access protected parent member
        return $this->name . " has " . $this->getBalance();
    }
}

$a = new Account("Alice", 100, 1234);
echo $a->getName() . "\n";
echo $a->describe() . "\n";

$s = new SavingsAccount("Bob", 200, 5678);
echo $s->showBalance() . "\n";

// test that private method is blocked from outside
$caught = false;
try {
    $a->getPin();
} catch (\Error $e) {
    $caught = true;
}
echo $caught ? "private method blocked" : "ERROR: private method accessible";
echo "\n";

// test that private property is blocked from outside
$caught2 = false;
try {
    $x = $a->pin;
} catch (\Error $e) {
    $caught2 = true;
}
echo $caught2 ? "private property blocked" : "ERROR: private property accessible";
echo "\n";

// test that protected method is blocked from outside
$caught3 = false;
try {
    $a->getBalance();
} catch (\Error $e) {
    $caught3 = true;
}
echo $caught3 ? "protected method blocked" : "ERROR: protected method accessible";
echo "\n";

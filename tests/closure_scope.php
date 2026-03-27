<?php

class Wallet {
    private float $balance = 100.0;
    protected string $currency = "USD";

    private function debit(float $amount): void {
        $this->balance -= $amount;
    }
}

// access private property via explicit scope binding
$getBalance = Closure::bind(function() {
    return $this->balance;
}, new Wallet(), 'Wallet');
echo $getBalance() . "\n"; // 100

// call private method via scope binding
$spend = Closure::bind(function(float $amount) {
    $this->debit($amount);
    return $this->balance;
}, new Wallet(), 'Wallet');
echo $spend(30) . "\n"; // 70

// scope from object instance (third arg is object)
$w = new Wallet();
$fn = Closure::bind(function() {
    return $this->balance;
}, $w, $w);
echo $fn() . "\n"; // 100

// access protected property via scope
$getCurrency = Closure::bind(function() {
    return $this->currency;
}, new Wallet(), 'Wallet');
echo $getCurrency() . "\n"; // USD

// bindTo with explicit scope
$fn2 = $getBalance->bindTo(new Wallet(), 'Wallet');
echo $fn2() . "\n"; // 100

// Closure::call implicitly uses object's class as scope
$callResult = (function() {
    return $this->balance;
})->call(new Wallet());
echo $callResult . "\n"; // 100

// call with private method
$callDebit = (function(float $amount) {
    $this->debit($amount);
    return $this->balance;
})->call(new Wallet(), 25);
echo $callDebit . "\n"; // 75

// captures preserved with scope binding
$multiplier = 2;
$doubleBalance = Closure::bind(function() use ($multiplier) {
    return $this->balance * $multiplier;
}, new Wallet(), 'Wallet');
echo $doubleBalance() . "\n"; // 200

// scope preserved through rebind (bindTo without scope arg keeps existing scope)
$rebound = $getBalance->bindTo(new Wallet());
echo $rebound() . "\n"; // 100

// inheritance: scope grants access to parent's protected members
class PremiumWallet extends Wallet {}
$premFn = Closure::bind(function() {
    return $this->currency;
}, new PremiumWallet(), 'Wallet');
echo $premFn() . "\n"; // USD

// closure defined inside a class method inherits class scope
class Account {
    private int $id = 42;
    public function makeGetter(): Closure {
        return function() {
            return $this->id;
        };
    }
}

$acc = new Account();
$getter = $acc->makeGetter();
echo $getter() . "\n"; // 42

// rebind class-scoped closure to different instance preserves scope
$acc2 = new Account();
$getter2 = $getter->bindTo($acc2);
echo $getter2() . "\n"; // 42

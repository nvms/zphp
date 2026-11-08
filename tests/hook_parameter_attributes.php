<?php
// a set hook's parameter may carry attributes
class Account {
    public string $secret {
        set (#[SensitiveParameter] string $value) { $this->secret = strrev($value); }
    }
}
$a = new Account;
$a->secret = 'abc';
echo $a->secret, "\n";

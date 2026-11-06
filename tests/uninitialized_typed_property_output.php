<?php
// a typed property that was never initialized shows as uninitialized(type)
// in var_dump, outside its count, and nowhere else
class Account {
    public $name = 'a';
    public int $id;
    protected string $secret;
    private array $roles;
}
$a = new Account;
var_dump($a);
print_r($a);
echo "\n";
var_export($a);
echo "\n";
var_dump((array)$a, json_encode($a), get_object_vars($a), serialize($a));
foreach ($a as $k => $v) echo "$k\n";

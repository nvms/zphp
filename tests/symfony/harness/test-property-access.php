<?php
// exercises symfony/property-access - reflection on getters/setters, nested
// array access, magic methods. stresses zphp's class introspection
require __DIR__ . '/../app/vendor/autoload.php';

use Symfony\Component\PropertyAccess\PropertyAccess;

class Address {
    private string $city;
    private string $zip;
    public function __construct(string $city, string $zip) { $this->city = $city; $this->zip = $zip; }
    public function getCity(): string { return $this->city; }
    public function getZip(): string { return $this->zip; }
    public function setCity(string $v): void { $this->city = $v; }
}

class Person {
    public string $name;
    private Address $address;
    private array $tags = [];
    public function __construct(string $name, Address $addr) { $this->name = $name; $this->address = $addr; }
    public function getAddress(): Address { return $this->address; }
    public function getTags(): array { return $this->tags; }
    public function setTags(array $t): void { $this->tags = $t; }
}

$pa = PropertyAccess::createPropertyAccessor();
$p = new Person('Alice', new Address('Berlin', '10115'));

echo "name: ", $pa->getValue($p, 'name'), "\n";
echo "city: ", $pa->getValue($p, 'address.city'), "\n";
echo "zip: ", $pa->getValue($p, 'address.zip'), "\n";

$pa->setValue($p, 'name', 'Bob');
echo "renamed: ", $pa->getValue($p, 'name'), "\n";

$pa->setValue($p, 'address.city', 'Munich');
echo "moved: ", $pa->getValue($p, 'address.city'), "\n";

$pa->setValue($p, 'tags', ['admin', 'editor']);
echo "tag0: ", $pa->getValue($p, 'tags[0]'), "\n";
echo "tag1: ", $pa->getValue($p, 'tags[1]'), "\n";

// readable / writable detection
echo "name readable: ", $pa->isReadable($p, 'name') ? 'y' : 'n', "\n";
echo "zip writable via setZip: ", $pa->isWritable($p, 'address.zip') ? 'y' : 'n', "\n";

// array path
$data = ['users' => [['name' => 'A'], ['name' => 'B']]];
echo "user0 name: ", $pa->getValue($data, '[users][0][name]'), "\n";

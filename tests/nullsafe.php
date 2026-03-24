<?php

class Address {
    public string $city;
    public string $street;

    public function __construct(string $city, string $street) {
        $this->city = $city;
        $this->street = $street;
    }

    public function getCity(): string {
        return $this->city;
    }

    public function getFormatted(): string {
        return $this->street . ", " . $this->city;
    }
}

class User {
    public ?string $name;
    public $address;

    public function __construct(?string $name, $address = null) {
        $this->name = $name;
        $this->address = $address;
    }

    public function getAddress() {
        return $this->address;
    }

    public function getName(): ?string {
        return $this->name;
    }
}

// basic nullsafe property access on non-null
$user = new User("Alice", new Address("NYC", "123 Main St"));
echo $user?->name . "\n";

// basic nullsafe property access on null
$nobody = null;
echo var_export($nobody?->name, true) . "\n";

// nullsafe method call on non-null
echo $user?->getName() . "\n";

// nullsafe method call on null
echo var_export($nobody?->getName(), true) . "\n";

// chained nullsafe
echo $user?->getAddress()?->getCity() . "\n";

// chained where first is null
echo var_export($nobody?->getAddress()?->getCity(), true) . "\n";

// chained where second returns null
$noaddr = new User("Bob", null);
echo var_export($noaddr?->getAddress()?->getCity(), true) . "\n";

// mixed chain: regular -> then ?->
echo $user->getAddress()?->getCity() . "\n";

// nullsafe property on nested
echo $user?->address?->city . "\n";

// nullsafe with method arguments
class Calculator {
    public function add(int $a, int $b): int {
        return $a + $b;
    }
}

$calc = new Calculator();
$nullCalc = null;
echo $calc?->add(3, 4) . "\n";
echo var_export($nullCalc?->add(3, 4), true) . "\n";

echo "done\n";

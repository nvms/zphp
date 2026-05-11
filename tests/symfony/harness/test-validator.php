<?php
// exercises symfony/validator with attribute-based constraints
require __DIR__ . '/../app/vendor/autoload.php';

use Symfony\Component\Validator\Validation;
use Symfony\Component\Validator\Constraints as Assert;

class User {
    public function __construct(
        #[Assert\NotBlank]
        #[Assert\Length(min: 2, max: 50)]
        public string $name,

        #[Assert\Email]
        public string $email,

        #[Assert\Range(min: 0, max: 150)]
        public int $age,

        #[Assert\Choice(choices: ['admin', 'user', 'guest'])]
        public string $role,

        #[Assert\Regex(pattern: '/^\d{5}$/', message: 'zip must be 5 digits')]
        public string $zip,
    ) {}
}

$validator = Validation::createValidatorBuilder()
    ->enableAttributeMapping()
    ->getValidator();

function report(iterable $vs): void {
    if (count($vs) === 0) { echo "OK\n"; return; }
    foreach ($vs as $v) {
        echo "  ", $v->getPropertyPath(), ": ", $v->getMessage(), "\n";
    }
}

echo "valid user: "; report($validator->validate(new User('Alice', 'a@b.com', 30, 'admin', '12345')));
echo "blank name: "; report($validator->validate(new User('', 'a@b.com', 30, 'admin', '12345')));
echo "short name: "; report($validator->validate(new User('A', 'a@b.com', 30, 'admin', '12345')));
echo "bad email: "; report($validator->validate(new User('Alice', 'not-an-email', 30, 'admin', '12345')));
echo "out of range: "; report($validator->validate(new User('Alice', 'a@b.com', 200, 'admin', '12345')));
echo "bad role: "; report($validator->validate(new User('Alice', 'a@b.com', 30, 'banned', '12345')));
echo "bad zip: "; report($validator->validate(new User('Alice', 'a@b.com', 30, 'admin', 'abc')));

$err = $validator->validate('not-an-email', new Assert\Email());
echo "raw email: "; report($err);
$err = $validator->validate('valid@example.com', new Assert\Email());
echo "raw ok: "; report($err);

<?php

interface RuleInterface
{
    public function passes($value): bool;
    public function message(): string;
}

abstract class Rule implements RuleInterface
{
    protected string $field = "";

    public function setField(string $field): self
    {
        $this->field = $field;
        return $this;
    }
}

class Required extends Rule
{
    public function passes($value): bool
    {
        if ($value === null) return false;
        if (is_string($value) && trim($value) === "") return false;
        if (is_array($value) && count($value) === 0) return false;
        return true;
    }

    public function message(): string
    {
        return "{$this->field} is required";
    }
}

class MinLength extends Rule
{
    private int $min;

    public function __construct(int $min)
    {
        $this->min = $min;
    }

    public function passes($value): bool
    {
        return is_string($value) && strlen($value) >= $this->min;
    }

    public function message(): string
    {
        return "{$this->field} must be at least {$this->min} characters";
    }
}

class MaxLength extends Rule
{
    private int $max;

    public function __construct(int $max)
    {
        $this->max = $max;
    }

    public function passes($value): bool
    {
        return is_string($value) && strlen($value) <= $this->max;
    }

    public function message(): string
    {
        return "{$this->field} must be at most {$this->max} characters";
    }
}

class Email extends Rule
{
    public function passes($value): bool
    {
        return is_string($value) && str_contains($value, "@") && str_contains($value, ".");
    }

    public function message(): string
    {
        return "{$this->field} must be a valid email";
    }
}

class InList extends Rule
{
    private array $allowed;

    public function __construct(array $allowed)
    {
        $this->allowed = $allowed;
    }

    public function passes($value): bool
    {
        return in_array($value, $this->allowed, true);
    }

    public function message(): string
    {
        return "{$this->field} must be one of: " . implode(", ", $this->allowed);
    }
}

class Between extends Rule
{
    private int $min;
    private int $max;

    public function __construct(int $min, int $max)
    {
        $this->min = $min;
        $this->max = $max;
    }

    public function passes($value): bool
    {
        $num = is_numeric($value) ? intval($value) : 0;
        return $num >= $this->min && $num <= $this->max;
    }

    public function message(): string
    {
        return "{$this->field} must be between {$this->min} and {$this->max}";
    }
}

class CallbackRule extends Rule
{
    private $callback;
    private string $msg;

    public function __construct(callable $callback, string $msg)
    {
        $this->callback = $callback;
        $this->msg = $msg;
    }

    public function passes($value): bool
    {
        return ($this->callback)($value);
    }

    public function message(): string
    {
        return str_replace(":field", $this->field, $this->msg);
    }
}

class ValidationResult
{
    private bool $passed;
    private array $errors;

    public function __construct(bool $passed, array $errors = [])
    {
        $this->passed = $passed;
        $this->errors = $errors;
    }

    public function passes(): bool { return $this->passed; }
    public function fails(): bool { return !$this->passed; }
    public function errors(): array { return $this->errors; }

    public function errorsFor(string $field): array
    {
        return $this->errors[$field] ?? [];
    }

    public function firstError(string $field): ?string
    {
        $fieldErrors = $this->errorsFor($field);
        return count($fieldErrors) > 0 ? $fieldErrors[0] : null;
    }

    public function allErrors(): array
    {
        $all = [];
        foreach ($this->errors as $field => $messages) {
            foreach ($messages as $msg) {
                $all[] = $msg;
            }
        }
        return $all;
    }

    public function errorCount(): int
    {
        return count($this->allErrors());
    }

    public function __toString(): string
    {
        if ($this->passed) return "Validation passed";
        $lines = [];
        foreach ($this->errors as $field => $messages) {
            foreach ($messages as $msg) {
                $lines[] = "- $msg";
            }
        }
        return "Validation failed:\n" . implode("\n", $lines);
    }
}

class Validator
{
    private array $rules = [];

    public function field(string $name, ...$rules): self
    {
        if (!isset($this->rules[$name])) {
            $this->rules[$name] = [];
        }
        foreach ($rules as $rule) {
            if ($rule instanceof Rule) {
                $rule->setField($name);
            }
            $this->rules[$name][] = $rule;
        }
        return $this;
    }

    public function validate(array $data): ValidationResult
    {
        $errors = [];
        $passed = true;

        foreach ($this->rules as $field => $rules) {
            $value = $data[$field] ?? null;
            foreach ($rules as $rule) {
                if (!$rule->passes($value)) {
                    $passed = false;
                    if (!isset($errors[$field])) $errors[$field] = [];
                    $errors[$field][] = $rule->message();
                }
            }
        }

        return new ValidationResult($passed, $errors);
    }

    public static function make(array $fieldRules): self
    {
        $v = new self();
        foreach ($fieldRules as $field => $rules) {
            $v->field($field, ...$rules);
        }
        return $v;
    }
}

// === test: passing validation ===

$validator = new Validator();
$validator
    ->field("name", new Required(), new MinLength(2), new MaxLength(50))
    ->field("email", new Required(), new Email())
    ->field("role", new Required(), new InList(["admin", "user", "editor"]));

$goodData = [
    "name" => "Alice Johnson",
    "email" => "alice@example.com",
    "role" => "admin",
];

$result = $validator->validate($goodData);
echo "valid: " . var_export($result->passes(), true) . "\n";
echo "error count: " . $result->errorCount() . "\n";
echo $result . "\n";

// === test: failing validation ===

$badData = [
    "name" => "",
    "email" => "not-an-email",
    "role" => "superadmin",
];

$result2 = $validator->validate($badData);
echo "valid: " . var_export($result2->passes(), true) . "\n";
echo "errors:\n";
foreach ($result2->allErrors() as $err) echo "  $err\n";

echo "name errors: " . count($result2->errorsFor("name")) . "\n";
echo "first name error: " . $result2->firstError("name") . "\n";
echo "first email error: " . $result2->firstError("email") . "\n";

// === test: callback rules ===

$v2 = new Validator();
$v2->field("age",
    new Required(),
    new Between(18, 120),
    new CallbackRule(
        function ($val) { return $val !== 69; },
        ":field has an invalid value"
    )
);

$result3 = $v2->validate(["age" => 25]);
echo "age 25: " . var_export($result3->passes(), true) . "\n";

$result4 = $v2->validate(["age" => 10]);
echo "age 10: " . var_export($result4->passes(), true) . "\n";
echo "age 10 error: " . $result4->firstError("age") . "\n";

// === test: static factory ===

$v3 = Validator::make([
    "username" => [new Required(), new MinLength(3)],
    "password" => [new Required(), new MinLength(8)],
]);

$result5 = $v3->validate(["username" => "ab", "password" => "short"]);
echo "factory errors: " . $result5->errorCount() . "\n";
foreach ($result5->allErrors() as $e) echo "  $e\n";

// === test: missing fields ===

$result6 = $validator->validate([]);
echo "empty data errors: " . $result6->errorCount() . "\n";

// === test: __toString on failure ===

$small = new Validator();
$small->field("x", new Required());
$r = $small->validate([]);
echo $r . "\n";

echo "done\n";

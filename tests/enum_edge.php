<?php

// enum implementing interface
interface HasLabel {
    public function label();
}

enum Priority: int implements HasLabel {
    case Low = 1;
    case Medium = 2;
    case High = 3;

    public function label() {
        return match($this) {
            Priority::Low => "low priority",
            Priority::Medium => "medium priority",
            Priority::High => "high priority",
        };
    }
}

echo Priority::High->label() . "\n";
echo Priority::Low->value . "\n";
echo Priority::Medium->name . "\n";

// from() with valid values
$p = Priority::from(2);
echo $p->name . "\n";

// tryFrom with invalid value
$invalid = Priority::tryFrom(99);
echo var_export($invalid === null, true) . "\n";

// enum cases() returns all
$cases = Priority::cases();
echo count($cases) . "\n";
foreach ($cases as $case) {
    echo $case->name . "=" . $case->value . " ";
}
echo "\n";

// backed enum value in expression
echo "Priority: " . Priority::High->value . "\n";

// enum identity
echo var_export(Priority::High === Priority::High, true) . "\n";
echo var_export(Priority::High === Priority::Low, true) . "\n";

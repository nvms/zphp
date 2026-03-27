<?php
// covers: ctype_alpha, ctype_digit, ctype_alnum, ctype_space, ctype_upper,
//   ctype_lower, ctype_xdigit, ctype_print, ctype_punct, substr_compare,
//   preg_match, strlen, trim, strtolower, strtoupper, sprintf, str_repeat,
//   in_array, array_keys, is_numeric, substr, strpos, str_contains

// ctype validation suite
echo "=== ctype functions ===\n";
$tests = [
    ['ctype_alpha', ['hello', 'Hello', 'hello world', 'abc123', '', '42']],
    ['ctype_digit', ['12345', '0', '3.14', '12 34', '', 'abc']],
    ['ctype_alnum', ['abc123', 'hello', '42', 'abc 123', 'abc!', '']],
    ['ctype_space', [" ", "\t\n", "  ", "hello", " x ", '']],
    ['ctype_upper', ['HELLO', 'Hello', 'ABC', 'ABC123', '', 'abc']],
    ['ctype_lower', ['hello', 'Hello', 'abc', 'abc123', '', 'ABC']],
    ['ctype_xdigit', ['1234af', 'DEADBEEF', '0x1f', 'ghij', '', 'cafe']],
    ['ctype_print', ['hello!', "hello\x00", 'abc 123', '', "tab\there"]],
    ['ctype_punct', ['!@#$', '...', 'abc!', '!!!', '', 'abc']],
];

foreach ($tests as $test) {
    $func = $test[0];
    echo "$func:\n";
    foreach ($test[1] as $input) {
        $display = str_replace(["\t", "\n", "\x00"], ["\\t", "\\n", "\\0"], $input);
        if ($display === '') $display = '(empty)';
        $result = $func($input);
        echo sprintf("  %-15s -> %s\n", "\"$display\"", $result ? 'true' : 'false');
    }
}

// substr_compare for prefix/suffix checking
echo "\n=== substr_compare ===\n";
function startsWith(string $haystack, string $prefix): bool {
    return substr_compare($haystack, $prefix, 0, strlen($prefix)) === 0;
}

function endsWith(string $haystack, string $suffix): bool {
    return substr_compare($haystack, $suffix, -strlen($suffix)) === 0;
}

$url = "https://api.example.com/v2/users.json";
echo "url: $url\n";
echo "starts with 'https://': " . (startsWith($url, 'https://') ? 'yes' : 'no') . "\n";
echo "starts with 'http://':  " . (startsWith($url, 'http://') ? 'yes' : 'no') . "\n";
echo "ends with '.json':      " . (endsWith($url, '.json') ? 'yes' : 'no') . "\n";
echo "ends with '.xml':       " . (endsWith($url, '.xml') ? 'yes' : 'no') . "\n";

// case-insensitive comparison
echo "\ncase-insensitive:\n";
echo "  'Hello' vs 'hello' at 0: " . substr_compare('Hello World', 'hello', 0, 5, true) . "\n";
echo "  'WORLD' vs 'world' at 6: " . substr_compare('Hello WORLD', 'world', 6, 5, true) . "\n";

// form validation engine
echo "\n=== form validation ===\n";

function validateField(string $name, string $value, array $rules): array {
    $errors = [];
    foreach ($rules as $rule) {
        if ($rule === 'required' && trim($value) === '') {
            $errors[] = "$name is required";
        } elseif ($rule === 'alpha' && $value !== '' && !ctype_alpha($value)) {
            $errors[] = "$name must contain only letters";
        } elseif ($rule === 'alnum' && $value !== '' && !ctype_alnum($value)) {
            $errors[] = "$name must be alphanumeric";
        } elseif ($rule === 'digits' && $value !== '' && !ctype_digit($value)) {
            $errors[] = "$name must contain only digits";
        } elseif ($rule === 'printable' && $value !== '' && !ctype_print($value)) {
            $errors[] = "$name contains non-printable characters";
        } elseif (substr_compare($rule, 'min:', 0, 4) === 0) {
            $min = (int)substr($rule, 4);
            if (strlen($value) < $min) {
                $errors[] = "$name must be at least $min characters";
            }
        } elseif (substr_compare($rule, 'max:', 0, 4) === 0) {
            $max = (int)substr($rule, 4);
            if (strlen($value) > $max) {
                $errors[] = "$name must be at most $max characters";
            }
        } elseif ($rule === 'email' && $value !== '') {
            if (!preg_match('/^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$/', $value)) {
                $errors[] = "$name must be a valid email";
            }
        }
    }
    return $errors;
}

$fields = [
    ['Username', 'john_doe', ['required', 'alnum', 'min:3', 'max:20']],
    ['Username', '', ['required', 'alnum', 'min:3', 'max:20']],
    ['Username', 'ab', ['required', 'alnum', 'min:3', 'max:20']],
    ['Username', 'john doe!', ['required', 'alnum', 'min:3', 'max:20']],
    ['Email', 'user@example.com', ['required', 'email']],
    ['Email', 'invalid-email', ['required', 'email']],
    ['Age', '25', ['required', 'digits']],
    ['Age', '25y', ['required', 'digits']],
    ['First Name', 'Alice', ['required', 'alpha', 'min:1', 'max:50']],
    ['First Name', 'Alice123', ['required', 'alpha', 'min:1', 'max:50']],
    ['Zip Code', '90210', ['required', 'digits', 'min:5', 'max:5']],
    ['Zip Code', '9021', ['required', 'digits', 'min:5', 'max:5']],
];

echo sprintf("  %-12s %-20s %s\n", "Field", "Value", "Result");
echo "  " . str_repeat("-", 60) . "\n";
foreach ($fields as $field) {
    $errors = validateField($field[0], $field[1], $field[2]);
    $display = $field[1] === '' ? '(empty)' : $field[1];
    if (count($errors) === 0) {
        echo sprintf("  %-12s %-20s ok\n", $field[0], $display);
    } else {
        echo sprintf("  %-12s %-20s %s\n", $field[0], $display, $errors[0]);
    }
}

// hex color validation
echo "\n=== hex color validation ===\n";
function isHexColor(string $color): bool {
    if ($color === '') return false;
    $hex = ltrim($color, '#');
    if (strlen($hex) !== 3 && strlen($hex) !== 6) return false;
    return ctype_xdigit($hex);
}

$colors = ['#ff0000', '#0f0', 'red', '#gghhii', '123abc', '#12', '#AABB00', ''];
foreach ($colors as $c) {
    $display = $c === '' ? '(empty)' : $c;
    echo sprintf("  %-12s %s\n", $display, isHexColor($c) ? 'valid' : 'invalid');
}

// password strength with ctype
echo "\n=== password strength ===\n";
function passwordStrength(string $pw): string {
    if (strlen($pw) < 8) return 'too short';
    $score = 0;
    $has_upper = false;
    $has_lower = false;
    $has_digit = false;
    $has_punct = false;
    for ($i = 0; $i < strlen($pw); $i++) {
        $ch = $pw[$i];
        if (ctype_upper($ch)) $has_upper = true;
        if (ctype_lower($ch)) $has_lower = true;
        if (ctype_digit($ch)) $has_digit = true;
        if (ctype_punct($ch)) $has_punct = true;
    }
    if ($has_upper) $score++;
    if ($has_lower) $score++;
    if ($has_digit) $score++;
    if ($has_punct) $score++;
    if (strlen($pw) >= 12) $score++;
    $labels = ['', 'weak', 'fair', 'good', 'strong', 'excellent'];
    return $labels[$score];
}

$passwords = ['abc', 'abcdefgh', 'Abcdefgh', 'Abcdefg1', 'Abcdefg1!', 'Tr0ub4dor&3!!'];
foreach ($passwords as $pw) {
    echo sprintf("  %-20s %s\n", $pw, passwordStrength($pw));
}

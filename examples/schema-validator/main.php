<?php
// covers: is_array, is_string, is_numeric, is_int, is_float, is_bool, is_null,
//         gettype, array_key_exists, array_keys, array_values, in_array, count,
//         preg_match, strlen, sprintf, implode, json_encode, json_decode,
//         array_map, array_merge, str_contains, is_callable, call_user_func

// --- schema validator ---

function validate($data, $schema, $path = '$') {
    $errors = [];

    if (!is_array($schema)) {
        $errors[] = "$path: schema must be an array";
        return $errors;
    }

    $type = $schema['type'] ?? null;

    if ($type !== null) {
        $valid = false;
        switch ($type) {
            case 'string':
                $valid = is_string($data);
                break;
            case 'integer':
                $valid = is_int($data);
                break;
            case 'float':
            case 'number':
                $valid = is_int($data) || is_float($data);
                break;
            case 'boolean':
                $valid = is_bool($data);
                break;
            case 'null':
                $valid = is_null($data);
                break;
            case 'array':
                $valid = is_array($data) && !isAssoc($data);
                break;
            case 'object':
                $valid = is_array($data) && (isAssoc($data) || empty($data));
                break;
            case 'any':
                $valid = true;
                break;
        }
        if (!$valid) {
            $actual = gettype($data);
            $errors[] = "$path: expected $type, got $actual";
            return $errors;
        }
    }

    // string constraints
    if (is_string($data)) {
        if (isset($schema['minLength']) && strlen($data) < $schema['minLength']) {
            $errors[] = "$path: string too short (min {$schema['minLength']})";
        }
        if (isset($schema['maxLength']) && strlen($data) > $schema['maxLength']) {
            $errors[] = "$path: string too long (max {$schema['maxLength']})";
        }
        if (isset($schema['pattern'])) {
            $pattern = $schema['pattern'];
            if (!preg_match($pattern, $data)) {
                $errors[] = "$path: does not match pattern $pattern";
            }
        }
        if (isset($schema['enum']) && !in_array($data, $schema['enum'])) {
            $allowed = implode(', ', $schema['enum']);
            $errors[] = "$path: must be one of: $allowed";
        }
        if (isset($schema['format'])) {
            $formatErrors = validateFormat($data, $schema['format'], $path);
            $errors = array_merge($errors, $formatErrors);
        }
    }

    // numeric constraints
    if (is_int($data) || is_float($data)) {
        if (isset($schema['minimum']) && $data < $schema['minimum']) {
            $errors[] = "$path: value too small (min {$schema['minimum']})";
        }
        if (isset($schema['maximum']) && $data > $schema['maximum']) {
            $errors[] = "$path: value too large (max {$schema['maximum']})";
        }
    }

    // array constraints (list)
    if (is_array($data) && !isAssoc($data) && $type === 'array') {
        if (isset($schema['minItems']) && count($data) < $schema['minItems']) {
            $errors[] = "$path: too few items (min {$schema['minItems']})";
        }
        if (isset($schema['maxItems']) && count($data) > $schema['maxItems']) {
            $errors[] = "$path: too many items (max {$schema['maxItems']})";
        }
        if (isset($schema['items'])) {
            foreach ($data as $i => $item) {
                $itemErrors = validate($item, $schema['items'], "{$path}[$i]");
                $errors = array_merge($errors, $itemErrors);
            }
        }
    }

    // object constraints
    if (is_array($data) && ($type === 'object' || $type === null) && isset($schema['properties'])) {
        $required = $schema['required'] ?? [];
        foreach ($required as $field) {
            if (!array_key_exists($field, $data)) {
                $errors[] = "$path.$field: required field missing";
            }
        }
        foreach ($schema['properties'] as $key => $propSchema) {
            if (array_key_exists($key, $data)) {
                $propErrors = validate($data[$key], $propSchema, "$path.$key");
                $errors = array_merge($errors, $propErrors);
            }
        }
    }

    return $errors;
}

function isAssoc($arr) {
    if (!is_array($arr) || empty($arr)) return false;
    return array_keys($arr) !== range(0, count($arr) - 1);
}

function validateFormat($value, $format, $path) {
    $errors = [];
    switch ($format) {
        case 'email':
            if (!preg_match('/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/', $value)) {
                $errors[] = "$path: invalid email format";
            }
            break;
        case 'url':
            $parts = parse_url($value);
            if (!$parts || !isset($parts['scheme']) || !isset($parts['host'])) {
                $errors[] = "$path: invalid URL format";
            }
            break;
        case 'date':
            if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $value)) {
                $errors[] = "$path: invalid date format (expected YYYY-MM-DD)";
            }
            break;
        case 'ipv4':
            $parts = explode('.', $value);
            if (count($parts) !== 4) {
                $errors[] = "$path: invalid IPv4 format";
            } else {
                foreach ($parts as $p) {
                    if (!is_numeric($p) || (int)$p < 0 || (int)$p > 255) {
                        $errors[] = "$path: invalid IPv4 format";
                        break;
                    }
                }
            }
            break;
    }
    return $errors;
}

// --- test helpers ---

function assertValid($data, $schema, $label) {
    $errors = validate($data, $schema);
    if (empty($errors)) {
        echo "PASS: $label\n";
    } else {
        echo "FAIL: $label\n";
        foreach ($errors as $e) echo "  - $e\n";
    }
}

function assertInvalid($data, $schema, $expectedCount, $label) {
    $errors = validate($data, $schema);
    if (count($errors) === $expectedCount) {
        echo "PASS: $label ($expectedCount errors)\n";
    } else {
        echo "FAIL: $label (expected $expectedCount errors, got " . count($errors) . ")\n";
        foreach ($errors as $e) echo "  - $e\n";
    }
}

// --- test: basic types ---

echo "--- basic types ---\n";
assertValid("hello", ['type' => 'string'], "string type");
assertValid(42, ['type' => 'integer'], "integer type");
assertValid(3.14, ['type' => 'number'], "float as number");
assertValid(42, ['type' => 'number'], "int as number");
assertValid(true, ['type' => 'boolean'], "boolean type");
assertValid(null, ['type' => 'null'], "null type");
assertInvalid(42, ['type' => 'string'], 1, "int is not string");
assertInvalid("42", ['type' => 'integer'], 1, "string is not integer");

// --- test: string constraints ---

echo "--- string constraints ---\n";
assertValid("hello", ['type' => 'string', 'minLength' => 3, 'maxLength' => 10], "string in range");
assertInvalid("hi", ['type' => 'string', 'minLength' => 3], 1, "string too short");
assertInvalid("hello world!!!", ['type' => 'string', 'maxLength' => 5], 1, "string too long");
assertValid("abc123", ['type' => 'string', 'pattern' => '/^[a-z0-9]+$/'], "pattern match");
assertInvalid("ABC", ['type' => 'string', 'pattern' => '/^[a-z]+$/'], 1, "pattern mismatch");
assertValid("red", ['type' => 'string', 'enum' => ['red', 'green', 'blue']], "enum valid");
assertInvalid("purple", ['type' => 'string', 'enum' => ['red', 'green', 'blue']], 1, "enum invalid");

// --- test: format validation ---

echo "--- format validation ---\n";
assertValid("user@example.com", ['type' => 'string', 'format' => 'email'], "valid email");
assertInvalid("not-an-email", ['type' => 'string', 'format' => 'email'], 1, "invalid email");
assertValid("https://example.com", ['type' => 'string', 'format' => 'url'], "valid url");
assertInvalid("not a url", ['type' => 'string', 'format' => 'url'], 1, "invalid url");
assertValid("2024-01-15", ['type' => 'string', 'format' => 'date'], "valid date");
assertInvalid("Jan 15", ['type' => 'string', 'format' => 'date'], 1, "invalid date");
assertValid("192.168.1.1", ['type' => 'string', 'format' => 'ipv4'], "valid ipv4");
assertInvalid("999.1.1.1", ['type' => 'string', 'format' => 'ipv4'], 1, "invalid ipv4");

// --- test: numeric constraints ---

echo "--- numeric constraints ---\n";
assertValid(5, ['type' => 'integer', 'minimum' => 0, 'maximum' => 10], "int in range");
assertInvalid(-1, ['type' => 'integer', 'minimum' => 0], 1, "int below minimum");
assertInvalid(100, ['type' => 'integer', 'maximum' => 50], 1, "int above maximum");

// --- test: array validation ---

echo "--- array validation ---\n";
assertValid([1, 2, 3], ['type' => 'array', 'items' => ['type' => 'integer']], "int array");
assertValid(["a", "b"], ['type' => 'array', 'items' => ['type' => 'string']], "string array");
assertInvalid([1, "two", 3], ['type' => 'array', 'items' => ['type' => 'integer']], 1, "mixed array");
assertValid([1, 2, 3], ['type' => 'array', 'minItems' => 2, 'maxItems' => 5], "array size ok");
assertInvalid([1], ['type' => 'array', 'minItems' => 2], 1, "array too small");

// --- test: object validation ---

echo "--- object validation ---\n";

$userSchema = [
    'type' => 'object',
    'required' => ['name', 'email'],
    'properties' => [
        'name' => ['type' => 'string', 'minLength' => 1, 'maxLength' => 100],
        'email' => ['type' => 'string', 'format' => 'email'],
        'age' => ['type' => 'integer', 'minimum' => 0, 'maximum' => 150],
        'role' => ['type' => 'string', 'enum' => ['admin', 'user', 'moderator']],
    ],
];

assertValid(
    ['name' => 'Alice', 'email' => 'alice@example.com', 'age' => 30, 'role' => 'admin'],
    $userSchema,
    "valid user"
);

assertInvalid(
    ['email' => 'alice@example.com'],
    $userSchema,
    1,
    "missing required name"
);

assertInvalid(
    ['name' => 'Bob', 'email' => 'not-email', 'age' => -5, 'role' => 'superadmin'],
    $userSchema,
    3,
    "multiple field errors"
);

// --- test: nested objects ---

echo "--- nested objects ---\n";

$addressSchema = [
    'type' => 'object',
    'required' => ['street', 'city', 'country'],
    'properties' => [
        'street' => ['type' => 'string', 'minLength' => 1],
        'city' => ['type' => 'string', 'minLength' => 1],
        'zip' => ['type' => 'string', 'pattern' => '/^\d{5}$/'],
        'country' => ['type' => 'string', 'minLength' => 2, 'maxLength' => 2],
    ],
];

$personSchema = [
    'type' => 'object',
    'required' => ['name', 'address'],
    'properties' => [
        'name' => ['type' => 'string'],
        'address' => $addressSchema,
    ],
];

assertValid(
    ['name' => 'Charlie', 'address' => ['street' => '123 Main', 'city' => 'Springfield', 'zip' => '62704', 'country' => 'US']],
    $personSchema,
    "valid nested object"
);

assertInvalid(
    ['name' => 'Dave', 'address' => ['street' => '456 Oak', 'city' => 'Portland', 'zip' => 'abc', 'country' => 'USA']],
    $personSchema,
    2,
    "nested validation errors"
);

// --- test: array of objects ---

echo "--- array of objects ---\n";

$teamSchema = [
    'type' => 'object',
    'required' => ['name', 'members'],
    'properties' => [
        'name' => ['type' => 'string'],
        'members' => [
            'type' => 'array',
            'minItems' => 1,
            'items' => [
                'type' => 'object',
                'required' => ['name', 'role'],
                'properties' => [
                    'name' => ['type' => 'string', 'minLength' => 1],
                    'role' => ['type' => 'string', 'enum' => ['lead', 'dev', 'qa']],
                ],
            ],
        ],
    ],
];

assertValid(
    ['name' => 'Backend', 'members' => [
        ['name' => 'Alice', 'role' => 'lead'],
        ['name' => 'Bob', 'role' => 'dev'],
    ]],
    $teamSchema,
    "valid team"
);

assertInvalid(
    ['name' => 'Frontend', 'members' => [
        ['name' => 'Carol', 'role' => 'lead'],
        ['name' => '', 'role' => 'invalid'],
    ]],
    $teamSchema,
    2,
    "team member errors"
);

// --- test: complex real-world schema ---

echo "--- real-world API response ---\n";

$apiResponseSchema = [
    'type' => 'object',
    'required' => ['status', 'data'],
    'properties' => [
        'status' => ['type' => 'integer', 'minimum' => 100, 'maximum' => 599],
        'message' => ['type' => 'string'],
        'data' => ['type' => 'any'],
        'errors' => [
            'type' => 'array',
            'items' => [
                'type' => 'object',
                'required' => ['code', 'message'],
                'properties' => [
                    'code' => ['type' => 'string'],
                    'message' => ['type' => 'string'],
                    'field' => ['type' => 'string'],
                ],
            ],
        ],
    ],
];

assertValid(
    ['status' => 200, 'data' => ['users' => []], 'message' => 'OK'],
    $apiResponseSchema,
    "valid success response"
);

assertValid(
    ['status' => 422, 'data' => null, 'errors' => [
        ['code' => 'REQUIRED', 'message' => 'Name is required', 'field' => 'name'],
        ['code' => 'INVALID', 'message' => 'Email is invalid', 'field' => 'email'],
    ]],
    $apiResponseSchema,
    "valid error response"
);

echo "done\n";

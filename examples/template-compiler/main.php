<?php
// covers: preg_replace_callback, preg_replace, preg_match_all, preg_split,
//         str_replace, substr, strpos, strlen, trim, ltrim, rtrim, explode, implode,
//         array_map, array_merge, array_key_exists, in_array, count,
//         sprintf, str_repeat, str_pad, strtoupper, strtolower, ucfirst,
//         is_array, is_string, is_numeric, json_encode, extract, compact

// --- simple template engine ---

function compile($template, $data) {
    $output = $template;

    // loops first (before variable interpolation, so loop vars aren't resolved prematurely)
    $output = preg_replace_callback('/\{%\s*for\s+(\w+)\s+in\s+(\w+)\s*%\}(.*?)\{%\s*endfor\s*%\}/s', function($matches) use ($data) {
        $varName = $matches[1];
        $listName = $matches[2];
        $body = $matches[3];
        $items = $data[$listName] ?? [];
        $result = '';
        foreach ($items as $index => $item) {
            $line = $body;
            if (is_array($item)) {
                foreach ($item as $k => $v) {
                    $line = str_replace("{{ {$varName}.{$k} }}", (string)$v, $line);
                }
            } else {
                $line = str_replace("{{ {$varName} }}", (string)$item, $line);
            }
            $line = str_replace("{{ loop.index }}", (string)($index + 1), $line);
            $result .= $line;
        }
        return $result;
    }, $output);

    // conditionals
    $output = preg_replace_callback('/\{%\s*if\s+(\w+)\s*%\}(.*?)\{%\s*endif\s*%\}/s', function($matches) use ($data) {
        $key = $matches[1];
        $body = $matches[2];
        $value = $data[$key] ?? null;
        if ($value) {
            return $body;
        }
        return '';
    }, $output);

    // variable interpolation last: {{ var }}
    $output = preg_replace_callback('/\{\{\s*(\w+(?:\.\w+)*)\s*\}\}/', function($matches) use ($data) {
        return resolve($data, $matches[1]);
    }, $output);

    return $output;
}

function resolve($data, $path) {
    $keys = explode('.', $path);
    $current = $data;
    foreach ($keys as $key) {
        if (is_array($current) && array_key_exists($key, $current)) {
            $current = $current[$key];
        } else {
            return '';
        }
    }
    if (is_array($current)) {
        return json_encode($current);
    }
    return (string)$current;
}

// --- test: variable interpolation ---

echo "--- variables ---\n";
$result = compile("Hello, {{ name }}!", ['name' => 'World']);
echo $result . "\n";

$result = compile("{{ greeting }}, {{ name }}! You have {{ count }} messages.", [
    'greeting' => 'Hi',
    'name' => 'Alice',
    'count' => 5,
]);
echo $result . "\n";

// --- test: nested access ---

echo "--- nested ---\n";
$result = compile("{{ user.name }} ({{ user.email }})", [
    'user' => ['name' => 'Bob', 'email' => 'bob@test.com'],
]);
echo $result . "\n";

$result = compile("City: {{ address.city }}, Zip: {{ address.zip }}", [
    'address' => ['city' => 'Portland', 'zip' => '97201'],
]);
echo $result . "\n";

// --- test: conditionals ---

echo "--- conditionals ---\n";
$result = compile("{% if admin %}[ADMIN] {% endif %}{{ name }}", [
    'admin' => true,
    'name' => 'Alice',
]);
echo $result . "\n";

$result = compile("{% if admin %}[ADMIN] {% endif %}{{ name }}", [
    'admin' => false,
    'name' => 'Bob',
]);
echo $result . "\n";

// --- test: loops ---

echo "--- loops ---\n";
$result = compile("{% for item in items %}* {{ item }}\n{% endfor %}", [
    'items' => ['apple', 'banana', 'cherry'],
]);
echo $result;

$result = compile("{% for user in users %}{{ loop.index }}. {{ user.name }} <{{ user.email }}>\n{% endfor %}", [
    'users' => [
        ['name' => 'Alice', 'email' => 'alice@test.com'],
        ['name' => 'Bob', 'email' => 'bob@test.com'],
        ['name' => 'Charlie', 'email' => 'charlie@test.com'],
    ],
]);
echo $result;

// --- test: filter pipeline ---

function applyFilter($value, $filter) {
    switch ($filter) {
        case 'upper': return strtoupper($value);
        case 'lower': return strtolower($value);
        case 'ucfirst': return ucfirst($value);
        case 'trim': return trim($value);
        case 'length': return (string)strlen($value);
        case 'reverse': return strrev($value);
        case 'repeat': return str_repeat($value, 2);
        default: return $value;
    }
}

function compileWithFilters($template, $data) {
    return preg_replace_callback('/\{\{\s*(\w+)\s*(?:\|\s*(\w+(?:\s*\|\s*\w+)*))?\s*\}\}/', function($matches) use ($data) {
        $value = (string)($data[$matches[1]] ?? '');
        if (isset($matches[2])) {
            $filters = array_map('trim', explode('|', $matches[2]));
            foreach ($filters as $f) {
                $value = applyFilter($value, $f);
            }
        }
        return $value;
    }, $template);
}

echo "--- filters ---\n";
echo compileWithFilters("{{ name | upper }}", ['name' => 'hello']) . "\n";
echo compileWithFilters("{{ name | lower }}", ['name' => 'HELLO']) . "\n";
echo compileWithFilters("{{ name | ucfirst }}", ['name' => 'hello world']) . "\n";
echo compileWithFilters("{{ name | upper | reverse }}", ['name' => 'hello']) . "\n";
echo compileWithFilters("{{ name | length }}", ['name' => 'hello']) . "\n";

// --- test: HTML escaping ---

function escapeHtml($str) {
    return str_replace(
        ['&', '<', '>', '"', "'"],
        ['&amp;', '&lt;', '&gt;', '&quot;', '&#039;'],
        $str
    );
}

echo "--- escaping ---\n";
$unsafe = '<script>alert("xss")</script>';
echo escapeHtml($unsafe) . "\n";
echo escapeHtml('Tom & Jerry "friends" <forever>') . "\n";

// --- test: indentation helper ---

function indent($text, $level, $char = '  ') {
    $prefix = str_repeat($char, $level);
    $lines = explode("\n", $text);
    $indented = array_map(function($line) use ($prefix) {
        return $line === '' ? '' : $prefix . $line;
    }, $lines);
    return implode("\n", $indented);
}

echo "--- indentation ---\n";
$code = "if (true) {\n    doSomething();\n}";
echo indent($code, 2) . "\n";

// --- test: string building at scale ---

echo "--- string building ---\n";
$parts = [];
for ($i = 0; $i < 100; $i++) {
    $parts[] = sprintf("item_%03d", $i);
}
$bigString = implode(', ', $parts);
echo "length: " . strlen($bigString) . "\n";
echo "first: " . substr($bigString, 0, 8) . "\n";
echo "last: " . substr($bigString, -8) . "\n";
echo "count: " . count(explode(', ', $bigString)) . "\n";

// --- test: tag parsing (preg_match_all) ---

echo "--- tag parsing ---\n";
$html = '<div class="main"><p id="intro">Hello</p><span class="highlight">World</span></div>';
preg_match_all('/<(\w+)(?:\s+[^>]*)?>/', $html, $matches);
echo "tags: " . implode(', ', $matches[1]) . "\n";
echo "count: " . count($matches[1]) . "\n";

// --- test: token splitting ---

echo "--- token split ---\n";
$expr = "  hello +  world  - foo * bar  ";
$tokens = preg_split('/\s*([+\-*\/])\s*/', trim($expr), -1, PREG_SPLIT_DELIM_CAPTURE | PREG_SPLIT_NO_EMPTY);
echo implode('|', $tokens) . "\n";
echo "tokens: " . count($tokens) . "\n";

echo "done\n";

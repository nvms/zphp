<?php
// covers: preg_split, str_getcsv, array_shift, array_pop, array_push, array_unshift,
//         array_slice, array_splice, trim, ltrim, rtrim, substr, strpos, strlen,
//         str_starts_with, str_ends_with, str_contains, str_replace, explode, implode,
//         array_map, array_filter, array_values, array_reverse, array_unique,
//         in_array, count, sprintf, str_pad, number_format, is_numeric,
//         array_fill, range, array_combine, array_chunk

// --- command tokenizer ---

function tokenize($input) {
    $tokens = [];
    $current = '';
    $inSingle = false;
    $inDouble = false;
    $escape = false;
    $len = strlen($input);

    for ($i = 0; $i < $len; $i++) {
        $ch = $input[$i];

        if ($escape) {
            $current .= $ch;
            $escape = false;
            continue;
        }

        if ($ch === '\\' && !$inSingle) {
            $escape = true;
            continue;
        }

        if ($ch === '"' && !$inSingle) {
            $inDouble = !$inDouble;
            continue;
        }

        if ($ch === "'" && !$inDouble) {
            $inSingle = !$inSingle;
            continue;
        }

        if ($ch === ' ' && !$inSingle && !$inDouble) {
            if ($current !== '') {
                $tokens[] = $current;
                $current = '';
            }
            continue;
        }

        $current .= $ch;
    }

    if ($current !== '') {
        $tokens[] = $current;
    }

    return $tokens;
}

echo "--- tokenizer ---\n";
echo implode('|', tokenize('echo hello world')) . "\n";
echo implode('|', tokenize('echo "hello world"')) . "\n";
echo implode('|', tokenize("echo 'hello world'")) . "\n";
echo implode('|', tokenize('echo "hello \\"world\\""')) . "\n";
echo implode('|', tokenize('  spaces   between   words  ')) . "\n";
echo implode('|', tokenize('mixed "quoted arg" plain \'single quoted\'')) . "\n";

// --- command parser ---

function parseCommand($input) {
    $tokens = tokenize(trim($input));
    if (empty($tokens)) return null;

    $cmd = array_shift($tokens);
    $args = [];
    $flags = [];
    $options = [];

    foreach ($tokens as $token) {
        if (str_starts_with($token, '--')) {
            $parts = explode('=', substr($token, 2), 2);
            if (count($parts) === 2) {
                $options[$parts[0]] = $parts[1];
            } else {
                $flags[] = $parts[0];
            }
        } elseif (str_starts_with($token, '-') && strlen($token) > 1 && !is_numeric($token)) {
            $chars = str_split(substr($token, 1));
            foreach ($chars as $c) {
                $flags[] = $c;
            }
        } else {
            $args[] = $token;
        }
    }

    return [
        'command' => $cmd,
        'args' => $args,
        'flags' => $flags,
        'options' => $options,
    ];
}

echo "--- parser ---\n";

$cmd = parseCommand('ls -la /home');
echo "cmd: {$cmd['command']}\n";
echo "args: " . implode(', ', $cmd['args']) . "\n";
echo "flags: " . implode(', ', $cmd['flags']) . "\n";

$cmd = parseCommand('git commit --message="initial commit" -a');
echo "cmd: {$cmd['command']}\n";
echo "args: " . implode(', ', $cmd['args']) . "\n";
echo "flags: " . implode(', ', $cmd['flags']) . "\n";
echo "message: {$cmd['options']['message']}\n";

$cmd = parseCommand('grep --ignore-case --color=always "search term" file.txt');
echo "cmd: {$cmd['command']}\n";
echo "args: " . implode(', ', $cmd['args']) . "\n";
echo "flags: " . implode(', ', $cmd['flags']) . "\n";
echo "color: {$cmd['options']['color']}\n";

// --- pipeline parser ---

function parsePipeline($input) {
    $segments = array_map('trim', explode('|', $input));
    $commands = [];
    foreach ($segments as $segment) {
        $cmd = parseCommand($segment);
        if ($cmd !== null) {
            $commands[] = $cmd;
        }
    }
    return $commands;
}

echo "--- pipeline ---\n";
$pipeline = parsePipeline('cat file.txt | grep error | sort -r | head -10');
echo "stages: " . count($pipeline) . "\n";
foreach ($pipeline as $i => $stage) {
    echo "  $i: {$stage['command']}";
    if (!empty($stage['args'])) echo " " . implode(' ', $stage['args']);
    if (!empty($stage['flags'])) echo " -" . implode('', $stage['flags']);
    echo "\n";
}

// --- variable expansion ---

function expandVars($input, $env) {
    $result = preg_replace_callback('/\$(\w+)|\$\{(\w+)\}/', function($m) use ($env) {
        $name = $m[1] !== '' ? $m[1] : $m[2];
        return $env[$name] ?? '';
    }, $input);
    return $result;
}

echo "--- variables ---\n";
$env = ['HOME' => '/home/user', 'USER' => 'alice', 'PATH' => '/usr/bin:/bin'];
echo expandVars('echo $HOME', $env) . "\n";
echo expandVars('Hello $USER, your home is ${HOME}', $env) . "\n";
echo expandVars('$UNDEFINED stays empty', $env) . "\n";

// --- history with array operations ---

echo "--- history ---\n";
$history = [];

array_push($history, 'ls -la');
array_push($history, 'cd /home');
array_push($history, 'cat file.txt');
array_push($history, 'grep error log.txt');
array_push($history, 'ls -la');

echo "history: " . count($history) . " entries\n";

$unique = array_values(array_unique($history));
echo "unique: " . count($unique) . " entries\n";

$reversed = array_reverse($history);
echo "last: {$reversed[0]}\n";

$filtered = array_filter($history, function($cmd) {
    return str_starts_with($cmd, 'ls') || str_starts_with($cmd, 'cat');
});
echo "ls/cat commands: " . count($filtered) . "\n";

// --- table formatting ---

function formatTable($headers, $rows) {
    $widths = array_map('strlen', $headers);
    foreach ($rows as $row) {
        foreach ($row as $i => $cell) {
            $cellLen = strlen((string)$cell);
            if ($cellLen > $widths[$i]) {
                $widths[$i] = $cellLen;
            }
        }
    }

    $lines = [];

    // header
    $headerCells = [];
    foreach ($headers as $i => $h) {
        $headerCells[] = str_pad($h, $widths[$i]);
    }
    $lines[] = implode(' | ', $headerCells);

    // separator
    $sepCells = [];
    foreach ($widths as $w) {
        $sepCells[] = str_repeat('-', $w);
    }
    $lines[] = implode('-+-', $sepCells);

    // rows
    foreach ($rows as $row) {
        $cells = [];
        foreach ($row as $i => $cell) {
            $cells[] = str_pad((string)$cell, $widths[$i]);
        }
        $lines[] = implode(' | ', $cells);
    }

    return implode("\n", $lines);
}

echo "--- table ---\n";
echo formatTable(
    ['PID', 'CMD', 'CPU', 'MEM'],
    [
        [1234, 'nginx', '2.5%', '128MB'],
        [5678, 'postgres', '15.2%', '1024MB'],
        [91011, 'node', '8.7%', '256MB'],
    ]
) . "\n";

// --- glob pattern matching ---

function globMatch($pattern, $string) {
    $regex = '/^';
    $len = strlen($pattern);
    for ($i = 0; $i < $len; $i++) {
        $ch = $pattern[$i];
        switch ($ch) {
            case '*':
                $regex .= '.*';
                break;
            case '?':
                $regex .= '.';
                break;
            case '.':
                $regex .= '\\.';
                break;
            default:
                $regex .= $ch;
        }
    }
    $regex .= '$/';
    return preg_match($regex, $string) === 1;
}

echo "--- glob ---\n";
echo "*.txt matches file.txt: " . (globMatch('*.txt', 'file.txt') ? 'yes' : 'no') . "\n";
echo "*.txt matches file.php: " . (globMatch('*.txt', 'file.php') ? 'yes' : 'no') . "\n";
echo "test?.log matches test1.log: " . (globMatch('test?.log', 'test1.log') ? 'yes' : 'no') . "\n";
echo "test?.log matches test12.log: " . (globMatch('test?.log', 'test12.log') ? 'yes' : 'no') . "\n";
echo "*.* matches any.file: " . (globMatch('*.*', 'any.file') ? 'yes' : 'no') . "\n";

// --- number formatting ---

echo "--- numbers ---\n";
echo number_format(1234567.89, 2) . "\n";
echo number_format(42, 0) . "\n";
echo number_format(1000000, 0, '.', ',') . "\n";
echo number_format(0.5, 4) . "\n";

// --- array operations ---

echo "--- array ops ---\n";

$items = range(1, 10);
echo "range: " . implode(', ', $items) . "\n";

$chunks = array_chunk($items, 3);
echo "chunks: " . count($chunks) . "\n";
echo "first chunk: " . implode(', ', $chunks[0]) . "\n";
echo "last chunk: " . implode(', ', $chunks[count($chunks) - 1]) . "\n";

$keys = ['a', 'b', 'c'];
$vals = [1, 2, 3];
$combined = array_combine($keys, $vals);
echo "combined: a={$combined['a']}, b={$combined['b']}, c={$combined['c']}\n";

$filled = array_fill(0, 5, 'x');
echo "filled: " . implode(', ', $filled) . "\n";

$sliced = array_slice($items, 2, 4);
echo "slice: " . implode(', ', $sliced) . "\n";

echo "done\n";

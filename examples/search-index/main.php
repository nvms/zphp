<?php
// covers: preg_split, mb_strtolower, array_filter, array_map, array_unique, usort, array_slice, array_merge, str_repeat, sprintf, log, sqrt, count, in_array, array_keys, array_values, generator yields, iterator_to_array, json_encode, json_decode, array_count_values, array_intersect_key, ksort

final class InvertedIndex {
    /** @var array<string, array<int, int>> term => doc_id => term_freq */
    private array $postings = [];
    /** @var array<int, array{title: string, body: string, len: int}> */
    private array $docs = [];
    /** @var array<int, int> doc_id => doc length in tokens */
    private array $doc_lens = [];
    private int $next_id = 1;

    private const STOP_WORDS = ['the', 'a', 'an', 'and', 'or', 'but', 'is', 'are', 'was', 'were', 'be', 'been', 'of', 'to', 'in', 'on', 'at', 'for', 'with', 'by', 'from'];

    public function add(string $title, string $body): int {
        $id = $this->next_id++;
        $tokens = $this->tokenize($title . ' ' . $body);
        $this->docs[$id] = ['title' => $title, 'body' => $body, 'len' => count($tokens)];
        $this->doc_lens[$id] = count($tokens);

        foreach (array_count_values($tokens) as $term => $freq) {
            $this->postings[$term] ??= [];
            $this->postings[$term][$id] = $freq;
        }
        return $id;
    }

    public function tokenize(string $text): array {
        $lower = mb_strtolower($text);
        $raw = preg_split('/[^a-z0-9]+/', $lower, -1, PREG_SPLIT_NO_EMPTY);
        $stopset = array_flip(self::STOP_WORDS);
        return array_values(array_filter($raw, fn($t) => !isset($stopset[$t]) && strlen($t) > 1));
    }

    public function avgDocLen(): float {
        if (count($this->doc_lens) === 0) return 0.0;
        return array_sum($this->doc_lens) / count($this->doc_lens);
    }

    /** @return Generator<array{id: int, score: float, title: string}> */
    public function search(string $query, int $top_k = 10): Generator {
        $terms = $this->tokenize($query);
        if (count($terms) === 0) return;

        $scores = [];
        $N = count($this->docs);
        $avgdl = $this->avgDocLen();
        $k1 = 1.5;
        $b = 0.75;

        foreach ($terms as $term) {
            if (!isset($this->postings[$term])) continue;
            $df = count($this->postings[$term]);
            $idf = log(1 + ($N - $df + 0.5) / ($df + 0.5));

            foreach ($this->postings[$term] as $doc_id => $tf) {
                $dl = $this->doc_lens[$doc_id];
                $norm = $tf * ($k1 + 1) / ($tf + $k1 * (1 - $b + $b * $dl / $avgdl));
                $scores[$doc_id] = ($scores[$doc_id] ?? 0.0) + $idf * $norm;
            }
        }

        $rows = [];
        foreach ($scores as $id => $score) {
            $rows[] = ['id' => $id, 'score' => $score, 'title' => $this->docs[$id]['title']];
        }
        usort($rows, fn($a, $b) => $b['score'] <=> $a['score']);

        foreach (array_slice($rows, 0, $top_k) as $row) {
            yield $row;
        }
    }

    public function snapshot(): string {
        return json_encode([
            'postings' => $this->postings,
            'docs' => $this->docs,
            'doc_lens' => $this->doc_lens,
            'next_id' => $this->next_id,
        ]);
    }

    public static function restore(string $blob): self {
        $data = json_decode($blob, true);
        $idx = new self();
        $idx->postings = $data['postings'];
        $idx->docs = array_map(fn($d) => ['title' => $d['title'], 'body' => $d['body'], 'len' => $d['len']], $data['docs']);
        $idx->doc_lens = $data['doc_lens'];
        $idx->next_id = $data['next_id'];
        return $idx;
    }
}

$idx = new InvertedIndex();
$idx->add('Introduction to Zig', 'Zig is a systems programming language designed for robustness, optimality, and clarity.');
$idx->add('PHP Performance Tuning', 'A guide to writing fast PHP code with profiling tools and opcode caching.');
$idx->add('Building a Compiler in Zig', 'Walkthrough of lexing, parsing, and code generation for a small language using Zig.');
$idx->add('Memory Models in Modern Runtimes', 'Compares garbage collection, reference counting, and arena allocation across PHP, Zig, and Rust.');
$idx->add('Optimizing Hot Loops', 'Techniques for reducing branch mispredictions and improving cache locality.');
$idx->add('Generators and Iterators', 'A practical look at lazy sequences, yield expressions, and iterator pipelines.');

echo "indexed " . count(iterator_to_array($idx->search('zig'))) . " hits for 'zig'\n";

foreach ($idx->search('zig compiler', 5) as $hit) {
    echo sprintf("  [%d] %.3f %s\n", $hit['id'], $hit['score'], $hit['title']);
}

echo "---\n";
foreach ($idx->search('php performance', 5) as $hit) {
    echo sprintf("  [%d] %.3f %s\n", $hit['id'], $hit['score'], $hit['title']);
}

echo "---\n";
foreach ($idx->search('memory generators', 3) as $hit) {
    echo sprintf("  [%d] %.3f %s\n", $hit['id'], $hit['score'], $hit['title']);
}

echo "---\n";
$blob = $idx->snapshot();
$restored = InvertedIndex::restore($blob);
echo "snapshot len: " . strlen($blob) . "\n";
foreach ($restored->search('zig compiler', 3) as $hit) {
    echo sprintf("  [%d] %.3f %s\n", $hit['id'], $hit['score'], $hit['title']);
}

// query parser: AND / OR / NOT (prefix !)
function parseQuery(InvertedIndex $idx, string $q): array {
    $parts = preg_split('/\s+/', trim($q));
    $must = [];
    $should = [];
    $must_not = [];
    foreach ($parts as $p) {
        if (str_starts_with($p, '!')) {
            $must_not[] = substr($p, 1);
        } elseif (str_starts_with($p, '+')) {
            $must[] = substr($p, 1);
        } else {
            $should[] = $p;
        }
    }
    return ['must' => $must, 'should' => $should, 'must_not' => $must_not];
}

$q = parseQuery($idx, '+zig compiler !php');
echo "parsed: must=" . implode(',', $q['must']) . " should=" . implode(',', $q['should']) . " not=" . implode(',', $q['must_not']) . "\n";

// boolean query execution
function executeBoolean(InvertedIndex $idx, array $q): array {
    $r = new ReflectionClass($idx);
    $postings = $r->getProperty('postings')->getValue($idx);

    $candidates = null;
    foreach ($q['must'] as $term) {
        $term = mb_strtolower($term);
        $hits = isset($postings[$term]) ? array_keys($postings[$term]) : [];
        $candidates = $candidates === null ? $hits : array_values(array_intersect($candidates, $hits));
    }
    if ($candidates === null) {
        $candidates = [];
        foreach ($q['should'] as $term) {
            $term = mb_strtolower($term);
            if (isset($postings[$term])) {
                $candidates = array_unique(array_merge($candidates, array_keys($postings[$term])));
            }
        }
    }
    foreach ($q['must_not'] as $term) {
        $term = mb_strtolower($term);
        if (!isset($postings[$term])) continue;
        $bad = array_keys($postings[$term]);
        $candidates = array_values(array_diff($candidates, $bad));
    }
    sort($candidates);
    return $candidates;
}

$q = parseQuery($idx, '+zig +compiler');
echo "must zig+compiler: " . implode(',', executeBoolean($idx, $q)) . "\n";

$q = parseQuery($idx, 'zig php !memory');
echo "zig|php not memory: " . implode(',', executeBoolean($idx, $q)) . "\n";

// highlight matched terms in body using preg_replace_callback
function highlight(string $text, array $terms): string {
    if (count($terms) === 0) return $text;
    $pattern = '/\b(' . implode('|', array_map('preg_quote', $terms)) . ')\b/i';
    return preg_replace_callback($pattern, fn($m) => '[' . $m[1] . ']', $text);
}

echo "---\n";
$snippet = $idx->snapshot();
$data = json_decode($snippet, true);
$body = $data['docs'][3]['body'];
echo highlight($body, ['zig', 'compiler', 'lexing']) . "\n";

// mb_* on multibyte strings
$mb = 'Café résumé naïve';
echo mb_strlen($mb) . " chars / " . strlen($mb) . " bytes\n";
echo mb_strtoupper($mb) . "\n";
echo mb_substr($mb, 5, 7) . "\n";

// merging sorted posting lists with a generator (skip-style join)
function mergeSorted(array $lists): Generator {
    $iters = array_map(fn($l) => (function() use ($l) { foreach ($l as $v) yield $v; })(), $lists);
    $heads = [];
    foreach ($iters as $k => $it) {
        if ($it->valid()) $heads[$k] = $it->current();
    }
    while (count($heads) > 0) {
        $min_key = array_keys($heads, min($heads), true)[0];
        yield $heads[$min_key];
        $iters[$min_key]->next();
        if ($iters[$min_key]->valid()) {
            $heads[$min_key] = $iters[$min_key]->current();
        } else {
            unset($heads[$min_key]);
        }
    }
}

$merged = iterator_to_array(mergeSorted([[1, 4, 7, 10], [2, 5, 8], [3, 6, 9, 11]]), false);
echo "merged: " . implode(',', $merged) . "\n";

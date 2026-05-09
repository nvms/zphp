<?php
// get_html_translation_table HTML_SPECIALCHARS
$hs = get_html_translation_table(HTML_SPECIALCHARS);
echo count($hs), "\n";   // 5 (with default ENT_QUOTES)
echo $hs['<'], "\n";
echo $hs['>'], "\n";
echo $hs['&'], "\n";
echo $hs['"'], "\n";
echo $hs["'"], "\n";

// without quotes
$hs2 = get_html_translation_table(HTML_SPECIALCHARS, ENT_NOQUOTES);
echo count($hs2), "\n";  // 3

// HTML_ENTITIES (with Latin-1)
$he = get_html_translation_table(HTML_ENTITIES);
var_dump(is_array($he));
echo count($he) > 5 ? "has-more\n" : "only-5\n";
echo isset($he['é']) ? "has-eacute\n" : "no-eacute\n";
echo isset($he['£']) ? "has-pound\n" : "no-pound\n";
echo $he['é'] ?? '?', "\n";
echo $he['©'] ?? '?', "\n";

// constants
echo HTML_SPECIALCHARS, "\n";
echo HTML_ENTITIES, "\n";

// SplPriorityQueue extracts by priority (highest first)
$pq = new SplPriorityQueue();
$pq->insert('a', 1);
$pq->insert('b', 10);
$pq->insert('c', 5);
echo $pq->extract(), "\n"; // b
echo $pq->extract(), "\n"; // c
echo $pq->extract(), "\n"; // a

// SplMinHeap / SplMaxHeap
$mh = new SplMinHeap();
$mh->insert(5); $mh->insert(1); $mh->insert(3);
echo $mh->extract(), "\n";
echo $mh->extract(), "\n";
echo $mh->extract(), "\n";

$xh = new SplMaxHeap();
$xh->insert(5); $xh->insert(1); $xh->insert(3);
echo $xh->extract(), "\n";

// array_combine duplicates: later wins
$r = array_combine([1, 2, 1, 3], ['a', 'b', 'c', 'd']);
print_r($r);

// sprintf flag combos
echo sprintf("%+05d", 42), "\n";
echo sprintf("%+05d", -42), "\n";
echo sprintf("% d", 42), "\n";
echo sprintf("% d", -42), "\n";
echo sprintf("%'#5d", 42), "\n";
echo sprintf("%-+5d|", 42), "\n";
echo sprintf("%05.2f", 1.5), "\n";
echo sprintf("%d%% done", 50), "\n";

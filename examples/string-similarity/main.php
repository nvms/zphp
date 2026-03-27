<?php
// covers: levenshtein, similar_text, soundex, metaphone, strtolower,
//   sprintf, str_pad, array_keys, array_values, usort, count, substr,
//   array_map, array_filter, implode, min, abs

// levenshtein: edit distance between strings
echo "=== levenshtein basics ===\n";
$pairs = [
    ['kitten', 'sitting'],
    ['saturday', 'sunday'],
    ['book', 'back'],
    ['', 'abc'],
    ['same', 'same'],
    ['php', 'PHP'],
];
foreach ($pairs as $pair) {
    $dist = levenshtein($pair[0], $pair[1]);
    echo sprintf("  %-12s -> %-12s distance=%d\n", $pair[0], $pair[1], $dist);
}

// spell checker using levenshtein
echo "\n=== spell checker ===\n";
$dictionary = ['accept', 'except', 'affect', 'effect', 'advice', 'advise',
    'practice', 'practise', 'license', 'licence', 'principal', 'principle'];

$misspelled = ['afect', 'advise', 'practisc', 'licsense', 'principl'];
foreach ($misspelled as $word) {
    $best = '';
    $best_dist = 999;
    foreach ($dictionary as $correct) {
        $dist = levenshtein($word, $correct);
        if ($dist < $best_dist) {
            $best_dist = $dist;
            $best = $correct;
        }
    }
    echo sprintf("  %-12s -> %-12s (distance: %d)\n", $word, $best, $best_dist);
}

// similar_text: longest common subsequence matching
echo "\n=== similar_text ===\n";
$comparisons = [
    ['World', 'Word'],
    ['Hello', 'Hallo'],
    ['PHP', 'PHP: Hypertext Preprocessor'],
    ['algorithm', 'altruistic'],
    ['abc', 'xyz'],
];
foreach ($comparisons as $pair) {
    $common = similar_text($pair[0], $pair[1], $percent);
    echo sprintf("  %-15s vs %-30s common=%d  pct=%.2f%%\n",
        $pair[0], $pair[1], $common, $percent);
}

// finding most similar strings
echo "\n=== find closest match ===\n";
$target = 'javascript';
$candidates = ['java', 'typescript', 'coffeescript', 'livescript', 'javafx', 'ecmascript'];
$scores = [];
foreach ($candidates as $c) {
    similar_text($target, $c, $pct);
    $scores[$c] = round($pct, 1);
}
arsort($scores);
echo "closest to '$target':\n";
$i = 0;
foreach ($scores as $name => $score) {
    echo sprintf("  %d. %-15s %.1f%%\n", $i + 1, $name, $score);
    $i++;
}

// soundex: phonetic algorithm
echo "\n=== soundex ===\n";
$names = [
    ['Robert', 'Rupert'],
    ['Smith', 'Smyth'],
    ['Johnson', 'Jonson'],
    ['Williams', 'Williamson'],
    ['Catherine', 'Katherine'],
];
foreach ($names as $pair) {
    $s1 = soundex($pair[0]);
    $s2 = soundex($pair[1]);
    $match = ($s1 === $s2) ? 'MATCH' : 'differ';
    echo sprintf("  %-12s (%s) vs %-12s (%s) -> %s\n", $pair[0], $s1, $pair[1], $s2, $match);
}

// phonetic search
echo "\n=== phonetic search ===\n";
$people = ['Steven', 'Stephen', 'Stefan', 'Stephan', 'Steve',
    'Stephanie', 'Stewart', 'Stuart'];
$search = 'Stephen';
$search_soundex = soundex($search);
echo "searching for names sounding like '$search' ($search_soundex):\n";
foreach ($people as $name) {
    $s = soundex($name);
    if ($s === $search_soundex) {
        echo "  $name ($s)\n";
    }
}

// metaphone
echo "\n=== metaphone ===\n";
$words = ['Thompson', 'Thomson', 'Tompson', 'Wright', 'Right', 'Rite'];
foreach ($words as $word) {
    echo sprintf("  %-12s -> %s\n", $word, metaphone($word));
}

// combined fuzzy matching score
echo "\n=== combined fuzzy matching ===\n";
function fuzzyScore(string $a, string $b): array {
    $lev = levenshtein(strtolower($a), strtolower($b));
    similar_text(strtolower($a), strtolower($b), $sim);
    $phonetic = (soundex($a) === soundex($b)) ? 1 : 0;
    $score = (100 - $lev * 10) * 0.4 + $sim * 0.4 + $phonetic * 20;
    return ['levenshtein' => $lev, 'similar' => round($sim, 1), 'phonetic' => $phonetic, 'score' => round($score, 1)];
}

$queries = [
    ['Michael', 'Micheal'],
    ['colour', 'color'],
    ['centre', 'center'],
    ['programme', 'program'],
];

echo sprintf("  %-12s %-12s %4s %6s %4s %6s\n", "String A", "String B", "Lev", "Sim%", "Phon", "Score");
echo "  " . str_repeat("-", 50) . "\n";
foreach ($queries as $pair) {
    $r = fuzzyScore($pair[0], $pair[1]);
    echo sprintf("  %-12s %-12s %4d %5.1f%% %4d %6.1f\n",
        $pair[0], $pair[1], $r['levenshtein'], $r['similar'], $r['phonetic'], $r['score']);
}

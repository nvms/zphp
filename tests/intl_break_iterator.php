<?php
// covers: IntlBreakIterator (word/sentence/line/grapheme boundary detection)

$text = "Hello, café world! It's 2:30pm. Naïve résumé.";

function dump(IntlBreakIterator $bi, string $text): void {
    $bi->setText($text);
    $pos = $bi->first();
    $prev = $pos;
    while (($pos = $bi->next()) !== IntlBreakIterator::DONE) {
        echo "  '", substr($text, $prev, $pos - $prev), "'@", $prev, "\n";
        $prev = $pos;
    }
}

echo "word boundaries:\n";
$bi = IntlBreakIterator::createWordInstance('en_US');
dump($bi, $text);

echo "sentence boundaries:\n";
$bi = IntlBreakIterator::createSentenceInstance('en_US');
dump($bi, $text);

echo "grapheme boundaries on 'résumé':\n";
$bi = IntlBreakIterator::createCharacterInstance('en_US');
$bi->setText("résumé");
$pos = $bi->first();
$prev = $pos;
while (($pos = $bi->next()) !== IntlBreakIterator::DONE) {
    echo "  '", substr("résumé", $prev, $pos - $prev), "'\n";
    $prev = $pos;
}

// navigation
$bi = IntlBreakIterator::createWordInstance('en_US');
$bi->setText("one two three four");
echo "first: ", $bi->first(), "\n";
echo "next: ", $bi->next(), "\n";
echo "next: ", $bi->next(), "\n";
echo "current: ", $bi->current(), "\n";
echo "last: ", $bi->last(), "\n";
echo "previous: ", $bi->previous(), "\n";
echo "following(5): ", $bi->following(5), "\n";
echo "preceding(8): ", $bi->preceding(8), "\n";
echo "isBoundary(4): ", $bi->isBoundary(4) ? 'y' : 'n', "\n";
echo "isBoundary(5): ", $bi->isBoundary(5) ? 'y' : 'n', "\n";

// rule status for word breaks distinguishes word vs whitespace
$bi = IntlBreakIterator::createWordInstance('en_US');
$bi->setText("foo bar 42");
$bi->first();
while (($pos = $bi->next()) !== IntlBreakIterator::DONE) {
    $status = $bi->getRuleStatus();
    $kind = ($status >= IntlBreakIterator::WORD_NUMBER && $status < IntlBreakIterator::WORD_NUMBER_LIMIT) ? 'number'
          : (($status >= IntlBreakIterator::WORD_LETTER && $status < IntlBreakIterator::WORD_LETTER_LIMIT) ? 'letter' : 'other');
    echo "  status=$status ($kind)\n";
}

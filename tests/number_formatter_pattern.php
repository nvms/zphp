<?php
// regression: NumberFormatter accepts an optional third $pattern argument
// for PATTERN_DECIMAL and PATTERN_RULEBASED styles. previously the pattern
// was discarded so format() produced the locale default

$nf = new NumberFormatter('en_US', NumberFormatter::PATTERN_DECIMAL, '#,##0.00');
echo $nf->format(1234.5) . "\n";
echo $nf->format(1234567.89) . "\n";
echo $nf->format(0.5) . "\n";

// pattern with negative subpattern
$nf = new NumberFormatter('en_US', NumberFormatter::PATTERN_DECIMAL, '#,##0.00;(#,##0.00)');
echo $nf->format(-1234.5) . "\n";

// pattern with percent
$nf = new NumberFormatter('en_US', NumberFormatter::PATTERN_DECIMAL, '0.00%');
echo $nf->format(0.85) . "\n";

// no pattern still defaults
$nf = new NumberFormatter('en_US', NumberFormatter::DECIMAL);
echo $nf->format(1234.5) . "\n";

// static create equivalents
$nf = NumberFormatter::create('en_US', NumberFormatter::PATTERN_DECIMAL, '0.000');
echo $nf->format(3.14) . "\n";

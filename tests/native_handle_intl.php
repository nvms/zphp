<?php
// covers: intl objects keep working after their old pointer-carrying property names are overwritten, and clone duplicates the ICU state

echo "--- Collator ---\n";
$coll = new Collator("en_US");
$coll->__coll = 0x41414141;
var_dump($coll->compare("apple", "banana"));
$coll->setStrength(Collator::PRIMARY);
var_dump($coll->getStrength());
var_dump(isset($coll->__coll));
try {
    $copy = clone $coll;
    echo "cloned\n";
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

echo "--- NumberFormatter ---\n";
$nf = new NumberFormatter("en_US", NumberFormatter::DECIMAL);
$nf->__nfmt = 0x41414141;
echo $nf->format(1234567.891), "\n";
var_dump(isset($nf->__nfmt));
$nf2 = clone $nf;
$nf2->setAttribute(NumberFormatter::MAX_FRACTION_DIGITS, 1);
echo $nf2->format(1234567.891), "\n";
echo $nf->format(1234567.891), "\n";
var_dump($nf2->parse("42.5"));

echo "--- IntlDateFormatter ---\n";
$df = new IntlDateFormatter("en_US", IntlDateFormatter::NONE, IntlDateFormatter::NONE, "UTC", null, "yyyy-MM-dd HH:mm");
$df->__dfmt = 0x41414141;
echo $df->format(86400 * 365), "\n";
var_dump(isset($df->__dfmt));
$df2 = clone $df;
$df2->setPattern("dd/MM/yyyy");
echo $df2->format(86400 * 365), "\n";
echo $df->format(86400 * 365), "\n";
echo $df->getPattern(), " | ", $df2->getPattern(), "\n";
var_dump($df2->parse("15/03/2021"));

echo "--- IntlCalendar ---\n";
$cal = IntlCalendar::createInstance("UTC", "en_US");
$cal->__cal = 0x41414141;
$cal->setTime(86400000.0 * 400);
var_dump($cal->get(IntlCalendar::FIELD_YEAR));
var_dump(isset($cal->__cal));
$cal2 = clone $cal;
$cal2->add(IntlCalendar::FIELD_YEAR, 5);
var_dump($cal->get(IntlCalendar::FIELD_YEAR), $cal2->get(IntlCalendar::FIELD_YEAR));

echo "--- IntlGregorianCalendar ---\n";
$greg = new IntlGregorianCalendar(2020, 1, 15);
$greg->__cal = 0x41414141;
var_dump($greg->get(IntlCalendar::FIELD_MONTH));
var_dump(isset($greg->__cal));
$greg2 = clone $greg;
$greg2->set(IntlCalendar::FIELD_YEAR, 1999);
var_dump($greg->get(IntlCalendar::FIELD_YEAR), $greg2->get(IntlCalendar::FIELD_YEAR));

echo "--- IntlBreakIterator ---\n";
$brk = IntlBreakIterator::createWordInstance("en_US");
$brk->__brk = 0x41414141;
$brk->setText("hello big world");
var_dump($brk->first());
var_dump($brk->next());
var_dump(isset($brk->__brk));
$brk2 = clone $brk;
var_dump($brk2->current());
var_dump($brk2->next());
var_dump($brk->current());
var_dump($brk2->getText());
$brk->setText("other text");
var_dump($brk2->getText());
var_dump($brk2->last());

echo "--- Transliterator ---\n";
$tr = Transliterator::create("Any-Upper");
$tr->__trans = 0x41414141;
echo $tr->transliterate("hello"), "\n";
var_dump(isset($tr->__trans));
$tr2 = clone $tr;
echo $tr2->transliterate("world"), "\n";
echo $tr2->id, "\n";

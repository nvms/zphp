<?php
// covers: Normalizer, Locale, Collator, NumberFormatter, Transliterator (via ICU)

// Normalizer
echo Normalizer::normalize("café"), "\n";
echo Normalizer::normalize("café", Normalizer::FORM_D) === "cafe\u{0301}" ? "NFD: ok\n" : "NFD: fail\n";
echo Normalizer::isNormalized("café") ? "isNorm: yes\n" : "isNorm: no\n";

// Locale
echo "default: ", Locale::getDefault() ?: "(empty)", "\n";
echo "lang: ", Locale::getPrimaryLanguage("en_US"), "\n";
echo "region: ", Locale::getRegion("fr_FR"), "\n";
echo "canon: ", Locale::canonicalize("en-us"), "\n";
echo "script: ", Locale::getScript("zh_Hans_CN"), "\n";

// NumberFormatter - decimal
$nf = new NumberFormatter('en_US', NumberFormatter::DECIMAL);
echo "us decimal: ", $nf->format(1234567.89), "\n";

$nf2 = new NumberFormatter('de_DE', NumberFormatter::DECIMAL);
echo "de decimal: ", $nf2->format(1234567.89), "\n";

$nf3 = new NumberFormatter('fr_FR', NumberFormatter::DECIMAL);
echo "fr decimal: ", $nf3->format(1234567.89), "\n";

// NumberFormatter - currency
$nfc = new NumberFormatter('en_US', NumberFormatter::CURRENCY);
echo "usd: ", $nfc->formatCurrency(99.5, 'USD'), "\n";

$nfc2 = new NumberFormatter('ja_JP', NumberFormatter::CURRENCY);
echo "jpy: ", $nfc2->formatCurrency(1234, 'JPY'), "\n";

// NumberFormatter - percent
$nfp = new NumberFormatter('en_US', NumberFormatter::PERCENT);
echo "percent: ", $nfp->format(0.876), "\n";

// NumberFormatter - parse
$parsed = $nf->parse('12,345.67');
echo "parsed: ", $parsed, "\n";

// Collator
$names = ['Müller', 'Mueller', 'Mahler', 'Möller'];
$de = new Collator('de_DE');
$de->sort($names);
echo "de sort: ", implode(',', $names), "\n";

$names2 = ['banana', 'apple', 'Cherry', 'date'];
$en = new Collator('en_US');
$en->setStrength(Collator::PRIMARY);
$en->sort($names2);
echo "en case-insens sort: ", implode(',', $names2), "\n";

// Transliterator
$t = Transliterator::create('Any-Latin; Latin-ASCII');
echo "translit: ", $t->transliterate("café Москва 中国"), "\n";

$t2 = Transliterator::create('Lower');
echo "lower: ", $t2->transliterate("Hello World"), "\n";

$t3 = Transliterator::create('Latin-Greek');
echo "to-greek: ", $t3->transliterate('hello'), "\n";

// procedural API
echo "loc fn: ", locale_get_primary_language('es_ES'), "\n";
echo "norm fn: ", normalizer_normalize("é") === "é" ? "ok" : "fail", "\n";

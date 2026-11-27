<?php
// IntlChar, php's wrapper of ICU's uchar.h: codepoints as ints or one UTF-8
// character, out-of-range and multi-character input refused with the intl
// error set, the enumerations calling back, and the class constants

function show(string $what, mixed $value): void
{
    echo $what, ': ', var_export($value, true), "\n";
}

show('chr', IntlChar::chr(0x1F600));
show('chr of a char', IntlChar::chr('a'));
show('ord', IntlChar::ord('€'));
show('ord int', IntlChar::ord(65));
show('ord too long', IntlChar::ord('ab'));
show('error', intl_get_error_message());
show('ord out of range', IntlChar::ord(0x110000));
show('error', intl_get_error_message());
show('ord fine', IntlChar::ord('x'));
show('error after', intl_get_error_message());

foreach (['a', 'Z', '5', ' ', "\t", '!', 'é', 'ß', '中', '١'] as $c) {
    echo $c, ':';
    foreach (['isalpha', 'isdigit', 'isalnum', 'isupper', 'islower', 'isspace', 'isblank', 'ispunct', 'isgraph', 'isprint', 'iscntrl', 'isxdigit', 'isUAlphabetic', 'isUWhiteSpace', 'isIDStart', 'isIDPart', 'isJavaIDStart', 'isMirrored', 'isdefined', 'isbase', 'istitle', 'isWhitespace', 'isJavaSpaceChar', 'isISOControl', 'isIDIgnorable', 'isJavaIDPart', 'isULowercase', 'isUUppercase'] as $f) {
        echo IntlChar::$f($c) ? '1' : '0';
    }
    echo ' type=', IntlChar::charType($c), ' dir=', IntlChar::charDirection($c), ' cc=', IntlChar::getCombiningClass($c);
    echo ' dv=', IntlChar::charDigitValue($c), ' block=', IntlChar::getBlockCode($c);
    echo ' upper=', IntlChar::toupper($c), ' lower=', IntlChar::tolower($c), ' title=', IntlChar::totitle($c), "\n";
}
show('toupper int', IntlChar::toupper(0x61));
show('mirror', IntlChar::charMirror('('));
show('bracket', IntlChar::getBidiPairedBracket('['));
show('foldCase', IntlChar::foldCase('A'));
show('foldCase int', IntlChar::foldCase(0x130, IntlChar::FOLD_CASE_EXCLUDE_SPECIAL_I));
show('digit', IntlChar::digit('7'));
show('digit hex', IntlChar::digit('f', 16));
show('digit bad', IntlChar::digit('z'));
show('error', intl_get_error_message());
show('forDigit', IntlChar::forDigit(11, 16));
show('numeric', IntlChar::getNumericValue('½'));
show('numeric none', IntlChar::getNumericValue('x'));
show('NO_NUMERIC_VALUE', IntlChar::NO_NUMERIC_VALUE);
show('charName', IntlChar::charName('A'));
show('charName int', IntlChar::charName(0x20AC));
show('charName none', IntlChar::charName(0xE000));
show('charFromName', IntlChar::charFromName('LATIN CAPITAL LETTER A'));
show('charFromName bad', IntlChar::charFromName('NO SUCH CHARACTER'));
show('code', intl_get_error_code());
show('property name', IntlChar::getPropertyName(IntlChar::PROPERTY_ALPHABETIC));
show('short name', IntlChar::getPropertyName(IntlChar::PROPERTY_ALPHABETIC, IntlChar::SHORT_PROPERTY_NAME));
show('bad property name', IntlChar::getPropertyName(-5));
show('error', intl_get_error_message());
show('property enum', IntlChar::getPropertyEnum('Alphabetic') === IntlChar::PROPERTY_ALPHABETIC);
show('value name', IntlChar::getPropertyValueName(IntlChar::PROPERTY_GENERAL_CATEGORY, IntlChar::CHAR_CATEGORY_UPPERCASE_LETTER));
show('value enum', IntlChar::getPropertyValueEnum(IntlChar::PROPERTY_GENERAL_CATEGORY, 'Lu') === IntlChar::CHAR_CATEGORY_UPPERCASE_LETTER);
show('binary', IntlChar::hasBinaryProperty('A', IntlChar::PROPERTY_ALPHABETIC));
show('int value', IntlChar::getIntPropertyValue('A', IntlChar::PROPERTY_GENERAL_CATEGORY) === IntlChar::CHAR_CATEGORY_UPPERCASE_LETTER);
show('min', IntlChar::getIntPropertyMinValue(IntlChar::PROPERTY_GENERAL_CATEGORY));
show('age', IntlChar::charAge('A'));
show('version parts', count(IntlChar::getUnicodeVersion()));
show('closure', IntlChar::getFC_NFKC_Closure('A'));
show('constants', [IntlChar::CODEPOINT_MIN, IntlChar::CODEPOINT_MAX, IntlChar::PROPERTY_ALPHABETIC, IntlChar::CHAR_CATEGORY_UPPERCASE_LETTER, IntlChar::UNICODE_CHAR_NAME, IntlChar::LONG_PROPERTY_NAME]);
show('constant count at least 600', count((new ReflectionClass('IntlChar'))->getConstants()) > 600);

$ranges = 0;
IntlChar::enumCharTypes(function ($start, $end, $type) use (&$ranges) {
    if ($ranges < 3) {
        echo "range $start-$end: $type\n";
    }
    $ranges++;
});
show('ranges seen', $ranges > 100);
IntlChar::enumCharNames('A', 'D', function ($code, $type, $name) {
    echo "$code $type $name\n";
});
try {
    IntlChar::enumCharTypes(function () {
        throw new Exception('stop');
    });
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
try {
    IntlChar::ord([]);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    IntlChar::enumCharTypes('no_such_function');
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}

// the callback resolves in the calling scope, where a private method is
// callable
class Types
{
    public int $seen = 0;

    public function run(): void
    {
        IntlChar::enumCharTypes([$this, 'count']);
        IntlChar::enumCharTypes('self::countStatic');
    }

    private function count(int $start, int $end, int $type): void
    {
        $this->seen++;
    }

    private static function countStatic(int $start, int $end, int $type): void
    {
    }
}
$t = new Types();
$t->run();
show('private callback ran', $t->seen > 100);

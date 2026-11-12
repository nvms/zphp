<?php
namespace Lib\Text {
    function upper($s) { return strtoupper($s); }
    function lower($s) { return strtolower($s); }
    const SEP = '-';
    const END = '.';
}
namespace App {
    use function Lib\Text\upper as up, Lib\Text\lower as down;
    use const Lib\Text\SEP as DASH, Lib\Text\END;
    use Lib\Text as T, Lib as L;
    echo up('a'), DASH, down('B'), END, "\n";
    echo T\upper('c'), L\Text\SEP, t\lower('D'), "\n";
}
namespace {
    use Exception;
    echo "global\n";
}

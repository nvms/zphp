<?php
// get_browser() matching a browscap file: exact sections, wildcard patterns
// (the longest literal match wins), parents, true/false settings, the
// default section, and the object form. browscap can only be set at startup,
// so the lookups run in a child process

var_dump(get_browser("Mozilla/5.0"));

$dir = sys_get_temp_dir() . '/zphp_browscap_' . getmypid();
@mkdir($dir);
$ini = "$dir/browscap.ini";
file_put_contents($ini, <<<'INI'
;;; a small browscap file
[GJK_Browscap_Version]
Version=5031
Released=Mon, 30 Jun 2014 11:00:00 +0000

[DefaultProperties]
Browser="DefaultProperties"
Version=0.0
Platform=unknown
Frames=false
JavaScript=false
isMobileDevice=false

[Opera 7.1]
Parent=DefaultProperties
Browser="Opera"
Version=7.1
MajorVer=7
Frames=true
JavaScript=yes

[Opera/7.1* (Windows NT 5.1; ?)*]
Parent="Opera 7.1"
Platform=WinXP
Win32=On

[Mozilla/5.0 (*Linux*) Gecko/* Firefox/*]
Parent=DefaultProperties
Browser=Firefox
Platform=Linux

[Mozilla/5.0 (*Linux x86_64*) Gecko/* Firefox/12.*]
Parent=DefaultProperties
Browser=Firefox
Version=12.0
Platform=Linux
Win64=no

[Mozilla/5.0 (+compat) (c) ~test~]
Browser="Special"

[*]
Browser=Default Browser
Version=0
Platform=unknown
INI);

$code = <<<'PHP'
foreach ([
    'Opera/7.11 (Windows NT 5.1; U) [en]',
    'Mozilla/5.0 (X11; Linux x86_64; rv:12.0) Gecko/20100101 Firefox/12.0',
    'Mozilla/5.0 (X11; Linux i686) Gecko/20100101 Firefox/30.0',
    'MOZILLA/5.0 (+COMPAT) (C) ~TEST~',
    'Opera 7.1',
    'something else',
    '',
] as $agent) {
    echo "== $agent\n";
    print_r(get_browser($agent, true));
}
var_dump(get_browser('Opera/7.11 (Windows NT 5.1; U) [en]'));
var_dump(get_browser(null, true));
PHP;

$out = shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d browscap=' . escapeshellarg($ini) . ' -d display_errors=1 -r ' . escapeshellarg($code) . ' 2>&1');
echo $out;

unlink($ini);
rmdir($dir);

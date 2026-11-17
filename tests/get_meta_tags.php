<?php
// get_meta_tags reads the name and content of each <meta> tag before </head>
$file = sys_get_temp_dir() . '/zphp_meta_' . getmypid() . '.html';
$pages = [
    "<html><head>\n<meta name=\"author\" content=\"Jane Doe\">\n<META NAME='Keywords' CONTENT='php, tags'>\n<meta name=geo.position content=49.33;-86.59>\n<meta content=\"first\" name=\"order\">\n<meta name=\"a b+c*d?e[f]g\$h(i)\" content=\"unsafe\">\n<meta name=\"only\">\n<meta name=\"dup\" content=\"one\"><meta name=\"DUP\" content=\"two\">\n<meta http-equiv=\"refresh\" content=\"5\">\n</head><body><meta name=\"late\" content=\"ignored\"></body></html>",
    "<meta name=\"x\" content=\"it's <here>\">",
    "<meta name=\"before\" content=\"nul\">\0<meta name=\"after\" content=\"x\">",
    "no tags at all",
    "<meta\tname=\"tab\"\ncontent=\"newline\"\r>",
    "<meta name=\"12\" content=\"numeric key\">",
];
foreach ($pages as $html) {
    file_put_contents($file, $html);
    var_dump(get_meta_tags($file));
}
unlink($file);
var_dump(@get_meta_tags($file));

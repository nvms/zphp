<?php
// covers: imagecreate / imagecreatetruecolor, color allocation, drawing primitives,
//   imagecopy / imagecopyresampled (thumbnail), imagepng/imagejpeg buffering,
//   image size queries, palette transparency

echo "=== create canvas and draw ===\n";
$im = imagecreatetruecolor(200, 100);
$bg = imagecolorallocate($im, 240, 240, 240);
$fg = imagecolorallocate($im, 50, 80, 200);
$red = imagecolorallocate($im, 220, 60, 60);
imagefill($im, 0, 0, $bg);

imagefilledrectangle($im, 10, 10, 100, 50, $fg);
imageline($im, 0, 0, 200, 100, $red);
imageellipse($im, 150, 50, 60, 60, $red);

echo "width: " . imagesx($im) . "\n";
echo "height: " . imagesy($im) . "\n";

$probe = imagecolorat($im, 5, 5);
$rgb = imagecolorsforindex($im, $probe);
echo "bg sample r/g/b: $rgb[red] $rgb[green] $rgb[blue]\n";

$probe = imagecolorat($im, 50, 30);
$rgb = imagecolorsforindex($im, $probe);
echo "fg sample r/g/b: $rgb[red] $rgb[green] $rgb[blue]\n";

echo "\n=== encode to PNG and JPEG, sniff magic bytes ===\n";
ob_start();
imagepng($im);
$png = ob_get_clean();
echo "PNG length > 0: " . (strlen($png) > 0 ? "yes" : "no") . "\n";
echo "PNG magic: " . bin2hex(substr($png, 0, 4)) . " (should be 89504e47)\n";

ob_start();
imagejpeg($im, null, 85);
$jpg = ob_get_clean();
echo "JPEG length > 0: " . (strlen($jpg) > 0 ? "yes" : "no") . "\n";
echo "JPEG magic: " . bin2hex(substr($jpg, 0, 3)) . " (should be ffd8ff)\n";

echo "\n=== imagecopyresampled produces thumbnail ===\n";
$src = imagecreatetruecolor(400, 200);
$blue = imagecolorallocate($src, 50, 100, 200);
imagefill($src, 0, 0, $blue);
$white = imagecolorallocate($src, 255, 255, 255);
imagefilledrectangle($src, 100, 50, 300, 150, $white);

$thumb = imagecreatetruecolor(80, 40);
imagecopyresampled($thumb, $src, 0, 0, 0, 0, 80, 40, 400, 200);
echo "thumb size: " . imagesx($thumb) . "x" . imagesy($thumb) . "\n";

// center pixel should be white-ish
$center = imagecolorsforindex($thumb, imagecolorat($thumb, 40, 20));
echo "thumb center: $center[red] $center[green] $center[blue]\n";

echo "\n=== palette image with transparency ===\n";
$pal = imagecreate(50, 50);
$bg2 = imagecolorallocate($pal, 100, 200, 100);
$tr = imagecolorallocatealpha($pal, 0, 0, 0, 127);
imagecolortransparent($pal, $tr);
imagefill($pal, 25, 25, $tr);

ob_start();
imagepng($pal);
$pal_png = ob_get_clean();
echo "palette PNG length > 0: " . (strlen($pal_png) > 0 ? "yes" : "no") . "\n";
echo "PNG magic: " . bin2hex(substr($pal_png, 0, 4)) . "\n";

echo "\n=== image rotate ===\n";
$rot_src = imagecreatetruecolor(10, 10);
$c = imagecolorallocate($rot_src, 100, 150, 200);
imagefill($rot_src, 0, 0, $c);
$rotated = imagerotate($rot_src, 90, 0);
echo "rotated size: " . imagesx($rotated) . "x" . imagesy($rotated) . "\n";

echo "\n=== imagecreatefromstring round-trip ===\n";
$reloaded = imagecreatefromstring($png);
echo "reload from PNG: " . ($reloaded !== false ? "ok" : "FAIL") . "\n";
echo "reload size: " . imagesx($reloaded) . "x" . imagesy($reloaded) . "\n";

// note: imagedestroy is deprecated since PHP 8.0; explicit destruction is a no-op
unset($im, $src, $thumb, $pal, $rot_src, $rotated, $reloaded);

echo "\ndone\n";

<?php
error_reporting(E_ERROR);  // silence PHP 8.5's imagedestroy() deprecation noise
// covers: GD image creation, drawing primitives, colors, save/load, dimensions

$tmp = sys_get_temp_dir();
$png = "$tmp/zphp-gd-test.png";

$img = imagecreatetruecolor(100, 50);
$bg = imagecolorallocate($img, 240, 240, 240);
$fg = imagecolorallocate($img, 50, 50, 200);
$red = imagecolorallocate($img, 255, 0, 0);

imagefilledrectangle($img, 0, 0, 99, 49, $bg);
imageline($img, 0, 0, 99, 49, $fg);
imagerectangle($img, 5, 5, 95, 45, $red);
imagefilledellipse($img, 50, 25, 30, 20, $red);
imagesetpixel($img, 1, 1, $fg);
imagestring($img, 3, 20, 5, "hi", $fg);

echo "w=", imagesx($img), " h=", imagesy($img), "\n";

imagepng($img, $png);
echo "png exists: ", file_exists($png) ? "yes" : "no", "\n";

$info = getimagesize($png);
echo "size: ", $info[0], "x", $info[1], " ", $info['mime'], "\n";

$img2 = imagecreatefrompng($png);
echo "loaded: ", imagesx($img2), "x", imagesy($img2), "\n";

// colorat
$c = imagecolorat($img2, 1, 1);
echo "pixel: ", $c, "\n";

// copy + resize
$thumb = imagecreatetruecolor(25, 12);
imagecopyresampled($thumb, $img2, 0, 0, 0, 0, 25, 12, imagesx($img2), imagesy($img2));
echo "thumb: ", imagesx($thumb), "x", imagesy($thumb), "\n";

imagedestroy($img);
imagedestroy($img2);
imagedestroy($thumb);
@unlink($png);
echo "done\n";

<?php

function formatTable(array $rows, array $columns): string
{
    if (count($rows) === 0) return "(empty)\n";

    $widths = [];
    foreach ($columns as $col) {
        $widths[$col] = strlen($col);
    }
    foreach ($rows as $row) {
        foreach ($columns as $col) {
            $val = (string) ($row[$col] ?? "");
            if (strlen($val) > $widths[$col]) {
                $widths[$col] = strlen($val);
            }
        }
    }

    $out = "";
    foreach ($columns as $col) {
        $out .= str_pad($col, $widths[$col]) . "  ";
    }
    $out .= "\n";
    foreach ($columns as $col) {
        $out .= str_repeat("-", $widths[$col]) . "  ";
    }
    $out .= "\n";
    foreach ($rows as $row) {
        foreach ($columns as $col) {
            $val = $row[$col] ?? "";
            if (is_bool($val)) $val = $val ? "yes" : "no";
            $out .= str_pad((string) $val, $widths[$col]) . "  ";
        }
        $out .= "\n";
    }
    return $out;
}

function slugify(string $text): string
{
    $text = strtolower(trim($text));
    $text = preg_replace('/[^a-z0-9]+/', '-', $text);
    $text = trim($text, '-');
    return $text;
}

const APP_NAME = "multi-file-demo";
const APP_VERSION = "1.0.0";

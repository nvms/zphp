<?php
// covers: grapheme_extract() return value across COUNT / MAXBYTES / MAXCHARS
// modes, byte offsets, and edge cases (empty, offset at end, multi-codepoint
// grapheme clusters). the by-ref $next out-param is not exercised.

// COUNT: number of grapheme clusters
var_dump(grapheme_extract('Hello', 3, GRAPHEME_EXTR_COUNT));
var_dump(grapheme_extract('Hello', 10, GRAPHEME_EXTR_COUNT));
var_dump(grapheme_extract('Hello', 2, GRAPHEME_EXTR_COUNT, 2));

// MAXBYTES: total bytes, never splitting a cluster
var_dump(grapheme_extract('café', 3, GRAPHEME_EXTR_MAXBYTES));
var_dump(grapheme_extract('café', 4, GRAPHEME_EXTR_MAXBYTES));
var_dump(grapheme_extract('Hello', 2, GRAPHEME_EXTR_MAXBYTES));

// MAXCHARS: total code points
var_dump(grapheme_extract('naïve', 4, GRAPHEME_EXTR_MAXCHARS));
var_dump(grapheme_extract('über', 2, GRAPHEME_EXTR_MAXCHARS));

// multi-codepoint clusters (ZWJ emoji = one grapheme)
var_dump(grapheme_extract('a👨‍👩‍👧b', 2, GRAPHEME_EXTR_COUNT));

// edge cases
var_dump(grapheme_extract('', 2, GRAPHEME_EXTR_MAXBYTES));        // empty -> false
var_dump(grapheme_extract('Hello', 2, GRAPHEME_EXTR_COUNT, 5));   // offset at end -> false
var_dump(grapheme_extract('é', 1, GRAPHEME_EXTR_MAXBYTES));       // can't fit cluster

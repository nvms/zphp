<?php
// output_add_rewrite_var: an output handler appends the variables to the
// urls of the tags url_rewriter.tags names and adds hidden inputs to forms
ini_set('url_rewriter.tags', 'a=href,area=href,frame=src,form=,img=src');
ini_set('url_rewriter.hosts', 'example.com,WWW.Example.com');
var_dump(output_add_rewrite_var('<name>', 'a b&c'));
var_dump(ob_list_handlers());
?>
<a href="">empty</a>
<a href="./page.php">relative</a>
<a href='page.php?x=1#frag'>query and fragment</a>
<a href=page.php>unquoted</a>
<A HREF = "page.php" class="c">upper case, spaced</A>
<a href="#top">fragment only</a>
<a href="mailto:me@example.com">other scheme</a>
<a href="http://example.com">host only</a>
<a href="https://user:pw@www.example.com:8080/p">user and port</a>
<a href="http://other.org/p">other host</a>
<img src="i.png"><img title="t" src="j.png" />
<area href="x"><frame src="y">
<form method="get"></form>
<form action="http://example.com/f" method="post"></form>
<form action="http://other.org/f"></form>
<form action="ftp://example.com/f"></form>
<p title="<a href=x>">not a tag</p>
<?php
ob_flush();
echo "<a hr";
ob_flush();
echo "ef=\"split.php\">split across flushes</a>\n";
output_reset_rewrite_vars();
?>
<a href="after.php">after a reset</a>
<?php
output_add_rewrite_var('k', 'v');
output_add_rewrite_var('k2', 'v2');
ini_set('arg_separator.output', '&amp;');
?>
<a href="two.php?q=1">two variables</a>
<form></form>
<?php
ob_end_flush();
echo "<a href=\"gone.php\">the handler is removed</a>\n";
output_add_rewrite_var('late', '1');
var_dump(ob_get_level());
?>
<a href="late.php">no handler again</a>

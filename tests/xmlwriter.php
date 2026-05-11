<?php
// covers: XMLWriter streaming output, attributes, nesting, CDATA, comments, indentation

$w = new XMLWriter();
$w->openMemory();
$w->setIndent(true);
$w->setIndentString('  ');
$w->startDocument('1.0', 'UTF-8');
$w->startElement('library');
$w->writeAttribute('name', 'home');

$w->startElement('book');
$w->writeAttribute('id', '1');
$w->writeElement('title', 'The Hobbit');
$w->writeElement('author', 'Tolkien');
$w->endElement();

$w->startElement('book');
$w->writeAttribute('id', '2');
$w->writeElement('title', 'Dune');
$w->writeElement('author', 'Herbert');
$w->endElement();

$w->writeComment('end of list');
$w->writeCData('raw <stuff>');

$w->endElement();
$w->endDocument();
echo $w->outputMemory();

// procedural style
$w2 = xmlwriter_open_memory();
xmlwriter_start_document($w2, '1.0', 'UTF-8');
xmlwriter_start_element($w2, 'r');
xmlwriter_write_attribute($w2, 'k', 'v');
xmlwriter_text($w2, 'hi');
xmlwriter_end_element($w2);
xmlwriter_end_document($w2);
echo xmlwriter_output_memory($w2);

// nested elements with text
$w3 = new XMLWriter();
$w3->openMemory();
$w3->startElement('div');
$w3->text('hello ');
$w3->startElement('b');
$w3->text('world');
$w3->endElement();
$w3->text('!');
$w3->endElement();
echo $w3->outputMemory(), "\n";

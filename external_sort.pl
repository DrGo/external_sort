#!/usr/bin/env perl

##
## This program sorts input text file using default lexicographic comparison
## and external sorting algorithm based on self-implemented classic quick sort
## of k pieces fitting memory limit (set in lines for simplicity)
## and k-way merge of the k pieces into resulting output file.
## No new inventions here, all credits to von Neumann and Hoare :)
##

use strict;
use warnings;

use Getopt::Long;

if (@ARGV < 2) {
  print "USAGE: $0 [-avail_mem <lines>] [-debug] <input file> <output file>\n";
  exit 1;
}

my $avail_mem = 100000; ## I make an assumption that we measure memory in lines.
## I could set this limit in bytes, look through the input file with one more pass
## to find the longest line length but I think we can omit this here.
my $debug = 0;
my $inter_fname_patt = "mysorted"; ## pattern to name intermediate files
GetOptions("avail_mem=i" => \$avail_mem, "debug" => \$debug);
my ($input_file, $output_file) = @ARGV;

## okay make my own sort function to avoid using std one
## accepts list reference to avoid list copy
## and say let it be classic quicksort
## part 1. partition
sub partition {
  my ($array_ref, $lo, $hi) = @_;
  my $pivot = $array_ref->[$hi];
  my $i = $lo;
  for (my $j = $lo; $j < $hi; ++$j) {
    if ($array_ref->[$j] le $pivot) {
      ## swap A[i] with A[j]
      ($array_ref->[$i], $array_ref->[$j]) = ($array_ref->[$j], $array_ref->[$i]);
      ++$i;
    }
  }
  ## swap A[i] with A[hi]
  ($array_ref->[$i], $array_ref->[$hi]) = ($array_ref->[$hi], $array_ref->[$i]);
  return $i;
}
## part 2. sorting recursion
sub mysort {
  my ($array_ref, $lo, $hi) = @_;
  return unless (defined $array_ref and @{$array_ref});
  $lo = 0 unless (defined $lo);
  $hi = $#{$array_ref} unless (defined $hi);
  my $swaps = 0; ## only for stats
  if ($lo < $hi) {
    my $p = partition($array_ref, $lo, $hi);
    ## we can count number of swaps
    $swaps = $p - $lo + 1;
    $swaps += mysort($array_ref, $lo, $p - 1);
    $swaps += mysort($array_ref, $p + 1, $hi);
  }
  return $swaps;
}

## And here goes our MAIN
## 1. Read input files into chunks fitting available memory, sort the chunks
##    using mysort() and dump them to set of intermediate files
open (IN, $input_file) or die "Could not open input file '$input_file': $!";
my $tot_lines = 0;
my $eof = 0;
my $ind = 0; ## intermediate file name index, also number of sorted pieces for further merge
while (not $eof) {
  my @lines; ## I believe here I empty the buffer
  my $line; ## current line read from input file, will also use memory so I'll decrease the buffer by 1
  while ((@lines < ($avail_mem - 1)) and defined ($line = <IN>)) {
    push @lines, $line;
  }
  $tot_lines += @lines;
  $eof = 1 unless (defined $line);
  if (@lines) {
    my $swaps = mysort (\@lines);
    print "DEBUG: swaps=$swaps\n" if ($debug);
    my $out_fname = "${inter_fname_patt}_$ind";
    open (OUT, ">$out_fname") or die "Could not open output file '$out_fname': $!";
    print OUT @lines;
    close OUT;
    ++$ind;
  }
}
print "DEBUG: read total $tot_lines lines\n" if ($debug);
close IN;

## 2. Merge the intermediate files into output file
open (OUT, ">$output_file") or die "Could not create output file '$output_file': $!";
my @fhandlers;
for (my $i = 0; $i < $ind; ++$i) {
  my $fname = "${inter_fname_patt}_$i";
  open ($fhandlers[$i], $fname) or die "Could not open intermediate file '$fname': $!";
}

my $chunk_size = int(($avail_mem - 1) / ($ind + 1)); ## +1 for output buffer, -1 for current line processing
print "DEBUG: chunk_size='$chunk_size'\n" if ($debug);
my @output_buffer;
my @input_buffers;

sub read_into_buffer {
  my ($i, $input_buffers_ref, $fhandler, $chunk_size) = @_;
  my @lines;
  my $line; ## current line read from input file, will also use memory so I'll decrease the buffer by 1
  while ((@lines < $chunk_size) and defined ($line = <$fhandler>)) {
    push @lines, $line;
  }
  $input_buffers_ref->[$i] = \@lines;
  return int(@lines);
}

## read into input buffers
for (my $i = 0; $i < $ind; ++$i) {
  read_into_buffer($i, \@input_buffers, $fhandlers[$i], $chunk_size);
}
my $empty_handlers = 0;
## top-level loop here
do {
  ## k-merge here (ind-merge)
  ## find "minimum" of ind heads, put it into output buffer and pop it
  my $min_ind;
  ## skip empty buffer
  for ($min_ind = 0; $min_ind < $ind; ++$min_ind) {
    if (@{$input_buffers[$min_ind]}) {
      last;
    }
  }
  for (my $i = $min_ind + 1; $i < $ind; ++$i) {
    ## skip empty buffer
    next unless (@{$input_buffers[$i]});
    ## ok I won't implement my own string comparison
    if ($input_buffers[$i][0] lt $input_buffers[$min_ind][0]) {
      $min_ind = $i;
    }
  }
  push @output_buffer, shift @{$input_buffers[$min_ind]};
  if (@output_buffer == $chunk_size) {
    ## flush output buffer
    print OUT @output_buffer;
    @output_buffer = ();
  }
  unless (@{$input_buffers[$min_ind]}) {
    unless (read_into_buffer($min_ind, \@input_buffers, $fhandlers[$min_ind], $chunk_size)) {
      ++$empty_handlers;
    }
  }
} while ($empty_handlers < $ind);

## final flush of out buffer
print OUT @output_buffer;
close OUT;

## cleanup
for (my $i = 0; $i < $ind; ++$i) {
  my $fname = "${inter_fname_patt}_$i";
  close ($fhandlers[$i]) or die "Could not close intermediate file '$fname': $!";
  unlink $fname or die "Could not delete intermediate file '$fname': $!";
}

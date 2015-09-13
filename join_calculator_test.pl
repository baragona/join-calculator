#!/usr/bin/perl -w

use strict;

use Data::Dumper;
use List::Util qw(max min maxstr minstr shuffle);

use join_calculator;

my $tables = [
        [qw( report.data              d 0 0 0), [qw( date hour sid mid )]],
        [qw( passback.data2           p 1 0 0), [qw( date hour sid mid )]],
        [qw( admin.media_tbl          a 0 0 0 ),['mid']],
        [qw( google.media            gm 1 0 0 ),['mid']],
        [qw( admin.camp_tbl           f 1 0 0 ),['cid']],
        [qw( admin.adv_tbl            g 1 0 0 ),['aid']],
        [qw( admin.adv_vertical       v 1 0 0 ),['vid']],
        [qw( admin.adv_types         at 1 0 0 ),['tid']],
        [qw( admin.type_tbl           c 0 0 0 ),['tid']],
        [qw( admin.site_tbl           b 0 0 0 ),['sid']],
        [qw( admin.cat                i 1 0 0 ),['cat_id']],
        [qw( admin.pub_tbl            e 0 0 0 ),['pid']],
        [qw( admin.site_rates         h 0 0 0 ),['sid','type']],
        [qw( admin.site_date_ranges  sd 0 0 0 ),['sid']],
        [qw( admin.media_date_ranges md 0 0 0 ),['mid']],
        ];
my $links = [
          [
            'a.cid',
            'f.cid'
          ],
          [
            'a.mid',
            'd.mid',
            'gm.mid',
            'md.mid'
          ],
          [
            'f.aid',
            'g.aid',
            'a.aid'
          ],
          [
            'g.vertical',
            'v.vid'
          ],
          [
            'g.adv_type',
            'at.tid'
          ],
          [
            'a.tid',
            'c.tid',
            'h.type'
          ],
          [
            'b.sid',
            'h.sid',
            'd.sid',
            'sd.sid'
          ],
          [
            'b.pid',
            'e.pid'
          ],
          [
            'i.cat_id',
            'b.category'
          ],
          [
            'd.date',
            'p.date'
          ],
          [
            'd.hour',
            'p.hour'
          ],
          [
            'd.sid',
            'p.sid'
          ],
          [
            'd.mid',
            'p.mid'
          ]
        ];

my $abbr_to_row = { map {$_->[1] => $_} @$tables};

my $abbr_to_keys = { map {$_->[1] => $_->[5] } @$tables};

my @all_table_abbrs = map {$_->[1]} @$tables;

sub binary_digits{
    my $num = shift;
    my $num_digits = shift;

    return '' if $num_digits == 0 and $num==0;
    my $bits;
    if($num_digits==1){
        $bits = $num;
    }else{
        $bits = sprintf("%0$num_digits"."b", $num);
    }


    warn "$num ->  $bits ; not $num_digits digits" if length($bits) != $num_digits;
    return $bits;
}



my $n_tables = scalar @all_table_abbrs;

my $max_binary_val = (2**$n_tables)-1;
my $min_binary_val = 1;

#die "$max_binary_val, $min_binary_val";

my @all = map {binary_digits($_, $n_tables)} ($min_binary_val .. $max_binary_val);

@all = shuffle (map { my @x = (split //, $_); [map { $x[$_] ? $all_table_abbrs[$_] : () } (0..$n_tables)]} @all);

#die Dumper \@all;


sub print_result{
    my $set = shift;
    my ($from_clause, $is_disconnected) = join_calculator::calc_from_clause($set, $tables, $links);
    local $" = ', ';
    print "Input: @$set\n";
    if($is_disconnected){
        print "This set of tables cannot be joined without introducing intermediate tables that limit the result set.\n";
    }else{
        print "Output:\n$from_clause\n";
    }
    print "\n";
}

if(1){
    my $set = [@ARGV];
    print_result($set);
}else{
    for my $set(@all[0..100]){
        print_result($set);
    }
}
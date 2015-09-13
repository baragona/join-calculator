
package join_calculator;

use strict;

use udm;
use Data::Dumper;
use List::MoreUtils qw(uniq);


sub extract_table_reference{
    my $col = shift;

    return substr($col, 0, index($col, '.'));
}

sub get_derived_cols_for_table{
    #Derived cols - all the cols you know the value of if you have one row of a table
    # = All of your columns
        # All of the derived cols of all the other tables that you have full keys to.
    my $sorted_link_map = shift;
    my $neighbors = shift;
    my $tbl = shift;
    my $abbr_to_row = shift;

    my %ignore_these_neighbors;

    my @cols = @{$neighbors->{$tbl}};
    $ignore_these_neighbors{$tbl}=1;

    my $tbl_to_links_used_to_access_it;

    LOOP_START: ;
    TBL2: for my $tbl2 (keys %$abbr_to_row){

        next if $ignore_these_neighbors{$tbl2};

        my $row = $abbr_to_row->{$tbl2};

        my @keys = @{$row->[5]};
        @keys = map {"$tbl2.$_"} @keys;

        KEY: for my $key(@keys){
            COL: for my $col (@cols){
                my $link = join '=', (sort {$a cmp $b} ($key, $col));
                if($sorted_link_map->{$link}){
                    $tbl_to_links_used_to_access_it->{$tbl2}{ $link}=1;
                    next KEY;
                }else{
                    next COL;
                }
            }
            #you scanned all the cols without finding a match
            #therefore you dont have this key
            #skip this table
            delete $tbl_to_links_used_to_access_it->{$tbl2};
            next TBL2;
        }
        #you scanned all keys without finding one that you cant satisfy
        #therefore you know all of its columns
        $ignore_these_neighbors{$tbl2}=1;
        push @cols, @{$neighbors->{$tbl2}};

        goto LOOP_START;#Now that you know more columns, maybe you can derive more too. Check all again.
    }

    return [\@cols,$tbl_to_links_used_to_access_it];
}

sub BFS{
    my $neighbors = shift;
    my $root = shift;
    my $call = shift;
    my $ignore_link = shift;

    my @q;
    my %visited;
    push @q, $root;

    my $layer=0;

    while(@q){
        my $n = shift @q;
        $call->($n, $layer);
        $visited{$n}=1;
        push @q, (grep { not $visited{$_} and not udm::in_list(@q, $_) and not($ignore_link and $ignore_link->($n, $_))} @{$neighbors->{$n}});
    }
}

sub transitive_links{
    my @links = @_;
    my @transited_links;
    my $merged=1;
    while($merged){
        $merged=0;
        for my $link(@links){
            my $add_to_this_set;
            for my $set(@transited_links){
                if(udm::list_intersection($link, $set)){
                    $add_to_this_set = $set;
                    last;
                }
            }

            if($add_to_this_set){
                @$add_to_this_set = uniq(@$add_to_this_set, @$link);
                $merged=1;
            }else{
                push @transited_links, [@$link];
            }

        }
        if($merged){
            @links = @transited_links;
            @transited_links = ();
        }
    }
    return @links;
}

sub calc_from_clause{
    my $set = shift;
    my $tables = shift;
    my $links = shift;
    my %wanted_set = (map {$_ => 1} @$set );
    local $"=' ';

    my $abbr_to_row = { map {$_->[1] => $_} @$tables};

    my $abbr_to_keys = { map {$_->[1] => $_->[5] } @$tables};

    my @all_table_abbrs = map {$_->[1]} @$tables;


    my $sorted_link_map = {};
    my $neighbors = {};

    my @links = transitive_links(@$links);

    for my $link(@links){
        COL: for my $col(@$link){
            if($col =~ /^(\w+)\.(\w+)$/){
                my $tbl = $1;
                my $colname = $2;
                next COL unless $abbr_to_row->{$tbl};

                $sorted_link_map->{join '=', (sort {$a cmp $b} ($col, $tbl))}=1;
                push @{$neighbors->{$col}}, $tbl;
                push @{$neighbors->{$tbl}}, $col;
                if(udm::in_list(@{$abbr_to_row->{$tbl}[5]}, $colname)){
                    #This is a key column
                    COL2: for my $col2(@$link){
                        next if $col eq $col2;
                        if($col2 =~ /^(\w+)\.(\w+)$/){
                            my $tbl2 = $1;
                            my $colname2 = $2;

                            next COL2 unless $abbr_to_row->{$tbl2};

                            $sorted_link_map->{join '=', (sort {$a cmp $b} ($col, $col2))}=1;

                            push @{$neighbors->{$col}}, $col2;
                            push @{$neighbors->{$col2}}, $col;

                        }else{
                            die "bad col spec in link: $col2";
                        }
                    }
                }
            }else{
                die "bad col spec in link: $col";
            }

        }
    }

    for my $node(keys %$neighbors){
        @{$neighbors->{$node}} = uniq(@{$neighbors->{$node}});
    }

    my $col_to_derived_cols = {map {$_ => get_derived_cols_for_table($sorted_link_map, $neighbors, $_, $abbr_to_row)} @all_table_abbrs};

    my $equalities={};

    my %link_checked;

    TBL_SQUARED: ;
    for my $tbl(keys %wanted_set){
        for my $tbl2(keys %wanted_set){
            next if $tbl2 eq $tbl;
            next if $link_checked{"$tbl -> $tbl2"};
            $link_checked{"$tbl -> $tbl2"}=1;

            if(udm::list_intersection($col_to_derived_cols->{$tbl}[0],$col_to_derived_cols->{$tbl2}[0])){
                for my $equality(keys %{ $col_to_derived_cols->{$tbl}[1]{$tbl2} }){
                    $equalities->{$equality}=1;
                }
            }
            my @tables_used_by_equalities = map {map {extract_table_reference($_)} (split /=/, $_)} keys %$equalities;
            my $added_some=0;
            for my $tbl3 (@tables_used_by_equalities){
                unless($wanted_set{$tbl3}){
                    $wanted_set{$tbl3}=1;
                    $added_some=1;
                }
            }
            goto TBL_SQUARED if $added_some;
        }
    }

    my @equal_sets = transitive_links( map {[ split /=/, $_ ]} (keys %$equalities));

    my @final_set;

    while(scalar(@final_set) < scalar(keys %wanted_set)){
        my @not_added_to_final_set = udm::list_difference([keys %wanted_set], \@final_set);

        my @non_left_tables = grep {not $abbr_to_row->{$_}[2]} @not_added_to_final_set;
        my $random_non_left_tbl = $non_left_tables[0];
        unless($random_non_left_tbl){
            $random_non_left_tbl=$not_added_to_final_set[0]; #there arent any non left tables so just pretend this one is
        }
        BFS($neighbors,$random_non_left_tbl, sub { my $node = shift; if($node =~ /^\w+$/){push @final_set, $node;} },

            sub{
                my $left=shift;
                my $right=shift;
                $left=extract_table_reference($left) if $left =~ /\./;

                $right=extract_table_reference($right)if $right =~ /\./;

                return 1 unless ( $wanted_set{$left} and  $wanted_set{$right});
                return 0;
            }

        );
    }

    die "some are unreachable?" unless scalar(@final_set) == scalar(keys %wanted_set);
    my $from_clause;
    my $is_disconnected=0;
    my $has_any_already=0;
    my %table_added_to_clause;
    for my $abbr(@final_set){
        my $tbl = $abbr_to_row->{$abbr};


        $table_added_to_clause{$abbr}=1;
        my $on_clause;
        for my $equal_set(@equal_sets){
            my $key = (grep {extract_table_reference($_) eq $abbr} @$equal_set)[0];
            if($key){
                my @possible_refs;
                for my $ref_col(@$equal_set){
                    next if $ref_col eq $key;
                    my $ref_tbl = extract_table_reference($ref_col);
                    if(not $table_added_to_clause{$ref_tbl}){
                        next;
                    }
                    push @possible_refs, $ref_col;
                }

                my @non_left_refs = grep {not $abbr_to_row->{extract_table_reference($_)}[2]} @possible_refs;

                my $chosen_ref = $non_left_refs[0];
                unless($chosen_ref){
                    $chosen_ref = $possible_refs[0];
                }


                if($chosen_ref){
                    my $ref_tbl = extract_table_reference($chosen_ref);
                    if($on_clause){
                        $on_clause .= " and ";
                    }
                    $on_clause .= "$key = $chosen_ref";
                }
            }
        }
        if($has_any_already and not $on_clause){
            $is_disconnected=1;
        }
        my $maybe_left = "    ";
        if($tbl->[2] and $has_any_already and $on_clause){
            $maybe_left = "LEFT";
        }
        my $join = $has_any_already ? 'JOIN' : 'FROM';
        $from_clause .= "$maybe_left $join $tbl->[0] $abbr \n";
        if($on_clause){
            $from_clause .= "       ON ( $on_clause ) \n";
        }
        $has_any_already=1;
    }
    return ($from_clause, $is_disconnected);
}

1;

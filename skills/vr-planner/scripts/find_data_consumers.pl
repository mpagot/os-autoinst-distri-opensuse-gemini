#!/usr/bin/perl
# find_data_consumers.pl — Find tests/libs that reference a changed data/ file.
# Run with --help for full usage information.

use strict;
use warnings;
use File::Find;
use File::Spec;
use File::Basename;
use Getopt::Long;
use JSON::PP;

my $repo_dir;
my $verbose = 0;
my $json_output = 0;
my $all_layers = 0;
my $help = 0;

GetOptions(
    'repo=s'     => \$repo_dir,
    'verbose'    => \$verbose,
    'json'       => \$json_output,
    'all-layers' => \$all_layers,
    'help|h'     => \$help,
) or do { print_usage(); exit 1 };

print_usage() && exit 0 if $help;

$repo_dir //= '.';

die "Not a valid OSADO repo: $repo_dir (missing tests/ or lib/)\n"
    unless -d "$repo_dir/tests" && -d "$repo_dir/lib";

my @input_paths = @ARGV;
if (!@input_paths) {
    print_usage();
    exit 1;
}

# --- Step 1: Parse data file paths into search terms ---

sub parse_data_path {
    my ($path) = @_;
    $path =~ s{^\Q$repo_dir\E/}{};
    $path =~ s{^\.\/}{};

    # Strip data/ prefix
    my $rel = $path;
    $rel =~ s{^data/}{};

    # Decompose into search layers
    my $filename = fileparse($rel);
    my ($name_no_ext) = $filename =~ /^([^.]+)/;
    my $parent_dir = '';
    if ($rel =~ m{([^/]+)/[^/]+$}) {
        $parent_dir = $1;
    }
    # Directory prefix: everything up to and including the last /
    my $dir_prefix = '';
    if ($rel =~ m{^(.+/)}) {
        $dir_prefix = $1;
    }

    return {
        original   => $path,
        rel        => $rel,           # Layer 1: full path without data/
        dir_prefix => $dir_prefix,    # Layer 2: directory prefix
        basename   => $name_no_ext,   # Layer 3: filename without extension
        parent_dir => $parent_dir,    # Layer 4: parent directory name
    };
}

my @targets;
for my $path (@input_paths) {
    unless ($path =~ m{(?:^|/)data/} || $path =~ m{^[^/]}) {
        warn "Warning: '$path' does not look like a data/ path, skipping\n";
        next;
    }
    push @targets, parse_data_path($path);
}
die "No valid data/ paths provided\n" unless @targets;

# --- Step 2: Collect all searchable files (tests/ and lib/) ---

my @search_files;
for my $dir (qw(tests lib)) {
    next unless -d "$repo_dir/$dir";
    find(sub {
        return unless /\.pm$/ && -f;
        push @search_files, File::Spec->abs2rel($File::Find::name, $repo_dir);
    }, "$repo_dir/$dir");
}

log_verbose("Searching " . scalar(@search_files) . " files in tests/ and lib/");

# --- Step 3: Search function ---

# Search all files for a pattern, return matches with context
sub search_files_for {
    my ($pattern) = @_;
    my @matches;

    return @matches unless $pattern && length($pattern) > 0;

    for my $file (@search_files) {
        my $abs = "$repo_dir/$file";
        open my $fh, '<', $abs or next;
        my $lineno = 0;
        while (my $line = <$fh>) {
            $lineno++;
            chomp $line;
            next if $line =~ /^\s*#/;
            if (index($line, $pattern) >= 0) {
                push @matches, {
                    file    => $file,
                    line    => $lineno,
                    content => $line,
                };
            }
        }
        close $fh;
    }

    return @matches;
}

# --- Step 4: Layered search for each target ---

my %results;

for my $target (@targets) {
    my @layers = (
        { name => 'full_path',  term => $target->{rel},        desc => "Full path (without data/ prefix)" },
        { name => 'dir_prefix', term => $target->{dir_prefix}, desc => "Directory prefix" },
        { name => 'basename',   term => $target->{basename},   desc => "Bare filename (no extension)" },
        { name => 'parent_dir', term => $target->{parent_dir}, desc => "Parent directory name" },
    );

    my @layer_results;
    my $found_in_layer;

    for my $i (0 .. $#layers) {
        my $layer = $layers[$i];
        next unless $layer->{term} && length($layer->{term}) > 1;

        my @matches = search_files_for($layer->{term});

        push @layer_results, {
            %$layer,
            matches => \@matches,
            index   => $i + 1,
        };

        if (@matches && !$found_in_layer) {
            $found_in_layer = $i + 1;
            last unless $all_layers;
        }
    }

    $results{$target->{original}} = {
        target         => $target,
        layers         => \@layer_results,
        found_in_layer => $found_in_layer,
    };

    log_verbose(sprintf("%s: %s",
        $target->{original},
        $found_in_layer
            ? "found in layer $found_in_layer"
            : "no matches in any layer"
    ));
}

# --- Output ---

if ($json_output) {
    print_json(\%results);
} else {
    print_text(\%results);
}

exit 0;

# --- Output functions ---

sub print_text {
    my ($results) = @_;

    for my $orig (sort keys %$results) {
        my $r = $results->{$orig};
        my $target = $r->{target};

        print "=" x 60, "\n";
        print "Consumers of: $orig\n";
        print "=" x 60, "\n\n";

        if (!$r->{found_in_layer}) {
            print "  No references found in any search layer.\n";
            print "  Try: git log --oneline $orig\n\n";
            next;
        }

        for my $layer (@{$r->{layers}}) {
            next unless @{$layer->{matches}};

            my @matches = @{$layer->{matches}};
            my $is_primary = ($layer->{index} == $r->{found_in_layer});

            printf "Layer %d: %s — search term: \"%s\" (%d matches)%s\n",
                $layer->{index},
                $layer->{desc},
                $layer->{term},
                scalar(@matches),
                $is_primary ? " [PRIMARY]" : "";

            # Group matches by file location (tests/ vs lib/)
            my %by_area;
            for my $m (@matches) {
                my ($area) = $m->{file} =~ m{^(tests|lib)/};
                $area //= 'other';
                push @{$by_area{$area}}, $m;
            }

            for my $area (sort keys %by_area) {
                print "  $area/ (" . scalar(@{$by_area{$area}}) . " matches)\n";
                for my $m (sort { $a->{file} cmp $b->{file} } @{$by_area{$area}}) {
                    print "    $m->{file}:$m->{line}\n";
                    if ($verbose) {
                        my $trimmed = $m->{content};
                        $trimmed =~ s/^\s+//;
                        # Truncate long lines
                        $trimmed = substr($trimmed, 0, 100) . "..."
                            if length($trimmed) > 100;
                        print "      $trimmed\n";
                    }
                }
            }
            print "\n";
        }

        # VR hint: list unique test files from the primary layer
        my $primary_layer;
        for my $layer (@{$r->{layers}}) {
            if ($layer->{index} == $r->{found_in_layer}) {
                $primary_layer = $layer;
                last;
            }
        }
        if ($primary_layer) {
            my %test_files;
            for my $m (@{$primary_layer->{matches}}) {
                $test_files{$m->{file}} = 1 if $m->{file} =~ m{^tests/};
            }
            if (%test_files) {
                print "VR hint — these test files reference the data file:\n";
                for my $tf (sort keys %test_files) {
                    print "  $tf\n";
                }
                print "\n";
            }
        }
    }
}

sub print_json {
    my ($results) = @_;

    my @entries;
    for my $orig (sort keys %$results) {
        my $r = $results->{$orig};

        my @layers_out;
        for my $layer (@{$r->{layers}}) {
            my @matches_out;
            for my $m (@{$layer->{matches}}) {
                push @matches_out, {
                    file    => $m->{file},
                    line    => $m->{line} + 0,
                    content => substr($m->{content}, 0, 200),
                };
            }
            push @layers_out, {
                layer   => $layer->{index} + 0,
                name    => $layer->{name},
                term    => $layer->{term} // '',
                matches => \@matches_out,
            };
        }

        push @entries, {
            data_file      => $orig,
            found_in_layer => $r->{found_in_layer},
            layers         => \@layers_out,
        };
    }

    print JSON::PP->new->pretty->canonical->encode({ results => \@entries });
}

sub log_verbose {
    my ($msg) = @_;
    print STDERR "[INFO] $msg\n" if $verbose;
}

sub print_usage {
    print <<'EOF';
find_data_consumers.pl — Find tests/libs that reference a changed data/ file.

USAGE
    perl find_data_consumers.pl [OPTIONS] data/A/B.ext [data/C/D.ext ...]

DESCRIPTION
    Given one or more data/* file paths, uses a layered search strategy to
    find which test and lib files reference each data file. About 43% of
    data_url() calls in OSADO use variables in the path, so a single grep
    for the full path misses nearly half of all references.

    Search layers (stops at the first layer with results, per file):

      1. Full relative path without data/ prefix
         e.g. "sles4sap/qe_sap_deployment/qesap_aws.yaml"

      2. Directory prefix (catches dynamic filenames built with variables)
         e.g. "sles4sap/qe_sap_deployment/"

      3. Bare filename without extension
         e.g. "qesap_aws"

      4. Parent directory name
         e.g. "qe_sap_deployment"

    Multiple data access patterns are recognized:
      - data_url('path/to/file')
      - autoinst_url('/data/path/to/file')
      - get_var('CASEDIR') . '/data/path/to/file'

OPTIONS
    --repo DIR
        Path to the OSADO repository root. Defaults to the current directory.

    --all-layers
        Show results from all search layers, not just the first one that
        produces matches. Useful to see broader context or find additional
        references.

    --verbose
        Show the matching source line for each result (truncated to 100 chars).

    --json
        Output results as JSON instead of human-readable text.

    --help, -h
        Show this help message and exit.

EXAMPLES
    perl find_data_consumers.pl data/sles4sap/qe_sap_deployment/qesap_aws.yaml

    perl find_data_consumers.pl --repo /path/to/osado --verbose \
        data/sssd/openldap/sssd.conf

    perl find_data_consumers.pl --all-layers --repo /path/to/osado \
        data/sssd/openldap/sssd.conf

SEE ALSO
    classify_changes.pl, find_test_schedule.pl
EOF
    return 1;
}

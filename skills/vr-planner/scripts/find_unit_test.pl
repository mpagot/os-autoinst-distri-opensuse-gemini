#!/usr/bin/perl
# find_unit_test.pl : Find unit test files (t/*.t) that cover a given lib/*.pm.
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
my $help = 0;

GetOptions(
    'repo=s'  => \$repo_dir,
    'verbose' => \$verbose,
    'json'    => \$json_output,
    'help|h'  => \$help,
) or do { print_usage(); exit 1 };

print_usage() && exit 0 if $help;

$repo_dir //= '.';

die "Not a valid OSADO repo: $repo_dir (missing lib/ or t/)\n"
    unless -d "$repo_dir/lib" && -d "$repo_dir/t";

my @input_paths = @ARGV;
if (!@input_paths) {
    print_usage();
    exit 1;
}

# --- Step 1: Convert file paths to package names ---

sub path_to_pkg {
    my ($path) = @_;
    $path =~ s{^\Q$repo_dir\E/}{};
    $path =~ s{^\.\/}{};
    $path =~ s{^lib/}{};
    $path =~ s{\.pm$}{};
    $path =~ s{/}{::}g;
    return $path;
}

sub path_to_basename {
    my ($path) = @_;
    my $base = fileparse($path, qr/\.pm$/);
    return lc($base);
}

my @targets;
for my $path (@input_paths) {
    unless ($path =~ m{(?:^|/)lib/.*\.pm$} || $path =~ m{^[^/]+.*\.pm$}) {
        warn "Warning: '$path' does not look like a lib/*.pm path, skipping\n";
        next;
    }
    my $pkg = path_to_pkg($path);
    my $base = path_to_basename($path);
    $path =~ s{^\Q$repo_dir\E/}{};
    $path =~ s{^\.\/}{};
    push @targets, { file => $path, pkg => $pkg, basename => $base };
}
die "No valid lib/*.pm paths provided\n" unless @targets;

log_verbose("Targets: " . join(", ", map { "$_->{pkg} ($_->{basename})" } @targets));

# --- Step 2: Collect all t/*.t files ---

my @test_files;
find(sub {
    return unless /\.t$/ && -f;
    push @test_files, File::Spec->abs2rel($File::Find::name, $repo_dir);
}, "$repo_dir/t");

log_verbose("Found " . scalar(@test_files) . " unit test files");

# --- Step 3: Scan each .t file for imports ---

# Cache: test_file => [list of imported package names]
my %test_imports;

for my $tf (@test_files) {
    my $abs = "$repo_dir/$tf";
    open my $fh, '<', $abs or next;
    my @imports;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^\s*#/;

        # use Mojo::Base 'Pkg::Name'; must be checked BEFORE the general 'use'
        # handler below, because the general handler would match 'Mojo::Base' and
        # then 'next' out of the loop body, making this branch unreachable.
        if ($line =~ /use\s+Mojo::Base\s+['"]([^'"]+)['"]/) {
            push @imports, $1;
            next;
        }

        # use Pkg::Name ... ;
        if ($line =~ /^\s*use\s+([\w:]+)/) {
            my $pkg = $1;
            next if $pkg =~ /^(strict|warnings|utf8|lib|Cwd|Test|File|Mojo|POSIX|Carp|Data|FindBin|Scalar|List)/;
            push @imports, $pkg;
        }

        # require Pkg::Name;
        if ($line =~ /require\s+([\w:]+)\s*;/) {
            push @imports, $1;
        }
    }
    close $fh;

    # Deduplicate
    my %seen;
    $test_imports{$tf} = [grep { !$seen{$_}++ } @imports];
}

# --- Step 4: Match targets to test files ---

my %results;

for my $target (@targets) {
    my @import_matches;     # t/ files that import this package
    my @name_matches;       # t/ files matching by name convention
    my @all_matches;

    # Match by import
    for my $tf (sort @test_files) {
        for my $imp (@{$test_imports{$tf} // []}) {
            if ($imp eq $target->{pkg}) {
                push @import_matches, { file => $tf, method => 'import', detail => "use/require $imp" };
                last;
            }
        }
    }

    # Match by naming convention
    # Common patterns: t/01_basename.t, t/basename.t, t/NN_basename.t
    my $base = $target->{basename};
    for my $tf (sort @test_files) {
        my $tf_base = fileparse($tf, qr/\.t$/);
        $tf_base = lc($tf_base);
        # Strip leading NN_ prefix for comparison
        my $tf_base_stripped = $tf_base;
        $tf_base_stripped =~ s/^\d+_//;
        if ($tf_base_stripped eq $base || $tf_base eq $base) {
            push @name_matches, { file => $tf, method => 'name', detail => "name match: $tf_base" };
        }
    }

    # Merge and deduplicate
    my %seen;
    for my $m (@import_matches, @name_matches) {
        unless ($seen{$m->{file}}++) {
            push @all_matches, $m;
        }
    }

    $results{$target->{file}} = {
        pkg            => $target->{pkg},
        basename       => $target->{basename},
        import_matches => \@import_matches,
        name_matches   => \@name_matches,
        all_matches    => \@all_matches,
    };

    log_verbose(sprintf("%s (%s): %d test files found",
        $target->{file}, $target->{pkg}, scalar(@all_matches)));
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

    my $any_gap = 0;

    for my $lib_file (sort keys %$results) {
        my $r = $results->{$lib_file};

        print "=" x 60, "\n";
        print "Unit tests for: $lib_file ($r->{pkg})\n";
        print "=" x 60, "\n\n";

        if (!@{$r->{all_matches}}) {
            print "  NO UNIT TEST FOUND\n";
            print "  No t/*.t file imports $r->{pkg} or matches name '$r->{basename}'\n";
            print "  Consider writing one: t/XX_$r->{basename}.t\n\n";
            $any_gap = 1;
            next;
        }

        if (@{$r->{import_matches}}) {
            print "By import (" . scalar(@{$r->{import_matches}}) . " files):\n";
            for my $m (@{$r->{import_matches}}) {
                print "  $m->{file}\n";
                print "    $m->{detail}\n" if $verbose;
            }
            print "\n";
        }

        if (@{$r->{name_matches}}) {
            my @unique_name = grep {
                my $f = $_->{file};
                !grep { $_->{file} eq $f } @{$r->{import_matches}}
            } @{$r->{name_matches}};

            if (@unique_name) {
                print "By naming convention (" . scalar(@unique_name) . " additional files):\n";
                for my $m (@unique_name) {
                    print "  $m->{file}\n";
                    print "    $m->{detail}\n" if $verbose;
                }
                print "\n";
            }
        }

        # Print run command hint
        my @files = map { $_->{file} } @{$r->{all_matches}};
        print "Run command:\n";
        for my $f (@files) {
            print "  PERL5OPT=-MCarp::Always prove --time --verbose -l -Ios-autoinst/ $f\n";
        }
        print "\n";
    }

    if ($any_gap) {
        print "-" x 60, "\n";
        print "NOTE: Some lib modules have no unit test coverage.\n";
        print "Consider adding unit tests before submitting a PR.\n";
    }
}

sub print_json {
    my ($results) = @_;

    my @entries;
    for my $lib_file (sort keys %$results) {
        my $r = $results->{$lib_file};
        push @entries, {
            lib_file => $lib_file,
            package  => $r->{pkg},
            has_test => @{$r->{all_matches}} ? JSON::PP::true : JSON::PP::false,
            tests    => [map { { file => $_->{file}, method => $_->{method} } }
                             @{$r->{all_matches}}],
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
find_unit_test.pl : Find unit test files (t/*.t) that cover a given lib/*.pm.

USAGE
    perl find_unit_test.pl [OPTIONS] lib/A/B.pm [lib/C/D.pm ...]

DESCRIPTION
    Given one or more lib/*.pm file paths, finds the corresponding unit test
    files in the t/ directory. Two matching strategies are used:

    1. Import matching: scans every t/*.t file for use/require statements
       that import the target lib package (e.g. "use sles4sap::ipaddr2;").

    2. Naming convention: matches t/ files whose basename (after stripping
       the leading NN_ prefix) equals the lib module basename. For example,
       lib/sles4sap/ipaddr2.pm matches t/22_ipaddr2.t.

    When no unit test is found for a module, the script reports the gap and
    suggests a filename for a new test file.

OPTIONS
    --repo DIR
        Path to the OSADO repository root. Defaults to the current directory.
        The directory must contain lib/ and t/ subdirectories.

    --verbose
        Show the match method (import vs. naming convention) for each result.

    --json
        Output results as JSON instead of human-readable text.

    --help, -h
        Show this help message and exit.

EXAMPLES
    perl find_unit_test.pl lib/sles4sap/ipaddr2.pm

    perl find_unit_test.pl --repo /path/to/osado \
        lib/publiccloud/utils.pm lib/utils.pm

    perl find_unit_test.pl --verbose --repo /path/to/osado lib/LTP/utils.pm

OUTPUT
    For each lib module, prints the matching t/*.t files grouped by match
    method, followed by the prove command to run them. If no test is found,
    prints a "NO UNIT TEST FOUND" warning with a suggested filename.

SEE ALSO
    classify_changes.pl, find_affected_tests.pl
EOF
    return 1;
}

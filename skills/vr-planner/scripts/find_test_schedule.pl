#!/usr/bin/perl
# find_test_schedule.pl — Find how a test module gets scheduled in openQA.
# Run with --help for full usage information.

use strict;
use warnings;
use File::Find;
use File::Spec;
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

die "Not a valid OSADO repo: $repo_dir (missing tests/ or schedule/)\n"
    unless -d "$repo_dir/tests";

my @input_paths = @ARGV;
if (!@input_paths) {
    print_usage();
    exit 1;
}

# --- Step 1: Convert test file paths to bare paths ---

sub test_path_to_bare {
    my ($path) = @_;
    $path =~ s{^\Q$repo_dir\E/}{};
    $path =~ s{^\.\/}{};
    $path =~ s{^tests/}{};
    $path =~ s{\.pm$}{};
    return $path;
}

my @targets;    # [{file => "tests/A/B.pm", bare => "A/B"}, ...]

for my $path (@input_paths) {
    unless ($path =~ m{(?:^|/)tests/.*\.pm$} || $path =~ m{^[^/]+\.pm$}) {
        warn "Warning: '$path' does not look like a tests/*.pm path, skipping\n";
        next;
    }
    my $bare = test_path_to_bare($path);
    $path =~ s{^\Q$repo_dir\E/}{};
    $path =~ s{^\.\/}{};
    $path = "tests/$bare.pm" unless $path =~ m{^tests/};
    push @targets, { file => $path, bare => $bare };
}
die "No valid tests/*.pm paths provided\n" unless @targets;

log_verbose("Targets: " . join(", ", map { $_->{bare} } @targets));

# --- Step 2: Scan YAML schedule files ---

my @schedule_files;
if (-d "$repo_dir/schedule") {
    find(sub {
        return unless /\.ya?ml$/ && -f;
        push @schedule_files, File::Spec->abs2rel($File::Find::name, $repo_dir);
    }, "$repo_dir/schedule");
}

log_verbose("Found " . scalar(@schedule_files) . " schedule files");

sub search_yaml_schedules {
    my ($bare_path) = @_;
    my @matches;

    for my $sched_file (@schedule_files) {
        my $abs_path = "$repo_dir/$sched_file";
        open my $fh, '<', $abs_path or next;
        my $lineno = 0;
        while (my $line = <$fh>) {
            $lineno++;
            chomp $line;
            # YAML schedule entries are indented lines like:
            #   - sles4sap/ipaddr2/deploy
            # or inside conditional_schedule blocks
            if ($line =~ /\b\Q$bare_path\E\b/) {
                push @matches, {
                    file    => $sched_file,
                    line    => $lineno,
                    content => $line,
                    type    => 'yaml_schedule',
                };
            }
        }
        close $fh;
    }

    return @matches;
}

# --- Step 3: Scan programmatic loaders ---

my @loader_files;
# lib/main_*.pm files
if (-d "$repo_dir/lib") {
    find(sub {
        return unless /^main_.*\.pm$/ && -f;
        push @loader_files, File::Spec->abs2rel($File::Find::name, $repo_dir);
    }, "$repo_dir/lib");
}
# products/*/main.pm files
if (-d "$repo_dir/products") {
    find(sub {
        return unless /^main\.pm$/ && -f;
        push @loader_files, File::Spec->abs2rel($File::Find::name, $repo_dir);
    }, "$repo_dir/products");
}
# Also check main.pm at root
push @loader_files, 'main.pm' if -f "$repo_dir/main.pm";

log_verbose("Found " . scalar(@loader_files) . " loader files");

# --- Step 3b: Build index of loadtest() calls in tests/**/*.pm ---
#
# Some test modules are not loaded directly by YAML schedules or lib/main_*.pm
# loaders.  Instead, a "scheduler" .pm file in tests/ (e.g.
# hana_sr_schedule_deployment.pm) calls loadtest('target/module') and is
# itself listed in a YAML schedule.  This creates a two-level indirection:
#
#   schedule/foo.yml → tests/area/scheduler.pm → tests/area/target.pm
#
# We build a bare-path index of all loadtest() calls found in tests/**/*.pm
# so we can do a transitive lookup when direct searches come up empty.

my %test_scheduler_index;    # bare_path => [ {file, line, content}, ... ]

if (-d "$repo_dir/tests") {
    find(
        {
            wanted => sub {
                return unless /\.pm$/ && -f;
                my $fpath = File::Spec->abs2rel($_, $repo_dir);
                open my $fh, '<', $_ or return;
                my $lineno = 0;
                while (my $line = <$fh>) {
                    $lineno++;
                    chomp $line;
                    next if $line =~ /^\s*#/;
                    if ($line =~ /\bloadtest\s*\(\s*['"]([^'"]+)['"]/) {
                        my $bare_ref = $1;
                        push @{$test_scheduler_index{$bare_ref}},
                            { file => $fpath, line => $lineno, content => $line };
                    }
                }
                close $fh;
            },
            no_chdir => 1,
        },
        "$repo_dir/tests"
    );
}

log_verbose(
    "Built test scheduler index: "
        . scalar(keys %test_scheduler_index)
        . " bare paths indexed from tests/**/*.pm"
);

sub search_programmatic_loaders {
    my ($bare_path) = @_;
    my @matches;

    # For loadtest_kernel: tests/kernel/foo.pm -> bare is kernel/foo
    # loadtest_kernel('foo') prepends tests/kernel/
    my $kernel_name;
    if ($bare_path =~ m{^kernel/(.+)$}) {
        $kernel_name = $1;
    }

    for my $loader (@loader_files) {
        my $abs_path = "$repo_dir/$loader";
        open my $fh, '<', $abs_path or next;
        my $lineno = 0;
        while (my $line = <$fh>) {
            $lineno++;
            chomp $line;

            # Skip comments
            next if $line =~ /^\s*#/;

            # Pattern: loadtest("A/B") or loadtest('A/B') or loadtest "A/B"
            if ($line =~ /loadtest\s*[\s(]\s*["']?\Q$bare_path\E["']?/) {
                push @matches, {
                    file    => $loader,
                    line    => $lineno,
                    content => $line,
                    type    => 'loadtest',
                };
            }

            # Pattern: loadtest_kernel('name') for tests/kernel/*
            if ($kernel_name && $line =~ /loadtest_kernel\s*[\s(]\s*["']?\Q$kernel_name\E["']?/) {
                push @matches, {
                    file    => $loader,
                    line    => $lineno,
                    content => $line,
                    type    => 'loadtest_kernel',
                };
            }
        }
        close $fh;
    }

    return @matches;
}

# --- Step 4: Check for load_testdir matches ---

sub search_testdir_loaders {
    my ($bare_path) = @_;
    my @matches;

    # load_testdir loads all .pm files in a tests/ subdirectory
    # If bare_path is "A/B/C", then load_testdir("A/B") would load it
    my ($parent_dir) = $bare_path =~ m{^(.+)/[^/]+$};
    return @matches unless $parent_dir;

    # Also check just the top-level dir: load_testdir("A")
    my ($top_dir) = $bare_path =~ m{^([^/]+)/};

    for my $loader (@loader_files) {
        my $abs_path = "$repo_dir/$loader";
        open my $fh, '<', $abs_path or next;
        my $lineno = 0;
        while (my $line = <$fh>) {
            $lineno++;
            chomp $line;
            next if $line =~ /^\s*#/;

            # Pattern: load_testdir("$suite") or load_testdir($var)
            if ($line =~ /load_testdir\s*\(/) {
                # Check if the directory matches
                if ($line =~ /load_testdir\s*\(\s*["']\Q$parent_dir\E["']/) {
                    push @matches, {
                        file    => $loader,
                        line    => $lineno,
                        content => $line,
                        type    => 'load_testdir',
                    };
                } elsif ($top_dir && $line =~ /load_testdir\s*\(\s*["']\Q$top_dir\E["']/) {
                    push @matches, {
                        file    => $loader,
                        line    => $lineno,
                        content => $line,
                        type    => 'load_testdir',
                    };
                } elsif ($line =~ /load_testdir\s*\(\s*\$/) {
                    # Dynamic variable — can't resolve statically, flag it
                    push @matches, {
                        file    => $loader,
                        line    => $lineno,
                        content => $line,
                        type    => 'load_testdir_dynamic',
                    };
                }
            }
        }
        close $fh;
    }

    return @matches;
}

# --- Step 5: Search for indirect loading via tests/*.pm scheduler modules ---
#
# Given a bare target path, look it up in the pre-built index, then do a
# secondary YAML schedule search for each scheduler module found.

sub search_test_schedulers {
    my ($bare_path) = @_;
    my @matches;

    my $refs = $test_scheduler_index{$bare_path} // [];
    for my $ref (@$refs) {
        my $scheduler_bare = $ref->{file};
        $scheduler_bare =~ s{^tests/}{};
        $scheduler_bare =~ s{\.pm$}{};

        my @yaml_for_scheduler = search_yaml_schedules($scheduler_bare);

        push @matches, {
            file           => $ref->{file},
            line           => $ref->{line},
            content        => $ref->{content},
            type           => 'loadtest_via_scheduler',
            scheduler_bare => $scheduler_bare,
            yaml_schedules => \@yaml_for_scheduler,
        };
    }
    return @matches;
}

# --- Main: process each target ---

my %results;    # target_file => { yaml => [...], programmatic => [...], testdir => [...], schedulers => [...] }

for my $target (@targets) {
    my @yaml_matches  = search_yaml_schedules($target->{bare});
    my @prog_matches  = search_programmatic_loaders($target->{bare});
    my @tdir_matches  = search_testdir_loaders($target->{bare});
    my @sched_matches = search_test_schedulers($target->{bare});

    $results{$target->{file}} = {
        bare         => $target->{bare},
        yaml         => \@yaml_matches,
        programmatic => \@prog_matches,
        testdir      => \@tdir_matches,
        schedulers   => \@sched_matches,
    };
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

    for my $target_file (sort keys %$results) {
        my $r = $results->{$target_file};
        my $bare = $r->{bare};
        my @yaml  = @{$r->{yaml}};
        my @prog  = @{$r->{programmatic}};
        my @tdir  = @{$r->{testdir}};
        my @sched = @{$r->{schedulers} // []};
        my $total = scalar(@yaml) + scalar(@prog) + scalar(@tdir) + scalar(@sched);

        print "=" x 60, "\n";
        print "Schedule for: $target_file (bare: $bare)\n";
        print "=" x 60, "\n\n";

        if ($total == 0) {
            print "  No scheduling references found.\n";
            print "  This test may be loaded via:\n";
            print "    - A dynamic load_testdir() with a variable argument\n";
            print "    - A conditional loadtest() behind runtime logic\n";
            print "    - Browse the openQA web UI to find a job that runs it\n";
            print "\n";
            next;
        }

        if (@yaml) {
            print "YAML schedules (" . scalar(@yaml) . " matches):\n";
            for my $m (@yaml) {
                print "  $m->{file}:$m->{line}\n";
                if ($verbose) {
                    my $trimmed = $m->{content};
                    $trimmed =~ s/^\s+//;
                    print "    $trimmed\n";
                }
            }
            print "\n";

            # Extract unique schedule files for VR hint
            my %sched_files = map { $_->{file} => 1 } @yaml;
            print "  VR hint — clone a job with one of these YAML_SCHEDULE values:\n";
            for my $sf (sort keys %sched_files) {
                print "    YAML_SCHEDULE=$sf\n";
            }
            print "\n";
        }

        if (@prog) {
            print "Programmatic loaders (" . scalar(@prog) . " matches):\n";
            for my $m (@prog) {
                my $label = $m->{type} eq 'loadtest_kernel'
                    ? 'loadtest_kernel' : 'loadtest';
                print "  $m->{file}:$m->{line} ($label)\n";
                if ($verbose) {
                    my $trimmed = $m->{content};
                    $trimmed =~ s/^\s+//;
                    print "    $trimmed\n";
                }
            }
            print "\n";
            print "  VR hint — find a job whose TEST triggers the loader above.\n";
            print "  Browse the relevant job group on openqa.suse.de.\n";
            print "\n";
        }

        if (@tdir) {
            my @static  = grep { $_->{type} eq 'load_testdir' } @tdir;
            my @dynamic = grep { $_->{type} eq 'load_testdir_dynamic' } @tdir;

            if (@static) {
                print "Directory loaders (" . scalar(@static) . " matches):\n";
                for my $m (@static) {
                    print "  $m->{file}:$m->{line}\n";
                    if ($verbose) {
                        my $trimmed = $m->{content};
                        $trimmed =~ s/^\s+//;
                        print "    $trimmed\n";
                    }
                }
                print "\n";
            }

            if (@dynamic) {
                print "Dynamic directory loaders (may load this test, " .
                    scalar(@dynamic) . " candidates):\n";
                for my $m (@dynamic) {
                    print "  $m->{file}:$m->{line}\n";
                    if ($verbose) {
                        my $trimmed = $m->{content};
                        $trimmed =~ s/^\s+//;
                        print "    $trimmed\n";
                    }
                }
                print "\n";
            }
        }

        if (@sched) {
            print "Indirect via test scheduler modules (" . scalar(@sched) . " match(es)):\n";
            my %vr_hint_schedules;
            for my $m (@sched) {
                print "  $m->{file}:$m->{line}\n";
                if ($verbose) {
                    my $trimmed = $m->{content};
                    $trimmed =~ s/^\s+//;
                    print "    $trimmed\n";
                }
                if (@{$m->{yaml_schedules}}) {
                    for my $ys (@{$m->{yaml_schedules}}) {
                        print "    → $ys->{file}:$ys->{line}\n" if $verbose;
                        $vr_hint_schedules{$ys->{file}} = 1;
                    }
                } else {
                    print "    (scheduler module $m->{scheduler_bare} not found in any YAML schedule)\n";
                }
            }
            print "\n";
            if (%vr_hint_schedules) {
                print "  VR hint — clone a job with one of these YAML_SCHEDULE values:\n";
                for my $sf (sort keys %vr_hint_schedules) {
                    print "    YAML_SCHEDULE=$sf\n";
                }
                print "\n";
            }
        }
    }
}

sub print_json {
    my ($results) = @_;

    my @entries;
    for my $target_file (sort keys %$results) {
        my $r = $results->{$target_file};

        my @matches_out;
        for my $list_name (qw(yaml programmatic testdir)) {
            for my $m (@{$r->{$list_name}}) {
                push @matches_out, {
                    file    => $m->{file},
                    line    => $m->{line} + 0,
                    type    => $m->{type},
                    content => $m->{content},
                };
            }
        }

        # Scheduler matches: flatten to yaml_schedule entries for find_openqa_job.pl
        for my $m (@{$r->{schedulers} // []}) {
            for my $ys (@{$m->{yaml_schedules}}) {
                push @matches_out, {
                    file             => $ys->{file},
                    line             => $ys->{line} + 0,
                    type             => 'yaml_schedule',
                    content          => $ys->{content},
                    via_scheduler    => $m->{file},
                    scheduler_line   => $m->{line} + 0,
                };
            }
            # If the scheduler module itself has no YAML schedule
            if (!@{$m->{yaml_schedules}}) {
                push @matches_out, {
                    file    => $m->{file},
                    line    => $m->{line} + 0,
                    type    => 'loadtest_via_scheduler',
                    content => $m->{content},
                };
            }
        }

        push @entries, {
            test    => $target_file,
            bare    => $r->{bare},
            matches => \@matches_out,
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
find_test_schedule.pl — Find how a test module gets scheduled in openQA.

USAGE
    perl find_test_schedule.pl [OPTIONS] tests/A/B.pm [tests/C/D.pm ...]

DESCRIPTION
    Given one or more tests/*.pm file paths, determines which openQA
    scheduling mechanism loads each test module and outputs the location.

    Three scheduling mechanisms are checked:

    A. YAML schedules (modern)
       Files in schedule/**/*.yml list test modules as bare paths (without
       the tests/ prefix or .pm suffix). For example, tests/sles4sap/foo.pm
       appears as "sles4sap/foo" in the YAML.

    B. Programmatic loading (legacy)
       lib/main_*.pm and products/*/main.pm files call loadtest("area/name")
       or loadtest_kernel("name") based on job settings at runtime.

    C. Directory loading (rare)
       load_testdir($dir) in lib/main_common.pm globs ALL .pm files in a
       tests/ subdirectory dynamically — no static reference to individual
       test modules.

OPTIONS
    --repo DIR
        Path to the OSADO repository root. Defaults to the current directory.

    --verbose
        Show the matching source line for each result.

    --json
        Output results as JSON instead of human-readable text.

    --help, -h
        Show this help message and exit.

EXAMPLES
    perl find_test_schedule.pl tests/sles4sap/ipaddr2/deploy.pm

    perl find_test_schedule.pl --repo /path/to/osado \
        tests/publiccloud/registration.pm tests/kernel/install_ltp.pm

    perl find_test_schedule.pl --verbose --repo /path/to/osado \
        tests/sles4sap/ipaddr2/deploy.pm

SEE ALSO
    classify_changes.pl, find_affected_tests.pl
EOF
    return 1;
}

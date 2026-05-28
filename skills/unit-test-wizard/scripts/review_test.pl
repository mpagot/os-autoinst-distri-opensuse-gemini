#!/usr/bin/perl
# review_test.pl - Audit an existing OSADO unit test file against best practices.
#
# Usage:
#   perl review_test.pl --repo /path/to/osado t/21_azure_cli.t
#   perl review_test.pl --json t/35_ibsm.t
#
# Checks the test file against the established patterns and reports pass/fail
# for each item in the checklist.

use strict;
use warnings;
use Getopt::Long;
use File::Spec;
use Cwd qw(abs_path);

my $repo = '.';
my $json_mode = 0;
my $verbose = 0;
my $help = 0;

GetOptions(
    'repo=s'    => \$repo,
    'json'      => \$json_mode,
    'verbose'   => \$verbose,
    'help'      => \$help,
) or die "Error in command line arguments\n";

if ($help) {
    print_usage();
    exit 0;
}

my $test_path = shift @ARGV;
unless ($test_path) {
    print STDERR "Error: No test file path provided.\n\n";
    print_usage();
    exit 1;
}

$repo = abs_path($repo);
my $full_test_path = File::Spec->file_name_is_absolute($test_path)
    ? $test_path
    : File::Spec->catfile($repo, $test_path);

unless (-f $full_test_path) {
    die "Error: File not found: $full_test_path\n";
}

# Read the test file
open(my $fh, '<', $full_test_path) or die "Cannot read $full_test_path: $!\n";
my $content = do { local $/; <$fh> };
close $fh;

my @lines = split /\n/, $content;

# Run all checks
my @results;

push @results, check_strict_warnings($content);
push @results, check_required_imports($content);
push @results, check_list_util_import($content);
push @results, check_module_under_test($content);
push @results, check_subtest_naming($content);
push @results, check_no_shared_calls($content, \@lines);
push @results, check_no_auto($content);
push @results, check_record_info_mocked($content, \@lines, $repo);
push @results, check_note_debug($content);
push @results, check_done_testing($content);
push @results, check_no_generic_values($content);
push @results, check_no_mock_method($content);
push @results, check_redefine_usage($content);
push @results, check_set_var_cleanup($content, \@lines);

# Output results
if ($json_mode) {
    require JSON::PP;
    my $output = {
        file    => $test_path,
        checks  => \@results,
        passed  => scalar(grep { $_->{status} eq 'PASS' } @results),
        failed  => scalar(grep { $_->{status} eq 'FAIL' } @results),
        warned  => scalar(grep { $_->{status} eq 'WARN' } @results),
    };
    print JSON::PP->new->pretty->canonical->encode($output);
}
else {
    my $pass_count = 0;
    my $fail_count = 0;
    my $warn_count = 0;

    for my $r (@results) {
        my $icon;
        if ($r->{status} eq 'PASS') {
            $icon = 'PASS';
            $pass_count++;
        }
        elsif ($r->{status} eq 'FAIL') {
            $icon = 'FAIL';
            $fail_count++;
        }
        else {
            $icon = 'WARN';
            $warn_count++;
        }
        printf "  [%s] %s\n", $icon, $r->{check};
        if ($r->{detail} && ($r->{status} ne 'PASS' || $verbose)) {
            printf "         %s\n", $r->{detail};
        }
    }

    print "\n";
    printf "Results: %d passed, %d failed, %d warnings (of %d checks)\n",
        $pass_count, $fail_count, $warn_count, scalar @results;

    exit($fail_count > 0 ? 1 : 0);
}

exit 0;

# =============================================================================
# Check subroutines
# =============================================================================

sub check_strict_warnings {
    my ($content) = @_;
    my $has_strict = $content =~ /^use strict;/m;
    my $has_warnings = $content =~ /^use warnings;/m;
    return {
        check  => 'use strict; use warnings;',
        status => ($has_strict && $has_warnings) ? 'PASS' : 'FAIL',
        detail => (!$has_strict ? 'Missing use strict;' : '') .
                  (!$has_warnings ? ' Missing use warnings;' : ''),
    };
}

sub check_required_imports {
    my ($content) = @_;
    my @required = ('Test::More', 'Test::Exception', 'Test::Warnings',
                    'Test::MockModule', 'Test::Mock::Time');
    my @missing;
    for my $mod (@required) {
        unless ($content =~ /^use $mod/m) {
            push @missing, $mod;
        }
    }
    return {
        check  => 'Required test module imports',
        status => @missing ? 'FAIL' : 'PASS',
        detail => @missing ? 'Missing: ' . join(', ', @missing) : '',
    };
}

sub check_list_util_import {
    my ($content) = @_;
    my $has_it = $content =~ /use List::Util\b/;
    return {
        check  => 'List::Util qw(any none) imported',
        status => $has_it ? 'PASS' : 'WARN',
        detail => $has_it ? '' : 'Consider importing List::Util qw(any none) for assertion idioms',
    };
}

sub check_module_under_test {
    my ($content) = @_;
    # Look for a use statement that loads a project module (not Test::*)
    # Matches any package that is not a known test framework module
    my $has_mut = $content =~ /^use (?!Test::)(?!strict)(?!warnings)(?!List::)(?!Getopt::)(?!File::)(?!Cwd)(?!JSON)[\w:]+/m;
    return {
        check  => 'Module under test is imported',
        status => $has_mut ? 'PASS' : 'WARN',
        detail => $has_mut ? '' : 'No project module import found (expected a use statement for the module under test)',
    };
}

sub check_subtest_naming {
    my ($content) = @_;
    my @subtests = $content =~ /subtest\s+'([^']+)'/g;
    my @bad;
    for my $name (@subtests) {
        unless ($name =~ /^\[/) {
            push @bad, $name;
        }
    }
    if (!@subtests) {
        return {
            check  => 'Subtest naming convention [function_name]',
            status => 'WARN',
            detail => 'No subtests found',
        };
    }
    return {
        check  => 'Subtest naming convention [function_name]',
        status => @bad ? 'FAIL' : 'PASS',
        detail => @bad ? 'Subtests not starting with [name]: ' . join(', ', @bad[0 .. ($#bad > 2 ? 2 : $#bad)]) : '',
    };
}

sub check_no_shared_calls {
    my ($content, $lines) = @_;
    # Check if @calls is declared outside a subtest block
    my $in_subtest = 0;
    my @violations;
    for my $i (0 .. $#$lines) {
        my $line = $lines->[$i];
        if ($line =~ /^subtest\b/) {
            $in_subtest = 1;
        }
        if ($in_subtest && $line =~ /^\};/) {
            $in_subtest = 0;
        }
        if (!$in_subtest && $line =~ /my \@calls\b/) {
            push @violations, $i + 1;
        }
    }
    return {
        check  => 'No shared @calls outside subtests',
        status => @violations ? 'FAIL' : 'PASS',
        detail => @violations ? 'my @calls outside subtest at line(s): ' . join(', ', @violations) : '',
    };
}

sub check_no_auto {
    my ($content) = @_;
    my @new_calls = $content =~ /Test::MockModule->new\([^)]+\)/g;
    my @missing_no_auto;
    for my $call (@new_calls) {
        unless ($call =~ /no_auto\s*=>\s*1/) {
            push @missing_no_auto, $call;
        }
    }
    if (!@new_calls) {
        return {
            check  => 'MockModule created with no_auto => 1',
            status => 'PASS',
            detail => 'No Test::MockModule usage found',
        };
    }
    return {
        check  => 'MockModule created with no_auto => 1',
        status => @missing_no_auto ? 'FAIL' : 'PASS',
        detail => @missing_no_auto ? scalar(@missing_no_auto) . ' MockModule->new() call(s) without no_auto => 1' : '',
    };
}

sub check_record_info_mocked {
    my ($content, $lines, $repo_path) = @_;
    # Check that subtests with @calls also mock record_info,
    # but only flag if the tested function actually calls record_info.

    # Step 1: Identify the module under test and find its source file
    my $lib_content = _load_module_source($content, $repo_path);

    # Step 2: Parse which functions in the library call record_info
    my %func_uses_record_info;
    if ($lib_content) {
        %func_uses_record_info = _parse_functions_using_record_info($lib_content);
    }

    # Step 3: Find subtests with @calls but no record_info mock
    my @subtests_missing_record_info;
    my $current_subtest = '';
    my $current_func = '';
    my $has_calls = 0;
    my $has_record_info_mock = 0;

    for my $line (@$lines) {
        if ($line =~ /subtest\s+'([^']+)'/) {
            # Process the previous subtest
            if ($current_subtest && $has_calls && !$has_record_info_mock) {
                # Only flag if we know the function uses record_info
                if (!$lib_content || $func_uses_record_info{$current_func}) {
                    push @subtests_missing_record_info, $current_subtest;
                }
            }
            $current_subtest = $1;
            # Extract function name from [function_name] pattern
            $current_func = '';
            if ($current_subtest =~ /^\[(\w+)\]/) {
                $current_func = $1;
            }
            $has_calls = 0;
            $has_record_info_mock = 0;
        }
        if ($line =~ /my \@calls\b/) {
            $has_calls = 1;
        }
        if ($line =~ /redefine\(record_info\b/) {
            $has_record_info_mock = 1;
        }
    }
    # Check last subtest
    if ($current_subtest && $has_calls && !$has_record_info_mock) {
        if (!$lib_content || $func_uses_record_info{$current_func}) {
            push @subtests_missing_record_info, $current_subtest;
        }
    }

    return {
        check  => 'record_info mocked in subtests with @calls',
        status => @subtests_missing_record_info ? 'WARN' : 'PASS',
        detail => @subtests_missing_record_info
            ? 'Missing record_info mock in: ' . join(', ', @subtests_missing_record_info[0 .. ($#subtests_missing_record_info > 2 ? 2 : $#subtests_missing_record_info)])
            : '',
    };
}

=head2 _load_module_source

Given test file content and repo path, finds and reads the library module source.
Returns the file content or empty string if not found.

=cut

sub _load_module_source {
    my ($test_content, $repo_path) = @_;

    # Find the module under test from use statements
    # Look for: use some::package::name; or use single_word_module;
    my @candidates;
    while ($test_content =~ /^use (\w+(?:::\w+)*)/mg) {
        my $mod = $1;
        # Skip test framework, standard modules, and pragmas
        next if $mod =~ /^(Test::|List::|Getopt::|File::|Cwd|JSON|Data::|POSIX|Carp|Scalar::|strict|warnings|utf8|constant|lib|base|parent)/;
        push @candidates, $mod;
    }

    return '' unless @candidates;

    # Try each candidate, convert package::name to lib/package/name.pm
    for my $mod (@candidates) {
        my $rel_path = $mod;
        $rel_path =~ s{::}{/}g;
        $rel_path = "lib/$rel_path.pm";
        my $full_path = File::Spec->catfile($repo_path, $rel_path);
        if (-f $full_path) {
            open(my $fh, '<', $full_path) or next;
            my $source = do { local $/; <$fh> };
            close $fh;
            return $source;
        }
    }

    return '';
}

=head2 _parse_functions_using_record_info

Given a .pm file content, returns a hash where keys are function names
that contain a call to record_info.

=cut

sub _parse_functions_using_record_info {
    my ($lib_content) = @_;
    my @lines = split /\n/, $lib_content;

    my %result;
    my $current_func = '';
    my $brace_depth = 0;
    my $in_func = 0;

    for my $line (@lines) {
        if ($line =~ /^sub\s+(\w+)/) {
            $current_func = $1;
            $in_func = 1;
            $brace_depth = 0;
            $brace_depth++ if $line =~ /\{/;
            next;
        }

        if ($in_func) {
            $brace_depth += (() = $line =~ /\{/g);
            $brace_depth -= (() = $line =~ /\}/g);

            if ($line =~ /\brecord_info\b/) {
                $result{$current_func} = 1;
            }

            if ($brace_depth <= 0) {
                $in_func = 0;
                $current_func = '';
            }
        }
    }

    return %result;
}

sub check_note_debug {
    my ($content) = @_;
    my $has_note_pattern = $content =~ /note\(.*join\(.*\@calls/;
    # Also check the simpler pattern
    $has_note_pattern ||= $content =~ /note\(.*-->.*\@calls/;
    return {
        check  => 'Debug note() before assertions',
        status => $has_note_pattern ? 'PASS' : 'WARN',
        detail => $has_note_pattern ? '' : 'Consider adding note("\\n  -->  " . join("\\n  -->  ", @calls)) for debug output',
    };
}

sub check_done_testing {
    my ($content) = @_;
    my $has_done = $content =~ /^done_testing/m;
    my $has_plan = $content =~ /plan\s+tests\s*=>/;
    if ($has_plan) {
        return {
            check  => 'File ends with done_testing (no fixed plan)',
            status => 'FAIL',
            detail => 'Uses plan tests => N (prefer done_testing)',
        };
    }
    return {
        check  => 'File ends with done_testing (no fixed plan)',
        status => $has_done ? 'PASS' : 'FAIL',
        detail => $has_done ? '' : 'Missing done_testing at end of file',
    };
}

sub check_no_generic_values {
    my ($content) = @_;
    # Look for obviously generic test values in function calls
    my @generics;
    while ($content =~ /=>\s*'(foo|bar|baz|test|qux|hello|world)'/gi) {
        push @generics, $1;
    }
    # Deduplicate
    my %seen;
    @generics = grep { !$seen{$_}++ } @generics;

    return {
        check  => 'No generic fake values (foo, bar, test)',
        status => @generics ? 'WARN' : 'PASS',
        detail => @generics ? 'Found generic values: ' . join(', ', @generics) . ' -- use distinctive names instead' : '',
    };
}

sub check_no_mock_method {
    my ($content) = @_;
    # Check for $mock->mock() which should be $mock->redefine()
    my $has_mock_call = $content =~ /\$\w+->mock\s*\(/;
    return {
        check  => 'Uses redefine() not mock()',
        status => $has_mock_call ? 'FAIL' : 'PASS',
        detail => $has_mock_call ? 'Found $mock->mock() -- use $mock->redefine() instead' : '',
    };
}

sub check_redefine_usage {
    my ($content) = @_;
    my $has_redefine = $content =~ /->redefine\(/;
    my $has_mock_module = $content =~ /Test::MockModule/;
    if ($has_mock_module && !$has_redefine) {
        return {
            check  => 'Test::MockModule uses redefine()',
            status => 'WARN',
            detail => 'Test::MockModule imported but no redefine() calls found',
        };
    }
    return {
        check  => 'Test::MockModule uses redefine()',
        status => 'PASS',
        detail => '',
    };
}

sub check_set_var_cleanup {
    my ($content, $lines) = @_;
    # Count set_var calls that set a value vs set_var with undef
    my @sets = $content =~ /set_var\s*\(\s*'[^']+'\s*,\s*(?!undef)/g;
    my @unsets = $content =~ /set_var\s*\(\s*'[^']+'\s*,\s*undef/g;

    if (!@sets) {
        return {
            check  => 'set_var cleaned up with undef',
            status => 'PASS',
            detail => 'No set_var usage found',
        };
    }
    if (scalar @sets > scalar @unsets) {
        return {
            check  => 'set_var cleaned up with undef',
            status => 'WARN',
            detail => sprintf('%d set_var calls but only %d undef cleanups', scalar @sets, scalar @unsets),
        };
    }
    return {
        check  => 'set_var cleaned up with undef',
        status => 'PASS',
        detail => '',
    };
}

# =============================================================================

=head2 print_usage

Prints usage information.

=cut

sub print_usage {
    print <<"USAGE";
Usage: review_test.pl [OPTIONS] <test_file>

Audit an OSADO unit test file against established best practices.

Arguments:
  test_file         Path to the .t file (relative to repo root)

Options:
  --repo PATH       Path to the OSADO repository (default: current directory)
  --json            Output structured JSON report
  --verbose         Show details even for passing checks
  --help            Show this help message

Examples:
  perl review_test.pl --repo /path/to/osado t/21_azure_cli.t
  perl review_test.pl --json t/35_ibsm.t
  perl review_test.pl --verbose t/22_ipaddr2.t

Exit codes:
  0     All checks passed (or warnings only)
  1     One or more checks failed
USAGE
}

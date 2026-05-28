#!/usr/bin/perl
# scaffold_test.pl - Generate a unit test skeleton for an OSADO Perl library module.
#
# Usage:
#   perl scaffold_test.pl --repo /path/to/osado lib/mypackage/module.pm
#   perl scaffold_test.pl --repo /path/to/osado --output t/40_module.t lib/mypackage/module.pm
#
# Parses the given .pm file for:
#   - Package name
#   - Exported sub names
#   - Mandatory arguments (croak patterns)
#   - Optional arguments (//= default patterns)
#   - Which testapi functions are called (assert_script_run, script_run, etc.)
#
# Outputs a complete .t file to stdout (or --output file).

use strict;
use warnings;
use Getopt::Long;
use File::Basename;
use File::Spec;
use Cwd qw(abs_path);

my $repo = '.';
my $output = '';
my $json_mode = 0;
my $verbose = 0;
my $help = 0;

GetOptions(
    'repo=s'    => \$repo,
    'output=s'  => \$output,
    'json'      => \$json_mode,
    'verbose'   => \$verbose,
    'help'      => \$help,
) or die "Error in command line arguments\n";

if ($help) {
    print_usage();
    exit 0;
}

my $module_path = shift @ARGV;
unless ($module_path) {
    print STDERR "Error: No module path provided.\n\n";
    print_usage();
    exit 1;
}

$repo = abs_path($repo);
my $full_module_path = File::Spec->file_name_is_absolute($module_path)
    ? $module_path
    : File::Spec->catfile($repo, $module_path);

unless (-f $full_module_path) {
    die "Error: File not found: $full_module_path\n";
}

# Parse the module
my $info = parse_module($full_module_path);

# Determine test file number
my $test_number = find_next_test_number($repo);

# Determine test file name
my $test_filename = generate_test_filename($module_path, $test_number);

# Generate the test content
my $test_content = generate_test($info, $module_path);

# Output
if ($json_mode) {
    require JSON::PP;
    my $result = {
        module_path    => $module_path,
        package_name   => $info->{package},
        functions      => $info->{functions},
        test_filename  => $test_filename,
        test_number    => $test_number,
    };
    print JSON::PP->new->pretty->canonical->encode($result);
}
elsif ($output) {
    open(my $fh, '>', $output) or die "Cannot write to $output: $!\n";
    print $fh $test_content;
    close $fh;
    print STDERR "Written: $output\n" if $verbose;
}
else {
    print $test_content;
}

exit 0;

# =============================================================================
# Subroutines
# =============================================================================

=head2 parse_module

Parses a .pm file and extracts package name, subroutines, mandatory args,
optional args, and which testapi functions are called.

=cut

sub parse_module {
    my ($path) = @_;

    open(my $fh, '<', $path) or die "Cannot read $path: $!\n";
    my @lines = <$fh>;
    close $fh;

    my $content = join('', @lines);

    # Extract package name
    my ($package) = $content =~ /^package\s+([\w:]+)/m;
    $package //= 'unknown';

    # Extract subroutines
    my @functions;
    my $current_sub;
    my $in_sub = 0;
    my $brace_depth = 0;

    for my $line (@lines) {
        # Match sub declarations
        if ($line =~ /^sub\s+(\w+)\s*(?:\(([^)]*)\))?\s*\{?/) {
            my $name = $1;
            my $proto = $2 // '';

            $current_sub = {
                name           => $name,
                mandatory_args => [],
                optional_args  => [],
                calls_testapi  => {},
            };

            $in_sub = 1;
            $brace_depth = 0;
            $brace_depth++ if $line =~ /\{/;
            push @functions, $current_sub;
            next;
        }

        if ($in_sub && $current_sub) {
            $brace_depth += (() = $line =~ /\{/g);
            $brace_depth -= (() = $line =~ /\}/g);

            if ($brace_depth <= 0) {
                $in_sub = 0;
                $current_sub = undef;
                next;
            }

            # Detect mandatory args: croak("Argument < $_ > missing") unless $args{$_}
            # Pattern: foreach (qw(...)) { croak(...) unless $args{$_}; }
            if ($line =~ /foreach\s*\(qw\(([^)]+)\)/) {
                my @args = split(/\s+/, $1);
                push @{$current_sub->{mandatory_args}}, @args;
            }
            # Single-line croak pattern
            elsif ($line =~ /croak\(.*?[<"'](\w+)[>"'].*?\)\s*unless\s+\$args\{['"]*(\w+)/) {
                push @{$current_sub->{mandatory_args}}, $2;
            }
            elsif ($line =~ /croak\b.*unless.*\$args\{(\w+)\}/) {
                push @{$current_sub->{mandatory_args}}, $1;
            }

            # Detect optional args with defaults: $args{foo} //= 'bar'
            if ($line =~ /\$args\{(\w+)\}\s*\/\/=\s*(.+?)\s*;/) {
                push @{$current_sub->{optional_args}}, { name => $1, default => $2 };
            }

            # Detect testapi calls
            for my $api_func (qw(assert_script_run script_run script_output record_info)) {
                if ($line =~ /\b$api_func\b/) {
                    $current_sub->{calls_testapi}{$api_func} = 1;
                }
            }
        }
    }

    # Filter out private subs (starting with _) and very short names
    @functions = grep { $_->{name} !~ /^_/ } @functions;

    return {
        package   => $package,
        functions => \@functions,
        path      => $path,
    };
}

=head2 find_next_test_number

Scans t/ directory for existing NN_*.t files and returns the next available number.

=cut

sub find_next_test_number {
    my ($repo_path) = @_;
    my $t_dir = File::Spec->catdir($repo_path, 't');

    return 40 unless -d $t_dir;

    opendir(my $dh, $t_dir) or return 40;
    my @nums;
    while (my $entry = readdir($dh)) {
        if ($entry =~ /^(\d+)_.*\.t$/) {
            push @nums, int($1);
        }
    }
    closedir $dh;

    return @nums ? (sort { $b <=> $a } @nums)[0] + 1 : 40;
}

=head2 generate_test_filename

Generates the test filename based on the module path.

=cut

sub generate_test_filename {
    my ($module_path, $number) = @_;

    # lib/mypackage/azure_cli.pm -> mypackage_azure_cli
    # lib/mypackage/sub/module.pm -> mypackage_sub_module
    my $name = $module_path;
    $name =~ s{^lib/}{};
    $name =~ s{\.pm$}{};
    $name =~ s{/}{_}g;

    return sprintf("t/%02d_%s.t", $number, $name);
}

=head2 generate_test

Generates the complete test file content.

=cut

sub generate_test {
    my ($info, $module_path) = @_;

    my $package = $info->{package};
    my @functions = @{$info->{functions}};

    # Build the use statement
    my $use_module = "use $package;";

    # Check if any function uses set_var/get_var
    my $needs_testapi = 0;
    for my $func (@functions) {
        # We'll always include testapi for safety in OSADO tests
        $needs_testapi = 1;
        last;
    }

    my $testapi_import = $needs_testapi ? "use testapi qw(set_var);\n" : '';

    # Header
    my $out = <<"HEADER";
use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Warnings;
use Test::MockModule;
use Test::Mock::Time;
use List::Util qw(any none);
${testapi_import}
$use_module

HEADER

    # Generate subtests for each function
    for my $func (@functions) {
        my $fname = $func->{name};
        my @mandatory = @{$func->{mandatory_args}};
        my @optional = @{$func->{optional_args}};
        my %testapi_calls = %{$func->{calls_testapi}};

        # --- Mandatory arg death tests ---
        if (@mandatory) {
            $out .= "subtest '[$fname] missing arguments' => sub {\n";
            for my $i (0 .. $#mandatory) {
                my $missing = $mandatory[$i];
                my @present = map { "$_ => 'X'" }
                    grep { $_ ne $missing } @mandatory;
                my $args_str = join(', ', @present);
                $out .= "    dies_ok { $fname($args_str) }\n";
                $out .= "        'Die for missing argument $missing';\n";
            }
            $out .= "};\n\n";
        }

        # --- Base case subtest ---
        $out .= "subtest '[$fname]' => sub {\n";
        $out .= "    my \@calls;\n";
        $out .= "    my \$mock = Test::MockModule->new('$package', no_auto => 1);\n";

        # Mock the testapi functions this sub calls
        if ($testapi_calls{assert_script_run}) {
            $out .= "    \$mock->redefine(assert_script_run => sub { push \@calls, \$_[0]; return; });\n";
        }
        if ($testapi_calls{script_run}) {
            $out .= "    \$mock->redefine(script_run => sub { push \@calls, \$_[0]; return 0; });\n";
        }
        if ($testapi_calls{script_output}) {
            $out .= "    \$mock->redefine(script_output => sub { push \@calls, \$_[0]; return '{}'; });\n";
        }
        if ($testapi_calls{record_info}) {
            $out .= "    \$mock->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', \@_)); });\n";
        }

        # If no testapi calls detected, add a minimal mock set
        unless (%testapi_calls) {
            $out .= "    \$mock->redefine(assert_script_run => sub { push \@calls, \$_[0]; return; });\n";
            $out .= "    \$mock->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', \@_)); });\n";
        }

        $out .= "\n";

        # Call the function with mandatory args using placeholder values
        # The user should replace these with distinctive, traceable names
        my @call_args;
        for my $i (0 .. $#mandatory) {
            my $placeholder = uc($mandatory[$i]) . '_VALUE';
            push @call_args, "$mandatory[$i] => '$placeholder'";
        }
        my $call_args_str = join(', ', @call_args);
        $out .= "    $fname($call_args_str);\n";
        $out .= "\n";

        # Debug output and assertions
        $out .= "    note(\"\\n  -->  \" . join(\"\\n  -->  \", \@calls));\n";
        $out .= "    ok(\@calls > 0, '$fname executed at least one command');\n";

        # Add placeholder assertions for mandatory args
        for my $i (0 .. $#mandatory) {
            my $placeholder = uc($mandatory[$i]) . '_VALUE';
            $out .= "    ok((any { /$placeholder/ } \@calls), '$mandatory[$i] value is present in command');\n";
        }

        $out .= "};\n\n";

        # --- Optional arg subtests ---
        for my $opt (@optional) {
            my $opt_name = $opt->{name};
            my $default = $opt->{default};
            $out .= "subtest '[$fname] with $opt_name' => sub {\n";
            $out .= "    my \@calls;\n";
            $out .= "    my \$mock = Test::MockModule->new('$package', no_auto => 1);\n";

            if ($testapi_calls{assert_script_run} || !%testapi_calls) {
                $out .= "    \$mock->redefine(assert_script_run => sub { push \@calls, \$_[0]; return; });\n";
            }
            if ($testapi_calls{script_run}) {
                $out .= "    \$mock->redefine(script_run => sub { push \@calls, \$_[0]; return 0; });\n";
            }
            if ($testapi_calls{script_output}) {
                $out .= "    \$mock->redefine(script_output => sub { push \@calls, \$_[0]; return '{}'; });\n";
            }
            $out .= "    \$mock->redefine(record_info => sub { note(join(' ', 'RECORD_INFO -->', \@_)); });\n";

            $out .= "\n";

            # Build call with mandatory args + optional
            my @opt_call_args = @call_args;
            push @opt_call_args, "$opt_name => 'CustomValue'";
            my $opt_args_str = join(', ', @opt_call_args);
            $out .= "    $fname($opt_args_str);\n";
            $out .= "\n";
            $out .= "    note(\"\\n  -->  \" . join(\"\\n  -->  \", \@calls));\n";
            $out .= "    ok((any { /CustomValue/ } \@calls), 'Custom $opt_name value is used');\n";
            $out .= "};\n\n";
        }
    }

    $out .= "done_testing;\n";
    return $out;
}

=head2 print_usage

Prints usage information.

=cut

sub print_usage {
    print <<"USAGE";
Usage: scaffold_test.pl [OPTIONS] <module_path>

Generate a unit test skeleton for an OSADO Perl library module.

Arguments:
  module_path       Path to the .pm file (relative to repo root)

Options:
  --repo PATH       Path to the OSADO repository (default: current directory)
  --output FILE     Write output to FILE instead of stdout
  --json            Output structured JSON (module info, no test code)
  --verbose         Print extra information to stderr
  --help            Show this help message

Examples:
  perl scaffold_test.pl --repo /path/to/osado lib/mypackage/module.pm
  perl scaffold_test.pl --repo . --output t/40_module.t lib/mypackage/module.pm
  perl scaffold_test.pl --json lib/mypackage/other.pm
USAGE
}

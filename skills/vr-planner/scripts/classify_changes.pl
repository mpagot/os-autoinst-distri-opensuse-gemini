#!/usr/bin/perl
# classify_changes.pl — Classify staged/changed files and output a testing plan.
# Run with --help for full usage information.

use strict;
use warnings;
use File::Spec;
use File::Basename;
use Getopt::Long;
use Cwd qw(abs_path);
use JSON::PP;

my $repo_dir;
my $verbose = 0;
my $json_output = 0;
my $use_git_diff_staged = 0;
my $use_git_diff = 0;
my $git_commit;
my $run_helpers = 0;
my $help = 0;

GetOptions(
    'repo=s'          => \$repo_dir,
    'verbose'         => \$verbose,
    'json'            => \$json_output,
    'git-diff-staged' => \$use_git_diff_staged,
    'git-diff'        => \$use_git_diff,
    'git-commit=s'    => \$git_commit,
    'helpers'         => \$run_helpers,
    'help|h'          => \$help,
) or do { print_usage(); exit 1 };

print_usage() && exit 0 if $help;

$repo_dir //= '.';
$repo_dir = abs_path($repo_dir);

die "Not a valid OSADO repo: $repo_dir (missing lib/ or tests/)\n"
    unless -d "$repo_dir/lib" && -d "$repo_dir/tests";

################################################################
# Get file list
my @changed_files;

if (@ARGV) {
    # Files passed as arguments
    @changed_files = @ARGV;
} elsif ($git_commit) {
    @changed_files = get_git_files('commit', $git_commit);
} elsif ($use_git_diff) {
    @changed_files = get_git_files('diff');
} else {
    # Default: git staged (--git-diff-staged or implicit default)
    @changed_files = get_git_files('staged');
}

die "No changed files found. Stage some changes, specify a commit, or pass file paths.\n"
    unless @changed_files;

# Normalize paths
@changed_files = map {
    my $f = $_;
    # removes the absolute repository path if the file path starts with it
    # s{...}{} -> "search for the pattern in the first bracket and replace it with nothing"
    #  \Q ... \E treat $repo_dir as literal characters. File paths might contain . or + that have special meanings in regular expressions
    $f =~ s{^\Q$repo_dir\E/}{};
    # turn ./tests/foo.pm into tests/foo.pm
    $f =~ s{^\.\/}{};
    $f;
} @changed_files;

log_verbose("Changed files (" . scalar(@changed_files) . "): " . join(", ", @changed_files));


################################################################
# Classify files
my %categories = (
    tests    => { files => [], vr_needed => 1, label => 'tests/ -- Test modules' },
    lib      => { files => [], vr_needed => 1, label => 'lib/ -- Shared libraries' },
    t        => { files => [], vr_needed => 0, label => 't/ -- Unit tests' },
    data     => { files => [], vr_needed => 1, label => 'data/ -- Static data files' },
    schedule => { files => [], vr_needed => 1, label => 'schedule/ -- YAML schedules' },
    no_vr    => { files => [], vr_needed => 0, label => 'No VR needed' },
);

for my $file (@changed_files) {
    if ($file =~ m{^tests/}) {
        push @{$categories{tests}{files}}, $file;
    } elsif ($file =~ m{^lib/}) {
        push @{$categories{lib}{files}}, $file;
    } elsif ($file =~ m{^t/}) {
        push @{$categories{t}{files}}, $file;
    } elsif ($file =~ m{^data/}) {
        push @{$categories{data}{files}}, $file;
    } elsif ($file =~ m{^schedule/}) {
        push @{$categories{schedule}{files}}, $file;
    } else {
        push @{$categories{no_vr}{files}}, $file;
    }
}


################################################################
# Output
my $branch   = get_git_branch($repo_dir, $git_commit);
my $fork_url = get_git_fork_url($repo_dir);
log_verbose("Resolved branch: $branch");
log_verbose("Resolved fork URL: " . ($fork_url // '(none)'));

my $report = build_report_data(\%categories, \@changed_files, $repo_dir,
    $branch, $fork_url);

if ($json_output) {
    print_json($report);
} else {
    print_text($report);
}


################################################################
# Run helper scripts if --helpers flag is set
if ($run_helpers) {
    run_helpers(\%categories);
}

exit 0;


=head2 get_git_files

Retrieve changed file paths from git based on the requested input mode.

Falls back to C<git diff HEAD> when staged mode produces no results,
so the script still works for developers who forgot to stage.

  @files = get_git_files($mode, $commit_hash);

Arguments:

  $mode        - One of 'staged', 'diff', or 'commit'
  $commit_hash - Git commit SHA (required when $mode is 'commit', ignored otherwise)

Returns: List of repo-relative file paths (Added/Copied/Modified/Renamed only).

Dies on git command failure.

=cut

sub get_git_files {
    my ($mode, $commit_hash) = @_;
    my $cmd;
    if ($mode eq 'commit') {
        die "--git-commit requires a commit hash\n" unless $commit_hash;
        $cmd = "git -C '$repo_dir' diff-tree --no-commit-id -r --name-only --diff-filter=ACMR '$commit_hash'";
    } elsif ($mode eq 'staged') {
        $cmd = "git -C '$repo_dir' diff --cached --name-only --diff-filter=ACMR";
    } else {
        $cmd = "git -C '$repo_dir' diff --name-only --diff-filter=ACMR";
    }

    log_verbose("Running: $cmd");
    my @files = `$cmd`;
    # $? holds the 16-bit wait status; >> 8 extracts the exit code (bits 8-15)
    my $rc = $? >> 8;
    chomp @files;

    if ($rc != 0) {
        die "git command failed (exit $rc): $cmd\n";
    }

    # If no staged files, try all uncommitted changes
    if (!@files && $mode eq 'staged') {
        log_verbose("No staged files found, trying all uncommitted changes");
        $cmd = "git -C '$repo_dir' diff HEAD --name-only --diff-filter=ACMR";
        @files = `$cmd`;
        chomp @files;
    }

    return @files;
}

=head2 get_git_branch

Resolve the current branch name for use in CASEDIR construction.

When a commit hash is provided, reverse-maps it to a branch name via
C<git branch --contains>. Falls back to the abbreviated commit hash
if no branch contains it.

  $branch = get_git_branch($repo_dir, $commit_hash);

Arguments:

  $repo_dir    - Absolute path to the OSADO repository
  $commit_hash - Optional git commit SHA to resolve

Returns: Branch name string (e.g. 'my-feature'), abbreviated SHA, or 'HEAD'.

=cut

sub get_git_branch {
    my ($repo_dir, $commit_hash) = @_;
    if ($commit_hash) {
        # Find a branch that contains this commit (prefer non-HEAD, non-detached)
        my @branches = `git -C '$repo_dir' branch --contains '$commit_hash' 2>/dev/null`;
        chomp @branches;
        for my $b (@branches) {
            $b =~ s/^\*?\s+//;
            next if $b =~ /HEAD detached/;
            return $b;
        }
        # Fallback: abbreviated commit hash
        my $short = `git -C '$repo_dir' rev-parse --short '$commit_hash' 2>/dev/null`;
        chomp $short;
        return $short || $commit_hash;
    }
    # No commit specified: use current branch
    my $branch = `git -C '$repo_dir' branch --show-current 2>/dev/null`;
    chomp $branch;
    return $branch || 'HEAD';
}

=head2 get_git_fork_url

Resolve the developer's GitHub fork URL from git remotes.

Normalizes SSH and HTTPS remote URLs to a canonical
C<https://github.com/USER/REPO> form for CASEDIR construction.
Tries the 'origin' remote first, then falls back to the first
available remote.

  $url = get_git_fork_url($repo_dir);

Arguments:

  $repo_dir - Absolute path to the OSADO repository

Returns: HTTPS URL string, or undef if no remote is configured.

=cut

sub get_git_fork_url {
    my ($repo_dir) = @_;
    # Try origin first, then any remote
    for my $remote ('origin', '') {
        my $cmd = $remote
            ? "git -C '$repo_dir' remote get-url '$remote' 2>/dev/null"
            : "git -C '$repo_dir' remote 2>/dev/null";
        if (!$remote) {
            my @remotes = `$cmd`;
            chomp @remotes;
            next unless @remotes;
            $cmd = "git -C '$repo_dir' remote get-url '$remotes[0]' 2>/dev/null";
        }
        my $url = `$cmd`;
        chomp $url;
        next unless $url;
        # Normalize: git@github.com:USER/REPO.git or https://github.com/USER/REPO.git
        if ($url =~ m{github\.com[:/](.+?)(?:\.git)?$}) {
            return "https://github.com/$1";
        }
        # Non-GitHub remote: return as-is
        return $url;
    }
    return undef;
}

=head2 find_script

Locate a helper script by filename in the same directory as this script.

  $path = find_script($name);

Arguments:

  $name - Basename of the script to find (e.g. 'find_unit_test.pl')

Returns: Absolute path to the script, or undef if not found.

=cut

sub find_script {
    my ($name) = @_;
    my $dir = dirname(abs_path($0));
    my $path = "$dir/$name";
    return $path if -f $path;
    return undef;
}

=head2 run_helpers

Orchestrate detailed analysis by dispatching to specialized helper scripts
for each non-empty file category.

Mapping:

  tests/    -> find_test_schedule.pl
  lib/      -> find_unit_test.pl + find_affected_tests.pl
               (+ find_test_schedule.pl for function-confirmed targets when --git-commit)
  data/     -> find_data_consumers.pl
  schedule/ -> prints ready-to-run find_openqa_job.pl commands (does NOT execute;
               network access requires user confirmation)

Output is printed directly to stdout.

  run_helpers(\%categories);

Arguments:

  $categories - Hashref of category name => {files => [...], vr_needed => 0|1, label => "..."}

Returns: Nothing (side effects: prints to stdout, may invoke subprocesses).

=cut

sub run_helpers {
    my ($categories) = @_;

    print "\n" . "=" x 60 . "\n";
    print "DETAILED ANALYSIS (--helpers)\n";
    print "=" x 60 . "\n\n";

    # tests/ -> find_test_schedule.pl
    if (@{$categories->{tests}{files}}) {
        my $script = find_script('find_test_schedule.pl');
        if ($script) {
            my $files = join(' ', map { "'$_'" } @{$categories->{tests}{files}});
            my $v = $verbose ? '--verbose' : '';
            print "--- find_test_schedule.pl ---\n\n";
            my $cmd = "perl '$script' --repo '$repo_dir' $v $files";
            log_verbose("Running: $cmd");
            system($cmd);
            print "\n";
        } else {
            print "  [find_test_schedule.pl not found — skipping]\n\n";
        }
    }

    # lib/ -> find_unit_test.pl + find_affected_tests.pl
    if (@{$categories->{lib}{files}}) {
        my $ut_script = find_script('find_unit_test.pl');
        my $at_script = find_script('find_affected_tests.pl');
        my $files = join(' ', map { "'$_'" } @{$categories->{lib}{files}});
        my $v = $verbose ? '--verbose' : '';

        if ($ut_script) {
            print "--- find_unit_test.pl ---\n\n";
            my $cmd = "perl '$ut_script' --repo '$repo_dir' $v $files";
            log_verbose("Running: $cmd");
            system($cmd);
            print "\n";
        } else {
            print "  [find_unit_test.pl not found — skipping]\n\n";
        }

        if ($at_script) {
            print "--- find_affected_tests.pl ---\n\n";
            my $gc = $git_commit ? "--git-commit '$git_commit'" : '';
            my $cmd = "perl '$at_script' --repo '$repo_dir' $v $gc $files";
            log_verbose("Running: $cmd");
            system($cmd);
            print "\n";

            # When --git-commit is provided, also resolve the function-confirmed
            # test files to YAML schedules automatically.  This closes the
            # full pipeline for lib/ changes so gemini doesn't need to pick
            # between the function-level and module-level lists manually.
            if ($git_commit) {
                my $ts_script = find_script('find_test_schedule.pl');
                if ($ts_script) {
                    # Run find_affected_tests.pl in JSON mode to extract recommended_tests
                    my $json_cmd = "perl '$at_script' --repo '$repo_dir' $gc --json $files";
                    log_verbose("Running (JSON): $json_cmd");
                    my $raw = qx($json_cmd 2>/dev/null);
                    if ($raw) {
                        my $data = eval { JSON::PP->new->decode($raw) };
                        my @rec = grep { /^tests\// } @{$data->{recommended_tests} // []};
                        if (!$@ && @rec) {
                            my $rec_files = join(' ', map { "'$_'" } @rec);
                            print "--- find_test_schedule.pl (function-confirmed VR targets) ---\n\n";
                            my $ts_cmd = "perl '$ts_script' --repo '$repo_dir' $v $rec_files";
                            log_verbose("Running: $ts_cmd");
                            system($ts_cmd);
                            print "\n";
                        }
                    }
                }
            }
        } else {
            print "  [find_affected_tests.pl not found — skipping]\n\n";
        }
    }

    # data/ -> find_data_consumers.pl
    if (@{$categories->{data}{files}}) {
        my $script = find_script('find_data_consumers.pl');
        if ($script) {
            my $files = join(' ', map { "'$_'" } @{$categories->{data}{files}});
            my $v = $verbose ? '--verbose' : '';
            print "--- find_data_consumers.pl ---\n\n";
            my $cmd = "perl '$script' --repo '$repo_dir' $v $files";
            log_verbose("Running: $cmd");
            system($cmd);
            print "\n";
        } else {
            print "  [find_data_consumers.pl not found — skipping]\n\n";
        }
    }

    # schedule/ -> find_openqa_job.pl
    # find_openqa_job.pl requires a --host/--osd/--o3 flag that we cannot
    # determine automatically, so we print the ready-to-run command rather than
    # executing it directly.
    if (@{$categories->{schedule}{files}}) {
        my $script = find_script('find_openqa_job.pl');
        my $files  = join(' ', sort @{$categories->{schedule}{files}});
        print "--- find_openqa_job.pl ---\n\n";
        if ($script) {
            print "  (requires network access — specify --host, --osd, or --o3)\n\n";
            print "  # For openqa.suse.de (SLE/SLE Micro):\n";
            print "  perl '$script' --osd --repo '$repo_dir' $files\n\n";
            print "  # For openqa.opensuse.org (Tumbleweed/Leap):\n";
            print "  perl '$script' --o3 --repo '$repo_dir' $files\n\n";
        } else {
            print "  [find_openqa_job.pl not found — skipping]\n\n";
        }
    }
}

=head2 build_report_data

Assemble the classification results into a single report hashref for rendering.

Computes the aggregate count of files needing a verification run and bundles
the git metadata alongside the categorized file lists.

  $report = build_report_data(\%categories, \@changed_files, $repo_dir, $branch, $fork_url);

Arguments:

  $categories    - Hashref of classified file categories
  $changed_files - Arrayref of all changed file paths
  $repo_dir      - Absolute path to the OSADO repository
  $branch        - Resolved branch name
  $fork_url      - Resolved GitHub fork URL (may be undef)

Returns: Hashref with keys: total_files, total_vr_needed, categories, repo_dir, branch, fork_url.

=cut

# --- Data preparation ---

sub build_report_data {
    my ($categories, $changed_files, $repo_dir, $branch, $fork_url) = @_;
    my $vr_needed = 0;
    for my $cat (values %$categories) {
        $vr_needed += scalar @{$cat->{files}}
            if $cat->{vr_needed} && @{$cat->{files}};
    }
    return {
        total_files     => scalar(@$changed_files),
        total_vr_needed => $vr_needed,
        categories      => $categories,
        repo_dir        => $repo_dir,
        branch          => $branch,
        fork_url        => $fork_url,
    };
}

=head2 print_text

Render the classification report as human-readable terminal output.

Prints per-category file listings with VR indicators, actionable guidance
for each category, and a summary section with copy-paste-ready commands
(prove for unit tests, openqa-clone-job for VR).

  print_text($report);

Arguments:

  $report - Hashref as returned by build_report_data()

Returns: Nothing (prints to stdout).

=cut

# --- Output functions ---

sub print_text {
    my ($report) = @_;
    my $categories = $report->{categories};
    my $repo_dir   = $report->{repo_dir};

    print "=" x 60, "\n";
    print "OSADO Change Classification & Testing Plan\n";
    print "=" x 60, "\n\n";

    print "Total files changed: $report->{total_files}\n";
    print "Files needing openQA VR: $report->{total_vr_needed}\n\n";

    # Print each non-empty category
    my @order = qw(tests lib t data schedule no_vr);
    for my $cat_name (@order) {
        my $cat = $categories->{$cat_name};
        next unless @{$cat->{files}};

        my $vr_tag = $cat->{vr_needed} ? " [VR NEEDED]" : " [No VR]";
        print "-" x 50, "\n";
        print "$cat->{label}$vr_tag (" . scalar(@{$cat->{files}}) . " files)\n";
        print "-" x 50, "\n\n";

        for my $file (sort @{$cat->{files}}) {
            print "  $file\n";
        }
        print "\n";

        # Category-specific guidance
        my $guidance = get_guidance($cat_name, $cat->{files}, $repo_dir);
        print "  $_\n" for @$guidance;
        print "\n";
    }

    # Summary
    print "=" x 60, "\n";
    print "SUMMARY\n";
    print "=" x 60, "\n\n";

    if (@{$categories->{t}{files}}) {
        print "1. Run unit tests locally:\n";
        for my $f (sort @{$categories->{t}{files}}) {
            print "   PERL5OPT=-MCarp::Always prove --time --verbose -l -Ios-autoinst/ $f\n";
        }
        print "\n";
    }

    if (@{$categories->{lib}{files}}) {
        print "2. Run this helper script to find which unit tests are associated to changed lib modules:\n";
        print "   perl find_unit_test.pl --repo $repo_dir " .
            join(' ', sort @{$categories->{lib}{files}}) . "\n";
        print "   (or: make unit-test)\n\n";
    }

    if ($report->{total_vr_needed} > 0) {
        my $casedir = $report->{fork_url}
            ? "$report->{fork_url}.git#$report->{branch}"
            : "https://github.com/USER/os-autoinst-distri-opensuse.git#$report->{branch}";
        print "3. Run openQA verification (VR):\n";
        print "   # First, find a passing production job to clone. Example:\n";
        print "   # openqa-cli api --host HOST jobs groupid=GROUP_ID test=TEST_NAME \\\n";
        print "   #   state=done result=passed latest=1\n";
        print "   #\n";
        print "   # Then clone it:\n";
        print "   openqa-clone-job --skip-chained-deps --within-instance \\\n";
        print "     http://HOST/tests/JOB_ID \\\n";
        print "     CASEDIR=$casedir \\\n";
        print "     BUILD=user_VR _GROUP=0\n\n";
    }

    if ($run_helpers) {
        # Detailed analysis already printed above
    } else {
        print "Tip: Re-run with --helpers for detailed analysis using helper scripts.\n";
    }
}

=head2 get_guidance

Generate category-specific "next action" lines for display or JSON output.

Maps each category to the recommended verification command(s) the developer
should run next.

  $lines = get_guidance($cat_name, $files, $repo_dir);

Arguments:

  $cat_name - Category key: 'tests', 'lib', 't', 'data', 'schedule', or 'no_vr'
  $files    - Arrayref of file paths in this category
  $repo_dir - Absolute path to the OSADO repository

Returns: Arrayref of guidance strings (one per output line).

=cut

sub get_guidance {
    my ($cat_name, $files, $repo_dir) = @_;
    my @sorted = sort @$files;
    my @lines;

    if ($cat_name eq 'tests') {
        push @lines, "Action: Clone an openQA job that runs each test module.";
        push @lines, "Find the schedule: perl find_test_schedule.pl --repo $repo_dir "
            . join(' ', @sorted);
    } elsif ($cat_name eq 'lib') {
        push @lines, "Action: (1) Run unit tests, (2) Clone an openQA job.";
        push @lines, "Find unit tests: perl find_unit_test.pl --repo $repo_dir "
            . join(' ', @sorted);
        push @lines, "Find affected tests: perl find_affected_tests.pl --repo $repo_dir "
            . join(' ', @sorted);
    } elsif ($cat_name eq 't') {
        push @lines, "Action: Run these test files locally.";
        for my $f (@sorted) {
            push @lines,
                "PERL5OPT=-MCarp::Always prove --time --verbose -l -Ios-autoinst/ $f";
        }
    } elsif ($cat_name eq 'data') {
        push @lines, "Action: Clone a job that uses the data file.";
        push @lines, "Find consumers: perl find_data_consumers.pl --repo $repo_dir "
            . join(' ', @sorted);
    } elsif ($cat_name eq 'schedule') {
        push @lines, "Action: Clone a job that uses the modified schedule.";
        for my $f (@sorted) {
            push @lines,
                "openqa-cli api --osd job_settings/jobs key=YAML_SCHEDULE value=$f";
        }
    } elsif ($cat_name eq 'no_vr') {
        push @lines, "Action: No openQA verification needed.";
        push @lines, "Consider running: make test";
    }

    return \@lines;
}

=head2 print_json

Render the classification report as pretty-printed JSON for machine consumption.

Produces a structure with keys: total_files, total_vr_needed, branch, fork_url,
and categories (each with label, vr_needed, files, guidance).

  print_json($report);

Arguments:

  $report - Hashref as returned by build_report_data()

Returns: Nothing (prints JSON to stdout).

=cut

sub print_json {
    my ($report) = @_;
    my $categories = $report->{categories};

    my %out = (
        total_files     => $report->{total_files},
        total_vr_needed => $report->{total_vr_needed},
        branch          => $report->{branch},
        fork_url        => $report->{fork_url},
        categories      => {},
    );

    my @order = qw(tests lib t data schedule no_vr);
    for my $name (@order) {
        my $cat = $categories->{$name};
        next unless @{$cat->{files}};
        my $guidance = get_guidance($name, $cat->{files}, $report->{repo_dir});
        $out{categories}{$name} = {
            label     => $cat->{label},
            vr_needed => $cat->{vr_needed} ? JSON::PP::true : JSON::PP::false,
            files     => [sort @{$cat->{files}}],
            guidance  => $guidance,
        };
    }

    print JSON::PP->new->pretty->canonical->encode(\%out);
}

=head2 log_verbose

Print a diagnostic message to stderr when verbose mode is active.

  log_verbose($msg);

Arguments:

  $msg - Message string to print

Returns: Nothing.

=cut

sub log_verbose {
    my ($msg) = @_;
    print STDERR "[INFO] $msg\n" if $verbose;
}

sub print_usage {
    print <<'EOF';
classify_changes.pl — Classify changed files and output an OSADO testing plan.

USAGE
    perl classify_changes.pl [OPTIONS] [file ...]

DESCRIPTION
    Given a set of changed files (from git or as arguments), categorizes each
    file by its location in the os-autoinst-distri-opensuse repository and
    outputs the appropriate testing strategy:

        tests/     → Clone an openQA job (VR needed)
        lib/       → Run unit tests + clone an openQA job (VR needed)
        t/         → Run locally with prove (no VR)
        data/      → Clone a job that uses the data file (VR needed)
        schedule/  → Clone a job that uses the schedule (VR needed)
        other      → No openQA verification needed

INPUT MODES
    By default (no flags, no file arguments), reads git staged files.

    --git-diff-staged
        Read from git staged files (same as the default behavior).

    --git-diff
        Read from unstaged working tree changes (git diff).

    --git-commit HASH
        Read files changed in a specific git commit.

    file ...
        When file paths are given as positional arguments, they are used
        directly instead of querying git.

OPTIONS
    --repo DIR
        Path to the OSADO repository root. Defaults to the current directory.
        The directory must contain lib/ and tests/ subdirectories.

    --helpers
        After classification, automatically invoke the specialized helper
        scripts for each category to produce detailed analysis:
          - find_test_schedule.pl   for tests/ files
          - find_unit_test.pl       for lib/ files
          - find_affected_tests.pl  for lib/ files
          - find_data_consumers.pl  for data/ files

    --verbose
        Print extra diagnostic information to stderr. When --helpers is also
        set, passes --verbose to each helper script.

    --json
        Output the classification as JSON instead of human-readable text.

    --help, -h
        Show this help message and exit.

EXAMPLES
    # Classify staged changes (default)
    perl classify_changes.pl --repo /path/to/osado

    # Classify unstaged working tree changes
    perl classify_changes.pl --repo /path/to/osado --git-diff

    # Classify a specific commit
    perl classify_changes.pl --repo /path/to/osado --git-commit abc1234

    # Classify explicit files
    perl classify_changes.pl --repo /path/to/osado lib/utils.pm tests/console/test.pm

    # Full analysis with helper scripts
    perl classify_changes.pl --repo /path/to/osado --helpers --verbose

SEE ALSO
    find_test_schedule.pl, find_affected_tests.pl, find_unit_test.pl,
    find_data_consumers.pl
EOF
    return 1;
}

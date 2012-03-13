#!/usr/bin/perl -w

#
# git_svn_externals.pl
#
# Author:
#  Dmitry Sushko <Dmitry.Sushko@yahoo.com>
#

use strict;
use warnings;
use Cwd;
use File::Path;
use File::Basename;
use Term::ANSIColor;

my $git_executable         = "git";
my $git_directory          = ".git";
my $git_externals_dir      = ".git_externals";
my $show_externals_command = "$git_executable svn show-externals";
my $clone_external_command = "$git_executable svn clone";
my $git_svn_fetch_command  = "$git_executable svn fetch";
my $git_svn_rebase_command = "$git_executable svn rebase";

sub removeListHeaders {
    my @externalsList = @_;
    return grep(!/^# \// && !/^$/, @externalsList);
}

sub parseExternal {
    my $externalLine = $_;
    my @external;

    if ($externalLine =~
        m/(.+\S)\s+-r\s*(\S+)\s+((?:file:|http:|https:|svn:|svn\+ssh:)\S+.*)/) {
        @external = [$1, $2, $3];
    }
    elsif ($externalLine =~
           m/(.+\S)\s+((?:file:|http:|https:|svn:|svn\+ssh:)\S+.*)/) {
        @external = [$1, "0", $2];
    }
    else {
        @external = ["", "0", ""];
    }

    return @external;
}

sub isGitRepository {
    my $ext_path = $_[0];
    my $directory = join("/", $ext_path, $git_directory);
    if (-d $directory) {
        return 1;
    }
    else {
        return 0;
    }
}

sub excludeExternal {
    my $directory = $_[0];

    open GITEXCLUDE, "<", ".git/info/exclude" or die "Error: $!\n";
    if (grep {$_ =~ m/^$directory\n$/} <GITEXCLUDE>) {
        close GITEXCLUDE;
        return;
    }
    close GITEXCLUDE;

    open GITEXCLUDE, ">>", ".git/info/exclude" or die "Error: $!\n";
    print GITEXCLUDE "$directory\n";
    close GITEXCLUDE;
}

sub switchExternalRevision {
    my $ext_rev = $_[0];

    my $git_sha = qx/git svn find-rev r$ext_rev/;
    $git_sha =~ s/\n//;

    qx/$git_executable checkout master/;
    qx/$git_executable branch -f __git_ext_br $git_sha/;
    qx/$git_executable checkout __git_ext_br/;
}

sub updateExternal {
    my ($ext_path, $ext_rev, $ext_url) = @_;

    my $command = $git_svn_fetch_command;
    qx/$command/;

    $command = $git_svn_rebase_command;
    qx/$command/;

    if ($ext_rev ne "0") {
        switchExternalRevision($ext_rev);
    }

    getExternals();
}

sub cloneExternal {
    my ($ext_path, $ext_rev, $ext_url) = @_;

    my $command = join(" ", $clone_external_command, $ext_url, ".");
    qx/$command/;

    if ($ext_rev ne "0") {
        switchExternalRevision($ext_rev);
    }

    getExternals();
}

sub makeSymlinkToExternal {
    my $ext_path = $_[0];

    if (basename($ext_path) ne $ext_path) {
        mkpath dirname($ext_path);
    }

    my $path_to_repo_root = qx/git rev-parse --show-cdup/;
    $path_to_repo_root =~ s/\n$//;
    my $externals_relative_dir = $path_to_repo_root . $git_externals_dir;

    symlink(join("/", $externals_relative_dir, $ext_path), $ext_path);
}

sub getExternal {
    my ($ext_path, $ext_rev, $ext_url) = @{$_};

    $ext_path =~ s/%20/ /g;
    $ext_path =~ s/\\//g;
    $ext_path =~ s/^\///g;

    print colored ['green'], "==============================================\n";
    print colored ['cyan'],
        "External found:\n" .
        " path: $ext_path\n" .
        " rev : $ext_rev\n" .
        " url : $ext_url\n";

    my $working_dir = cwd();

    chdir $git_externals_dir or die "Error: $!\n";

    mkpath $ext_path or die "Error: $!\n" unless -d $ext_path;

    if (isGitRepository($ext_path)) {
        chdir $ext_path or die "Error: $!\n";
        updateExternal($ext_path, $ext_rev, $ext_url);
    }
    else {
        chdir $ext_path or die "Error: $!\n";
        cloneExternal($ext_path, $ext_rev, $ext_url);
    }

    chdir $working_dir or die "Error: $!\n";
    excludeExternal($ext_path);

    makeSymlinkToExternal($ext_path);
}

sub getExternals {
    my @show_externals_output = qx/$show_externals_command/;
    my @externalsList = grep(!/^# \// && !/^$/, @show_externals_output);
    my @externals = map(parseExternal, @externalsList);

    mkpath $git_externals_dir or die "Error: $!\n" unless -d $git_externals_dir;
    excludeExternal($git_externals_dir);

    map(getExternal, @externals);
}

getExternals();

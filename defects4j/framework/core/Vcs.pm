#-------------------------------------------------------------------------------
# Copyright (c) 2014 René Just, Darioush Jalali, and Defects4J contributors.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#-------------------------------------------------------------------------------

=pod

=head1 NAME

Vcs.pm -- Provides a simple abstraction for version control systems

=head1 SYNOPSIS

=head2 Example using Vcs::Svn:

use Vcs::Svn;

my $vcs = Vcs::Svn->new("project", "repo_url", "commit_db_file", \&_co_hook);

$vcs->checkout_id("1b", "/tmp/1b");

sub _co_hook {
    my ($vcs, $revision, $work_dir) = @_;

    # do some post processing
}

=head1 DESCRIPTION

This module provides a simple abstraction for version control systems.

=head2 Available subpackages:

=over 4

=item B<Vcs::Git> 

=item B<Vcs::Svn>

=back

=cut
package Vcs;

use warnings;
use strict;

use Constants;
use Utils;
use File::Path qw(make_path);
use PatchReader::Raw;
use PatchReader::NarrowPatchRegexp;
use PatchReader::DiffPrinter::raw;

=pod

A vcs object has to be instantiated with:

- Project name

- Repository url 

- File name of the commit database (commit-db), see below for details

- Reference to post-checkout hook (optional) -- if provided, this method is called after each checkout.

The commit database has to be a csv file with the structure C<version_id,rev_1,rev_2>. 

=head2 Commit-db example for Svn:

=over 4

=item 1,1024,1025 

=item 2,1064,1065

=back

=head2 Commit-db example for Git:

=over 4

=item 1,788193a54e0f1aaa428ccfdd3bb45e32c311c18b,c96ae569bbe0167cfa15caa7f784fdb2e1ecdc12

=item 2,ab333482c629d33d5484b4af6eb27918382ccc28,f77c5101df42f501d96d0363084dcc9c17400fce

=back

=cut
sub new {
    @_ >= 4 or die $ARG_ERROR;
    my ($class, $pid, $repo, $db, $hook) = @_;
    my $self = {
        pid => $pid,
        repo => $repo,
        commit_db => $db,
        _cache => _build_db_cache($db),
        _co_hook => $hook
    };

    bless $self, $class;
    return $self;
}

=pod

=head2 Provided object methods:

=over 4

=item B<lookup> C<lookup(version_id)>

Queries the commit database (commit-db) and returns the C<revision_id> for 
the given C<version_id>. The format of the C<version_id> is B<\d+[bf]>.

=cut
sub lookup {
    my ($self, $version_id) = @_;
    $version_id =~ /(\d+)([bf])/ or die "Wrong version_id format: $version_id! Expected: \\d+[bf]";
    defined $self->{_cache}->{$1}->{$2} or die "Version_id does not exist: $version_id!";
    return $self->{_cache}->{$1}->{$2};
}

=pod

=item B<num_revision_pairs> C<num_revision_pairs()>

Returns the number of revision pairs in the C<commit-db>.

=cut
sub num_revision_pairs {
    my $self = shift;
    return scalar keys %{$self->{_cache}};
}

=pod

=item B<get_version_ids> C<get_version_ids()>

Returns an array of all C<version_id>s in the C<commit-db>.

=cut
sub get_version_ids {
    my $self = shift;
    return sort {$a <=> $b} keys %{$self->{_cache}};
}

=pod

=item B<checkout_id> C<checkout_id(version_id, work_dir)>

Performs a lookup of C<version_id> in the C<commit-db> followed by a checkout of 
the corresponding revision with C<revision_id> to C<work_dir>.
The format of the C<version_id> is B<\d+[bf]>.

B<This method always performs a clean checkout, i.e., the working directory is 
deleted before the checkout if it already exists>.

=cut
sub checkout_id {
    @_ == 3 or die $ARG_ERROR;
    my ($self, $version_id, $work_dir) = @_;
    my $revision = $self->lookup($version_id);
    die "Version_id not found in commit-db!" unless defined $revision;

    # Get specific checkout command
    my $cmd = $self->_checkout_cmd($revision, $work_dir);
 
    my %config = ();

    # Check whether working directory exists
    if (-d $work_dir) { 
        # Check whether we should not delete the existing directory

        # Is the existing directory empty?
        opendir(DIR, $work_dir) or die "Could not open directory: $work_dir!";
        my @entries = readdir(DIR);
        closedir(DIR);
        my $dir_empty=1;
        foreach (@entries) {
            next if m/^\.\.?$/;
            $dir_empty=0;
            last;
        }
        
        # If the directory is not empty check whether it is a previously used
        # working directory, and delete all files if so.
        unless ($dir_empty) {
            my $old_config = Utils::read_config_file("$work_dir/$CONFIG");
            unless(defined $old_config) {
                die "Directory exists but is not a previously used working directory: $work_dir";
            }
            # Preserve old config
            %config = %{$old_config};
            foreach (@entries) {
                next if m/^\.\.?$/;
                system("rm -rf $work_dir/$_") == 0 or die "Failed to clean working directory: $!";
            }
        }       
    } else {
        make_path($work_dir) or die "Failed to create working directory: $!";    
    }

    print "Checking out " . _trunc_rev_id($revision) . " to $work_dir ... ";
    my $log = `$cmd`; my $ret = $?;
    if ($ret!=0) {
        print "FAIL\n$log";
        return $ret;
    }
    
    # Check whether post-checkout hook is provided
    $self->{_co_hook}($self, $revision, $work_dir) if defined $self->{_co_hook};
   
    # Update version info file
    $config{$CONFIG_PID} = $self->{pid};
    $config{$CONFIG_VID} = $version_id; 
    Utils::write_config_file("$work_dir/$CONFIG", \%config);
 
    # Init new git repository to keep track of local changes
    # Note that we commit after executing the checkout hook,
    # so we can easily revert without re-applying patches etc.
    #
    $log = `cd $work_dir && git init && git add -A && git commit -a -m original 2>&1`;
    $ret=$?;
    if ($ret!=0) {
        print "FAIL\n$log";
        die "Cannot init local git repository!";
    }
    
    print "OK\n";
    return $ret;
}

=pod

=item B<diff> C<diff(revision_id_1, revision_id_2 [, path])>

Returns the diff between C<revision_id_1> and C<revision_id_2> or C<undef> if
the diff failed. The C<path> argument is optional and can be used to compute a diff 
between certain files or directories. Note that C<path> is relative to the root 
of the working directory.

=cut
sub diff {
    @_ >= 3 or die "Invalid number of arguments!";
    my ($self, $rev1, $rev2, $path) = @_;
    my $opt = defined $path ? $path : "";
    printf("Diff $opt %.16s : %.16s ... ", $rev1, $rev2);    
    my $cmd = $self->_diff_cmd($rev1, $rev2, $path);
    my $diff = `$cmd`; my $ret = $?;
    if ($ret!=0) {
        print "FAIL\n$diff";
        return undef;
    }
    print "OK\n";
    return $diff;    
}

=pod

=item B<export_diff> C<export_diff(revision_id_1, revision_id_2, out_file [, path])>

Exports the diff between C<revision_id_1> and C<revision_id_2> to C<out_file>. 
The path argument is optional and can be used to compute a diff between certain 
files or directories. Note that C<path> is relative to the root of the working directory.

=cut
sub export_diff {
    @_ >= 4 or die $ARG_ERROR;
    my ($self, $rev1, $rev2, $out_file, $path) = @_;
    my $diff = $self->diff($rev1, $rev2, $path);
    return 1 unless defined $diff;

    # Export diff to file
    open(OUT, ">$out_file") or die "Cannot open diff file ($out_file): $!";
    print OUT $diff;
    close OUT;

    return 0;
}

=pod

=item B<apply_patch> C<apply_patch(work_dir, patch_file [, path])>

Applies the patch provided in C<patch_file> to the working directory
C<work_dir>.  The path argument is optional and used as prefix for the files
to be patched. Note that C<path> is relative to the root of the working directory.

=cut
sub apply_patch {
    @_ >= 3 or die $ARG_ERROR;
    my ($self, $work_dir, $patch_file, $path) = @_;
    print "Applying patch ... ";
    my $cmd = $self->_apply_cmd($work_dir, $patch_file, $path);
    my $log = `$cmd`; my $ret = $?;
    if ($ret==0) {
        print "OK\n";
    } else {
        print "FAIL\n$log";
    }
    return $ret;    
}

=pod

=head2 Provide new Vcs implementation

The provided default implementations may be overriden to provide specific behavior.
In most cases it is sufficient to override the following abstract methods to provide a vcs-specific cmd:

=over 4

=item B<_checkout_cmd(revision, work_dir)>

      Returns the cmd to checkout C<revision> to the working directory C<work_dir>

=cut
sub _checkout_cmd { die $ABSTRACT_METHOD; }
=pod

=item B<_apply_cmd(work_dir, patch_file [, path])>

      Returns the cmd to apply the patch in file C<patch_file> to the working 
      directory C<work_dir>. The optional path C<path> is relative to the
      working directory and used to apply patches to certain files or directories.

=cut
sub _apply_cmd { die $ABSTRACT_METHOD; }
=pod

=item B<_diff_cmd(rev1, rev2, path)>

      Returns the cmd to compute a diff between two revisions C<rev1> and C<rev2>.
      The optional path C<path> is relative to the repository root and used to 
      diff between certain files or directories.

=back

=cut
sub _diff_cmd { die $ABSTRACT_METHOD; }
sub _get_parent_revisions { die $ABSTRACT_METHOD; }

#
# Read commit-db and build cache
#
sub _build_db_cache {
    my $db = shift;
    open (IN, "<$db") or die "Cannot open commit-db $db: $!";
    my $cache = {};
    while (<IN>) {
        chomp;
        /(\d+),([^,]+),([^,]+)/ or die "Corrupted commit-db!";
        $cache->{$1} = {b => $2, f => $3, line => $_};
    }
    close IN;

    return $cache;
}

#
# Truncate revision id to 8 characters if necessary
#
sub _trunc_rev_id {
    my $id = shift;
    if (length($id) > 8) {
        $id = substr($id, 0, 8) . "...";
    }
    return $id;
}

1;

=pod

=head1 AUTHORS

Rene Just, Darioush Jalali

=cut


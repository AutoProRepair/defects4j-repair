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

Project/Time.pm -- Concrete project instance for Joda-Time.

=head1 DESCRIPTION

This module provides all project-specific configurations and methods for the
Joda-Time project.

=cut
package Project::Time;

use strict;
use warnings;

use Constants;
use Vcs::Git;

our @ISA = qw(Project);
my $PID  = "Time";

sub new {
    my $class = shift;
    my $name = "joda-time";
    my $src  = "src/main/java";
    my $test = "src/test/java";
    my $vcs = Vcs::Git->new($PID,
                            "$REPO_DIR/$name.git", 
                            "$SCRIPT_DIR/projects/$PID/commit-db",
                             \&_post_checkout);
    
    return $class->SUPER::new($PID, $name, $vcs, $src, $test);
}


sub _post_checkout {
    my ($vcs, $revision, $work_dir) = @_;
    my $name = $vcs->{prog_name};
    
    if (-e "$work_dir/JodaTime") {
        system("mv $work_dir/JodaTime/* $work_dir");
    }

    # Check whether ant build file exists
    unless (-e "$work_dir/build.xml") {
        system("cp $SCRIPT_DIR/projects/$PID/build_files/$revision/* $work_dir");
    }

    # Check for a broken-build-revision
    my $id = rev_lookup($vcs, $revision); # TODO: very ugly.
    my $filename = "${SCRIPT_DIR}/projects/${PID}/broken-builds/build-${id}.xml";
    if (-e $filename) {
        system ("cp $filename $work_dir/build.xml");
    }
}

sub rev_lookup {
    my ($self, $revision) = @_;
    my @answer = grep {$self->lookup($_ . "f") eq $revision || 
                       $self->lookup($_ . "b") eq $revision} $self->get_version_ids();
    die unless scalar(@answer) > 0;
    return $answer[0];
}

sub export_diff {
    my ($self, $rev1, $rev2, $out_file, $path) = @_;
    if ($self->rev_lookup($rev2) >= 22) {
        # path is an optional argument
        $path = "JodaTime/" . ($path//"");
    }
    return $self->{_vcs}->export_diff($rev1, $rev2, $out_file, $path);
}


sub diff {
    my ($self, $rev1, $rev2, $path) = @_;
    if ($self->rev_lookup($rev2) >= 22) {
        # path is an optional argument
        $path = "JodaTime/" . ($path//"");
    }
    return $self->{_vcs}->diff($rev1, $rev2, $path);
}


1;

=pod

=head1 AUTHORS

Darioush Jalali, Rene Just

=head1 SEE ALSO

F<Project.pm>

=cut


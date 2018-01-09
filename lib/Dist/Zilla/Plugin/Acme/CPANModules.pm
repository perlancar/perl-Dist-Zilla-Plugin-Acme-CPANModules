package Dist::Zilla::Plugin::Acme::CPANModules;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Moose;
use namespace::autoclean;

with (
    'Dist::Zilla::Role::BeforeBuild',
    'Dist::Zilla::Role::FileMunger',
    'Dist::Zilla::Role::FileFinderUser' => {
        default_finders => [':InstallModules'],
    },
);

use File::Spec::Functions qw(catfile);

# either provide filename or filename+filecontent
sub _get_abstract_from_list_summary {
    my ($self, $filename, $filecontent) = @_;

    local @INC = @INC;
    unshift @INC, 'lib';

    unless (defined $filecontent) {
        $filecontent = do {
            open my($fh), "<", $filename or die "Can't open $filename: $!";
            local $/;
            ~~<$fh>;
        };
    }

    unless ($filecontent =~ m{^#[ \t]*ABSTRACT:[ \t]*([^\n]*)[ \t]*$}m) {
        $self->log_debug(["Skipping %s: no # ABSTRACT", $filename]);
        return undef;
    }

    my $abstract = $1;
    if ($abstract =~ /\S/) {
        $self->log_debug(["Skipping %s: Abstract already filled (%s)", $filename, $abstract]);
        return $abstract;
    }

    my $pkg;
    if (!defined($filecontent)) {
        (my $mod_p = $filename) =~ s!^lib/!!;
        require $mod_p;

        # find out the package of the file
        ($pkg = $mod_p) =~ s/\.pm\z//; $pkg =~ s!/!::!g;
    } else {
        eval $filecontent;
        die if $@;
        if ($filecontent =~ /\bpackage\s+(\w+(?:::\w+)*)/s) {
            $pkg = $1;
        } else {
            die "Can't extract package name from file content";
        }
    }

    no strict 'refs';
    my $list = ${"$pkg\::LIST"};

    return $list->{summary} if $list->{summary};
}

# dzil also wants to get abstract for main module to put in dist's
# META.{yml,json}
sub before_build {
   my $self  = shift;
   my $name  = $self->zilla->name;
   my $class = $name; $class =~ s{ [\-] }{::}gmx;
   my $filename = $self->zilla->_main_module_override ||
       catfile( 'lib', split m{ [\-] }mx, "${name}.pm" );

   $filename or die 'No main module specified';
   -f $filename or die "Path ${filename} does not exist or not a file";
   my $abstract = $self->_get_abstract_from_list_summary($filename);
   return unless $abstract;

   $self->zilla->abstract($abstract);
   return;
}

sub munge_files {
    my $self = shift;
    $self->munge_file($_) for @{ $self->found_files };
}

sub munge_file {
    my ($self, $file) = @_;
    my $content = $file->content;

    unless ($file->isa("Dist::Zilla::File::OnDisk")) {
        $self->log_debug(["skipping %s: not an ondisk file, currently generated file is assumed to be OK", $file->name]);
        return;
    }

    my $abstract = $self->_get_abstract_from_list_summary($file->name, $file->content);

  ADD_X_MENTIONS_PREREQS:
    {
        my $pkg = do {
            my $pkg = $file->name;
            $pkg =~ s!^lib/!!;
            $pkg =~ s!\.pm$!!;
            $pkg =~ s!/!::!g;
            $pkg;
        };
        no strict 'refs';
        my $list = ${"$pkg\::LIST"};
        my @mods;
        for my $entry (@{ $list->{entries} }) {
            push @mods, $entry->{module};
            for (@{ $entry->{alternate_modules} || [] }) {
                push @mods, $_;
            }
            for (@{ $entry->{related_modules} || [] }) {
                push @mods, $_;
            }
        }
        for my $mod (@mods) {
            $self->zilla->register_prereqs(
                {phase=>'x_mentions', type=>'x_mentions'}, $mod, 0);
        }
    }

  SET_ABSTRACT:
    {
        last unless $abstract;
        $content =~ s{^#\s*ABSTRACT:.*}{# ABSTRACT: $abstract}m
            or die "Can't insert abstract for " . $file->name;
        $self->log(["inserting abstract for %s (%s)", $file->name, $abstract]);
        $file->content($content);
    }
}

__PACKAGE__->meta->make_immutable;
1;
# ABSTRACT: Plugin to use when building Acme::CPANModules::* distribution

=for Pod::Coverage .+

=head1 SYNOPSIS

In F<dist.ini>:

 [Acme::CPANModules]


=head1 DESCRIPTION

This plugin is to be used when building C<Acme::CPANModules::*> distribution. It
currently does the following:

=over

=item * Fill the Abstract from list's summary

=item * Add prereq to the mentioned modules (phase=x_mentions, relationship=x_mentions)

=back


=head1 SEE ALSO

L<Acme::CPANModules>

L<Pod::Weaver::Plugin::Acme::CPANModules>

package Perinci::Access::Lite;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    bless \%args, $class;
}

# copy-pasted from SHARYANTO::Package::Util
sub __package_exists {
    no strict 'refs';

    my $pkg = shift;

    return unless $pkg =~ /\A\w+(::\w+)*\z/;
    if ($pkg =~ s/::(\w+)\z//) {
        return !!${$pkg . "::"}{$1 . "::"};
    } else {
        return !!$::{$pkg . "::"};
    }
}

sub request {
    my ($self, $action, $url, $extra) = @_;

    if ($url =~ m!\A(?:pl:)?/(\w+(?:/\w+)*)/(\w*)\z!) {
        my ($mod, $func) = ($1, $2);
        # skip if package already exists, e.g. 'main'
        require "$mod.pm" unless __package_exists($mod);
        $mod =~ s!/!::!g;

        if ($action eq 'meta') {
            my $meta;
            {
                no strict 'refs';
                if (length $func) {
                    $meta = ${"$mod\::SPEC"}{$func}
                        or return [500, "No metadata for '$url'"];
                } else {
                    $meta = ${"$mod\::SPEC"}{':package'} // {v=>1.1};
                }
                $meta->{entity_v}    //= ${"$mod\::VERSION"};
                $meta->{entity_date} //= ${"$mod\::DATE"};
            }

            require Perinci::Sub::Normalize;
            $meta = Perinci::Sub::Normalize::normalize_function_metadata($meta);
            return [200, "OK", $meta];
        } else {
            return [502, "Unknown/unsupported action '$action'"];
        }
    } elsif (0 && $url =~ m!\Ahttps?:/(/?)!i) {
        my $is_unix = !$1;
    } else {
        return [502, "Unsupported url scheme or bad URL '$url'"];
    }
}

1;
# ABSTRACT: A lightweight Riap client library

=head1 DESCRIPTION

This module is a lightweight alternative to L<Perinci::Access>. It has less
prerequisites but does fewer things. Differences with Perinci::Access:

=over

=item * No wrapping

For 'pl' or schemeless URL, no wrapping (L<Perinci::Sub::Wrapper>) is done, only
normalization (using L<Perinci::Sub::Normalize>).

=item * No transaction or logging support

=item * No support for some schemes

This includes: Riap::Simple over pipe/TCP socket.

=back


=head1 SEE ALSO

L<Perinci::Access>

=cut

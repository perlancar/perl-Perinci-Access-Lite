package Perinci::Access::Lite;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Perinci::AccessUtil qw(strip_riap_stuffs_from_res);

sub new {
    my ($class, %args) = @_;
    $args{riap_version} //= 1.1;
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

    $extra //= {};

    my $v = $extra->{v} // 1.1;
    if ($v ne '1.1' && $v ne '1.2') {
        return [501, "Riap protocol not supported, must be 1.1 or 1.2"];
    }

    my $res;
    if ($url =~ m!\A(?:pl:)?/(\w+(?:/\w+)*)/(\w*)\z!) {
        my ($mod, $func) = ($1, $2);
        # skip if package already exists, e.g. 'main'
        unless (__package_exists($mod)) {
            eval { require "$mod.pm" };
            return [500, "Can't load module $mod: $@"] if $@;
        }
        $mod =~ s!/!::!g;

        if ($action eq 'list') {
            return [501, "Action 'list' not implemented for ".
                        "non-package entities"]
                if length($func);
            no strict 'refs';
            my $spec = \%{"$mod\::SPEC"};
            return [200, "OK (list)", [grep {/\A\w+\z/} sort keys %$spec]];
        } elsif ($action eq 'meta' || $action eq 'call') {
            return [501, "Action 'call' not implemented for package entity"]
                if !length($func) && $action eq 'call';
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
            return [200, "OK ($action)", $meta] if $action eq 'meta';

            # convert args
            my $args = $extra->{args} // {};
            my $aa = $meta->{args_as} // 'hash';
            my @args;
            if ($aa =~ /array/) {
                require Perinci::Sub::ConvertArgs::Array;
                my $convres = Perinci::Sub::ConvertArgs::Array::convert_args_to_array(
                    args => $args, meta => $meta,
                );
                return $convres unless $convres->[0] == 200;
                if ($aa =~ /ref/) {
                    @args = ($convres->[2]);
                } else {
                    @args = @{ $convres->[2] };
                }
            } elsif ($aa eq 'hashref') {
                @args = ({ %$args });
            } else {
                # hash
                @args = %$args;
            }

            # call!
            {
                no strict 'refs';
                $res = &{"$mod\::$func"}(@args);
            }

            # add envelope
            if ($meta->{result_naked}) {
                $res = [200, "OK (envelope added by ".__PACKAGE__.")", $res];
            }

            # add hint that result is binary
            if (defined $res->[2]) {
                if ($meta->{result} && $meta->{result}{schema} &&
                        $meta->{result}{schema}[0] eq 'buf') {
                    $res->[3]{'x.hint.result_binary'} = 1;
                }
            }

        } else {
            return [501, "Unknown/unsupported action '$action'"];
        }
    } elsif ($url =~ m!\Ahttps?:/(/?)!i) {
        my $is_unix = !$1;
        my $ht;
        require JSON;
        state $json = JSON->new->allow_nonref;
        if ($is_unix) {
            require HTTP::Tiny::UNIX;
            $ht = HTTP::Tiny::UNIX->new;
        } else {
            require HTTP::Tiny;
            $ht = HTTP::Tiny->new;
        }
        my %headers = (
            "x-riap-v" => $self->{riap_version},
            "x-riap-action" => $action,
            "x-riap-fmt" => "json",
            "content-type" => "application/json",
        );
        my $args = $extra->{args} // {};
        for (keys %$extra) {
            next if /\Aargs\z/;
            $headers{"x-riap-$_"} = $extra->{$_};
        }
        my $htres = $ht->post(
            $url, {
                headers => \%headers,
                content => $json->encode($args),
            });
        return [500, "Network error: $htres->{status} - $htres->{reason}"]
            if $htres->{status} != 200;
        return [500, "Server error: didn't return JSON (".$htres->{headers}{'content-type'}.")"]
            unless $htres->{headers}{'content-type'} eq 'application/json';
        return [500, "Server error: didn't return Riap 1.1 response (".$htres->{headers}{'x-riap-v'}.")"]
            unless $htres->{headers}{'x-riap-v'} =~ /\A1\.1(\.\d+)?\z/;
        $res = $json->decode($htres->{content});
    } else {
        return [501, "Unsupported scheme or bad URL '$url'"];
    }

    strip_riap_stuffs_from_res($res);
}

1;
# ABSTRACT: A lightweight Riap client library

=head1 DESCRIPTION

This module is a lightweight alternative to L<Perinci::Access>. It has less
prerequisites but does fewer things. The things it supports:

=over

=item * Local (in-process) access to Perl modules and functions

Currently only C<call>, C<meta>, and C<list> actions are implemented. Variables
and other entities are not yet supported.

The C<list> action only gathers keys from C<%SPEC> and do not yet list
subpackages.

=item * HTTP/HTTPS

=item * HTTP over Unix socket

=back

Differences with Perinci::Access:

=over

=item * For network access, uses HTTP::Tiny module family instead of LWP

This results in fewer dependencies.

=item * No wrapping, no argument checking

For 'pl' or schemeless URL, no wrapping (L<Perinci::Sub::Wrapper>) is done, only
normalization (using L<Perinci::Sub::Normalize>).

=item * No transaction or logging support

=item * No support for some schemes

This includes: Riap::Simple over pipe/TCP socket.

=back


=head1 ATTRIBUTES

=head2 riap_version => float (default: 1.1)

=head1 METHODS

=head2 new(%attrs) => obj

=head2 $pa->request($action, $url, $extra) => hash


=head1 SEE ALSO

L<Perinci::Access>

=cut

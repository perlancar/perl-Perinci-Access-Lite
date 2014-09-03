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

    $extra //= {};

    if ($url =~ m!\A(?:pl:)?/(\w+(?:/\w+)*)/(\w*)\z!) {
        my ($mod, $func) = ($1, $2);
        # skip if package already exists, e.g. 'main'
        require "$mod.pm" unless __package_exists($mod);
        $mod =~ s!/!::!g;

        if ($action eq 'meta' || $action eq 'call') {
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
            return [200, "OK", $meta] if $action eq 'meta';

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
            my $res;
            {
                no strict 'refs';
                $res = &{"$mod\::$func"}(@args);
            }

            # add envelope
            if ($meta->{result_naked}) {
                $res = [200, "OK (envelope added by ".__PACKAGE__.")", $res];
            }
            return $res;

        } else {
            return [502, "Unknown/unsupported action '$action'"];
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
        return $json->decode($htres->{content});
    } else {
        return [502, "Unsupported scheme or bad URL '$url'"];
    }
}

1;
# ABSTRACT: A lightweight Riap client library

=head1 DESCRIPTION

This module is a lightweight alternative to L<Perinci::Access>. It has less
prerequisites but does fewer things. Differences with Perinci::Access:

=over

=item * No wrapping, no argument checking

For 'pl' or schemeless URL, no wrapping (L<Perinci::Sub::Wrapper>) is done, only
normalization (using L<Perinci::Sub::Normalize>).

=item * No transaction or logging support

=item * No support for some schemes

This includes: Riap::Simple over pipe/TCP socket.

=back


=head1 METHODS

=head2 new => obj

=head2 $pa->request($action, $url, $extra) => hash


=head1 SEE ALSO

L<Perinci::Access>

=cut

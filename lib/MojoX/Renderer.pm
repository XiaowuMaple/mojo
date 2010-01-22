# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Renderer;

use strict;
use warnings;

use base 'Mojo::Base';

use File::Spec;
use Mojo::ByteStream 'b';
use Mojo::Command;
use Mojo::JSON;
use MojoX::Types;

__PACKAGE__->attr(default_format => 'html');
__PACKAGE__->attr([qw/default_handler default_template_class encoding/]);
__PACKAGE__->attr(default_status => 200);
__PACKAGE__->attr(handler        => sub { {} });
__PACKAGE__->attr(helper         => sub { {} });
__PACKAGE__->attr(layout_prefix  => 'layouts');
__PACKAGE__->attr(root           => '/');
__PACKAGE__->attr(types          => sub { MojoX::Types->new });

# This is not how Xmas is supposed to be.
# In my day Xmas was about bringing people together, not blowing them apart.
sub new {
    my $self = shift->SUPER::new(@_);

    # JSON
    $self->add_handler(
        json => sub {
            my ($r, $c, $output, $options) = @_;
            $$output = Mojo::JSON->new->encode($options->{json});
        }
    );

    # Text
    $self->add_handler(
        text => sub {
            my ($r, $c, $output, $options) = @_;
            $$output = $options->{text};
        }
    );

    return $self;
}

sub add_handler {
    my $self = shift;

    # Merge
    my $handler = ref $_[0] ? $_[0] : {@_};
    $handler = {%{$self->handler}, %$handler};
    $self->handler($handler);

    return $self;
}

sub add_helper {
    my $self = shift;

    # Merge
    my $helper = ref $_[0] ? $_[0] : {@_};
    $helper = {%{$self->helper}, %$helper};
    $self->helper($helper);

    return $self;
}

sub get_inline_template {
    my ($self, $c, $template) = @_;

    # Class
    my $class =
         $c->stash->{template_class}
      || $ENV{MOJO_TEMPLATE_CLASS}
      || $self->default_template_class
      || 'main';

    # Get
    return Mojo::Command->new->get_data($template, $class);
}

# Bodies are for hookers and fat people.
sub render {
    my ($self, $c) = @_;

    # We got called
    $c->stash->{rendered} = 1;
    $c->stash->{content} ||= {};

    # Partial?
    my $partial = delete $c->stash->{partial};

    # Template
    my $template = delete $c->stash->{template};

    # Format
    my $format = $c->stash->{format} || $self->default_format;

    # Handler
    my $handler = $c->stash->{handler} || $self->default_handler;

    # Text
    my $text = delete $c->stash->{text};

    # JSON
    my $json = delete $c->stash->{json};

    my $options =
      {template => $template, format => $format, handler => $handler};
    my $output;

    # Text
    if (defined $text) {

        # Render
        $self->handler->{text}->($self, $c, \$output, {text => $text});

        # Extends?
        $c->stash->{content}->{content} = b("$output")
          if ($c->stash->{extends} || $c->stash->{layout}) && !$partial;
    }

    # JSON
    elsif (defined $json) {

        # Render
        $self->handler->{json}->($self, $c, \$output, {json => $json});
        $format = 'json';

        # Extends?
        $c->stash->{content}->{content} = b("$output")
          if ($c->stash->{extends} || $c->stash->{layout}) && !$partial;
    }

    # Template or templateless handler
    elsif ($template || $handler) {

        # Render
        return unless $self->_render_template($c, \$output, $options);

        # Extends?
        $c->stash->{content}->{content} = b("$output")
          if ($c->stash->{extends} || $c->stash->{layout}) && !$partial;
    }

    # Extends
    while (!$partial && (my $extends = $self->_extends($c))) {

        # Handler
        $handler = $c->stash->{handler} || $self->default_handler;
        $options->{handler} = $handler;

        # Format
        $format = $c->stash->{format} || $self->default_format;
        $options->{format} = $format;

        # Template
        $options->{template} = $extends;

        # Render
        $self->_render_template($c, \$output, $options);
    }

    # Partial
    return $output if $partial;

    # Encoding (JSON is already encoded)
    $output = b($output)->encode($self->encoding)->to_string
      if $self->encoding && !$json;

    # Response
    my $res = $c->res;
    $res->code($c->stash('status') || $self->default_status)
      unless $res->code;
    $res->body($output) unless $res->body;

    # Type
    my $type = $self->types->type($format) || 'text/plain';
    $res->headers->content_type($type) unless $res->headers->content_type;

    # Success!
    return 1;
}

sub template_name {
    my ($self, $options) = @_;

    # Template?
    return unless my $template = $options->{template} || '';
    return unless my $format   = $options->{format};
    return unless my $handler  = $options->{handler};

    return "$template.$format.$handler";
}

sub template_path {
    my $self = shift;
    return File::Spec->catfile($self->root, split '/',
        $self->template_name(shift));
}

sub _extends {
    my ($self, $c) = @_;

    # Layout
    $c->stash->{extends}
      ||= ($self->layout_prefix . '/' . delete $c->stash->{layout})
      if $c->stash->{layout};

    # Extends
    return delete $c->stash->{extends};
}

# Well, at least here you'll be treated with dignity.
# Now strip naked and get on the probulator.
sub _render_template {
    my ($self, $c, $output, $options) = @_;

    # Renderer
    my $handler  = $options->{handler};
    my $renderer = $self->handler->{$handler};

    # No handler
    unless ($renderer) {
        $c->app->log->error(qq/No handler for "$handler" available./);
        return;
    }

    # Render
    return unless $renderer->($self, $c, $output, $options);

    # Success!
    return 1;
}

1;
__END__

=head1 NAME

MojoX::Renderer - MIME type based renderer

=head1 SYNOPSIS

    use MojoX::Renderer;

    my $renderer = MojoX::Renderer->new;

=head1 DESCRIPTION

L<MojoX::Renderer> is the standard Mojo renderer. It turns your
stashed data structures into content. See the 'render' method for the main

=head2 ATTRIBUTES

L<MojoX::Types> implements the follwing attributes.

=head2 C<default_format>

    my $default = $renderer->default_format;
    $renderer   = $renderer->default_format('html');

The default format to render if C<format> is not set in stash. The
renderer will use L<MojoX::Types> to look up the content mime type.

=head2 C<default_handler>

    my $default = $renderer->default_handler;
    $renderer   = $renderer->default_handler('epl');

The default template handler to use for rendering. There are two handlers
in this distribution. The default 'epl' refers to Embedded Perl Lite, 
handled by L<Mojolicious::Plugin::EplRenderer> and 'ep', 'Embedded Perl',
handled by L<Mojolicious::Plugin::EpRenderer>.

=head2 C<default_status>

    my $default = $renderer->default_status;
    $renderer   = $renderer->default_status(404);

The default status to set when rendering content. Defaults to 200.

=head2 C<default_template_class>

    my $default = $renderer->default_template_class;
    $renderer   = $renderer->default_template_class('main');

Default class to look for templates in. The renderer will use this
to look for templates in the __DATA__ section, if it cannot find a
file to use.

=head2 C<encoding>

    my $encoding = $renderer->encoding;
    $renderer    = $renderer->encoding('koi8-r');

Encoding to use to encode content. If unset, will not encode
the content.

=head2 C<handler>

    my $handler = $renderer->handler;
    $renderer   = $renderer->handler({epl => sub { ... }});

Registered handlers in the renderer. Add to this with the add_handler
method.

=head2 C<helper>

    my $helper = $renderer->helper;
    $renderer  = $renderer->helper({url_for => sub { ... }});

Registered helpers in the renderer. Add to this with the add_helper
method.

=head2 C<layout_prefix>

    my $prefix = $renderer->layout_prefix;
    $renderer  = $renderer->layout_prefix('layouts');

Directory to look for layouts in. Defaults to 'layouts'.

=head2 C<root>

   my $root  = $renderer->root;
   $renderer = $renderer->root('/foo/bar/templates');
   
Directory to look for templates in. Defaults to the system root.

=head2 C<types>

    my $types = $renderer->types;
    $renderer = $renderer->types(MojoX::Types->new);

L<MojoX::Types> instance to use for looking up MIME types.

=head1 METHODS

L<MojoX::Renderer> inherits all methods from L<Mojo::Base> and implements the
follwing the ones.

=head2 C<new>

    my $renderer = MojoX::Renderer->new;

Create a new renderer. Takes a hash or hashref with any
of the attributes listed above.

=head2 C<add_handler>

    $renderer = $renderer->add_handler(epl => sub { ... });
    
Add a new handler to the renderer. See L<Mojolicious::Plugin::EpRenderer>
for a sample renderer.

=head2 C<add_helper>

    $renderer = $renderer->add_helper(url_for => sub { ... });

Add a new helper to the renderer. See L<Mojolicious::Plugin::EpRenderer> for
more information about the helpers.

=head2 C<get_inline_template>

    my $template = $renderer->get_inline_template($c, 'foo.html.ep');

This is a helper method for the renderer. Gets an inline template by name.

=head2 C<render>

    my $success  = $renderer->render($c);

    $c->stash->{partial} = 1;
    my $output = $renderer->render($c);

Render output through one of the Mojo renderers. This renderer requires
some configuration, at the very least you will need to have a default
renderer set and a default handler, as well as a template or text/json.
See L<Mojolicious::Controller> for a more user friendly render method.

=head2 C<template_name>

    my $template = $renderer->template_name({
        template => 'foo/bar',
        format   => 'html',
        handler  => 'epl'
    });
    
Helper method for the renderer. Builds a template based on an option hash
with template, format and handler.

=head2 C<template_path>

    my $path = $renderer->template_path({
        template => 'foo/bar',
        format   => 'html',
        handler  => 'epl'
    });

Helper method for the renderer. Returns a full path to a template. Takes 
the same options hash as template_name.

=cut

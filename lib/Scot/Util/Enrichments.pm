package Scot::Util::Enrichments;

use Module::Runtime qw(require_module compose_module_name);

use Moose;

# config is passed in the new call

has mappings    => (
    is          => 'ro',
    isa         => 'HashRef',
    required    => 1,
    default     => sub { {} },
);

has configs     => (
    is          => 'ro',
    isa         => 'HashRef',
    required    => 1,
    default     => sub { {} },
);

sub BUILD {
    my $self    = shift;
    my $maps    = $self->mappings;
    my $confs   = $self->configs;
    my $meta    = $self->meta;
    $meta->make_mutable;

    foreach my $name (keys %{$confs} ) {
        my $href    = $confs->{$name};
        my $type    = $href->{type};

        if ( $type eq "native" ) {
            my $module  = $href->{module};
            my $config  = $href->{config};
            require_module($module);
            $meta->add_attribute(
                $name   => (
                    is      => 'rw',
                    isa     => $module,
                )
            );
            my $instance  = $module->new($config);

            if ( defined $module ) {
                $self->$name($instance);
            }
        }
        elsif ( $type =~ /link/ ) {
            $meta->add_attribute(
                $name   => (
                    is          => 'rw',
                    isa         => 'HashRef',
                    default     => sub { $href },
                )
            );
        }
        else {
            die "Unsupported Enrichment Type!";
        }
    }
    $meta->make_immutable;
}

sub enrich {
    my $self    = shift;
    my $entity  = shift;
    my $force   = shift;
    my $data    = {};   # put enrichments here

    my $update_count    = 0;

    NAME:
    foreach my $enricher_name (keys %{$self->mappings}) {
        my $enricher    = $self->$enricher_name;

        unless ( $enricher ) {
            $data->{$enricher_name} = {
                type    => 'error',
                data    => 'invalid enricher',
            };
            next NAME;
        }

        if ( ref($enricher) eq "HASH" ) {
            if ( $enricher->{type} =~ /link/ ) {
                if (! defined $force &&
                      defined $entity->data->{$enricher_name} ) {
                    $data->{$enricher_name} = {
                        type    => 'link',
                        data    => {
                            url     => sprintf($enricher->{url},
                                               $entity->value),
                            title   => $enricher->{title},
                        },
                    };
                    $update_count++;
                }
            }
            else {
                $data->{$enricher_name} = {
                    type => 'error',
                    data => 'unsupported enrichment type',
                };
            }
        }
        else {
            if (! defined $force && 
                  defined $entity->data->{$enricher_name}) {
                next NAME;
            }
            my $entity_data = $enricher->get_data($entity->type, 
                                                  $entity->value);
            if ($entity_data) {
                $data->{$enricher_name} = {
                    data    => $entity_data,
                    type    => 'data',
                };
                $update_count++;
            }
            else {
                $data->{$enricher_name} = {
                    type    => 'error',
                    data    => 'no data',
                };
            }
        }
    }
    return $update_count, $data;
}


1;

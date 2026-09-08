"""Converge managed Router options without replacing bootstrap identity/keyring."""

from configparser import ConfigParser, Error
from io import StringIO

from ansible.errors import AnsibleFilterError


def mysql_router_config(content, settings):
    parser = ConfigParser(interpolation=None, delimiters=('=',))
    parser.optionxform = str
    try:
        for key, allowed in (
            ('rw_strategy', ('first-available', 'round-robin')),
            ('ro_strategy', ('first-available', 'round-robin', 'round-robin-with-fallback')),
            ('split_strategy', ('first-available', 'round-robin')),
        ):
            if settings[key] not in allowed:
                raise ValueError('Routing strategy is incompatible with destination role')
        parser.read_string(content)
        required = ('routing:bootstrap_rw', 'routing:bootstrap_ro')
        if not all(parser.has_section(section) for section in required):
            raise ValueError('Router configuration lacks standard bootstrap routes')
        if not any(s.startswith('metadata_cache:') for s in parser.sections()):
            raise ValueError('Router configuration lacks bootstrap metadata')
        # Older repository versions added a second split route on the same port.
        parser.remove_section('routing:read_write_split')
        split = 'routing:bootstrap_rw_split'
        if not parser.has_section(split):
            parser.add_section(split)
        defaults = {
            'max_total_connections': settings['max_total_connections'],
            'read_timeout': settings['metadata_read_timeout'],
            'connect_timeout': settings['metadata_connect_timeout'],
        }
        for key, value in defaults.items():
            parser['DEFAULT'][key] = str(value)
        for section in parser.sections():
            if section.startswith('routing:'):
                for key in ('max_connections', 'max_connect_errors', 'client_connect_timeout', 'connect_timeout'):
                    parser[section][key] = str(settings['routing'][key])
        for suffix, port, strategy in (
            ('rw', settings['rw_port'], settings['rw_strategy']),
            ('ro', settings['ro_port'], settings['ro_strategy']),
            ('rw_split', settings['split_port'], settings['split_strategy']),
        ):
            section = parser['routing:bootstrap_' + suffix]
            section['bind_port'] = str(port)
            section['routing_strategy'] = strategy
        parser[split].update({
            'bind_address': parser['routing:bootstrap_rw'].get('bind_address', '0.0.0.0'),
            'destinations': 'metadata-cache://' + settings['cluster_name'] + '/default?role=PRIMARY_AND_SECONDARY',
            'access_mode': 'auto', 'connection_sharing': '1', 'protocol': 'classic',
        })
        if parser.has_section('http_server'):
            parser['http_server']['port'] = str(settings['admin_port'])
        output = StringIO()
        parser.write(output, space_around_delimiters=False)
        return output.getvalue()
    except (Error, ValueError, KeyError):
        # Do not echo config content; it contains bootstrap account details.
        raise AnsibleFilterError('Cannot converge Router configuration; check bootstrap structure and managed settings') from None


class FilterModule:
    def filters(self):
        return {'mysql_router_config': mysql_router_config}

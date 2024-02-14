from .EndpointHandlers import (
    handle_get_jobs,
    handle_add_job,
    get_content,
    handle_add_worker,
    handle_add_queue,
    handle_get_queue,
    handle_get_login,
    handle_get_register,
    handle_login,
    handle_register,
    handle_get_workers,
    handle_add_site,
    handle_get_sites
)
from typing import Any

endpoints: dict[str, dict[str, Any]] = {
    '/api/login': {
        'GET': {
            'decoder': get_content,
            'action': handle_get_login,
            'content_type': 'application/json',
            'required_parameters': ['username', 'password']
        },
        'POST': {
            'decoder': get_content,
            'action': handle_login,
            'content_type': 'application/json',
            'required_parameters': ['username', 'password']
        }
    },
    '/api/register': {
        'GET': {
            'decoder': get_content,
            'action': handle_get_register,
            'content_type': 'application/json',
        },
        'POST': {
            'decoder': get_content,
            'action': handle_register,
            'content_type': 'application/json',
        }
    },
    '/api/jobs': {
        'GET': {
            'decoder': get_content,
            'action': handle_get_jobs,
            'content_type': 'application/json',
            'optional_parameters': ['worker_id'],
            'auth_required': True
        },
        'POST': {
            'decoder': get_content,
            'action': handle_add_job,
            'content_type': 'application/json',
            'auth_required': True
        }
    },
    '/api/sites': {
        'GET': {
            'decoder': get_content,
            'action': handle_get_sites,
            'content_type': 'application/json',
            'optional_parameters': ['worker_id'],
            'auth_required': True
        },
        'POST': {
            'decoder': get_content,
            'action': handle_add_site,
            'content_type': 'application/json',
            'auth_required': True
        }
    },
    '/api/queues': {
        'GET': {
            'decoder': get_content,
            'action': handle_get_queue,
            'content_type': 'application/json',
            'auth_required': True
        },
        'POST': {
            'decoder': get_content,
            'action': handle_add_queue,
            'content_type': 'application/json',
            'auth_required': True
        }
    },
    '/api/workers': {
        'GET': {
            'decoder': get_content,
            'action': handle_get_workers,
            'content_type': 'application/json',
            'auth_required': True
        },
        'POST': {
            'decoder': get_content,
            'action': handle_add_worker,
            'content_type': 'application/json',
            'required_parameters': ['worker_id'],
            'auth_required': True
        }
    }
}

from .MessageHandling import handle_get_jobs, handle_add_job, get_content, handle_add_worker
messages = {
    'get_jobs': {
        'method': 'GET',
        'decoder': get_content,
        'action': handle_get_jobs,
        'content_type': 'application/json',
        'optional_parameters': ['worker_id']
    },
    'add_job': {
        'method': 'POST',
        'decoder': get_content,
        'action': handle_add_job,
        'content_type': 'application/json',
    },
    'add_worker': {
        'method': 'POST',
        'decoder': get_content,
        'action': handle_add_worker,
        'content_type': 'application/json',
        'required_parameters': ['worker_id']
    },
    'add_queue': {
        'method': 'POST',
        'decoder': get_content,
        'action': handle_add_queue,
        'content_type': 'application/json',
    },
    'get_queue': {
        'method': 'GET',
        'decoder': get_content,
        'action': handle_get_queue,
        'content_type': 'application/json',
    },
    # ... (other routes)
}

classdef Message
% Message class
% Common messages. A message is produced using the static constructors in this class. This class helps ensure consistency between tools, required arguments are specified in the constructors.
properties
    content
    httpMethod
    contentType
    endpoint
end

methods (Static)
    function messageObj = register_worker(worker_id)
        % Register a worker with a server

        % Make sure worker_id is a string
        worker_id = OI.Message.arg_to_string(worker_id);

        % Create message object
        messageObj = OI.Message();
        messageObj.httpMethod = 'POST';
        messageObj.endpoint = 'add_worker';
        messageObj.contentType = 'json';
        messageObj.content = {'worker_id',worker_id,'octave_query','workaround'};

    end % register_worker

    function messageObj = get_job(worker_id)
        % Get a task from the server

        % Make sure worker_id is a string
        worker_id = OI.Message.arg_to_string(worker_id);

        % Create message object
        messageObj = OI.Message();
        messageObj.httpMethod = 'GET';
        messageObj.endpoint = 'get_jobs';
        messageObj.contentType = 'json';
        messageObj.content = {'worker_id',worker_id,'octave_query','workaround'};

    end % get_task

    function messageObj = ready_for_job(worker_id)
        % Tell the manager that the worker is ready for a job

        % Make sure worker_id is a string
        worker_id = OI.Message.arg_to_string(worker_id);

        % Create message object
        messageObj = OI.Message();
        messageObj.httpMethod = 'POST';
        messageObj.endpoint = 'get_jobs';
        messageObj.contentType = 'json';
        messageObj.content = {'worker_id','manager', 'requested_by',worker_id, 'octave_query','workaround'};

    end

    function str = arg_to_string(arg)
        % Convert argument to string
        if isnumeric(arg)
            str = num2str(arg);
        elseif ischar(arg)
            str = arg;
        else
            error('Argument must be numeric or string');
        end
    end % arg_to_string

end % methods (Static)

end % classdef

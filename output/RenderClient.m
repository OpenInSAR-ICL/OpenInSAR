% FILEPATH: /rds/user/saa116/home/OI_ICL_FORK/output/RenderClient.m
% RenderClient A simple HTTP client for Matlab. Finds a server at 'https://openinsar-jobs.onrender.com/jobs' 
% and sends a POST request with JSON data. The server responds with JSON data.
% data. The server responds with JSON data.
% The required JSON data is:

% messages = {
%     'get_jobs': {
%         'method': 'GET',
%         'decoder': get_content,
%         'action': handle_get_jobs,
%         'content_type': 'application/json',
%         'optional_parameters': ['worker_id']
%     },
%     'add_job': {
%         'method': 'POST',
%         'decoder': get_content,
%         'action': handle_add_job,
%         'content_type': 'application/json',
%     },
%     'add_worker': {
%         'method': 'POST',
%         'decoder': get_content,
%         'action': handle_add_worker,
%         'content_type': 'application/json',
%         'required_parameters': ['worker_id']
%     }
%     # ... (other routes)
% }


classdef RenderClient
methods
    function obj = RenderClient()
        % Constructor

        address = 'https://openinsar-jobs.onrender.com';

        % Wait for server to start
        while true
            try
                response = webread(address);
                disp(response)
                break
            catch
                pause(60)
            end
        end

        % Get our worker ID from PBS
        worker_id = getenv('PBS_ARRAY_INDEX');
        % make sure it's a string
        if isnumeric(worker_id)
            worker_id = num2str(worker_id);
        end
        

        % Add a job
        job = struct();
        job.assigned_to = worker_id;
        job.task = ['doing stuff on render client ' worker_id];

        % Send the job
        options = weboptions('MediaType','application/json');
        response = webwrite([address '/add_job'], job, options);
        disp(response)
        disp('now waiting 10 seconds')

        % wait a second
        pause(10)

        % Get some jobs
        response = webread([address '/jobs']);
        disp(response)
        jobs = response.jobs;

        for i = 1:length(jobs)
            disp(i)
            disp(jobs(i))
            disp(jobs(i).assigned_to)
            disp(jobs(i).task)
            % fprintf(1,'  assigned_to: %s\n', response(i).assigned_to)
            % fprintf(1,'  task: %s\n', response(i).task)
            if strcmp(jobs(i).assigned_to, worker_id)
                jobFromServer = jobs(i);
            end
        end

        if ~exist('jobFromServer', 'var')
            error('No job found for worker %s', worker_id)
        else
            % Print the job
            fprintf(1,'Job from server for me:\n')
            disp(jobFromServer)
        end



    end % RenderClient
end % methods
end % classdef

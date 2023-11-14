classdef WorkerInformation

properties
    id
    startDirectory
    nCpus
end

methods
    function obj = WorkerInformation( ~ )
        % Get the worker ID from the environment
        obj = obj.get_worker_index();
        % Get the number of available cores
        obj = obj.get_max_cpus();
        [~,obj.startDirectory] = fileparts(pwd);
    end

    function obj = get_worker_index( obj )
        % Get the worker ID from the environment
        obj.id = getenv('PBS_ARRAY_INDEX');
        % Convert to a number
        if ~isempty(obj.id) && ~isnumeric(obj.id)
            obj.id = str2double(obj.id);
        end
        % if it doesn't exist, use a random integer
        if isempty(obj.id)
            obj.id = randi(100) + 1000;
            warning('PBS_ARRAY_INDEX environment variable not set. Using random integer.');
        end
    end

    function obj = get_max_cpus( obj )
        % get number of available cores
        nCpuEnvVar = getenv('nCpus');
        if ~isempty(nCpuEnvVar)
            nCpu = str2num(nCpuEnvVar); %#ok<ST2NM>
        else
            warning('nCpus environment variable not set. Using 4.');
            nCpu = 4; % Pure guess
        end
        obj.nCpus = nCpu;
    end

end % methods

end % classdef
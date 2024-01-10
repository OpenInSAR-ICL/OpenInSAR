classdef WorkerClient

properties
    workerInfo
    messenger
    engine
    status
    exitFlag = false
    role = 'processor'
end % properties

methods
    function this = WorkerClient()
        try
            this = this.setup();
            % main loop, breaks out on either a config or stop event
            while true
                if strcmpi(this.role,'manager')
                    this = this.manager_main();
                else
                    this = this.main();
                end
                % Check the exit flag
                if this.exitFlag
                    break;
                end % if
            end % while
        catch ERR
            disp(ERR)
            this.handle_uncaught_exception(ERR);
            exit(1);
        end % try
    end % constructor

    function this = setup(this)
        % Setup the worker
        this.workerInfo = OI.WorkerInformation(this);
        this = this.set_messenger();
        this = this.set_role();
    end % function

    function this = set_messenger(this, messengerType, serverAddress)
        % Set the messenger, according to environment variables
        if nargin < 2
            messengerType = getenv('OI_MESSENGER');
        end % if
        if nargin < 3
            serverAddress = getenv('OI_SERVER');
            if isempty(serverAddress)
                serverAddress = '$WORK/comms/';
            end % if
        end % if

        if strcmpi(messengerType, 'http')
            this.messenger = OI.HttpMessenger(serverAddress);
        else
            this.messenger = OI.FileSystemMessenger(this.workerInfo, serverAddress);
        end % if
    end % function

    function this = set_role(this, role)
        % Default is to get role from env
        if nargin == 1
            role = this.workerInfo.role;
        end
        % Set the role of the worker
        if strcmpi(role, 'manager')
            this.engine = OI.DistributionEngine();
            this.role = 'manager';
        elseif strcmpi(role, 'relay')
            this.engine = OI.Engine();
            this.role = 'relay';
        else
            % if strcmpi(role, 'processor')
            this.engine = OI.Engine();
            this.role = 'processor';
        end % if
    end % function

    function this = set_config(this, config)
        % Split the config into key-value pairs
        config = strsplit(config, ',');

        % convert the config to a struct
        s = struct();
        for i = 1:numel(config)
            keyVal = strsplit(config{i}, '=');
            key = keyVal{1};
            val = keyVal{2};
            s.(key) = val;
        end % for

        % if the config contains a messenger, set it
        if isfield(s, 'OI_MESSENGER')
            this = this.set_messenger(s.OI_MESSENGER, s.OI_MESSENGER_ENDPOINT);
        end % if

        % if the config contains a role, set it
        if isfield(s, 'OI_ROLE')
            this = this.set_role(s.OI_ROLE);
        end % if

    end % function

    function handle_uncaught_exception(this, ERR)
        % Error is unhandled. Restart matlab via the calling script.
        % check we have workerInfo, otherwise we don't know how to restart
        if isempty(this.workerInfo)
            % We probably haven't initialised successfully
            rethrow(ERR);
        end % if

        % First, log the error:
        try
            OI.Compatibility.print_error_stack(ERR);
        catch ERRPRINT
            disp(ERRPRINT)
            rethrow(ERR);
        end
        WRITE_ERROR_TO_FILE = false; % TODO implement controls for this
        if WRITE_ERROR_TO_FILE
            this.write_error_to_file(ERR);
        end % if


    end

    function write_error_to_file(this, ERR)
        workerId = this.id();
        if isnumeric(workerId)
            workerId = num2str(workerId);
        end % if

        errorFilePath = fullfile( ...
        this.workerInfo.startDirectory, ...
        sprintf('worker_%s.error"', workerId) ...
        );

        fid = fopen(errorFilePath, 'w');
        try
            errStr = OI.Compatibility.print_error_stack(ERR);
            fprintf(fid, '%s', errStr);
        catch
            % Just write any old shit
            fprintf(fid, 'weird error');
        end % try
        fclose(fid);
        % Rethrow the error
        rethrow(ERR);
    end

    function [result, error] = run(this, task)
        [result, error] = this.workerInfo.run(task);
    end % run

    function id = id( this )
        if isempty(this.workerInfo)
            id = 'Unknown';
            return
        end

        % Shortcut to get the id from the worker info struct
        id = this.workerInfo.id;
    end % function

    function this = update_status(this, task)
        % Update the status of the worker
        this.status = task;
        % Tell the server our status
        this.messenger.send( ...
            OI.Message.update_worker(this.id, 'status', this.status) ...
            );
    end % function

    function this = main(this)
        % Connect to the server
        assert(~isempty(this.messenger), 'No messenger specified');
        this.messenger = this.messenger.connect();

        % Register the worker
        this.messenger.send( ...
            OI.Message.register_worker(this.id) ...
            );

        % Main loop
        while true
            % Get a task
            task = this.messenger.send( ...
                OI.Message.get_job(this.id) ...
                );

            % Check the task
            if isempty(task)
                fprintf(1, 'No task received')
                % Ask for a new task
                response = this.messenger.send( ...
                    OI.Message.ready_for_job(this.id) ...
                    );
                assert(response, 'No response from server')
                break;
            end % if

            fprintf(1, 'Received task: %s\n', task)

            % The task might be something like 'stop', or 'config'

            if strcmpi(task, 'stop')
                % Stop the worker
                this.exitFlag = true;
                break;
            end % if

            if numel(task)>6 && strcmpi(task(1:6), 'config')
                % Set the config
                config = task(8:end);
                this.workerInfo.set_config(config);
                break;
            end % if

            % load and validate the task
            job = OI.Job(task);

            % Add the job to the queue
            this.engine.queue.add_job(job);

            while ~oi.engine.queue.is_empty()
                dbSize = numel(this.engine.database.data);
                try
                    oi.engine.run_next_job();
                catch err
                    fprintf(1, 'Error running job: %s\n', err.message);
                    this.update_status('error', err.message);
                end % try
            end % while ~oi.engine.queue.is_empty()

            % Check the plugin
            if this.engine.plugin.isFinished
                answer = '';
                if dbSize < numel(oi.engine.database.data)
                    lastEntry = oi.engine.database.data{end};
                    if (isa(lastEntry,'OI.Data.DataObj') && ~lastEntry.hasFile) ...
                            || isstruct(lastEntry)
                        % convert the database additions to xml
                        resultAsStruct = OI.Functions.obj2struct( lastEntry );
                        resultAsXmlString = OI.Functions.struct2xml( resultAsStruct ).to_string();
                        answer = resultAsXmlString;
                    end
                end
            end % if engine.plugin.isFinished

            % Tell the server we are done
            this.messenger.send( ...
                OI.Message.job_done(this.id, task, answer) ...
                );

        end % while main loop

    end % main



    function this = manager_main(this)
        disp('Manager main routine')

        % Connect to the server
        assert(~isempty(this.messenger), 'No messenger specified');
        this.messenger = this.messenger.connect();

        % Register the manager
        this.messenger.send(OI.Message.register_manager(this.id));

        % Try to load some target data. This will add jobs to the queue.
        thingToDo = OI.Data.PsiSummary();
        this.engine.load( thingToDo )

        % Main loop for managing tasks
        while true
            % check for stop signal
            task = this.messenger.send( OI.Message.get_job(this.id) );
            if strcmpi(task, 'stop')
                % Stop the manager
                this.exitFlag = true;
                break;
            end % if

            % check for config signal
            if numel(task)>6 && strcmpi(task(1:6), 'config')
                % Set the config
                config = task(8:end);
                this.workerInfo.set_config(config);
                break;
            end % if
            queueSummaryString = this.engine.queue.summary();
            this.messenger.send( OI.Message.status('manager_queue', queueSummaryString) );
            currentJobs = this.messenger.send( OI.Message.get_current_jobs() );

            % clear the queue of any running jobs, handle any finished jobs
            for i = 1:numel(currentJobs)
                cj = currentJobs{i};
                if cj.hasAnswer
                    answer = fj.answer;
                    % Try to convert to xml and add to database
                    resultXmlParsed = OI.Data.XmlFile( answer );
                    resultAsStructFromXml = resultXmlParsed.to_struct();
                    dataObj = OI.Functions.struct2obj( resultAsStructFromXml );
                    if isa(dataObj,'OI.Data.DataObj')
                        oi.engine.database.add( dataObj );
                    elseif isstruct(dataObj)
                        oi.engine.database.add( dataObj, dataObj.name );
                    end
                end % if

                if cj.isFinished
                    this.engine.queue.remove_job(cj);
                    this.messenger.send( OI.Message.ack_job_done(cj) );
                end % if

                if cj.isAssigned
                    this.engine.queue.remove_job(cj);
                end % if
            end % for

            % Check if the queue is empty
            if this.engine.queue.is_empty()
                % Load some more data
                this.engine.load( thingToDo )
                % if the queue is still empty, we are done
                if this.engine.queue.is_empty()
                    this.messenger.send( OI.Message.status('manager_queue', 'empty') );
                    this.messenger.send( OI.Message.status('manager', 'done') );
                    exit(0);
                end % if
                break;
            end % if

            % run the next job. The engine will find an available worker.
            this.engine.run_next_job();
            % if the job is for us, then we will run it and add jobs to the queue

        end

end

end % methods

end % classdef

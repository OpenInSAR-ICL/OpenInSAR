classdef Leader
    properties
        client = [];
        engine = [];
        data_directory = '';

        projects = [];
        projectActive = [];
        projectEngineCopies = {};
        projectIndex = []; % will become a map in ctor

        WAIT_TIME = 0.1;
    end % properties

    methods
        function self = Leader(host, username, password, data_directory)

            self = self.clear_project_copies();
            if nargin == 4
                self.client = OI.BaseClient(host);
                self.client = self.client.login(username, password);
                self.data_directory = data_directory;
            else
                api_host = getenv('OI_API_HOST');
                username = getenv('OI_USERNAME');
                password = getenv('OI_PASSWORD');
                self.data_directory = getenv('OI_DATA_DIRECTORY');
                if ( isempty(api_host) || isempty(username) || ...
                    isempty(password) || isempty(self.data_directory) )
                    error('Worker:Worker', ...
                        ['API host, username, password, data directory must be set', ...
                        ' by either arguments or environment variables']);
                end
                self.client = OI.BaseClient(api_host);
                self.client = self.client.login(username, password);
            end
            self.engine = OI.Engine();
        end % Worker

        function self = clear_project_copies(self)
            self.projectEngineCopies = {};
            self.projectIndex = ...
                containers.Map('KeyType','char','ValueType','double');
        end

        function run(self)
            while true
                self = self.process_projects();
                fprintf(1,'It appears that there is no more work. Waiting for 1 min.\n')
                for ii=1:60
                    pause(1)
                end
            end
        end % run


        function self = process_projects(self)
            self.projects = self.client.list_projects();
            self = self.prioritise_projects();

            if isempty(self.projects)
                fprintf('No projects to process\n');
                return
            end
            if self.projectActive(1) == 0
                fprintf('No active projects to process\n');
                return
            end
            
            for ii = 1:numel(self.projects)
                if ~self.projectActive(ii)
                    fprintf(1,'Skipping project %s as it appears to be finished or inactive.\n',self.projects(ii).name)
                    continue
                end
                % load in jobs for the first project
                self = self.switch_to_project(self.projects(ii));
                if self.engine.queue.length()
                    self = self.process_step(self.projects(ii));
                else
                    fprintf(1,'No more jobs for project %s.\n',self.engine.database.fetch('PROJECT_NAME'))
                    self.projectActive(ii) = 0;
                    % patch the remote project to '0 priority?'
                end
            end

        end % process_projects

        function self = process_step(self, projJson)
            % loop through all jobs for this project queue
            while self.engine.queue.length > 0
                fprintf(1,'Loop start qlength %d\n',self.engine.queue.length)
                self.stop_if_canary_file_present();

                % % Get an update from the server
                % assignments = self.client.list_assignments();
                % jobs = self.client.list_jobs();
                % self.workerPool = self.client.list_workers();

                % [finishedJobs, ongoingJobs, errorJobs] = ...
                %     self.categorise_jobs(jobs, assignments);

                % % update our database with the results
                % self.engine = self.handle_results(finishedJobs);
                % % 
                % self.workerPool = self.handle_errors(errorJobs);
                % self = self.handle_ongoing(ongoingJobs);
                [self, status] = self.get_system_status();
                if ~isempty(status.categorisedJobs.errored)
                    self.engine = self.handle_error_jobs(status.categorisedJobs.errored);
                end
                if ~isempty(status.categorisedJobs.finished)
                    self = self.handle_finished_jobs(status.assignments, status.categorisedJobs.finished);
                    fprintf(1,'Qlength %d\n',self.engine.queue.length)
                end

                eligibleWorkers = status.eligibleWorkers;
                nEligibleWorkers = numel(eligibleWorkers);

                if nEligibleWorkers
                    % If we have workers available, while other jobs have been
                    % assigned but not acknowledged (perhaps by old workers) we
                    % should reassign the jobs and deregister the old workers.
                    self.handle_dangling_jobs(status.categorisedJobs.dangling);
                end

                nextJob = self.engine.queue.next_job();
                % distributable jobs have the target property set
                if ~isempty(nextJob.target)

                    if nEligibleWorkers == 0
                        fprintf('No workers available, waiting %d seconds\n', self.WAIT_TIME);
                        % no workers available, wait for a worker to become available
                        pause(self.WAIT_TIME);
                        continue
                    end
                    jobArray = self.engine.queue.jobArray;
                    fprintf('There are %d jobs in the queue\n', numel(jobArray));
                    % pull out distributable jobs
                    distributableJobs = jobArray(cellfun(@(x) ~isempty(x.target), jobArray));
                    ongoingJobStrings = cell(numel(status.categorisedJobs.ongoing),1);
                    for ii=1:numel(status.categorisedJobs.ongoing)
                        oiJob = self.client.json2job(status.categorisedJobs.ongoing(ii));
                        ongoingJobStrings{ii} = oiJob.to_string();
                    end
                    
                    
                    for ii=1:numel(distributableJobs)
                        if isempty(eligibleWorkers)
                            break
                        end

                        % check if job is already ongoing
                        skipJob = false;
                        for jj=1:numel(ongoingJobStrings)
                            if strcmp(distributableJobs{ii}.to_string(), ongoingJobStrings{jj})
                                skipJob = true;
                                break
                            end
                        end
                        if skipJob
                            continue
                        end

                        [worker, eligibleWorkers] = ...
                            self.pop_worker(eligibleWorkers);
                        self.client.post_job(projJson.id, distributableJobs{ii}, worker);
                        nEligibleWorkers = nEligibleWorkers - 1;
                    end
                    nextJob = self.engine.queue.next_job();

                    % % job is distributable, assign to a worker
                    % while ~isempty(eligibleWorkers) && ~isempty(nextJob) && ~isempty(nextJob.target)
                    %     [worker, eligibleWorkers] = ...
                    %         self.pop_worker(eligibleWorkers);
                    %     self.client.post_job(projJson.id, nextJob, worker);
                    %     nEligibleWorkers = nEligibleWorkers - 1;
                    %     nextJob = self.engine.queue.next_job();
                    % end

                    %% Debugging statements
                    fprintf('There are %d eligible workers remaining\n', nEligibleWorkers);
                    if isempty(nextJob)
                        fprintf('No more jobs to distribute\n');
                        break;
                    end
                    if nEligibleWorkers == 0
                        fprintf('No more eligible workers, waiting\n');
                        pause(self.WAIT_TIME)
                    end
                    if isempty(nextJob.target)
                        fprintf('Next job is not distributable\n');
                    end
                else
                    % job is not distributable, run it locally
                    self.engine.run_next_job();
                end               

                %% TODO somehow in the few preceding lines we need to identify
                % the case where: We have lots of workers and no useful work.
                % Currently the engine will hang waiting for the few remaining
                % workers to finish their jobs. We need to temporarily move on
                % to the next project in the prioritised list.
                % Heres an idea: when a job-creation occurs locally, we track
                % the id of the job-creation job and the created jobs. If the
                % created jobs are outstanding then we mark the job-creator as
                % 'waiting for results'. If there are no jobs in the queue that
                % aren't waiting or distributed then we move on to the next
                % project.
            end
        end % process_step

        function self = handle_dangling_jobs(self, danglingJobs)
            currentTime = now();
            daysToSeconds = 24*60*60;
            for dj = danglingJobs(:)'
                % check how long the job has been dangling
                disp('Dangling job detected')
                jobCreationTimeString = dj.created;
                % example: '2024-12-16T21:12:05.228123Z'
                % It's easier to drop the fractional seconds
                jobCreateTimeString = jobCreationTimeString(1:19);
                jobCreateTime = datenum(jobCreateTimeString,'yyyy-mm-ddTHH:MM:SS');
                timeDiff = (currentTime - jobCreateTime)*daysToSeconds;
                if timeDiff > 60
                    % if it's been dangling for more than 60 seconds, reassign
                    % the job and deregister the worker
                    self.handle_dangling_job(dj);
                end
            end
        end

        function self = handle_dangling_job(self, danglingJob)
            % find the worker
            self.client.delete_worker(danglingJob.worker);
            % reassign the job, for now we can just delete the job and
            % let the engine decide if it needs to be requeued
            self.client.delete_job(danglingJob.id);

        end

        function [self, status] = get_system_status(self)
            status = struct( ...
                'assignments', [], 'jobs', [], 'workerPool', [], ...
                'allWorkers', [], 'categorisedJobs', [], 'eligibleWorkers', []);
                
            % Get an update from the server
            status.assignments = self.client.list_assignments();
            status.jobs = self.client.list_jobs();
            status.workerPool = self.client.list_workers();
            status.allWorkers = status.workerPool;
            okToWork = status.workerPool;
            
            status.categorisedJobs = ...
                self.categorise_jobs(status.jobs, status.assignments);

            % anything ongoing, assigned, dangling, is not an eligible worker
            if ~isempty(status.categorisedJobs.ongoing)
                okToWork = okToWork(~ismember([okToWork.id], [status.categorisedJobs.ongoing.worker]));
            end
            if ~isempty(status.categorisedJobs.assigned)
                okToWork = okToWork(~ismember([okToWork.id], [status.categorisedJobs.assigned.worker]));
            end
            if ~isempty(status.categorisedJobs.dangling)
                okToWork = okToWork(~ismember([okToWork.id], [status.categorisedJobs.dangling.worker]));
            end
            status.eligibleWorkers = okToWork;
        end


        function jobCats = categorise_jobs(self, jobs, assignments)
            jobCats = struct( ...
                'finished', [], 'ongoing', [], 'errored', [], ...
                'unassigned', [], 'assigned', [], 'dangling', []);
            if isempty(jobs)
                return
            end

            % Finished jobs have 'completed' set
            isComplete = arrayfun(@(x) x.completed, assignments);
            completedAssignments = assignments(isComplete);
            if ~isempty(completedAssignments)
                jobCats.finished = jobs(arrayfun(@(x) any([x.id] == [completedAssignments.job]), jobs));
            end

            % Error jobs are those that have status 'error'
            isError = arrayfun(@(x) strcmpi(x.status, 'error') || strcmpi(x.status, 'failed'), assignments);
            errorAssignments = assignments(isError);
            if ~isempty(errorAssignments)
                jobCats.errored = jobs(arrayfun(@(x) any([x.id] == [errorAssignments.job]), jobs));
            end

            % Ongoing jobs are those that are not complete or errored
            jobCats.ongoing = jobs;
            if ~isempty(jobCats.errored)
                jobCats.ongoing = jobCats.ongoing(~ismember([jobCats.ongoing.id], [jobCats.errored.id]));
            end
            if ~isempty(jobCats.finished)
                jobCats.ongoing = jobCats.ongoing(~ismember([jobCats.ongoing.id], [jobCats.finished.id]));
            end


            % Unassigned jobs have no worker assigned
            if ~isempty(assignments)
                jobCats.assigned = jobs(ismember([jobs.id], [assignments.job]));
                jobCats.unassigned = jobCats.ongoing(~ismember([jobCats.ongoing.id], [jobCats.assigned.id]));
            end
            
            % Dangling jobs have been assigned by the leader but are not present
            % in the list of assignments
            jobCats.dangling = jobs;
            if ~isempty(jobCats.assigned)
                jobCats.dangling = jobCats.dangling(~ismember([jobCats.dangling.id], [jobCats.assigned.id]));
            end


        end

        function stop_if_canary_file_present(self)
            if ~OI.OperatingSystem.isUnix
                return
            end
            canaryFile = fullfile(self.data_directory,'canary');
            resetFile = fullfile(self.data_directory,'canaryr');

            if exist(canaryFile,'file')
                restoredefaultpath
                addpath('ICL_HPC')
%                 delete(canaryFile)
                error('canary')
            end
            if exist(resetFile,'file')
                restoredefaultpath
                addpath('ICL_HPC')
                delete(resetFile)
                error('canary reset')
            end
        end

        function self = handle_finished_jobs(self, assignments, finishedJobs)
            for fj = finishedJobs(:)'
                jId = fj.id;
                % find the assignment
                assignment = assignments([assignments.job] == jId);
                % check for a result
                if ~isempty(assignment.result)
                    self.handle_result(assignment.result);
                end

                % remove the job from the server
                self.client.delete_job(fj.id);
                % self.client.finish_job(fj.id);
                % remove the job from the queue
                oiJob = self.client.json2job(fj);
                oiJob.project = self.engine.database.fetch('PROJECT_NAME');
                self.engine.queue.remove_job(oiJob);
            end
        end



        function self = handle_error_jobs(self, errorJobs)
            error('not implemented');
        end

        function self = load_project_from_json(self, projectJson)
            oiProj = self.client.parse_project(projectJson);
            oiProj.DATA_DIRECTORY = self.data_directory;
            self.engine.load_project(oiProj);
        end

        function self = add_targets_to_queue(self, projJson)
            targetProductList = self.get_target_product(projJson);
            targetProductList = strsplit(targetProductList,{' ',',',';'});
            targetProductList = {'TestDataObjSummary'}
            for product = targetProductList(:)''
                productClass = OI.Data.(product{1});
                self.engine.load(productClass);
            end
        end


            % % check if the project is already loaded
            % if isKey(self.projectIndex, projectJson.id) 
            %     idx = self.projectIndex(projectJson.id);
            %     notLoaded = isempty(self.projectEngineCopies{idx});
            %     % if it is, switch to it
            %     self.engine = self.projectEngineCopies(...
            %         self.projectIndex(projectJson.id));
            % else
            %     % if it isn't, load it
            %     self = self.load_project_from_json(projectJson);
            %     % seed the initial queue
            %     self = self.add_targets_to_queue(projectJson);
            % end

        function self = switch_to_project(self, projectJson)
            loaded = false;
            idx = 0;

            % check if the project is already loaded ...
            if isKey(self.projectIndex, projectJson.name)
                idx = self.projectIndex(projectJson.name);
                loaded = ~isempty(self.projectEngineCopies{idx});
            end

            if ~loaded
                % ... if not, load it
                self = self.load_project_from_json(projectJson);
                self = self.add_targets_to_queue(projectJson);
                self.projectEngineCopies{idx} = self.engine;
            else
                % ... if it is, switch to it
                self.engine = self.projectEngineCopies{idx};
            end
        end

        function self = prioritise_projects(self, projects)
            % sort by priority property
            priorities = arrayfun(@(x) x.priority, self.projects);
            [~,idx] = sort(priorities,'descend');
            sortedProjects = self.projects(idx);
            INACTIVE_STATUSES = {'inactive','completed','failed'};
            inactive = arrayfun(@(x) ...
                any(strcmpi(x.status,INACTIVE_STATUSES) ...
                ), sortedProjects);
            sortedProjects = sortedProjects(~inactive);

            self.projects = sortedProjects;

            % create a map of project id to index in the projects array
            self.projectIndex = containers.Map('KeyType','char','ValueType','uint32');
            for i = 1:numel(sortedProjects)
                self.projectIndex(sortedProjects(i).name) = i;
                self.projectActive(i) = sortedProjects(i).priority;
                self.projectEngineCopies{i} = [];
            end
        end

        function targetProduct = get_target_product(self, projectJson)
            % query the projectTemplate
            templateId = projectJson.project_template;
            templateList = self.client.list_templates();
            template = templateList(templateList.id == templateId);
            targetProduct = template.product_list;
        end

        function worker_pool = update_worker_pool(self)
            worker_pool = []
            workers = self.client.list_workers();
            if isempty(workers)
                return
            end
            jobs = self.client.list_jobs();
            assignments = self.client.list_assignments();

            % loop through assignments, check for any that are finished
            for assignment = assignments(:)'
                if assignment.completed
                    % check for a result
                    if ~isempty(assignment.result)
                        self.handle_result(assignment.result);
                    end

                    % remove the job and the assignment
                    self.client.delete_job(assignment.job);
                    self.client.delete_assignment(assignment.id);
%                   self.client.delete_job(assignment.job);

                    % find the worker in the worker pool
                    worker = workers([workers.id] == assignment.worker);
                    % add the worker back to the worker pool
                    self.worker_pool = [self.worker_pool, worker];
                end
            end

            % filter out workers that have been assigned a job
            assignedJobs = arrayfun(@(x) ~isempty(x.worker), jobs);
            assignedWorkers = []
            if ~isempty(jobs)
                assignedWorkers = [jobs(assignedJobs).worker];
            end
            worker_pool = workers(~ismember([workers.id], assignedWorkers));
        end

        function handle_result(self, encodedResult)
            % decode from base64
            result = OI.Compatibility.base64decode(encodedResult);
            resultXmlParsed = OI.Data.XmlFile( result );
            resultAsStructFromXml = resultXmlParsed.to_struct();
            dataObj = OI.Functions.struct2obj( resultAsStructFromXml );
            if isa(dataObj,'OI.Data.DataObj')
                self.engine.database.add( dataObj );
            elseif isstruct(dataObj)
                self.engine.database.add( dataObj, dataObj.name );
            end
        end



    end % methods

    methods (Static = true)
        function [worker, workerPool] = pop_worker(workerPool)
            worker = workerPool(1);
            workerPool = workerPool(2:end);
        end
    end % methods


end % classdef

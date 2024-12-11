classdef Leader
    properties
        client = [];
        engine = [];
        data_directory = '';
        worker_pool = [];
    end % properties

    methods
        function self = Leader(host, username, password, data_directory)
            if nargin == 4
                self.client = OI.BaseClient(host);
                self.client = self.client.login(username, password);
                self.data_directory = data_directory;
            else
                api_host = getenv('OI_API_HOST');
                username = getenv('OI_USERNAME');
                password = getenv('OI_PASSWORD');
                self.data_directory = getenv('OI_DATA_DIRECTORY');
                if isempty(api_host) || isempty(username) || isempty(password) || isempty(self.data_directory)
                    error('Worker:Worker', ...
                        ['API host, username, password, data directory must be set', ...
                        ' by either arguments or environment variables']);
                end
                self.client = OI.BaseClient(api_host);
                self.client = self.client.login(username, password);
            end
            self.engine = OI.Engine();
        end % Worker

        function run(self)
            while true
                self.process_projects();
            end
        end % run


        function process_projects(self)
            projects = self.client.list_projects();

            projects = self.prioritise_projects(projects);
            for proj = projects(:)'

                projObj = self.client.parse_project(proj);
                projObj.DATA_DIRECTORY = self.data_directory;
                self.engine.load_project(projObj);
                targetProductList = self.get_target_product(proj);
                targetProductList = strsplit(targetProductList,{' ',',',';'});
                for product = targetProductList(:)''
                    productClass = OI.Data.(product{1});
                    self.engine.load(productClass);
                end
                while self.engine.queue.length > 0
                    nextJob = self.engine.queue.next_job();
                    if ~isempty(nextJob.target)
                        self.worker_pool = self.update_worker_pool();
                        if isempty(self.worker_pool)
                            disp('No workers')
                            pause(10)
                            continue
                        end
                        while ~isempty(self.worker_pool) && ~isempty(nextJob) && ~isempty(nextJob.target)
                            % pop a worker
                            worker = self.worker_pool(1);
                            self.worker_pool = self.worker_pool(2:end);
                            % assign job to worker
                            self.client.post_job(proj.id, nextJob, worker);
                            % check the next job
                            nextJob = self.engine.queue.next_job();
                        end
                    else
                        self.engine.run_next_job();
                    end
                end
            end
        end % process_projects

        function sortedProjects = prioritise_projects(self, projects)
            % sort by priority property
            priorities = arrayfun(@(x) x.priority, projects);
            [~,idx] = sort(priorities,'descend');
            sortedProjects = projects(idx);
            INACTIVE_STATUSES = {'inactive','completed','failed'};
            inactive = arrayfun(@(x) ...
                any(strcmpi(x.status,INACTIVE_STATUSES) ...
                ), sortedProjects);
            sortedProjects = sortedProjects(~inactive);
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
                    self.client.delete_job(assignmentObj.job);
                    self.client.delete_assignment(assignmentObj.id);

                    % find the worker in the worker pool
                    worker = workers([workers.id] == assignmentObj.worker);
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



end % classdef

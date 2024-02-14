% if ~exist('oi','var')
    J=0;

    [~,startDirectory,~]=fileparts(pwd);

    if strcmpi(startDirectory,'ICL_HPC')
        cd('..')
    end
    addpath('ICL_HPC')

    projectPath = OI.ProjectLink().projectPath;

    oi = OpenInSAR('-log','info','-project', projectPath);


    % load the project object
    projObj = oi.engine.load( OI.Data.ProjectDefinition() );
    oi.engine = DistributedEngine();
    oi.engine.connect( projObj );


    oi.engine.postings = oi.engine.postings.reset_workers();
    oi.engine.postings = oi.engine.postings.wipe_all_errors();

    oi.engine.postings.report_ready(0);
    nextWorker = 0;

    if strcmpi(projObj.PROCESSING_SCHEME,'PSI')
        thingToDoList = { OI.Data.TransientScatterers_Summary() };
    elseif strcmpi(projObj.PROCESSING_SCHEME,'GEOTIFFS')
        thingToDoList = { OI.Data.GeotiffSummary()};
    elseif strcmpi(projObj.PROCESSING_SCHEME,'EDF')
        thingToDoList = { OI.Data.GeotiffSummary(), OI.Data.PsiSummary() };
    else
        warning('Unknown processing scheme')
        thingToDoList = { OI.Data.CoregistrationSummary() };
    end

    %thingToDoList = { OI.Data.FieldSamplesSummary() }
%     thingToDoList = { OI.Data.TsCorrectionSummary() }
%thingToDoList = { OI.Data.ClassificationComponents() }
    
    % Flag to help refreshing worker status
    %   True - wait if no workers available
    %   False - try rehashing Matlab file cache before waiting
doImmediateWaitForWorkers = false;
assignment = cell(1, 100);
assignment(:)={'worker not yet initialised'};

for thingToDo = thingToDoList

    % oi.engine.load( thingToDo{1} )
    matcher = @(posting, x) numel(posting) >= numel(x) && any(strfind(posting(1:numel(x)), x));


    while true

        while nextWorker == 0
            
            try
                leaderPosting = oi.engine.postings.get_posting_contents(0);
                if matcher(leaderPosting,'STOP') || matcher(leaderPosting, 'stop')
                    leaderFilePath = oi.engine.postings.get_posting_filepath(0);
                    leaderFileHandle = fopen(leaderFilePath,'w');
                    fclose(leaderFileHandle);
                    return
                end
            catch LEADER_ERROR
                oi.ui.log('warning','error in leader posting\n%s\n',...
                    LEADER_ERROR.message);
            end
                
            oi.ui.log('info','Jobs remaining in queue:\n');
            oi.engine.queue.overview();
            
            oi.engine.postings = oi.engine.postings.find_workers();
            % assignment{ numel(oi.engine.postings.workers) } = '';

            % clean up old jobs and add the results to database
            for ii = 1:length(oi.engine.postings.workers)
%                 [nextWorker, nextWorkerWaiting] = oi.engine.postings.get_next_worker();
                % get the filepath
                JJ = oi.engine.postings.workers(ii);
                if JJ==0
                    continue
                end
                fp = oi.engine.postings.get_posting_filepath(JJ);
                % load the posting file
                fid = fopen(fp);
                frewind(fid);
                posting = fread(fid,inf,'*char')';
                fclose(fid);
                % what is it?
                if matcher( posting, 'READY')
                    oi.engine.ui.log('trace','Worker %i is ready\n', JJ);
                    assignment{JJ} = '';
                    nextWorker = JJ; %#ok<NASGU>
                end
                % running
                if matcher( posting, 'RUNNING')
                    % fprintf(1, 'Worker %i : %s\n', JJ,posting);
                    oi.engine.ui.log('debug','Worker %i : %s\n', JJ,posting);
                    jobstr = strsplit(posting, 'Job(');
                    if numel(jobstr)>1
                        jobstr = ['Job(' jobstr{2}];
                        assignment{JJ} = OI.Job(jobstr);
                    else
                        assignment{JJ} = '';
                    end
                end
                % finished
                if matcher( posting, 'FINISHED') || OI.Compatibility.contains(posting,'_FINISHED')
                    assignment{JJ}='';
                    oi.engine.ui.log('info','Worker %i : %s\n', JJ,posting);
                    ss = strsplit(posting, '_ANSWER=');
                    if numel(ss)>1
                        answer = ss{2};
                        try
                            resultXmlParsed = OI.Data.XmlFile( answer );
                            resultAsStructFromXml = resultXmlParsed.to_struct();
                            dataObj = OI.Functions.struct2obj( resultAsStructFromXml );
                            if isa(dataObj,'OI.Data.DataObj')
                                oi.engine.database.add( dataObj );
                            elseif isstruct(dataObj)
                                oi.engine.database.add( dataObj, dataObj.name );
                            end

                        catch ERR
                            oi.engine.ui.log( OI.Compatibility.CompatibleError(ERR) )
                            oi.engine.ui.log('error',['failed to add result:' answer(:)'])
                        end
                    end
                    postingNoAnswer = ss{1};
                    finishedJob = strsplit(postingNoAnswer,'JOB=');
                    if numel(finishedJob) > 1
                        finishedJob = finishedJob{2};
                        oi.engine.queue.remove_job( OI.Job(finishedJob) );
                    end
    
                    fp = oi.engine.postings.get_posting_filepath(JJ);
                    fid = fopen(fp,'w');
                    fwrite(fid,'');
                    fclose(fid);

                    % Remove the job
                end
                % error
                if matcher( posting, 'ERROR')
                    oi.engine.ui.log('error','Worker %i : %s\n', JJ, posting);
                    oi.engine.ui.log('error',posting);
                    warning(posting);
%                     assignment{JJ} = ''; % don't unassign the job ffs...
                    % return % Throw back so we can debug if in interactive mode
                end
            end

            [nextWorker, nextWorkerWaiting] = oi.engine.postings.get_next_worker(); 
            if nextWorker == 0 && nextWorkerWaiting == 0
                nextJob = oi.engine.queue.next_job();
                if ~isempty(nextJob) && ~isempty(nextJob.target) && nextJob.target
                    % jobs require assignment, but
                    % still no workers, lets wait a bit
                    oi.ui.log('info','%s\n',datestr(now())) %#ok<TNOW1,DATST>
                    
                    if isunix
                        system('qstat')
                    end
                    if ~doImmediateWaitForWorkers
                        oi.ui.log('info','All workers busy or none running. Rehashing.\n');
                        dirPostings = dir(oi.engine.postings.postingPath);
                        dirPostings = dirPostings( arrayfun(@(x) matcher(x.name,oi.engine.postings.prefix), dirPostings) );
                        if ~isempty(dirPostings)    
                            oi.ui.log('info','%s - %s',dirPostings(end).name,datestr(dirPostings(end).datenum))
                        end
                        rehash; % Refresh timestamps, maybe matlab blocking read
                        if ~isempty(dirPostings)    
                            oi.ui.log('info','%s - %s',dirPostings(end).name,datestr(dirPostings(end).datenum))
                        end
                        doImmediateWaitForWorkers = true;
                        continue
                    else
                        oi.ui.log('info','All workers busy or none running. Waiting.\n');
                        pause(5)
                        doImmediateWaitForWorkers = false;
                        continue
                    end
                else
                    break %?? Why would we wait and loop back here ??
                    % lets break and check for leader jobs?
                end
            end
        end

        oi.ui.log('info','Jobs remaining in queue:\n');
        oi.engine.queue.overview()

        % check the job isn't already running
        nextJob = oi.engine.queue.next_job();
        
        if isempty(nextJob)
            % try loading our target
            oi.engine.load( thingToDo{1} );
            nextJob = oi.engine.queue.next_job();
            if isempty(nextJob)
                oi.engine.ui.log('info',...
                    'No more jobs for leader at this step');
                break
            end
        end

        while isempty(nextJob.target)
            % ID LIKE TO NOT RUN A LEADER JOB, IF:
            % - there are workers that have finished and need clearing up
            % - there are unassigned jobs
            % TODO
            
            % we can carry on running jobs that don't have a target
            oi.engine.run_next_job();
            % try loading our target
            oi.engine.load( thingToDo{1} );
            nextJob = oi.engine.queue.next_job();
            if isempty(nextJob)
                % 'No more jobs for leader.'
                oi.engine.ui.log('info',...
                    ['No more jobs for leader at this step,'... 
                    'running distributed jobs']);
            end
            checkOnWorkers = true;
            break;
        end
        if isempty(nextJob) || checkOnWorkers
            checkOnWorkers = false;
            continue
        end

        tfClash = false;
        nJobsAssigned = 0;
        allJobsAssigned = false;
        firstJob = nextJob;
        
        % Check if our worker is running our proposed job
        % Check through workers and their current assignments
        for workerId = oi.engine.postings.workers(:)'
            if ~isempty(assignment{workerId}) && ~ischar(assignment{workerId}) % if worker is working
                % check the job we want to push isn't already assigned to
                % the worker
                if isa(assignment{workerId},'OI.Job') && assignment{workerId}.eq(nextJob) 
                    nJobsAssigned = nJobsAssigned + 1;
                    oi.engine.ui.log('debug',...
                        'Removed an already assigned job - %s', ...
                        nextJob.to_string());
                    oi.engine.queue.remove_job(1);
                    oi.engine.queue.add_job(nextJob); %add to back
                   
                    nextJob = oi.engine.queue.next_job();
                    if nextJob.eq(firstJob)
                        allJobsAssigned = true; % if we reach here we have clcyed 
                        break
                    end
                end
            end
        end
        
        % Check for conflict here
        if allJobsAssigned
            tfClash=true;
            oi.engine.ui.log('info','All jobs appear assigned: %i\n',sum(cellfun(@(x) ~isempty(x),assignment)))
            for jj=1:numel(assignment)
                x=assignment{jj};
                if isempty(x) || ischar(x);continue; end
                oi.ui.log('info','Worker %i - %s\n',jj,assignment{jj}.to_string());
%                 if jj>numel(oi.engine.postings.workers)
%                     break
%                 end
%                 wId = oi.engine.postings.workers(jj);
%                 oi.ui.log('info','Worker %i - %s\n',wId,assignment{jj}.to_string());
            end
            pause(5)
        else
            tfClash = false;
        end
        
        if ~tfClash
            nextJob = oi.engine.queue.next_job();
            if isempty(nextJob) || isempty(nextJob.target)
                nextWorker = 0;
                continue
            end
            oi.engine.run_next_job()
            if oi.engine.lastPostee
                assignment{ oi.engine.lastPostee } = OI.Job( oi.engine.currentJob );
            end
        else
            % Job already assigned?
            if numel(oi.engine.queue.jobArray) < numel(oi.engine.postings.workers)
                oi.engine.ui.log('debug',...
                    'Jobs assigned and more workers than jobs, waiting.')
                nextWorker = 0;
                pause(10)
                if allJobsAssigned
                    oi.engine.ui.log('debug',...
                        'all jobs assigned');
                    pause(10)
                end
                continue;
            else
                oi.engine.ui.log('Error','Some conflict has arrisen?!')
                warning('Somehow multiple jobs have been assigned? Please investigate')
                % ' wait for the clash to be resolved'
                pause(20); % wait for the clash to be resolved
            end
        end

        nextWorker = 0;
        if oi.engine.queue.is_empty()
            % 'WINNER!'
            oi.engine.ui.log('info',...
                'Step %s from %s is complete!', ...
                thingToDo{1}.id,thingToDo{1}.generator);
            break
        else 
            oi.engine.ui.log('info', ...
                'Queue length: %i\n', oi.engine.queue.length());
            
        end
    end
end

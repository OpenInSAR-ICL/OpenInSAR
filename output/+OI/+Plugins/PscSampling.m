classdef PscSampling < OI.Plugins.PluginBase


properties
    inputs = {OI.Data.BlockPsiSummary()}
    outputs = {OI.Data.PscSampleSummary()}
    id = 'PscSampling'
    STACK = ''
    BLOCK = []
end

methods

    function this = PscSampling(varargin)
        this.isArray = true;
    end % constructor

    function this = run(this, engine, varargin)
        
        % Check prior work is complete before continuing
        requiredStage = engine.load( OI.Data.BlockPsiSummary() );
        if isempty(requiredStage)
            return % pass back to engine
        end

        % If we have no parameters, generate jobs
        if isempty( this.STACK ) && isempty( this.BLOCK )
            this = this.queue_jobs(engine);
            return % pass back to engine
        end

        % if we have a stack and a block, we run the psc sampling
        if ~isempty( this.STACK ) && ~isempty( this.BLOCK )
            this.psc_sampling(engine);
        end

        % If our parameter is just the stack, we run a clean up/consolidate job
        if ~isempty( this.STACK ) && isempty( this.BLOCK )
            this = this.consolidate(engine);
        end
    end % run

    function this = queue_jobs(this, engine)
        blockMap = engine.load( OI.Data.BlockMap() );
        if isempty(blockMap)
            return % pass back to engine
        end

        allDone = true;
        jobCount = 0
        targetTemplate = OI.Data.PscSample();

        for stackInd = 1:numel(blockMap.stacks)
            this.STACK = stackInd;
            % check if we've consolidated this stack
            target = targetTemplate.configure( ...
                'STACK', num2str(stackInd), ...
                'BLOCK', 'ALL'
            ).identify( engine );
            if target.exists()
                continue % to next stack
            end

            % otherwise queue jobs for each block in the stack
            stackBlockMap = blockMap.stacks(stackInd);
            jobsInStack = 0;
            for blockInd = stackBlockMap.usefulBlockIndices(:)'
                target = target.configure( ...
                    'BLOCK', num2str(blockInd), ...
                ).identify( engine );

                if ~target.exists();
                    allDone = false;
                    jobCount = jobCount + 1;
                    jobsInStack = jobsInStack + 1;
                    % queue the job
                    this.BLOCK = blockInd;
                    engine.requeue_job_at_index( jobCount );
                end
            end % for blockInd = 1:numel(usefulBlocks)

            % if no blocks remain to be processed, queue a job to consolidate the stack
            if jobsInStack == 0
                jobCount = jobCount + 1;
                % queue a job to consolidate the stack
                this.STACK = stackInd;
                this.BLOCK = [];
                engine.requeue_job_at_index( jobCount );
            end
        end % for stackInd = 1:numel(blockMap.stacks)


    end % queue_jobs

    function this = consolidate(this, engine)
        
    end

end % methods


methods (Static = true) 

    function do_psc_sampling(engine, stackInd, blockMap)
        this.STACK = stackInd;
        usefulBlock = blockMap.stacks(stackInd).usefulBlocks(1);
        
        %% Parameters
        this = struct( ...
            'BLOCK', usefulBlock.indexInStack, ...
            'STACK', stackInd);
        stabilityThreshold = 3;
        % load in up to this many values, initially:
        maxTotalMemory = 4e9; 
        % after filtering low stability pix missing values, target this size for array:
        maxWorkingMemory = 0.5e9;
        
        
        %% Load inputs
        stacks = engine.load( OI.Data.Stacks() );
        blockMap = engine.load( OI.Data.BlockMap() );
        stackMap = blockMap.stacks( this.STACK );
        nDays = numel(stacks.stack(this.STACK).visits);
        nBlocks = numel(stackMap.usefulBlocks);
        normz = @(x) x./abs(x);
        avfilt = @(x,w,h) imfilter(x, fspecial('average', [w, h]));
        baselinesObjectTemplate = OI.Data.BlockBaseline().configure( ...
        'STACK', num2str(this.STACK), ...
        'BLOCK', num2str(this.BLOCK) ...
        ).identify( engine );
        baselinesObject = engine.load( baselinesObjectTemplate );
        if isempty(baselinesObject)
            return
        end
        
        timeSeries = baselinesObject.timeSeries(:)';
        kFactors = baselinesObject.k(:)';
        stack = stacks.stack(stackInd);
        
        %% Memory management
        % Lets say we want our aps model to be based on a 4GB
        % training set
        bytesPerComplexDouble = 16;
        memToPixels = @(mem) floor(mem / (bytesPerComplexDouble .*nBlocks .* nDays));
        nPixPerBlockLoad = memToPixels( maxTotalMemory );
        nPixPerBlockUse = memToPixels( maxWorkingMemory );
        psPerKm = nPixPerBlockLoad / (5*5);
        nSamples = nPixPerBlockLoad.*nBlocks;
        phi = zeros(nSamples, nDays); % The phase of each pixel, for each day
        phi(1) = 1i; 
        pscAz = zeros(nSamples,1); % The azimuth of each pixel
        pscRg = pscAz; % The range of each pixel
        pscAS = pscAz; % The stability of each pixel
        pscBlock = pscAz;  % The block index of each pixel
        pscLLE = zeros(nSamples,3);
        
        %% Load the data
        timePerBlock = zeros(1,numel(stack.visits));
        for iiBlock = 1:nBlocks
            bTic = tic;
            index = (1:nPixPerBlockLoad)' + (iiBlock-1) * nPixPerBlockLoad;
            % Create the block object template
            blockIndex = stackMap.usefulBlockIndices( iiBlock );
            blockIndexForGeocode=stackMap.usefulBlocks( iiBlock ).index;
            blockObj = OI.Data.Block().configure( ...
                'POLARISATION', 'VV', ...
                'STACK',num2str( this.STACK ), ...
                'BLOCK', num2str( blockIndex ) ...
                ).identify( engine );
        
            psPhaseObject = OI.Data.BlockResult( blockObj, 'InitialPsPhase' );
            psPhaseObject = engine.load( psPhaseObject );
        
            if isempty(psPhaseObject)
                warning('missing data for %i %i!',iiBlock, blockIndex);
                continue
            end
            
            blockGeocode = engine.load( ...
                OI.Data.BlockGeocodedCoordinates().configure( ...
                'STACK', this.STACK, ...
                'BLOCK', blockIndexForGeocode ...
                ) ...
                );
        
            tpAS = psPhaseObject.candidateStability;
            spAS = sort(tpAS);
            
            if nPixPerBlockLoad > numel(tpAS)
                mask = true(numel(tpAS),1);
            else
                mask = tpAS > spAS(end-nPixPerBlockLoad+1);
            end
        
            % Also remove any pixels that aren't stable enough
            mask = mask & tpAS > stabilityThreshold;
            
            nAvail = sum(mask);
            if nPixPerBlockLoad > nAvail
                index = index(1:nAvail);
            end
            
            sz = stackMap.usefulBlocks(iiBlock).size;
            cands = psPhaseObject.candidateMask;
            candidateInds = find(cands(:));
            pscLLE(index, 1)=blockGeocode.lat(candidateInds(mask));
            pscLLE(index, 2)=blockGeocode.lon(candidateInds(mask));
            pscLLE(index, 3)=blockGeocode.ele(candidateInds(mask));
            
            
            phi(index,:) = psPhaseObject.candidatePhase(mask,:);
            pscAz(index) = psPhaseObject.candidateAz(mask);
            pscRg(index) = psPhaseObject.candidateRg(mask);
            pscBlock(index) = blockIndex;
            pscAS(index) = tpAS(mask);
        
            timePerBlock(iiBlock) = toc(bTic);
            muTimePerBlock = mean(timePerBlock(1:iiBlock));
            remTime = muTimePerBlock * (nBlocks - iiBlock);
            fprintf(1,['Time for last block %i of %i: %.2f, ' ...
                'Avg time: %.2f,' ...
                'Total time: %.2f,' ...
                'Finished by (est) %s\n'], ...
                iiBlock, nBlocks, timePerBlock(iiBlock), ...
                muTimePerBlock, sum(timePerBlock), ...
                datestr(now() + remTime./86400) );
        
        end % for iiBlock = 1:nBlocks
        
        %% Clean up
        % 0 indicates missing data, remove these elements
        noDataMask = pscAS == 0;
        phi(noDataMask,:) = [];
        pscAz(noDataMask) = [];
        pscRg(noDataMask) = [];
        pscBlock(noDataMask) = [];
        pscAS(noDataMask) = [];
        pscLLE(noDataMask,:) = [];
        
        % See if we need to downsample the data
        workingBytes = numel(phi) * bytesPerComplexDouble;
        oversize = workingBytes > maxWorkingMemory;
        
        %% Downsample the data to a manageable size
        % how many pixels per block we want to keep: nPixPerBlockUse in params at top
        if oversize
            removeMask = false(size(phi,1),1);
            blockThresholdAS = zeros(nBlocks,1);
            % Downsample, keeping the most stable pixels in each block
            for iiBlock = 1:nBlocks
                blockIndex = stackMap.usefulBlockIndices( iiBlock );
                blockMask = pscBlock == blockIndex;
                % if there are fewer pixels in this block than we want to keep, skip
                if sum(blockMask) < nPixPerBlockUse
                    continue
                end
                % Get the stability values for this block
                blockAS = pscAS(blockMask);
                % Sort the stability values
                [sortedAS, sortIndex] = sort(blockAS);
                % Find the threshold stability value for this block
                blockThresholdAS(iiBlock) = sortedAS(end-nPixPerBlockUse+1);
                % Find the indices of the pixels that are below the threshold
                blockRemoveMask = blockAS < blockThresholdAS(iiBlock);
                % Convert the block indices to global indices
                removeMask(blockMask) = blockRemoveMask;
            end
            % Remove the pixels that are below the threshold
            phi(removeMask,:) = [];
            pscAz(removeMask) = [];
            pscRg(removeMask) = [];
            pscBlock(removeMask) = [];
            pscAS(removeMask) = [];
            pscLLE(removeMask,:) = [];
        end % if oversize
    end % do_psc_sampling

    function this = consolidate(this)
        % Consolidate all block samples in this stack


    end

end % static methods

end % classdef



classdef PscSampling < OI.Plugins.PluginBase
% PscSampling
% Pull out global samples of persistent scatterers from the stacks in this
% project.

properties
    inputs = {OI.Data.BlockPsiSummary()}
    outputs = {OI.Data.PscSampleSummary()}
    id = 'PscSampling'
    STACK = ''
    method = '';
    maxTotalMemory = 4e9;
end

methods

    function this = PscSampling(varargin)
        this.isArray = true;
        this.method = [this.id '_' num2str(floor(this.maxTotalMemory./1e9)) 'GBmax'];
    end % constructor

    function this = run(this, engine, varargin)
        
        % Check prior work is complete before continuing
        requiredStage = engine.load( OI.Data.BlockPsiSummary() );
        if isempty(requiredStage)
            return % pass back to engine
        end

        % If we have no parameters, generate jobs
        if isempty( this.STACK )
            this = this.queue_jobs(engine);
        else
            % otherwise, consolidate the results for this stack
            this = sample_psc_dataset_for_stack(this, engine);
        end

    end % run

    function this = queue_jobs(this, engine)
        blockMap = engine.load( OI.Data.BlockMap() );
        if isempty(blockMap)
            return % pass back to engine
        end

        allDone = true;
        jobCount = 0;

        for stackInd = 1:numel(blockMap.stacks)
            this.STACK = stackInd;
            % check if we've consolidated this stack already
            target = this.generate_target().identify( engine );
            if ~target.exists()
                allDone = false;
                engine.requeue_job_at_index( jobCount, 'STACK', stackInd );
            end
        end % for each stack

        if allDone
            engine.save(this.outputs{1});
            this.isFinished = true;
        end

    end % queue_jobs
    
    function target = generate_target(this)
        target = OI.Data.PscSample().configure( ...
            'STACK', num2str(this.STACK), ...
            'type', 'stack', ...
            'BLOCK', 'ALL', ...
            'POLARISATION', 'VV', ...
            'METHOD', this.method ...
        );
    end
    
    
    function this = sample_psc_dataset_for_stack(this, engine)

        
        %% Parameters
        stabilityThreshold = 3;

        % Create the output object
        pscSample = this.generate_target();

        %% Load inputs
        stackInd = this.STACK;
        stacks = engine.load( OI.Data.Stacks() );
        blockMap = engine.load( OI.Data.BlockMap() );
        stackMap = blockMap.stacks( this.STACK );
        nDays = numel(stacks.stack(this.STACK).visits);
        nBlocks = numel(stackMap.usefulBlocks);
        stack = stacks.stack(stackInd);
        
        %% Memory management
        % Lets say we want our aps model to be based on a 4GB
        % training set
        bytesPerComplexDouble = 16;
        memToPixels = @(mem) floor(mem / (bytesPerComplexDouble .*nBlocks .* nDays));
        nPixPerBlockLoad = memToPixels( this.maxTotalMemory );
        % nPixPerBlockUse = memToPixels( maxWorkingMemory );
        % psPerKm = nPixPerBlockLoad / (BlockSizeSquared)
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
                datestr(now() + remTime./86400) ); %#ok<DATST,TNOW1>
        
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

        pscSample.samplePhase = phi;
        pscSample.sampleAz = pscAz;
        pscSample.sampleRg = pscRg;
        pscSample.sampleStability = pscAS;
        pscSample.sampleBlock = pscBlock;
        pscSample.sampleLLE = pscLLE;

        engine.save( pscSample );
        this.isFinished = true;

    end % do_psc_sampling

end % methods


methods (Static = true) 


end % static methods

end % classdef



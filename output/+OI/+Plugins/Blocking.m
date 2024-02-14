classdef Blocking < OI.Plugins.PluginBase
    
properties
    inputs = {OI.Data.BlockMap()}
    outputs = {OI.Data.BlockingSummary()}
    id = 'Blocking'
    STACK = ''
    POLARISATION = ''
    BLOCK = []
end

methods
    function this = Blocking( varargin )
        this.isArray = true;
        this.isFinished = false;
    end    


    function this = run(this, engine, varargin)
        if numel(varargin)
            this = this.configure(engine, varargin{1});
        end
        
        if isempty(this.POLARISATION)
            % Check which polarisations are requested
            this = this.get_polarisations(engine);
        end

        if isempty(this.BLOCK)
            % We haven't been told which blocks to collect
            % So we will create jobs to generate them.
            this = this.queue_jobs(engine);
            return
        end
        % Load the block map
        blockMap = engine.load( OI.Data.BlockMap() );
        cat = engine.load( OI.Data.Catalogue() );
        stacks = engine.load( OI.Data.Stacks() );
        projObj = engine.load( OI.Data.ProjectDefinition() );
        if isempty(blockMap) || isempty(cat) || isempty(stacks)
            return
        end

        
        % Get our block
        blockInfo = blockMap.stacks(this.STACK).blocks(this.BLOCK(1));
        blockObj = OI.Data.Block().configure( ...
            'POLARISATION',this.POLARISATION, ...
            'STACK', num2str( this.STACK ), ...
            'BLOCK', num2str( this.BLOCK(1) ), ...
            'blockInfo', blockInfo ).identify( engine );

        % Get the segments that are in the block
        segIndexInReference = blockInfo.segmentIndex;
        stack = stacks.stack(this.STACK);
        segIndexInCatalogue = stack.correspondence(segIndexInReference,:);
        
        % Create a holder for the data
        blockData = zeros( blockInfo.size(1), blockInfo.size(2), numel(segIndexInCatalogue));

        for visitIndex = 1:numel(segIndexInCatalogue)
            coregDataObj = OI.Data.CoregisteredSegment().configure( ...
                'POLARIZATION', this.POLARISATION, ...
                'STACK',num2str(this.STACK), ...
                'REFERENCE_SEGMENT_INDEX',num2str(segIndexInReference), ...
                'VISIT_INDEX',num2str(visitIndex) );
            coregDataObj = coregDataObj.identify( engine );
            coregData = engine.load( coregDataObj );
            
            if ~segIndexInCatalogue(visitIndex)
                % No data available...
                continue
            end
            
            if isempty(coregData)
                engine.ui.log('warning', ...
                    'No coreged data available! T%i S%i V%i P%s\n', ...
                    this.STACK, blockInfo.segmentIndex, visitIndex, this.POLARISATION);
                return;
                % break; % throw back to the engine, not resampled/coregistered
            end

            % Crop the data to the block
            blockData(:,:,visitIndex) = coregData( ...
                blockInfo.rgDataStart:blockInfo.rgDataEnd, ...
                blockInfo.azDataStart:blockInfo.azDataEnd).';
        end % visits

        % Save the block
        engine.save( blockObj, blockData );
        this.isFinished = true;
        
        if ~isfield(blockInfo,'indexInStack')
            overallIndex = blockInfo.index;
            blockInfo.indexInStack = ...
                find(arrayfun(@(x) x.index == overallIndex, ...
                    blockMap.stacks( this.STACK ).blocks));
        end
        
        safeInd = cat.catalogueIndexByTrack(1,this.STACK);
        direction = cat.safes{safeInd}.direction; % ascending or desc
        
        % Save a preview of the block
        OI.Plugins.Blocking.preview_block(projObj, blockInfo, blockData, this.POLARISATION, direction);

    end % run

    function this = get_polarisations(this, engine)
        projObj = engine.load( OI.Data.ProjectDefinition() );
        % what polarisations do we need?
        requestedPol = {'VV', 'VH', 'HV', 'HH'};
        if ~isempty(projObj.POLARIZATION)
            keepPol = zeros(size(requestedPol));
            ii=0;
            for POLARIZATION = requestedPol
                ii = ii+1;
                if any(strfind(projObj.POLARIZATION,POLARIZATION{1}))
                    keepPol(ii) = 1;
                end
            end
            requestedPol = requestedPol(keepPol==1);
        end
        this.POLARISATION = requestedPol;
    end

    function this = queue_jobs(this, engine)
        % Determine which blocks are in the AOI
        blockMap = engine.load( OI.Data.BlockMap() );
        stacks = engine.load( OI.Data.Stacks() );
        cat = engine.load( OI.Data.Catalogue() );
        if isempty(blockMap) || isempty(cat) || isempty(stacks)
            return
        end

        % Do each stack
        allComplete = true;
        jobCount=0;
        for stackInd = 1:numel( blockMap.stacks )
            stack = stacks.stack(stackInd);
            stackBlockMap = blockMap.stacks(stackInd);
            % Loop through the list of useful blocks
            for blockInd = blockMap.stacks(stackInd).usefulBlockIndices(:)'
                segmentIndex = stackBlockMap.blocks(blockInd).segmentIndex;
                % find the safe
                safeIndex = stack.reference.segments.safe(segmentIndex);
                safe = cat.safes{safeIndex};

                for POL = this.POLARISATION
                    if ~this.is_pol_in_safe( safe, POL{1} )
                        continue
                    end

                    % Create the block object template
                    blockObj = OI.Data.Block().configure( ...
                        'POLARISATION',POL{1}, ...
                        'STACK',num2str(stackInd), ...
                        'BLOCK', num2str( blockInd ) ...
                        ).identify( engine );
                    blockInDatabase = engine.database.find( blockObj );
                    
                    % If file not found, create a job to generate it
                    if isempty(blockInDatabase)
                        jobCount = jobCount+1;
                        % Create a job to generate the block
                        engine.requeue_job_at_index( ...
                            jobCount, ...
                            'BLOCK', blockInd, ...
                            'STACK', stackInd, ...
                            'POLARISATION', POL{1} );
                        allComplete = false;
                    end

                end % polarisation
            end % block loop
        end % stack loop

        % Save and exit if all jobs are complete
        if allComplete
            this.isFinished = true;
            engine.save( this.outputs{1} );
        end
    end % queue_jobs

end % methods

methods (Static = true)
    function tf = is_pol_in_safe( safe, pol ) % this should be in SAFE obj
        polInSafe = reshape(safe.polarization,[],2);
        tf = any( all(polInSafe == pol,2) );
    end

    function previewKmlPath = preview_block(projObj, blockInfo, blockData, POL, direction)
        % get the block extent
        sz = blockInfo.size;
        sz(3) = size(blockData,3);

        % save a preview of the block
        baddies = squeeze(sum(sum(blockData))) == 0;

        amp = sum(log(abs(blockData(:,:,~baddies))),3,'omitnan');
        amp = amp./(sz(3) - sum(baddies)); % roundabout way of doing mean
        amp(isnan(amp)) = 0;
        
        if strcmpi(direction,'ASCENDING')
            amp = flipud(fliplr(amp)); %# ok
        end
      
        blockExtent = OI.Data.GeographicArea().configure( ...
            'lat', blockInfo.latCorners, ...
            'lon', blockInfo.lonCorners );
        blockExtent = blockExtent.make_counter_clockwise();

        % preview directory
        previewDir = fullfile(projObj.WORK,'preview','block');
        blockName = sprintf('Stack_%i_%s_block_%i',blockInfo.stackIndex,POL,blockInfo.indexInStack);

        previewKmlPath = fullfile( previewDir, ...
            'amplitude', ...
            [blockName '.kml']);
        previewKmlPath = OI.Functions.abspath( previewKmlPath );
        OI.Functions.mkdirs( previewKmlPath );
        % save the preview
        if all(POL == 'VH')
            cLims = [2.5 5];
        else % copol
            cLims = [3 5.5];
        end
        blockExtent.save_kml_with_image( ...
            previewKmlPath, fliplr(amp), cLims);
    end
end

end % classdef

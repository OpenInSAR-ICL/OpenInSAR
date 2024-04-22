classdef Blocking < OI.Plugins.PluginBase

    properties
        inputs = {OI.Data.BlockMap()}
        outputs = {OI.Data.BlockingSummary()}
        id = 'Blocking'
        STACK = ''
        SEGMENT = ''
        POLARISATION = ''
        BLOCK = []
    end

    methods
        function this = Blocking(varargin)
            this.isArray = true;
            this.isFinished = false;
        end

        function this = run(this, engine, varargin)
            % Parse arguments
            if numel(varargin)
                this = this.configure(engine, varargin{1});
            end

            % load the inputs
            blockMap = engine.load(OI.Data.BlockMap());
            cat = engine.load(OI.Data.Catalogue());
            stacks = engine.load(OI.Data.Stacks());
            projObj = engine.load(OI.Data.ProjectDefinition());
            if isempty(blockMap) || isempty(cat) || isempty(stacks)
                return
            end

            % If we have no arguments, queue jobs to generate them
            if isempty(this.BLOCK) && isempty(this.SEGMENT)
                this = this.queue_jobs(engine, cat, stacks, blockMap, projObj);
                return
            end

            % If we have no block argument, we are spliting the segment
            if isempty(this.BLOCK) && ~isempty(this.SEGMENT)
                preprocessingInfo = engine.load( OI.Data.PreprocessedFiles() );
                this = this.split_segment(engine, cat, stacks, preprocessingInfo, blockMap, projObj);
                return
            end

            %  Otherwise, we are loading a block from binary and saving it
            this = this.finalise_block(engine, cat, stacks, blockMap, projObj);

        end

        function this = finalise_block(this, engine, cat, ~, blockMap, projObj)

            assert(~isempty(this.BLOCK), 'No block specified');
            assert(~isempty(this.SEGMENT), 'No segment specified');
            assert(~isempty(this.POLARISATION), 'No polarisation specified');
            assert(~isempty(this.STACK), 'No stack specified');

            % load the binary data, and save it as a .mat / OpenInSAR file
            binary_file = sprintf('T%i_S%i_B%i_P%s', this.STACK, this.SEGMENT, this.BLOCK, this.POLARISATION);
            fid = fopen(fullfile(OI.Plugins.Blocking.get_binary_dir(projObj), binary_file), 'r+');
            
            if fid == -1
                engine.ui.log('warning', 'Binary file not found: %s\n', binary_file);
                return
            end
            blockDataRI = fread(fid, [2,inf], 'double');
            fclose(fid);
            blockData = blockDataRI(1,:)+1i.*blockDataRI(2,:);
            blockDataRI = []; %#ok<NASGU>
            
            % Make the block object
            blockInfo = blockMap.stacks(this.STACK).blocks(this.BLOCK);
            blockObj = OI.Data.Block().configure( ...
                'POLARISATION', this.POLARISATION, ...
                'STACK', num2str(this.STACK), ...
                'BLOCK', num2str(this.BLOCK), ...
                'blockInfo', blockInfo).identify(engine);

            % reshape the blockData to 3D
            blockData = reshape(blockData, blockInfo.size(2), blockInfo.size(1), []);
            blockData = permute(blockData, [2 1 3]);

            % Save the block
            engine.save(blockObj, blockData);
            this.isFinished = true;

            if ~isfield(blockInfo, 'indexInStack')
                overallIndex = blockInfo.index;
                blockInfo.indexInStack = ...
                    find(arrayfun(@(x) x.index == overallIndex, ...
                    blockMap.stacks(this.STACK).blocks));
            end

            safeInd = cat.catalogueIndexByTrack(1, this.STACK);
            direction = cat.safes{safeInd}.direction; % ascending or desc

            % Save a preview of the block
            OI.Plugins.Blocking.preview_block(projObj, blockInfo, blockData, this.POLARISATION, direction);
            
        end

        function this = split_segment(this, engine, cat, stacks, preprocInfo, blockMap, projObj)
            seg = this.SEGMENT;
            stackInd = this.STACK;
            pol = this.POLARISATION;
            stack = stacks.stack(stackInd);
            fprintf(1,'%s - Stack %i segment %i\n',datestr(now), stackInd, seg);
            % Check the binary dir for data
            binDir = OI.Plugins.Blocking.get_binary_dir(projObj);

            binDirStruct = dir(binDir);
            binDirContents = {binDirStruct.name};

            % check we haven;t already done this segment
            seg_done_binary_file = sprintf('T%i_S%i_P%s', stackInd, seg, pol);
            if any(strcmp(seg_done_binary_file, binDirContents))
                engine.ui.log('warning', 'Segment already split: %s\n', seg_done_binary_file);
                return
            end

            timePerVisit = zeros(1,numel(stack.visits));
            doneBlocks = false(1,max(blockMap.stacks(stackInd).usefulBlockIndices(:)));
            
            for ubi = blockMap.stacks(stackInd).usefulBlockIndices(:)'
                blockInfo = blockMap.stacks(stackInd).blocks(ubi);
                blockObj = OI.Data.Block().configure( ...
                        'POLARISATION', this.POLARISATION, ...
                        'STACK', num2str(this.STACK), ...
                        'BLOCK', num2str(blockInfo.indexInStack), ...
                        'blockInfo', blockInfo).identify(engine);
                    
                % Check if the block is already in the database
                blockInDatabase = engine.database.find(blockObj);
                if ~isempty(blockInDatabase)
                    % engine.ui.log('warning', 'Block already exists: %s\n', blockObj.id);
                    doneBlocks(ubi)=true;
                end
            end
            
            for visitInd = 1:numel(stack.visits)
                % check against no data available for this visit
                if stacks.stack(stackInd).correspondence(seg, visitInd) == 0
                    continue 
                end
                vTic = tic;
                
                % lazy load the visit
                coregData = [];

                % Loop through the useful blocks
                for ubi = blockMap.stacks(stackInd).usefulBlockIndices(:)'
                    blockInfo = blockMap.stacks(stackInd).blocks(ubi);
                    % skip blocks not in this segment...
                    if blockInfo.segmentIndex ~= seg || doneBlocks(ubi)
                        continue
                    end

                    if isempty(coregData)
                        coregData = engine.load( ...
                            OI.Data.CoregisteredSegment().configure( ...
                            'POLARIZATION', pol, ...
                            'STACK', num2str(stackInd), ...
                            'REFERENCE_SEGMENT_INDEX', num2str(seg), ...
                            'VISIT_INDEX', num2str(visitInd) ...
                        ).identify(engine) ...
                        );
                        if isempty(coregData)
                            % check if we expect data here...
                            segmentIndexInStack = ...
                                stacks.stack(stackInd).correspondence(seg, visitInd);
                            safeIndex = stacks.stack(stackInd).segments.safe(segmentIndexInStack);
                            
                            safeAvailable = safeIndex ~= 0;
                            
                            if safeAvailable
                                safePolStr = cat.safes{safeIndex}.polarization;
                                nPolChars = numel(safePolStr);
                                badMetadata = ...
                                    nPolChars == 0 || mod(nPolChars, 2) == 1;
                                if badMetadata
                                   error('Invalid polarisation info for safe: %i', ...
                                       safeIndex);
                                end
                                polsInSafe = cellstr(reshape(safePolStr, [], 2));
                                polAvailable = any(strcmpi(polsInSafe, pol));
                            end
                            
                            if safeAvailable && polAvailable
                                miss = sprintf( ...
                                    'coreg _ s %i seg %i visit %i %s', ...
                                    stackInd, seg, visitInd, pol);
                                error('Missing coregistered data: %s', miss);
                            end
                            
                            % If we are missing data for a legit reason,
                            % fill blanks.
                            info = ...
                                stacks.get_reference_info(preprocInfo, stackInd, seg);
                            coregData = ...
                                zeros(info.samplesPerBurst, info.linesPerBurst, ...
                                'like',1i);
                        end % lazy load
                    end % no data 

                    % Extract the data
                    extract = coregData( ...
                        blockInfo.rgDataStart:blockInfo.rgDataEnd, ...
                        blockInfo.azDataStart:blockInfo.azDataEnd);
                   realExtract = [real(extract(:)'); imag(extract(:)')];
            
                   % TODO this would be a lot easier if it was
                   % block-in-stack instead...
                    binary_file = sprintf('T%i_S%i_B%i_P%s', stackInd, seg, ubi, pol);
                    binary_filepath = fullfile(OI.Plugins.Blocking.get_binary_dir(projObj), binary_file);

                    % Open the file, seek to the offset, write the data, close the file
                    if visitInd == 1
                        % unclear if 'W' auto clears prior file. Let's make
                        % sure.
                        fid = fopen(binary_filepath, 'w'); % note lowercase
                        fclose(fid);
                        % Use buffered writing.
                        fid = fopen(binary_filepath, 'W');
                    else
                        fid = fopen(binary_filepath, 'A');
                    end
                    fwrite(fid, realExtract, 'double');
                    fclose(fid);

                end % block loop
    
                timePerVisit(visitInd) = toc(vTic);
                muTimePerVisit = mean(timePerVisit(1:visitInd));
                remTime = muTimePerVisit * (numel(stack.visits) - visitInd);
                fprintf(1,['Time for last visit %i of %i: %.2f, ' ...
                    'Avg time: %.2f,' ...
                    'Total time: %.2f,' ...
                    'Finished by (est) %s\n'], ...
                    visitInd, numel(stack.visits), timePerVisit(visitInd), ...
                    muTimePerVisit, sum(timePerVisit), ...
                    datestr(now() + remTime./86400));
                    
            end % visit loop

            % Write a file in the binary dir to indicate that the segment is done
            fid = fopen(fullfile(OI.Plugins.Blocking.get_binary_dir(projObj), seg_done_binary_file), 'w+');
            fclose(fid);
            this.isFinished = true; % remove this job
        end % split_segment

        function this = queue_jobs(this, engine, cat, stacks, blockMap, projObj)
            allDone = true;

            % Loop through the stacks
            jobCount = 0;
            for stackInd = 1:numel(blockMap.stacks)
                stack = stacks.stack(stackInd);
                stackBlockMap = blockMap.stacks(stackInd);

                % Loop through the useful blocks
                ubi = stackBlockMap.usefulBlockIndices(:)';
                segments = unique([stackBlockMap.blocks(ubi).segmentIndex]);
                segments(segments == 0) = [];

                binDirStruct = dir(OI.Plugins.Blocking.get_binary_dir(projObj));
                if ~isempty(binDirStruct)
                    binDirContents = {binDirStruct.name};
                else
                    binDirContents = {};
                end
                file_in_dir = @(x) any(strcmp(x, binDirContents));
                % Use arrayfun to check in the first N characters match the file in the dir
                % file_in_dir_n = @(x, n) arrayfun(@(y) strcmp(x(1:n), y(1:n)), binDirContents);
                % find_binary_file = @(x) file_in_dir_n(x, numel(binary_file)) && strcmp(x(1:numel(binary_file)), binary_file);

                % QUEUE A JOB FOR EACH SEGMENT
                nJobs = 0;
                nSegPolCombos = 0;
                segPolCombos = [];
                polCode.('VV') = 1;
                polCode.('VH') = 2;
                polCode.('HV') = 3;
                polCode.('HH') = 4;

                for seg = segments
                    % Get the safe
                    safeIndex = stack.reference.segments.safe(seg);
                    safe = cat.safes{safeIndex};
                    % Get the polarisations
                    % pols is a 4 char array e.g. 'VVVH', or a 2 char array e.g. 'VV'
                    % We want a cell for each 2 character combination e.g. {'VV', 'VH'} or {'VV'}
                    polCell = cellstr(reshape(safe.polarization, 2, [])');
                    for POL = polCell'
                        nSegPolCombos = nSegPolCombos + 1;
                        segPolCombos(nSegPolCombos, :) = [stackInd, seg, polCode.(POL{1}), false]; %#ok<AGROW>
                        % Check for the binary flag for this stack_seg_pol combination
                        binary_file = sprintf('T%i_S%i_P%s', stackInd, seg, POL{1});
                        if file_in_dir(binary_file)
                            segPolCombos(end, end) = true;
                        else
                            % Create a job to generate the blocks
                            engine.requeue_job_at_index( ...
                                1, ...
                                'SEGMENT', seg, ...
                                'STACK', stackInd, ...
                                'POLARISATION', POL{1});
                            allDone = false;
                            nJobs = nJobs + 1;
                            jobCount = jobCount + 1;
                        end
                    end
                end % segment loop
                % If none of the segments have been done, continue to the next stack
                if ~allDone && (nJobs == nSegPolCombos)
                    continue % to next stack
                end

                % QUEUE A JOB FOR EACH BLOCK
                for blockInd = ubi
                    % get segment index 
                    
                    blockInfo = stackBlockMap.blocks(blockInd);
                    seg = blockInfo.segmentIndex;
                    % get polarisations
                    safeIndex = stack.reference.segments.safe(seg);
                    safe = cat.safes{safeIndex};
                    polCell = cellstr(reshape(safe.polarization, 2, [])');
                    for POL = polCell'
                        
                        % This checks that the segment is done:
                        segDone = any(all( ...
                            segPolCombos == ...
                            [stackInd, seg, polCode.(POL{1}), true], 2));
                        if ~segDone
                            continue
                        end
                        
                        % Check binary file exists
                        binary_file = sprintf('T%i_S%i_B%i_P%s', stackInd, seg, blockInfo.indexInStack, POL{1});
                        binFileExists = file_in_dir(binary_file);
                        % Check if output object exists
                        blockObj = OI.Data.Block().configure( ...
                            'POLARISATION', POL{1}, ...
                            'STACK', num2str(stackInd), ...
                            'BLOCK', num2str(blockInfo.indexInStack) ...
                        ).identify(engine);
                        blockInDatabase = engine.database.find(blockObj);
                        % If the binary file exists and the output object doesn't, create a job
                        if binFileExists && isempty(blockInDatabase)
                            allDone = false;
                            nJobs = nJobs + 1;
                            jobCount = jobCount + 1;
                            engine.requeue_job_at_index( ...
                                jobCount, ...
                                'BLOCK', blockInfo.indexInStack, ...
                                'STACK', stackInd, ...
                                'SEGMENT', seg, ...
                                'POLARISATION', POL{1});
                        end
                    end % polarisation loop
                end % block loop
            end % stack loop
            
            if allDone
                this.isFinished = true;
                engine.save( this.outputs{1} );
            else
                this.isFinished = false;
            end
        end % queue_jobs

    end % methods

    methods (Static = true)
        function tf = is_pol_in_safe(safe, pol) % this should be in SAFE obj
            polInSafe = reshape(safe.polarization, [], 2);
            tf = any(all(polInSafe == pol, 2));
        end

        function binary_dir = get_binary_dir(projObj)
            binary_dir = fullfile(projObj.WORK, 'binary');
            if ~exist(binary_dir, 'dir')
                mkdir(binary_dir);
            end
        end

        function binSize = calc_binary_size(stack, blockInfo)
            % Calculate the expected size of the binary file
            bytesPerDouble = 8;
            doublesPerComplex = 2;
            samplesPerBlock = blockInfo.size(1) * blockInfo.size(2);
            numberOfVisits = numel(stack.visits);
            binSize = bytesPerDouble * doublesPerComplex * samplesPerBlock * numberOfVisits;
        end

        function offset = calc_binary_offset(~, blockInfo, visitIndex)
            % Calculate the expected offset of the visit in the binary file
            bytesPerDouble = 8;
            doublesPerComplex = 2;
            samplesPerBlock = blockInfo.size(1) * blockInfo.size(2);
            offset = bytesPerDouble * doublesPerComplex * samplesPerBlock * (visitIndex - 1);
        end

        function previewKmlPath = preview_block(projObj, blockInfo, blockData, POL, ~)
            % get the block extent
            sz = blockInfo.size;
            sz(3) = size(blockData,3);

            % save a preview of the block
            baddies = squeeze(sum(sum(blockData))) == 0;

            amp = sum(log(abs(blockData(:,:,~baddies))),3,'omitnan');
            amp = amp./(sz(3) - sum(baddies)); % roundabout way of doing mean
            amp(isnan(amp)) = 0;
        
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

    end % methods (Static = true)

end % classdef

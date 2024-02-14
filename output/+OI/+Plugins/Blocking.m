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
                this = this.split_segment(engine, cat, stacks, blockMap, projObj);
                return
            end

            %  Otherwise, we are loading a block from binary and saving it
            this = this.finalise_block(engine, cat, stacks, blockMap, projObj);

        end

        function this = finalise_block(this, engine, cat, stacks, blockMap, projObj)

            assert(~isempty(this.BLOCK), 'No block specified');
            assert(~isempty(this.SEGMENT), 'No segment specified');
            assert(~isempty(this.POLARISATION), 'No polarisation specified');
            assert(~isempty(this.STACK), 'No stack specified');

            % load the binary data, and save it as a .mat / OpenInSAR file
            binary_file = sprintf('T%i_S%i_B%i_P%s', this.STACK, this.SEGMENT, this.BLOCK, this.POLARISATION);

            fid = fopen(fullfile(OI.Plugins.NewBlocking.get_binary_dir(projObj), binary_file), 'r+');
            if fid == -1
                engine.ui.log('warning', 'Binary file not found: %s\n', binary_file);
                return
            end
            blockDataRI = fread(fid, [2,inf], 'double');
            fclose(fid);
            blockData = blockDataRI(1,:)+1i.*blockDataRI(2,:);
            blockDataRI = [];
            
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

        function this = split_segment(this, engine, cat, stacks, blockMap, projObj)
            seg = this.SEGMENT;
            stackInd = this.STACK;
            pol = this.POLARISATION;
            stack = stacks.stack(stackInd);
            fprintf(1,'%s - Stack %i segment %i\n',datestr(now), stackInd, seg);
            % Check the binary dir for data
            binDir = OI.Plugins.NewBlocking.get_binary_dir(projObj);
            binDirStruct = dir(binDir);
            binDirContents = {binDirStruct.name};
            binDirFileSizes = [];
            if ~isempty(binDirContents)
                binDirFileSizes = [binDirStruct.bytes];
            end

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
                    
                    blockObj = OI.Data.Block().configure( ...
                        'POLARISATION', this.POLARISATION, ...
                        'STACK', num2str(this.STACK), ...
                        'BLOCK', num2str(blockInfo.indexInStack), ...
                        'blockInfo', blockInfo).identify(engine);

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
                            error('Should be data here for %s',sprintf('coreg _ s %i seg %i visit %i %s', stackInd, seg, visitInd, pol));
                            return
                        end
                    end

                    % Extract the data
                    extract = coregData( ...
                        blockInfo.rgDataStart:blockInfo.rgDataEnd, ...
                        blockInfo.azDataStart:blockInfo.azDataEnd);
%                     realExtract = zeros(2,prod(blockInfo.size(1:2)));
%                     realExtract(1,:) = real(extract);
%                     realExtract(2,:) = imag(extract);
                   realExtract = [real(extract(:)'); imag(extract(:)')];
            
                   % TODO this would be a lot easier if it was
                   % block-in-stack instead...
                    binary_file = sprintf('T%i_S%i_B%i_P%s', stackInd, seg, ubi, pol);
                    binary_filepath = fullfile(OI.Plugins.NewBlocking.get_binary_dir(projObj), binary_file);
%                     offset = OI.Plugins.NewBlocking.calc_binary_offset(stacks.stack(stackInd), blockInfo, visitInd);
                    % Open the file, seek to the offset, write the data, close the file
                    if visitInd == 1
                        fid = fopen(binary_filepath, 'W');
                    else
                        fid = fopen(binary_filepath, 'A');
                    end
%                     fseek(fid, offset, 'bof');
                    fwrite(fid, realExtract, 'double');
                    fclose(fid);
%                     imagesc(log(abs(extract)))
                    
%                     fid = fopen(binary_filepath, 'r');
%                     ddd = fread(fid,[2,Inf],'double');
%                     fclose(fid)
                    2;

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
                    
                1;
            end % visit loop

            % Write a file in the binary dir to indicate that the segment is done
            fid = fopen(fullfile(OI.Plugins.NewBlocking.get_binary_dir(projObj), seg_done_binary_file), 'w+');
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

                binDirStruct = dir(OI.Plugins.NewBlocking.get_binary_dir(projObj));
                if ~isempty(binDirStruct)
                    binDirContents = {binDirStruct.name};
                    binDirFileSizes = [binDirStruct.bytes];
                else
                    binDirContents = {};
                    binDirFileSizes = [];
                end
                file_in_dir = @(x) any(strcmp(x, binDirContents));
                % Use arrayfun to check in the first N characters match the file in the dir
                file_in_dir_n = @(x, n) arrayfun(@(y) strcmp(x(1:n), y(1:n)), binDirContents);
                find_binary_file = @(x) file_in_dir_n(x, numel(binary_file)) && strcmp(x(1:numel(binary_file)), binary_file);

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
                        segPolCombos(nSegPolCombos, :) = [stackInd, seg, polCode.(POL{1}), false];
                        % Check for the binary flag for this stack_seg_pol combination
                        binary_file = sprintf('T%i_S%i_P%s', stackInd, seg, POL{1});
                        if file_in_dir(binary_file)
                            segPolCombos(end, end) = true;
                        else
                            % Create a job to generate the block
                            engine.requeue_job_at_index( ...
                                jobCount, ...
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
                if ~allDone && nJobs == nSegPolCombos
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
                            engine.requeue_job_at_index( ...
                                jobCount, ...
                                'BLOCK', blockInfo.indexInStack, ...
                                'STACK', stackInd, ...
                                'SEGMENT', seg, ...
                                'POLARISATION', POL{1});
                            allDone = false;
                            nJobs = nJobs + 1;
                            jobCount = jobCount + 1;
                        end
                    end % polarisation loop
                end % block loop
            end % stack loop
            
            if allDone
                this.isFinished = true;
                engine.save( this.outputs{1} );
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

        function offset = calc_binary_offset(stack, blockInfo, visitIndex)
            % Calculate the expected offset of the visit in the binary file
            bytesPerDouble = 8;
            doublesPerComplex = 2;
            samplesPerBlock = blockInfo.size(1) * blockInfo.size(2);
            offset = bytesPerDouble * doublesPerComplex * samplesPerBlock * (visitIndex - 1);
        end
    end % methods (Static = true)

end % classdef

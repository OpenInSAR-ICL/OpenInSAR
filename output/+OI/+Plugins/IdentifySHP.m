classdef IdentifySHP < OI.Plugins.PluginBase

    properties
        inputs = {OI.Data.BlockBaselineSummary()}
        outputs = {OI.Data.SHPMasksSummary()}
        id = 'IdentifySHP'
        STACK = []
        BLOCK = []
    end

    methods

        function this = IdentifySHP(varargin)
            this.isArray = true;
            this.isFinished = false;
        end

        function this = run(this, engine, varargin)

            blockMap = engine.load(OI.Data.BlockMap());

            if isempty(this.STACK) || isempty(this.BLOCK)
                this = this.queue_jobs(engine, blockMap);
                return
            end

            % Get the window settings
            windowSize = [5, 21];
            nWindow = prod(windowSize);
            middlePixel = ceil(prod(windowSize) / 2);

            % Load the target block
            targetBlock = blockMap.stacks(this.STACK).blocks(this.BLOCK);
            blockDataTemplate = OI.Data.Block().configure( ...
                'POLARISATION', 'VV', ...
                'STACK', num2str(this.STACK), ...
                'BLOCK', num2str(this.BLOCK) ...
            ).identify(engine);
            blockData = engine.load(blockDataTemplate);
            if isempty(blockData)
                return
            end

            % Now we need to load data around the block
            % In order that we can analyse samples at the edges.
            blockSize = size(blockData);
            bufferEdgeSize = floor(windowSize / 2);
            bufferBlockSize = blockSize(1:2) + (bufferEdgeSize * 2);

            % Get the axis limits for the block, and its buffered equivalent
            targetBlockAzLimits = [targetBlock.azOutputStart targetBlock.azOutputEnd];
            targetBlockRgLimits = [targetBlock.rgOutputStart targetBlock.rgOutputEnd];
            bufferBlockAzLimits = targetBlockAzLimits + [-1 1] * bufferEdgeSize(1);
            bufferBlockRgLimits = targetBlockRgLimits + [-1 1] * bufferEdgeSize(2);
            bufferedBlockAz = bufferBlockAzLimits(1):bufferBlockAzLimits(2);
            bufferedBlockRg = bufferBlockRgLimits(1):bufferBlockRgLimits(2);

            % Initialise array for the buffered block data
            bufferBlockData = zeros(bufferBlockSize(1), bufferBlockSize(2), blockSize(3));

            % Find the blocks which intersect the buffered block
            blocksInStack = blockMap.stacks(this.STACK).usefulBlocks;
            tfBlockInStack = false(size(blocksInStack));
            bufferBlockInfo = struct( ...
                'azOutputStart', bufferBlockAzLimits(1), ...
                'azOutputEnd', bufferBlockAzLimits(2), ...
                'rgOutputStart', bufferBlockRgLimits(1), ...
                'rgOutputEnd', bufferBlockRgLimits(2), ...
                'indexInStack', 0 ...
            );
            for blockInd = 1:numel(blocksInStack)
                tfBlockInStack(blockInd) = this.intersects( ...
                    bufferBlockInfo, blocksInStack(blockInd));
            end

            % Load in each block which intersects the buffered block
            for blockInd = 1:numel(blocksInStack)
                if tfBlockInStack(blockInd)
                    blockInfo = blocksInStack(blockInd);
                    blockDataTemplate = OI.Data.Block().configure( ...
                        'POLARISATION', 'VV', ...
                        'STACK', num2str(this.STACK), ...
                        'BLOCK', num2str(blockInfo.indexInStack) ...
                    ).identify(engine);
                    blockData = engine.load(blockDataTemplate);
                    if isempty(blockData)
                        return
                    end
                    % Find where the loaded data is in the buffered block
                    azIntersectInBufferedBlock = find(bufferedBlockAz >= blockInfo.azOutputStart & ...
                        bufferedBlockAz <= blockInfo.azOutputEnd);
                    rgIntersectInBufferedBlock = find(bufferedBlockRg >= blockInfo.rgOutputStart & ...
                        bufferedBlockRg <= blockInfo.rgOutputEnd);

                    % Find where the buffered block intersect is in the loaded data
                    blockDataAzAxis = blockInfo.azOutputStart:blockInfo.azOutputEnd;
                    blockDataRgAxis = blockInfo.rgOutputStart:blockInfo.rgOutputEnd;
                    azIntersectInData = find(blockDataAzAxis >= bufferBlockAzLimits(1) & ...
                        blockDataAzAxis <= bufferBlockAzLimits(2));
                    rgIntersectInData = find(blockDataRgAxis >= bufferBlockRgLimits(1) & ...
                        blockDataRgAxis <= bufferBlockRgLimits(2));

                    bufferBlockData(azIntersectInBufferedBlock, rgIntersectInBufferedBlock, :) = ...
                        blockData(azIntersectInData, rgIntersectInData, :);
                end
            end

            % Now, init an array for the mask at each pixel
            masks = zeros(nWindow, prod(blockSize(1:2)));
            pValues = masks;

            sz = blockSize;
            wOneSide = floor(windowSize./2);
            dx = (-wOneSide(2):wOneSide(2)).*ones(windowSize(1),1);
            dy = (-wOneSide(1):wOneSide(1))'.*ones(1,windowSize(2));
            pix_to_area = @(x,y) sub2ind(sz, y+dy(:), x+dx(:));
            O=zeros(sz(1),sz(2));
            inds = zeros(numel(dx),prod(sz(1:2)));
            for xi = 11:sz(2)-11+1
                for yi=3:sz(1)-3+1
                    inds(:, yi+(xi-1)*sz(1)) = pix_to_area(xi,yi);
                end
            end
            
            for xi=1:sz(2)
                for yi=1:sz(1)
                    inds(:,yi+(xi-1)*sz(1)) = ...
                        sub2ind(bufferBlockSize, ...
                            yi+dy(:)+wOneSide(1), ...
                            xi+dx(:)+wOneSide(2));                
                end
            end

            % Loop through each pixel in the target block
            ii=0;
%             for ir = 1:blockSize(2)
%                 for ia = 1:blockSize(1)
%                     ii=ii+1;
%                     calcii=ia + (ir-1) .*blockSize(1);
%                     % Get the data for the window around this pixel
%                     dataInWindow = abs(bufferBlockData( ...
%                         ia:ia + windowSize(1) - 1, ...
%                         ir:ir + windowSize(2) - 1, ...
%                         :));
%                     % Reshape the data into a 2D array
%                     dataInWindow = reshape(dataInWindow, nWindow, blockSize(3));
%                     % Perform the KS test
%                     for iSample = nWindow:-1:1
%                         [h, p] = ...
%                             kstest2(dataInWindow(iSample, :), dataInWindow(middlePixel, :));
%                         masks(iSample, calcii) = h;
%                         pValues(iSample, calcii) = p;
%                     end
% 
%                 end
%             end
            j = (1:101)'; % for estimating pValue
            for ir = 1:blockSize(2)
                for ia = 1:blockSize(1)
                    ii=ii+1;
                    calcii=ia + (ir-1) .*blockSize(1);
                    % Get the data for the window around this pixel
                    dataInWindow = abs(bufferBlockData( ...
                        ia:ia + windowSize(1) - 1, ...
                        ir:ir + windowSize(2) - 1, ...
                        :));
                    % Reshape the data into a 2D array
                    dataInWindow = reshape(dataInWindow, nWindow, blockSize(3));
                    % Perform the KS test
                    n = size(dataInWindow,2);
                    sd = sort(dataInWindow,2);
                    binEdges = [-inf sd(middlePixel,:) inf];
                    ecdfData = cumsum( histc(sd, binEdges, 2), 2) ./ n;
                    ksStatistic = max(abs(ecdfData-ecdfData(middlePixel,:)),[],2)';
                    n1      =  n.^2/(2.*n);
                    lbconst = -2*(j.^2).*(sqrt(n1) + 0.12 + 0.11/sqrt(n1)).^2;
                    seriesTerms = exp(lbconst .* ksStatistic.^2);
                    pValues(:, calcii) = 2.*sum(seriesTerms(1:2:end-1,:)-seriesTerms(2:2:end,:));
                end
            end
            
            masks = pValues > 0.05;
            inds2=inds;
            for ii=1:prod(sz(1:2))
                % do the bwarea stuff
                e1 = reshape(masks(:, ii),size(dy))>0;
                e1m = imfill(e1,[3,11]); % imfill must be using nargout so needs own line???
                e1 = e1m-e1;
                inds2(:,ii) = inds2(:,ii).*e1(:);
            end

            % example:
            rBufferBlockData = reshape(bufferBlockData,[],sz(3));
            dayInd = 1;
            for jj=1:prod(sz(1:2))
                maskedIndices = inds2(:,jj);
                maskedIndices(maskedIndices==0)=[];
                O(jj)=mean(abs(rBufferBlockData(maskedIndices,dayInd)));
            end

            % save the result
            shpMask = OI.Data.SHPMasks().configure( ...
                'STACK', num2str(this.STACK), ...
                'BLOCK', num2str(this.BLOCK), ...
                'masks', masks, ...
                'pValues', pValues ...
            );
            engine.save(shpMask);
            this.isFinished = true;
        end % run

        function this = queue_jobs(this, engine, blockMap)
            allDone = true;
            nJobs = 0;
            for stackIndex = 1:numel(blockMap.stacks)
                % Get the blocks in the block map
                blocksInStack = blockMap.stacks(stackIndex).usefulBlocks;
                for bis = blocksInStack'
                    blockIndex = bis.indexInStack;
                    % Create the result object template
                    resultObj = OI.Data.SHPMasks().configure( ...
                        'STACK', num2str(stackIndex), ...
                        'BLOCK', num2str(blockIndex) ...
                    ).identify(engine);
                    % Check if the block is already done
                    priorObj = engine.database.find(resultObj);
                    if isempty(priorObj)
                        allDone = false;
                        engine.requeue_job_at_index(1 + nJobs, ...
                            'STACK', stackIndex, ...
                            'BLOCK', blockIndex);
                        nJobs = nJobs + 1;
                    end
                end % block loop
            end % stack loop

            if allDone
                engine.save(this.outputs{1})
                this.isFinished = true;
            end

        end % queue_jobs
    end % methods

    methods (Static = true)

        function tf = intersects(block1, block2)
            tf = false;
            if block1.azOutputStart <= block2.azOutputEnd && block1.azOutputEnd >= block2.azOutputStart
                if block1.rgOutputStart <= block2.rgOutputEnd && block1.rgOutputEnd >= block2.rgOutputStart
                    tf = true;
                end
            end
        end % intersects

    end % methods (Static = true)

end % IdentifyShp
% ghooooo

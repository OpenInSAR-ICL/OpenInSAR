classdef GetFieldSamples < OI.Plugins.PluginBase
properties
    inputs = {OI.Data.BlockPsiSummary}
    outputs = {OI.Data.FieldSamplesSummary()}
    id = 'GetFieldSamples'
    STACK 
    BLOCK
    POLARISATION
end


% oi = OpenInSAR;
% engine = oi.engine;
% this = struct( ...
%     'BLOCK', 160, ...
%     'STACK', 1, ...
%     'POLARISATION', 'VV');

methods
    function this = GetFieldSamples( varargin )
        this.isArray = true;
    end
    
function this = run(this, engine, varargin)

% this = this.

% stackInd = this.STACK;
% blockInd = this.BLOCK;
if isempty(this.POLARISATION)
    polCells = {'VV', 'VH'};
else
    polCells = {this.POLARISATION};
end

if isempty(this.BLOCK) || isempty(this.STACK)
    % Queue jobs for all blocks/stacks
    this = this.queue_jobs(engine);
    return;
end

% check we havent finished already
resultObj = OI.Data.FieldSamples().configure( ...
        'STACK', this.STACK, ...
        'BLOCK', this.BLOCK ... %'POLARISATION', pol ...
    ).identify( engine );
if resultObj.exists
   this.isFinished = true;
   return
end

normz = @(x) x./abs(x);
projObj = engine.load( OI.Data.ProjectDefinition() );
blockMap = engine.load( OI.Data.BlockMap() );
dsMask = engine.load( ...
    OI.Data.SHPMasks().configure( ...
        'STACK', this.STACK, ...
        'BLOCK', this.BLOCK));
% blockData = engine.load( ...
%     OI.Data.Block().configure( ...
%         'POLARISATION', 'VV', ...
%         'STACK', this.STACK, ...
%         'BLOCK', this.BLOCK ...
%     ));

% blockInfo = blockMap.stacks(stackInd).blocks(blockInd);
% 
% sz = size(blockData);
% bdr = reshape(blockData,[],sz(3));

apsModelFn = fullfile(projObj.WORK,sprintf('aps_model_stack_%i.mat',this.STACK));
apsModel = load( apsModelFn );
apsModel = apsModel.apsModel;

nDays = numel(apsModel.timeSeries);

rgGrid = apsModel.rgGrid;
azGrid = apsModel.azGrid;
apsGrid = apsModel.apsGrid;

azLimits = apsModel.azLimits;
rgLimits = apsModel.rgLimits;

aRamp = apsModel.aRamp;
rRamp = apsModel.rRamp;
meanApsOffset = apsModel.meanApsOffset;

% blockAzAxis = blockInfo.azOutputStart:blockInfo.azOutputEnd;
% blockRgAxis = blockInfo.rgOutputStart:blockInfo.rgOutputEnd;
% [blockRgGrid,blockAzGrid] = meshgrid(blockRgAxis,blockAzAxis);
% 
% % Use the min/max az/rg from the aps model to adjust the block az/rg values
% normalisedRg = (blockRgGrid(:) - rgLimits(1)) / (rgLimits(2) - rgLimits(1)) - .5;
% normalisedAz = (blockAzGrid(:) - azLimits(1)) / (azLimits(2) - azLimits(1)) - .5;
% 
% for ii=nDays:-1:1
%     aps2dT = reshape(apsGrid(:,ii),size(rgGrid,1),size(rgGrid,2),[]);
% 	apsT = interp2(rgGrid, azGrid, aps2dT, blockRgGrid, blockAzGrid);
%     aps(:,ii) = apsT(:);
% end
% aps = normz(aps);
% % aps = aps .* exp( 1i * ( normalisedAz .* aRamp + normalisedRg .* rRamp) );
% % aps = aps .* meanApsOffset;
% % for ii=1:prod(sz(1:2));
% aps = conj(aps) ...
%     .* exp(1i.*(normalisedAz.*aRamp +normalisedRg.*rRamp)) ...
%     .* meanApsOffset;
% bdr = normz(bdr.*aps);



% Get the window settings
windowSize = [5, 21];
nWindow = prod(windowSize);
middlePixel = ceil(prod(windowSize) / 2);

for polCell = polCells
pol = polCell{1};

% Load the target block
targetBlock = blockMap.stacks(this.STACK).blocks(this.BLOCK);
blockDataTemplate = OI.Data.Block().configure( ...
    'POLARISATION', pol, ...
    'STACK', num2str(this.STACK), ...
    'BLOCK', num2str(this.BLOCK) ...
).identify(engine);
blockData = engine.database.find(blockDataTemplate);
if isempty(blockData)
    return
end

% Now we need to load data around the block
% In order that we can analyse samples at the edges.
blockSize = blockMap.stacks(this.STACK).blocks(this.BLOCK).size;
bufferEdgeSize = floor(windowSize / 2);
bufferBlockSize = blockSize(1:2) + (bufferEdgeSize * 2);

% Get the axis limits for the block, and its buffered equivalent
targetBlockAzLimits = [targetBlock.azOutputStart targetBlock.azOutputEnd];
targetBlockRgLimits = [targetBlock.rgOutputStart targetBlock.rgOutputEnd];
bufferBlockAzLimits = targetBlockAzLimits + [-1 1] * bufferEdgeSize(1);
bufferBlockRgLimits = targetBlockRgLimits + [-1 1] * bufferEdgeSize(2);
bufferedBlockAz = bufferBlockAzLimits(1):bufferBlockAzLimits(2);
bufferedBlockRg = bufferBlockRgLimits(1):bufferBlockRgLimits(2);

pol = polCell{1};
% Initialise array for the buffered block data
bufferBlockData = zeros(bufferBlockSize(1), bufferBlockSize(2), nDays);
% bufferBlockDataVH = zeros(bufferBlockSize(1), bufferBlockSize(2), blockSize(3));
% initialise the imaginary part of the data
bufferBlockData(end) = eps * 1i;
% bufferBlockDataVH(end) = eps * 1i;

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
    tfBlockInStack(blockInd) = OI.Plugins.IdentifySHP.intersects( ...
        bufferBlockInfo, blocksInStack(blockInd));
end

% Load in each block which intersects the buffered block
for blockInd = 1:numel(blocksInStack)
    if tfBlockInStack(blockInd)
        blockInfo = blocksInStack(blockInd);
        blockDataTemplate = OI.Data.Block().configure( ...
            'POLARISATION', pol, ...
            'STACK', num2str(this.STACK), ...
            'BLOCK', num2str(blockInfo.indexInStack) ...
        ).identify(engine);
        blockData = engine.load(blockDataTemplate);
        if isempty(blockData)
            return
        end
        
        blockAzAxis = blockInfo.azOutputStart:blockInfo.azOutputEnd;
        blockRgAxis = blockInfo.rgOutputStart:blockInfo.rgOutputEnd;
        [blockRgGrid,blockAzGrid] = meshgrid(blockRgAxis,blockAzAxis);

        % Use the min/max az/rg from the aps model to adjust the block az/rg values
        normalisedRg = (blockRgGrid(:) - rgLimits(1)) / (rgLimits(2) - rgLimits(1)) - .5;
        normalisedAz = (blockAzGrid(:) - azLimits(1)) / (azLimits(2) - azLimits(1)) - .5;

        aps = zeros(prod(blockInfo.size), nDays);
        for ii=nDays:-1:1
            aps2dT = reshape(apsGrid(:,ii),size(rgGrid,1),size(rgGrid,2),[]);
            apsT = interp2(rgGrid, azGrid, aps2dT, blockRgGrid, blockAzGrid);
            aps(:,ii) = apsT(:);
        end
        aps = normz(aps);
        aps = conj(aps) ...
            .* exp(1i.*(normalisedAz.*aRamp +normalisedRg.*rRamp)) ...
            .* meanApsOffset;
        aps = reshape(aps, size(blockData));
        blockData = blockData.*aps;
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
            blockData(azIntersectInData, rgIntersectInData, :); %#ok<FNDSB>

        % % Now load VH as well
        % blockDataTemplate.POLARISATION = 'VH';
        % blockData = engine.load(blockDataTemplate);
        % bufferBlockDataVH(azIntersectInBufferedBlock, rgIntersectInBufferedBlock, :) = ...
        %     blockData(azIntersectInData, rgIntersectInData, :);
    end
end

% Clear unused variables
clear blockData aps apsModel
bufferBlockData = reshape(bufferBlockData,[],nDays);
bufferBlockData(end+1,:) = 0; %#ok<AGROW> % for masking out data
maskIndex = size(bufferBlockData,1);

sz = blockSize;
wOneSide = floor(windowSize./2);
dx = (-wOneSide(2):wOneSide(2)).*ones(windowSize(1),1);
dy = (-wOneSide(1):wOneSide(1))'.*ones(1,windowSize(2));
% pix_to_area = @(x,y) sub2ind(sz, y+dy(:), x+dx(:));
% O=zeros(sz(1),sz(2));
inds = zeros(numel(dx),prod(sz(1:2)));

for xi=1:sz(2)
    for yi=1:sz(1)
        inds(:,yi+(xi-1)*sz(1)) = ...
            sub2ind(bufferBlockSize, ...
                yi+dy(:)+wOneSide(1), ...
                xi+dx(:)+wOneSide(2));                
    end
end

dsMask1 = dsMask.masks;
dsMask1(middlePixel,:) = 1; % Don't mask the target pixel
inds2 = inds.*dsMask1;

% Now we will pull out samples of DS from the data
TARGET_NUMBER_OF_SAMPLES = 500;

% We want these to be evenly distributed across the block
% Az is around 12m, Rg is around 3m
block_width_m = 3 * blockSize(2);
block_height_m = 12 * blockSize(1);
block_area_m = block_width_m * block_height_m;
sample_area_m = block_area_m / TARGET_NUMBER_OF_SAMPLES;
sample_side_m = sqrt(sample_area_m);
% Hence find the stride in azimuth and range pixels which will give us
% samples of this area
sampleRgStride= ceil(sample_side_m/3);
sampleAzStride = ceil(sample_side_m / 12);
% Now, from the mesh grid of range and azimuth, find the indices of the
% samples we want to take
sample_az_ax = floor(sampleAzStride/2):sampleAzStride:blockSize(1) - floor(sampleAzStride/2);
sample_rg_ax = floor(sampleRgStride/2):sampleRgStride:blockSize(2) - floor(sampleRgStride/2);
[sample_rg, sample_az] = meshgrid(sample_rg_ax, sample_az_ax);
% convert these to linear indices
sample_inds = sub2ind(blockSize, sample_az(:), sample_rg(:));
ACTUAL_NUMBER_OF_SAMPLES = numel(sample_inds);

if ~exist('s','var')
    % Create the output structure
    s = struct( ...
        'VV', zeros(nWindow, nDays, ACTUAL_NUMBER_OF_SAMPLES), ...
        'VH', zeros(nWindow, nDays, ACTUAL_NUMBER_OF_SAMPLES), ...
        'index', zeros(ACTUAL_NUMBER_OF_SAMPLES, 1), ...
        'az', zeros(ACTUAL_NUMBER_OF_SAMPLES, 1), ...
        'rg', zeros(ACTUAL_NUMBER_OF_SAMPLES, 1), ...
        'dataInds', zeros(prod(windowSize), ACTUAL_NUMBER_OF_SAMPLES), ...
        'shpSize', zeros(ACTUAL_NUMBER_OF_SAMPLES, 1), ...
        'blockInd', this.BLOCK ...
    );
end

%% Pull out samples
inds3 = inds2;
inds3(inds3==0) = maskIndex;
for jj = 1:numel(sample_inds)
    ii = sample_inds(jj);
    inds = inds3(:,ii);
    s.index(jj) = ii;
    s.dataInds(:,jj) = inds;
    s.az(jj) = blockAzGrid(ii);
    s.rg(jj) = blockRgGrid(ii);
    s.shpSize(jj) = sum(dsMask1(:,ii));

    if strcmpi(pol, 'VV')
        s.VV(:, :, jj) = bufferBlockData(inds, :);
    else
        s.VH(:, :, jj) = bufferBlockData(inds, :);
    end
    %s.(pol)(:, :, jj) = bufferBlockDataVV(inds, 1);
end

bBlockObj = OI.Data.BufferedBlock().configure( ...
    'STACK', this.STACK, ...
    'BLOCK', this.BLOCK, ...
    'POLARISATION', pol, ...
    'WAZ', windowSize(1), ...
    'WRG', windowSize(2));
engine.save(bBlockObj, bufferBlockData);

end % polarisation loop
engine.save( ...
    OI.Data.FieldSamples().configure( ...
        'STACK', this.STACK, ...
        'BLOCK', this.BLOCK ... %'POLARISATION', pol ...
    ), ...
    s ...
);
this.isFinished = true;

end %run

function this = queue_jobs(this, engine)
    blockMap = engine.load( OI.Data.BlockMap() );
    nJobs = 0;
    
    fieldDir = fileparts(OI.Data.FieldSamples().identify(engine).filepath);
    fieldDirConts = dir(fieldDir);
    
    for stackInd = 1:numel(blockMap.stacks)
        for blockInd = blockMap.stacks(stackInd).usefulBlockIndices(:)'
%             for pol = {'VV','VH'}
                priorObj = ...
                    OI.Data.FieldSamples().configure( ...
                        'STACK', stackInd, ...
                        'BLOCK', blockInd);%, ...
%                         'POLARISATION', pol{1}).identify(engine);
                [~, fn, ext] = fileparts(priorObj.filepath);
                if ~isempty(ext)
                    fn = [fn '.' ext]; %#ok<AGROW>
                end
                
                if ~any(strcmpi(fn,{fieldDirConts.name}))
                    nJobs = nJobs + 1;
                    engine.requeue_job_at_index( ...
                        nJobs, ...
                        'STACK', stackInd, ...
                        'BLOCK', blockInd);%, ...
%                         'POLARISATION', pol{1});
                end
%             end
        end
    end
    
    if nJobs == 0
        this.isFinished = true;
        engine.save( this.outputs{1} );
    end
end
end % methods

end % classdef
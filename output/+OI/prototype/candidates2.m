oi = OpenInSAR
engine = oi.engine;

blockMap = engine.load( OI.Data.BlockMap() );

% for stackInd = 1:2
stackInd = 1;
usefulBlock = blockMap.stacks(stackInd).usefulBlocks(1);

%% Parameters
this = struct( ...
    'BLOCK', usefulBlock.index, ...
    'STACK', stackInd);
stabilityThreshold = 3;
% load in up to this many values, initially:
maxTotalMemory = 4e9; 
% after filtering low stability pix missing values, target this size for array:
maxWorkingMemory = 0.5e9;

stackInd = this.STACK;

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

%% Load the data
timePerBlock = zeros(1,numel(stack.visits));
for iiBlock = 1:nBlocks
    bTic = tic;
    index = (1:nPixPerBlockLoad)' + (iiBlock-1) * nPixPerBlockLoad;
    % Create the block object template
    blockIndex = stackMap.usefulBlockIndices( iiBlock );
    blockObj = OI.Data.Block().configure( ...
        'POLARISATION', 'VV', ...
        'STACK',num2str( this.STACK ), ...
        'BLOCK', num2str( blockIndex ) ...
        ).identify( engine );

    psPhaseObject = OI.Data.BlockResult( blockObj, 'InitialPsPhase' );
    psPhaseObject = engine.load( psPhaseObject );

    if isempty(psPhaseObject)
        warning('missing data for %i %i!',iiBlock, blockIndex);
    end

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

end

%% Clean up
% 0 indicates missing data, remove these elements
noDataMask = pscAS == 0;
phi(noDataMask,:) = [];
pscAz(noDataMask) = [];
pscRg(noDataMask) = [];
pscBlock(noDataMask) = [];
pscAS(noDataMask) = [];
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
end
nSamples = numel(pscAz);

%% Set up APS grid
% Split the stack into a lower resolution grid
maxRg = max(pscRg);
maxAz = max(pscAz);
minRg = min(pscRg);
minAz = min(pscAz);

% grid point resolution in metres
modelInfo.gridRes = 300;
modelInfo.azSpacing = 12;
modelInfo.rgSpacing = 3;

% Determine the stride required to acheieve the desired grid resolution
rgStride = floor(modelInfo.gridRes/modelInfo.rgSpacing);
azStride = floor(modelInfo.gridRes/modelInfo.azSpacing);

% The grid should encompass all PSCs and be a multiple of the stride
modelInfo.maxGridRg = ceil(maxRg / rgStride) * rgStride;
modelInfo.maxGridAz = ceil(maxAz / azStride) * azStride;
modelInfo.minGridRg = floor(minRg / rgStride) * rgStride;
modelInfo.minGridAz = floor(minAz / azStride) * azStride;

% Define the grid
rgGridAxis = modelInfo.minGridRg : rgStride : modelInfo.maxGridRg;
azGridAxis = modelInfo.minGridAz : azStride : modelInfo.maxGridAz;
[rgGrid, azGrid] = meshgrid(rgGridAxis, azGridAxis);

% Determine the number of grid points
nRgGrid = numel(rgGridAxis);
nAzGrid = numel(azGridAxis);
nGrid = nRgGrid * nAzGrid;


%% Initial APS
ITER_LIMIT = 10;
% Decompose the following variables:
meanApsOffsetT = ones(1,nDays); %#ok<PREALL>
velPsc = zeros(nSamples,1);
virtualMaster = ones(nSamples,1); %#ok<PREALL>

lambda = 0.0555;
phasePerMetersPerYear = (1/365.25) * 2 * (1/lambda) * (2*pi);
% Meters per day, (doubled due to two-way travel) in cycles, then in
% radians.
vPhiTs = phasePerMetersPerYear .* timeSeries;
acm = phi'*phi;
[a1, a2]=eig(acm);
[~,maxComp] = max(diag(a2));
meanApsOffsetT = normz(a1(:,maxComp).');

P = phi .* meanApsOffsetT;
virtualMaster = normz(conj(mean(P,2)));
P = phi .* meanApsOffsetT .*virtualMaster; 

% Find phase ramps in azimuth and range
% normalise the azimuth and range to [-.5,.5]
normalAz = (pscAz - min(pscAz)) ./ (max(pscAz) - min(pscAz)) - 0.5;
normalRg = (pscRg - min(pscRg)) ./ (max(pscRg) - min(pscRg)) - 0.5;

% Create periodograms, in azimuth and range.
MAX_FRINGE = 10;
azRampSearch = linspace(-2*pi*MAX_FRINGE,2*pi*MAX_FRINGE,101);
azPeriodogram = exp(1i.*azRampSearch.*normalAz);
rgRampSearch = linspace(-2*pi*MAX_FRINGE,2*pi*MAX_FRINGE,101);
rgPeriodogram = exp(1i.*rgRampSearch.*normalRg);

% [aRamp,rRamp]= deal(zeros(1,nDays));
[azRampCoh, rgRampCoh]=deal(zeros(nDays,numel(rgRampSearch)));

for ii = 1:nDays
    % Find the coherence between ramps and the data
    azRampCoh(ii,:) = sum(P(:,ii) .* azPeriodogram,1);
    rgRampCoh(ii,:) = sum(P(:,ii) .* rgPeriodogram,1);
end

% Find the ramp that maximises coherence
[maxAzCoh, maxAzRamp] = max(abs(azRampCoh),[],2);
[maxRgCoh, maxRgRamp] = max(abs(rgRampCoh),[],2);

% Convert the ramp indices to ramp values
aRamp = azRampSearch(maxAzRamp);
rRamp = rgRampSearch(maxRgRamp);

doAzFirst = maxAzCoh > maxRgCoh;
for ii=1:nDays
    if doAzFirst
        rgRampCoh(ii,:) = sum(P(:,ii) .* rgPeriodogram ...
            .*exp(1i*  normalAz * aRamp(ii)), 1);
    else
         azRampCoh(ii,:) = sum(P(:,ii) .* azPeriodogram ...
             .* exp(1i * normalRg * rRamp(ii)), 1);
    end
end

% Find the ramp that maximises coherence
[maxAzCoh, maxAzRamp] = max(abs(azRampCoh),[],2);
[maxRgCoh, maxRgRamp] = max(abs(rgRampCoh),[],2);

% Convert the ramp indices to ramp values
aRamp = azRampSearch(maxAzRamp);
rRamp = rgRampSearch(maxRgRamp);


% for ii = 1:nDays
%     T = P(:,ii)';
%     cost = @(x) -abs(T / exp((1i*x).*azX));
%     aRamp(ii) = fminsearch(cost,0);
% end

P = P.*exp(1i.*(normalAz.*aRamp +normalRg.*rRamp));
acm2 = P'*P;
[a1, a2]=eig(acm2);
[~,maxComp] = max(diag(a2));

residualApsOffset = normz(a1(:,maxComp).');
meanApsOffset = meanApsOffsetT .* residualApsOffset;
P = P.*residualApsOffset;

residualMaster = normz(conj(mean(P,2)));
virtualMaster = virtualMaster .* residualMaster;
P = P .* residualMaster;

[Cv, velTemp] = OI.Functions.invert_velocity(P, vPhiTs);

% iter = 0;
% while iter < ITER_LIMIT
%     if iter 
%         [Cv, velTemp] = OI.Functions.invert_velocity(P, vPhiTs);
%         velPsc = velPsc + velTemp;
%         fprintf(1,'Iter %i - Coh: %.2f\n', iter, mean(Cv));
%     end
%     P = phi .* meanApsOffset .*exp(1i *velPsc.*vPhiTs) .*virtualMaster;
%     
%     for ii=nDays:-1:1
%         acm(ii,:) =  P(:,ii)'*P;
%     end
%     [a1, a2]=eig(acm);
%     [~,maxComp] = max(diag(a2));
%     meanApsOffset = meanApsOffset.*normz(a1(:,maxComp).');
%     P = phi .* meanApsOffset .*exp(1i *velPsc.*vPhiTs);
%     
%     meanSamplePhase = mean(P,2);
%     virtualMaster = normz(conj(meanSamplePhase));
%     P = P .* virtualMaster;
%     
%     iter = iter +1;
% end
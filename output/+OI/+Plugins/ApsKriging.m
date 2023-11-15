classdef ApsKriging < OI.Plugins.PluginBase
    
properties
    inputs = {OI.Data.BlockPsiSummary()}
    outputs = {OI.Data.ApsModel()}
    id = 'BlockPsiAnalysis'
    STACK = []
    BLOCK = []
end

methods
    
function this = ApsKriging( varargin )
    this.isArray = true;
    this.isFinished = false;
end    


function this = run(this, engine, varargin)


%% SETTINGS       
DO_NPSD = true;

%% LOAD INPUTS
blockMap = engine.load( OI.Data.BlockMap() );
projObj = engine.load( OI.Data.ProjectDefinition() );

% Exit if we're missing inputs
if isempty(projObj) || isempty(blockMap)
    return
end

this.STACK = 2
this.BLOCK = 55
if isempty(this.STACK)
   1;
   this = this.queue_jobs(engine, blockMap);
   return
end

%% SET UP STACK DATA STRUCTS
stackBlocks = blockMap.stacks( this.STACK );
blockCount = 1;
blocksToDo = stackBlocks.usefulBlockIndices(:)';
pscAz = [];
pscRg = [];
pscPhi = [];
pscAS = [];
pscBlock = [];
missingData =[];
blockInds = [];
    
for blockCount = 1:numel(blocksToDo)
    
    this.BLOCK = blocksToDo(blockCount);
    
%% LOAD BLOCK INPUTS
baselinesObjectTemplate = OI.Data.BlockBaseline().configure( ...
    'STACK', num2str(this.STACK), ...
    'BLOCK', num2str(this.BLOCK) ...
).identify( engine );
baselinesObject = engine.load( baselinesObjectTemplate );
blockObj = OI.Data.Block().configure( ...
    'POLARISATION', 'VV', ...
    'STACK',num2str( this.STACK ), ...
    'BLOCK', num2str( this.BLOCK ) ...
).identify( engine );
blockData=engine.load( blockObj);

if isempty(baselinesObject) || isempty(blockData)
    return
end

sz = size(blockData);
coherenceObj = OI.Data.BlockResult( blockObj, 'Coherence');
C0 = load(coherenceObj.identify(engine));

if isempty(C0)
    return
end

cohMask = C0>.5;
blockData = reshape(blockData,[],sz(3));

ampStabObj = OI.Data.BlockResult( blockObj, 'AmplitudeStability' );
amplitudeStability = engine.load( ampStabObj );
if isempty(amplitudeStability)
    return
end

blockGeocode = OI.Data.BlockGeocodedCoordinates().configure( ...
    'STACK', num2str(this.STACK), ...
    'BLOCK', num2str(blockMap.stacks(this.STACK).blocks(this.BLOCK).index) ...
    );
bg = engine.load(blockGeocode);
if isempty(bg)
    return
end


pAzAxis = 1:sz(1);
pRgAxis = 1:sz(2);
[pRgGrid, pAzGrid] = meshgrid(pRgAxis,pAzAxis);

MASK = cohMask(:);


temp = sum(blockData(MASK,:));
missingData(blockCount,:) = temp == 0 | isnan(temp);
kFactors(blockCount,:) = baselinesObject.k(:)';
timeSeries(blockCount,:) = baselinesObject.timeSeries(:)';

% Save PSC locations
% pscObj = OI.Data.PscLocations().configure( blockMap, stackIndex );
% engine.save( pscObj, [pscAz, pscRg] );

% normalise the phase
normz = @(x) OI.Functions.normalise(x);
pscPhi = pscPhi(:,missingData(blockCount,:)==0);
pscPhi = normz(pscPhi);
pscPhi(isnan(pscPhi))=0;

% DATA GOES HERE
pscAz = [pscAz; pAzGrid(MASK)];
pscRg = [pscRg; pRgGrid(MASK)];
pscPhi = [pscPhi; blockData(MASK,:)];
pscAS = [pscAS; amplitudeStability(MASK)];
blockInds = [blockInds; ones(numel(pscAz),1) * this.BLOCK ];



% Get a first estimate of the APS from the most stable PSC
[~, maxASInd] = max(pscAS);
aps0 = pscPhi(maxASInd,:);

% Remove initial aps estimate from reference
pscPhi = pscPhi .* conj(aps0);

% Split the stack into a lower resolution grid
maxRg = max(pRgAxis);
maxAz = max(pAzAxis);
minRg = min(pRgAxis);
minAz = min(pAzAxis);

% Determine the number of pixels in the grid
memoryLimit = 1e8;
bytesPerComplexDouble = 16;
% grid point resolution in metres
gridRes = 300;
azSpacing = 12;
rgSpacing = 3;

% Determine the stride required to acheieve the desired grid resolution
rgStride = floor(gridRes/rgSpacing);
azStride = floor(gridRes/azSpacing);

% The grid should encompass all PSCs and be a multiple of the stride
maxGridRg = ceil(maxRg/rgStride)*rgStride;
maxGridAz = ceil(maxAz/azStride)*azStride;
minGridRg = floor(minRg/rgStride)*rgStride;
minGridAz = floor(minAz/azStride)*azStride;

% Define the grid
rgGridAxis = minGridRg:rgStride:maxGridRg;
azGridAxis = minGridAz:azStride:maxGridAz;
[rgGrid,azGrid]=meshgrid(rgGridAxis,azGridAxis);

% Determine the number of grid points
nRgGrid = numel(rgGridAxis);
nAzGrid = numel(azGridAxis);
nGrid = nRgGrid * nAzGrid;

% Determine the number of bytes required for a correlation matrix
% for each grid point
% matsize = npoints^2 * bytesPerComplexDouble
nTraining = floor(sqrt(memoryLimit/bytesPerComplexDouble));

% Hence determine N
nTraining = min(nTraining,numel(pscRg));



d2C = @(d) exp(-d./300);
apsEst = zeros(nGrid,size(pscPhi,2));

gridTic = tic;
lowPass = normz(conj(movmean(pscPhi,11,2)));
CC = abs(mean(lowPass,2));
phiNoD = pscPhi.*lowPass;

end

for gridInd = numel(rgGrid):-1:1
    if mod(gridInd,round(numel(rgGrid)./2))==0 || gridInd == 1
        ttt=toc(gridTic);
        propdone = 1-gridInd./numel(rgGrid);
        timeRemaining = ttt./propdone-ttt;
        fprintf('%f done, %i remaining\n',propdone,timeRemaining);
    end
    % Calculate the distance for each PSC to the grid point
    dist = sqrt((rgGrid(gridInd)-pscRg).^2 + (azGrid(gridInd)-pscAz).^2);
    % Sort the distances
    [sortedDist,sortedInd] = sort(dist);
    % Select the N closest PSCs
    inds = sortedInd(1:nTraining);
    dists = sortedDist(1:nTraining);
    % pscNeighbourhoodIndices(gridInd,:) = inds;
    % pscNeighbourhoodDistances(gridInd,:) = sortedDist(1:nTraining);

    % calculate the distance matrix between the PSCs
    tPscAz = pscAz(inds);
    tPscRg = pscRg(inds);
    distMat = sqrt((tPscRg-tPscRg').^2 + (tPscAz-tPscAz').^2);

    % Calculate the correlation matrix
    CI = CC(inds);
    C = d2C(distMat).*sqrt(CI.*CI');
    if DO_NPSD
        C = npsd(C);
    end

    % Calculate the weights
    X = d2C(dists).*CI;
    w = C \ X;
    w = w./sum(w);

    iVals = phiNoD(inds,:);

    % Take the conjugate of the negative weights
    iVals(w<0)=conj(iVals(w<0));
    w=abs(w);

    % Calculate the weighted mean phase
    apsEst(gridInd,:) = w' * iVals;
end

engine.save( this.outputs{1} )
end % run

function [this, v] = inversion(this, pscPhi, apsEst, rgGrid, azGrid, pscRg,pscAz, cohMask, timeSeries, kFactors)
    O = nan(sz(1),sz(2));
    pscNoAps = pscPhi;
    blahs = pscNoAps;
    for ii=1:size(pscPhi,2)
        blah = interp2(rgGrid,azGrid,reshape(apsEst(:,ii),size(rgGrid,1),size(rgGrid,2),[]),pscRg,pscAz);
        blahs(:,ii) = normz(blah);
        pscNoAps(:,ii) = pscPhi(:,ii).*conj(blahs(:,ii));
        O(cohMask) = angle(pscNoAps(:,ii) .* conj(pscNoAps(:,max(1,ii-1))));
        imagesc(O)
    end

    pscNoAps = normz(pscNoAps);
    displacement = movmean(pscNoAps,11,2);
    displacement = normz(displacement);
    pscNoApsNoDisp = pscNoAps .* conj(displacement);
    [Cq,q]=OI.Functions.invert_height(pscNoApsNoDisp, kFactors(1,:));
    pscNoApsNoQ = displacement.*pscNoApsNoDisp.*exp(1i.*q.*kFactors(1,:));
    pscNoApsNoQ = normz(pscNoApsNoQ);
    [Cv,v]=OI.Functions.invert_velocity(pscNoApsNoQ, timeSeries(1,:));
    
    % NoANoQ was used for v
    % So disp - exp(1i v) is the residual
    res = displacement.*conj(displacement(:,round(mean(size(displacement,2)))));
    res = res.*conj(normz(mean(res)));

    % Remove v and unwrap
    res = res.*exp(-1i.*timeSeries.*(4*pi/(365.25.*0.055)).*v);
    res = res .* conj(normz(mean(res,2)));
    res = res.*conj(normz(mean(res)));
    uwres = unwrap(angle(res)')';
    uwres = uwres-uwres(:,1);
    uwres = uwres .* (0.055 ./ (4*pi) );

    [Cv4,v4]=OI.Functions.invert_velocity(res,timeSeries,0.01,51);
 
    datestrCells = cell(length(timeSeries),1);
    for ii = 1:length(timeSeries)
        datestrCells{ii} = datestr(timeSeries(ii),'YYYYmmDD');
    end


    % // free some mem
    blockData = [];
    blahs = [];
    displacement = [];
    lowPass = [];
    phiNoD = [];
    pscNoAps = [];
    pscNoApsNoQ = [];
    pscNoApsNoDisp = [];
    
    fnout = [projObj.WORK '/' projObj.PROJECT_NAME '_krigged_' num2str(this.STACK) '_' num2str(this.BLOCK) '.shp'];
    OI.Functions.ps_shapefile( ...
        fnout, ...
        bg.lat(cohMask), ...
        bg.lon(cohMask), ...
        uwres, ... % displacements 2d Array
        datestrCells, ... % datestr(timeSeries(1),'YYYYMMDD')
        q, ...
        v4, ...
        Cv4);
    O(cohMask)=v;
end

function this = queue_jobs(this, engine, blockMap)
    allDone = true;
    jobCount = 0;
    projObj = engine.load( OI.Data.ProjectDefinition() );
    % Queue up all blocks
    for stackIndex = 1:numel(blockMap.stacks)
        stackBlocks = blockMap.stacks( stackIndex );
        for blockIndex = stackBlocks.usefulBlockIndices(:)'
            blockInfo = stackBlocks.blocks( blockIndex );
            if ~isfield(blockInfo,'indexInStack')
                overallIndex = blockInfo.index;
                blockInfo.indexInStack = ...
                    find(arrayfun(@(x) x.index == overallIndex, ...
                        blockMap.stacks( stackIndex ).blocks));
            end

            % Create the block object template
            blockObj = OI.Data.Block().configure( ...
                'STACK',num2str( stackIndex ), ...
                'BLOCK', num2str( blockInfo.indexInStack ) ...
                );
            resultObj = OI.Data.BlockResult(blockObj, 'InitialPsPhase').identify( engine );

            % Create a shapefile of the block
            blockName = sprintf('Stack_%i_block_%i.shp',stackIndex,blockIndex);
            blockFilePath = fullfile( projObj.WORK, 'shapefiles', this.id, blockName);

            % Check if the block is already done
            priorObj = engine.database.find( resultObj );
            if ~isempty(priorObj) && exist(blockFilePath,'file')
                % Already done
                continue
            end
            jobCount = jobCount+1;
            allDone = false;
            engine.requeue_job_at_index( ...
                jobCount, ...
                'BLOCK', blockIndex, ...
                'STACK', stackIndex);
        end
    end

    if allDone
        engine.save( this.outputs{1} )
    end

end % queue_jobs

end % methods

end % classdef
   
classdef ApsKriging < OI.Plugins.PluginBase
    %#ok<*NASGU>
    %#ok<*AGROW>
properties
    inputs = {OI.Data.BlockPsiSummary()}
    outputs = {OI.Data.ApsModelSummary()}
    id = 'ApsKriging'
    STACK = []
end

methods
    
function this = ApsKriging( varargin )
    this.isArray = true;
    this.isFinished = false;
end    


function this = run(this, engine, varargin)


%% SETTINGS       
DO_NPSD = false;
normz = @(x) OI.Functions.normalise(x);

%% LOAD INPUTS
blockMap = engine.load( OI.Data.BlockMap() );
projObj = engine.load( OI.Data.ProjectDefinition() );

% Exit if we're missing inputs
if isempty(projObj) || isempty(blockMap)
    return
end

% Queue up all stacks jobs if we've not been told what to do
if isempty(this.STACK)
   this = this.queue_jobs(engine, blockMap);
   return
end

apsModelTemplate = OI.Data.ApsModel().configure('STACK', this.STACK);


%% SET UP STACK DATA STRUCTS
stackBlocks = blockMap.stacks( this.STACK );
blocksToDo = stackBlocks.usefulBlockIndices(:)';
pscAz = [];
pscRg = [];
pscLat = [];
pscLon = [];
pscPhi = [];
pscAS = [];
pscCoh = [];
missingData =[];
blockInds = [];
    
for blockCount = 1:numel(blocksToDo)

    engine.ui.log('warning','Block %i',blockCount);
    currentBlock = blocksToDo(blockCount);
    blockInfo = stackBlocks.blocks( currentBlock );

%% LOAD BLOCK INPUTS
baselinesObjectTemplate = OI.Data.BlockBaseline().configure( ...
    'STACK', num2str(this.STACK), ...
    'BLOCK', num2str(currentBlock) ...
).identify( engine );
baselinesObject = engine.load( baselinesObjectTemplate );
blockObj = OI.Data.Block().configure( ...
    'POLARISATION', 'VV', ...
    'STACK',num2str( this.STACK ), ...
    'BLOCK', num2str( currentBlock ) ...
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
    'BLOCK', num2str(blockMap.stacks(this.STACK).blocks(currentBlock).index) ...
    );
bg = engine.load(blockGeocode);
if isempty(bg)
    return
end


pAzAxis = blockInfo.azOutputStart:blockInfo.azOutputEnd;
pRgAxis = blockInfo.rgOutputStart:blockInfo.rgOutputEnd;
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
% pscPhi = pscPhi(:,missingData(blockCount,:)==0);
% pscPhi = normz(pscPhi);
% pscPhi(isnan(pscPhi))=0;

% DATA GOES HERE
pscAz = [pscAz; pAzGrid(MASK)]; 
pscRg = [pscRg; pRgGrid(MASK)]; 
pscLat = [pscLat; bg.lat(MASK)];
pscLon = [pscLon; bg.lon(MASK)];
pscPhi = [pscPhi; blockData(MASK,:)];
pscCoh = [pscCoh; C0(MASK)];
pscAS = [pscAS; amplitudeStability(MASK)];
blockInds = [blockInds; ones(numel(pscAz),1) * currentBlock ];
end
validVisits = sum(missingData)==0;

% Get a first estimate of the APS from the most stable PSC
[maxAS, maxASInd] = max(pscAS);
aps0 = pscPhi(maxASInd,:);
refAddress = struct();
refAddress.AS = maxAS;
refAddress.block = blockInds(maxASInd);
refAddress.az = pscAz(maxASInd);
refAddress.rg = pscRg(maxASInd);
refAddress.lat = pscLat(maxASInd);
refAddress.lon = pscLon(maxASInd);

% Remove initial aps estimate from reference
pscPhi = pscPhi .* conj(aps0);

% Split the stack into a lower resolution grid
maxRg = max(pscRg);
maxAz = max(pscAz);
minRg = min(pscRg);
minAz = min(pscAz);

% Determine the number of pixels in the grid
memoryLimit = 1e7;
bytesPerComplexDouble = 16;
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


apsEstObj = engine.load( apsModelTemplate );
if isempty(apsEstObj) % Generate if not found
    
% Determine the number of bytes required for a correlation matrix
% for each grid point
% matsize = npoints^2 * bytesPerComplexDouble
nTraining = floor(sqrt(memoryLimit/bytesPerComplexDouble));

% Hence determine N
nTraining = min(nTraining,numel(pscRg));

d2C = @(d) exp(-d./300);
apsEst = zeros(nGrid, size(pscPhi,2));

modelInfo.nTraining = nTraining;
modelInfo.nGrid = nGrid;

gridTic = tic;
lowPass = normz(conj(movmean(pscPhi,11,2)));
CC = abs(mean(lowPass,2));
phiNoD = pscPhi.*lowPass;


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
        C = OI.Functions.nearest_positive_definite(C); %#ok<UNRCH>
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

apsModelTemplate.phase = apsEst;
apsModelTemplate.rgGrid = rgGrid;
apsModelTemplate.azGrid = azGrid;
apsModelTemplate.timeSeries = timeSeries(1,:);
apsModelTemplate.referencePhase = aps0;
apsModelTemplate.referenceAddress = refAddress;
apsModelTemplate.info = modelInfo;

engine.save( apsModelTemplate.identify(engine) );

else
    apsEstObj = engine.load( apsModelTemplate );
    apsEst = apsEstObj.phase;
end

lowPass = [];
phiNoD = [];
blockData = [];
blockInds = [];
bg = [];
CC = [];
dist = [];
pscAS = [];
pscCoh = [];
sortedDist = [];
sortedInd = [];

this.inversion(projObj, pscPhi(:,validVisits), apsEst(:,validVisits), rgGrid, azGrid, pscRg, pscAz, timeSeries, kFactors, pscLat, pscLon);

this.isFinished = true;

end % run

function [this, v] = inversion(this, projObj, pscPhi, apsEst, rgGrid, azGrid, pscRg,pscAz, timeSeries, kFactors, pscLat, pscLon)
    shpName = OI.Functions.generate_shapefile_name(this, projObj);
    
    pscNoAps = pscPhi;
    blahs = pscNoAps;
    normz = @(x) OI.Functions.normalise(x);
    for ii=1:size(pscPhi,2)
        blah = interp2(rgGrid,azGrid,reshape(apsEst(:,ii),size(rgGrid,1),size(rgGrid,2),[]),pscRg,pscAz);
        blahs(:,ii) = normz(blah);
        pscNoAps(:,ii) = pscPhi(:,ii).*conj(blahs(:,ii));
    end

    pscNoAps = normz(pscNoAps);
    displacement = movmean(pscNoAps,11,2);
    displacement = normz(displacement);
    pscNoApsNoDisp = pscNoAps .* conj(displacement);
    [~, q]=OI.Functions.invert_height(pscNoApsNoDisp, kFactors(1,:));
    pscNoApsNoQ = displacement.*pscNoApsNoDisp.*exp(1i.*q.*kFactors(1,:));
    pscNoApsNoQ = normz(pscNoApsNoQ);
    [Cv, v]=OI.Functions.invert_velocity(pscNoApsNoQ, timeSeries(1,:).*(4*pi/(365.25.*0.055)));
    
    % NoANoQ was used for v
    % So disp - exp(1i v) is the residual
    res = displacement.*conj(displacement(:,round(mean(size(displacement,2)))));
    res = res.*conj(normz(mean(res)));

    % Remove v and unwrap
    res = res.*exp(-1i.*timeSeries(1,:).*(4*pi/(365.25.*0.055)).*v);
    res = res .* conj(normz(mean(res,2)));
    res = res.*conj(normz(mean(res)));
    uwres = unwrap(angle(res)')';
    uwres = uwres-uwres(:,1);
    uwres = uwres .* (0.055 ./ (4*pi) );

    datestrCells = cell(length(timeSeries),1);
    for ii = 1:length(timeSeries)
        datestrCells{ii} = datestr(timeSeries(1,ii),'YYYYmmDD');
    end


    % // free some mem
    blockData = []; 
    blahs = [];
    displacement = [];

    pscNoAps = [];
    pscNoApsNoQ = [];
    pscNoApsNoDisp = [];
    pscPhi = [];
    res = [];
    
    
    OI.Functions.ps_shapefile( ...
        shpName, ...
        pscLat, ...
        pscLon, ...
        uwres, ... % displacements 2d Array
        datestrCells, ... % datestr(timeSeries(1),'YYYYMMDD')
        q, ...
        v, ...
        Cv);

end

function this = queue_jobs(this, engine, blockMap)
    allDone = true;
    jobCount = 0;

    % Queue up all blocks
    for stackIndex = 1:numel(blockMap.stacks)
        if isempty(blockMap.stacks(stackIndex).usefulBlocks)
            continue
        end
        priorModelTemplate = OI.Data.ApsModel();
        priorModelTemplate.STACK = num2str(stackIndex);
        priorModel = engine.database.fetch( priorModelTemplate );
        if isempty( priorModel )
            jobCount = jobCount+1;
            engine.requeue_job_at_index( ...
                jobCount, ...
                'STACK', stackIndex);
            allDone = false;
        end
    end
    
    if allDone
        engine.save( this.outputs{1} )
        this.isFinished = true;
    end

end % queue_jobs

end % methods

end % classdef
   

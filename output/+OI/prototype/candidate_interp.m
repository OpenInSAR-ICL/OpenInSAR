% run candidates2 before this.

% Find the nearest N PSCs to each grid point

nTraining = 1000;
gridTic = tic;
nGrid = numel(rgGrid);
inds = zeros(nTraining,nGrid);
dists = zeros(nTraining,nGrid);

for gridInd = nGrid:-1:1
    if mod(gridInd,round(numel(rgGrid)./20))==0 || gridInd == nGrid - 2
        ttt=toc(gridTic);
        propdone = (nGrid - gridInd)/nGrid;
        timeRemaining = ttt./propdone-ttt;
        fprintf('Grid neighbourhood search, %.2f %% done, %.1f mins remaining\n',propdone*100,timeRemaining/60);
    end
    % Calculate the distance for each PSC to the grid point
    dist = sqrt((rgGrid(gridInd)-pscRg).^2 + (azGrid(gridInd)-pscAz).^2);
    
    % Sort the distances
    [sortedDist,sortedInd] = sort(dist);
    % Select the N closest PSCs
    inds(:,gridInd) = sortedInd(1:nTraining);
    dists(:,gridInd) = sortedDist(1:nTraining);
    
end

% Now use the distances to calculate the weights
% d2w = @(d) 1./d.^2;
d2w = @(d) exp(-d/600);
w = d2w(dists);
w = w./sum(w); % normalise to 1;

P_lowpass = conj(normz(movmean(P,21,2)));
P_highpass = P.*P_lowpass;


% while true
    % Now for each grid point, interpolate the aps from phi
    apsGrid = zeros(nGrid,nDays);
    for gridInd = nGrid:-1:1
        apsGrid(gridInd,:) = w(:,gridInd)'*P_highpass(inds(:,gridInd),:);
    end

    for ii=nDays:-1:1
        apsAtPscT = interp2(rgGrid,azGrid,reshape(apsGrid(:,ii),size(rgGrid,1),size(rgGrid,2),[]),pscRg,pscAz);
        apsAtPsc(:,ii) = normz(apsAtPscT);
    end

    filteredPscPhi = ...
        normz( phi .* ...
        meanApsOffset .* ...
        exp(1i.*(normalAz.*aRamp +normalRg.*rRamp)) .* ...
        conj(apsAtPsc));

    filteredPscPhi = filteredPscPhi .* ...
        conj(normz(mean(filteredPscPhi,2)));
    [Cq, q, qi] = OI.Functions.invert_height(filteredPscPhi,kFactors);
    filteredPscPhi = filteredPscPhi.*exp(1i.*kFactors.*q);
    [Cv, pscVel] = OI.Functions.invert_velocity(filteredPscPhi, vPhiTs);
    filteredPscPhi = filteredPscPhi.*exp(1i.*vPhiTs.*pscVel);
%     P_highpass = filteredPscPhi .* conj(normz(movmean(filteredPscPhi, 21, 2)));
% end

% so in summary:
fpp = phi ...
    .* exp(1i.*vPhiTs.*pscVel) ...
    .* exp(1i.*kFactors.*q) ...
    .* conj(apsAtPsc) ...
    .* exp(1i.*(normalAz.*aRamp +normalRg.*rRamp)) ... 
    .* meanApsOffset;

apsModel = struct();
apsModel.phi = phi;
apsModel.pscAz = pscAz;
apsModel.pscRg = pscRg;
apsModel.pscAS = pscAS;
apsModel.pscBlock = pscBlock;
apsModel.stack = stackInd;
apsModel.kFactors = kFactors;
apsModel.timeSeries = timeSeries;
apsModel.vPhiTs = vPhiTs;
apsModel.pscVel = pscVel;
apsModel.pscHeightError = q;
apsModel.aRamp = aRamp;
apsModel.rRamp = rRamp;
apsModel.azLimits = [min(pscAz) max(pscAz)];
apsModel.rgLimits = [min(pscRg) max(pscRg)];
apsModel.meanApsOffset = meanApsOffset;
apsModel.stabilityThreshold = stabilityThreshold;
apsModel.rgGrid = rgGrid;
apsModel.azGrid = azGrid;
apsModel.closestInds = inds;
apsModel.closestDistances = dists;
apsModel.apsGrid = apsGrid;

projObj = engine.load( OI.Data.ProjectDefinition() );
fn = fullfile(projObj.WORK,sprintf('aps_model_stack_%i.mat',stackInd));

save(fn,'apsModel');


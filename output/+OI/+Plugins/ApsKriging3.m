classdef ApsKriging3 < OI.Plugins.PluginBase
%#ok<*TNOW1,*DATST>
properties
    inputs = {OI.Data.BlockPsiSummary()}
    outputs = {OI.Data.ApsModelSummary()}
    id = 'ApsKriging3'
    STACK = []
end

methods

    function this = ApsKriging( varargin )
        this.isArray = true;
    end    
    
    function this = run(this, engine, varargin)
        if isempty(this.STACK)
            this = this.queue_jobs(engine);
            return
        end
        this = this.estimate_aps_for_stack(engine);
    end % run


    function this = estimate_aps_for_stack(this, engine)
        % load the inputs for a given stack (specified in the plugin
        % property) and estimate the aps via a sparse grid.
        GRID_SPACING = 300; % meters
        MAX_ITER = 10;

        % check if finished already
        apsModel = OI.Data.ApsModel3().configure( ...
            'STACK', this.STACK);
        if ~this.isOverwriting && apsModel.identify(engine).exists()
            return
        end

        %% LOAD INPUTS
        % stack info
        stacks = engine.load( OI.Data.Stacks() );
        referenceVisit = find(stacks.stack(this.STACK).correspondence(1,:)==1);

        % Baselines
        blockMap = engine.load( OI.Data.BlockMap() );
        if isempty(blockMap)
            return
        end
        baselinesObject = engine.load( OI.Data.BlockBaseline().configure( ...
            'STACK', num2str(this.STACK), ...
            'BLOCK', num2str(blockMap.stacks(this.STACK).usefulBlockIndices(1)) ...
        ) );
        if isempty(baselinesObject)
            return
        end
        timeSeries = baselinesObject.timeSeries(1,:);
        kFactors = baselinesObject.k';
        ts = timeSeries-timeSeries(1);
        PHASE_TO_M_PER_A = 4 * pi / (365.25 .* 0.055);
        tsp = ts .* PHASE_TO_M_PER_A;

        % Phase sample over the stack
        pscSampleObj = OI.Data.PscSample().configure('METHOD','PscSampling_4GBmax','BLOCK','ALL','STACK', this.STACK, 'POLARISATION','VV');
        pscSample = engine.load( pscSampleObj );        
        if isempty(pscSample)
            return
        end
        pscLLE = pscSample.sampleLLE;
        phi = pscSample.samplePhase;
        nD = size(phi,2);
        nSamples = size(phi,1);
        [~, masi]=max(pscSample.sampleStability); % reference point
        clearvars pscSample
        

        %% INITIAL CONFIG
        phiTraining=phi.*conj(phi(masi,:)); % starting phase
        C0 = abs(mean(phiTraining,2)); % starting coherence
        apsModel.overwrite = this.isOverwriting;
        apsModel.referenceTimeSeries = timeSeries;
        apsModel.referenceKFactors = kFactors;
        apsModel.virtualMasterImage_initial = mean(phiTraining,2);
        apsModel.referencePointPhase = phi(masi,:);
        apsModel.referencePointIndex = masi;
        apsModel.referenceElevation = pscLLE(masi,3);
        apsModel.inputPhase = pscSampleObj;
        apsModel.temporalCoherence_initial = C0;

        % Set up xy meter grid
        apsModel.referenceLLE = pscLLE(masi,1:2); % distance from reference pt
        [dy, dx]=OI.Functions.haversineXY(pscLLE(:,1:2), pscLLE(masi,1:2));
        dd = hypot(dx,dy);
        [sdd, ~]=sort(dd);

        % fit variograms for each ifg
        startDistance = sdd(2);
        nBins = 20;
        bins = linspace(startDistance,min(max(dd),1e4), nBins);
        midBins = (bins(1:end-1)+bins(2:end))/2;
        for jj=nBins-1:-1:1
            inBin = dd>bins(jj) & dd<bins(jj+1);
            eN(jj)=sum(inBin);
            eC(jj) = abs(mean(C0(inBin,:)));
        end
        sill=eC(end);
        cost = @(x) var(eC - (1-sill).*exp(-midBins/x));
        decay = fminsearch(cost, 1000);
        apsModel.variogramStructs = struct('sill',sill,'decay',decay);


        %% LOCAL GRID
        ngX = ceil((max(dx)-min(dx))/GRID_SPACING);
        ngY = ceil((max(dy)-min(dy))/GRID_SPACING);
        szG = [ngY ngX];
        nG = prod(szG);
        yAxis = linspace(min(dy),max(dy),ngY);
        xAxis = linspace(min(dx),max(dx),ngX);
        [xGrid, yGrid]=meshgrid(xAxis,yAxis);
        apsModel.xGrid = xGrid;
        apsModel.yGrid = yGrid;


        %% KD NETWORK
        kdt = KDTreeSearcher([dx dy]);
        K = 500;
        KNN = zeros(ngY,K,ngX);
        KNND = KNN;
        % for iY=ngY:-1:1
        for iX = ngX:-1:1
            iatic=tic;
                tY = yGrid(:,iX);
                tX = xGrid(:,iX);
                [KNN(:,:,iX), KNND(:,:,iX)] = knnsearch(kdt, [tX, tY], 'k', K);
            iatoc=toc(iatic);
            if iX == ngX-1 || mod(iX,round(ngX/10)) == 1
                fprintf(1,'Nearest neighbour distances %f sec remaining\n',iatoc.*(iX-1));
            end
        end
        KNN = permute(KNN, [1,3,2]);
        KNND = permute(KNND, [1,3,2]);


        %% HELPERS
        normz = @(x) x./abs(x);
        % F = @(c) min(12*pi,(1-c.^2)./c.^2);
        % s2i = @(az,rg) (rg-1)*ngY+az;
        e1i = @(x) exp(1i.*x);
        avfilt = @(x) imfilter(x, fspecial('average', [3,3]));
        % mask0s = @(A) OI.Functions.mask0s(A);


        %% ESTIMATE APS GRID
        velocity = zeros(nSamples,1);
        coherence = abs(mean(phiTraining,2));
        phiTraining = phiTraining .* conj(phiTraining(:, referenceVisit));

        fprintf('%s - Starting aps estimation - Raw coherence: %f\n', datestr(now), mean(coherence))
        for iter = 1:MAX_ITER
            fprintf(1,'%s - Iter %i\n', datestr(now),iter)
            phiFiltered = phiTraining .* e1i(velocity.*tsp);
            phiFiltered = phiFiltered .* conj(phiFiltered(:, referenceVisit)); %#ok<FNDSB>

            filteredInterferograms = OI.Functions.filter_with_knn_distance(phiFiltered,KNN,KNND,sill,decay);

            filteredInterferogramCoherence = abs(sum(normz(filteredInterferograms),3))./nD;
            [~, bestGridPoint]=max(filteredInterferogramCoherence(:));

            unwrappedHipassInterferograms = OI.Functions.unwrap_lsq(xGrid, yGrid, reshape(filteredInterferograms, [], nD), @(P) movmean(P, 31, 2));
            % unwrappedHipassInterferograms = unwrappedHipassInterferograms - unwrappedHipassInterferograms(bestGridPoint,:);

            % fit initial velocity ramp and mean
            for jj=nG:-1:1
                pf = polyfit(ts,unwrappedHipassInterferograms(jj,:),1);
                referenceApsGrid(jj) = pf(2);
                apsVelocity(jj) = pf(1);
            end
    
            % interpolate
            for ii=nD:-1:1
                apsAtPsc(:,ii) = interp2(xGrid,yGrid,avfilt(reshape(unwrappedHipassInterferograms(:,ii),szG)),dx,dy);
            end
            referenceAps = interp2(xGrid,yGrid,reshape(referenceApsGrid,szG),dx,dy);
    
            % rereference to the ref point, and remove mean 
            apsAtPsc = apsAtPsc-apsAtPsc(masi,:)-referenceAps;
    
            phiNoAps = phiTraining .* exp(-1i.*apsAtPsc);
            phiNoAps = phiNoAps.*conj(phiNoAps(masi,:));

            [coherenceIteration, velocityIteration] = OI.Functions.invert_velocity(normz(phiNoAps), tsp, 0.2, 101);
            fprintf('%s - Iter %i - Mean coherence: %f\n', datestr(now()), iter, mean(coherenceIteration))
            if mean(coherenceIteration) > mean(coherence)
                velocity = velocityIteration;
                coherence = coherenceIteration;
                bestAps = unwrappedHipassInterferograms;
            else
                break
            end
    
        end

        % apsGrid should have the reference point phase removed before
        % assignment
        apsModel.apsGrid = reshape(bestAps,ngY,ngX,nD);

        % % fit q
        % [cq, q] = OI.Functions.invert_height( ...
        %     normz(whateteteteteteevever), ...
        %     kFactors, ...
        %     600, ...
        %     200 ...
        % );
        % disp('cq')
        % mean(cq)
        % 
        % % fit elevation dependent aps
        % eRamp = [];
        % for ii = size(phi1,2):-1:1
        %     cost = @(x) -abs(exp(1i*x.*pscLLE(:,3)') * phi1(:,ii));
        %     eRamp(ii) = fminsearch(cost,0);
        % end
        % apsModel.elevationToPhase = eRamp;
        

        %% FINALISE
        engine.save(apsModel)
        this.isFinished=true;
    end % estimate

    function this = queue_jobs(this, engine)

        stacks = engine.load( OI.Data.Stacks );
        allDone = true;
        
        for ii=1:numel(stacks.stack)
            apsModel = OI.Data.ApsModel2().configure( ...
                'STACK', ii ...
            );
            if ~apsModel.identify(engine).exists()
                allDone = false;
                engine.requeue_job_at_index( ...
                    1, ...
                    'STACK', ii ...
                );
            end
        end

        if allDone
            engine.save(this.outputs{1})
            this.isFinished = true;
        end

    end % queue jobs

end % methods

end % classdef

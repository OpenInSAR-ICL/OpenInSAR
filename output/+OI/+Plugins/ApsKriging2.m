classdef ApsKriging2 < OI.Plugins.PluginBase
properties
    inputs = {OI.Data.BlockPsiSummary()}
    outputs = {OI.Data.ApsModelSummary()}
    id = 'ApsKriging2'
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
        apsModel = OI.Data.ApsModel2().configure( ...
            'STACK', this.STACK);
        if ~this.isOverwriting && apsModel.identify(engine).exists()
            return
        end
        
        pscSampleObj = OI.Data.PscSample().configure('METHOD','PscSampling_4GBmax','BLOCK','ALL','STACK', this.STACK, 'POLARISATION','VV');
        pscSample = engine.load( pscSampleObj );
        nSamples = numel(pscSample.sampleAz);
        
        FEW_SAMPLES = nSamples < 15e3; % ~ 4gb for N^2 complex double mat
        if isempty(pscSample)
            return
        end
        
        blockMap = engine.load( OI.Data.BlockMap() );
        baselinesObject = engine.load( OI.Data.BlockBaseline().configure( ...
            'STACK', num2str(this.STACK), ...
            'BLOCK', num2str(blockMap.stacks(this.STACK).usefulBlockIndices(1)) ...
        ) );
        timeSeries = baselinesObject.timeSeries(:)';
        kFactors = baselinesObject.k';
        
        % save these for convenience
        apsModel.referenceTimeSeries = timeSeries;
        apsModel.referenceKFactors = kFactors;

        
        pscLLE = pscSample.sampleLLE;
        phi = pscSample.samplePhase;
        % reference point:
        [~, masi]=max(pscSample.sampleStability);
        
        clearvars pscSample
        
        normz = @(x) x./abs(x);



        % phase to use:
        phiTraining=phi.*conj(phi(masi,:));
        apsModel.virtualMasterImage_initial = mean(phiTraining,2);
        apsModel.referencePointPhase = phi(masi,:);
        apsModel.referencePointIndex = masi;
        apsModel.inputPhase = pscSampleObj;
        
        phiTraining=normz(phiTraining.*conj(mean(phiTraining,2)));
        C0 = abs(mean(phiTraining,2));
        apsModel.temporalCoherence_initial = C0;


        F = @(c) min(12*pi,(1-c.^2)./c.^2);

        % get the distance from the reference point
        apsModel.referenceLLE = pscLLE(masi,1:2);
        [dy, dx]=OI.Functions.haversineXY(pscLLE(:,1:2), pscLLE(masi,1:2));
        dd = hypot(dx,dy);
        [sdd, ~]=sort(dd);

        % fit variograms for each ifg
        startDistance = sdd(2);
        nBins = 20;
        nD=size(phiTraining,2);
        bins = linspace(startDistance,min(max(dd),1e4), nBins);
        midBins = (bins(1:end-1)+bins(2:end))/2;
        eC=zeros(1,nBins-1);
        eN=zeros(1,nBins-1);

        for jj=1:nBins-1
            inBin = dd>bins(jj) & dd<bins(jj+1);
            eN(jj)=sum(inBin);
            eC(jj) = abs(mean(C0(inBin,:)));
        end

        sill=eC(end);
        cost = @(x) var(eC - (1-sill).*exp(-midBins/x));
        decay = fminsearch(cost, 1000);

        apsModel.variogramStructs = struct('sill',sill,'decay',decay);


        % Grid spacing
        gSpace = 100;
        ngX = ceil((max(dx)-min(dx))/gSpace);
        ngY = ceil((max(dy)-min(dy))/gSpace);

        
        yAxis = linspace(min(dy),max(dy),ngY);
        xAxis = linspace(min(dx),max(dx),ngX);
        [xGrid, yGrid]=meshgrid(xAxis,yAxis);
        apsModel.xGrid = xGrid;
        apsModel.yGrid = yGrid;
%         % Initial estimate of APS at each PSC:
%         if FEW_SAMPLES
% 
%             D = sqrt((dx-dx').^2+(dy-dy').^2);
%             T = (1-sill).*exp(-D./decay);
% 
%             TT=T.*sqrt(F(C0)).*sqrt(F(C0))';
% 
%             L=numel(C0);
% 
% %             pTT=inv([TT ones(L,1); ones(1,L) 0]);
% %             W = pTT*[T.*F(C0); ones(1,L)];
%             W = [TT ones(L,1); ones(1,L) 0] \ [T.*F(C0); ones(1,L)];
%             
%             W(end,:)=[];
%             W=W./sum(W,2);
%             AE = normz(W'*phiTraining);
%       
%         else % many samples

            kdt = KDTreeSearcher([dx dy]);
            K = 500;
            KNN = zeros(ngY,K,ngX);
            KNND = KNN;
            % for iY=ngY:-1:1
            for iX = ngX:-1:1
                iatic=tic;
                % for iX = ngX:-1:1

                    tY = yGrid(:,iX);
                    tX = xGrid(:,iX);
                    [KNN(:,:,iX), KNND(:,:,iX)] = knnsearch(kdt, [tX, tY], 'k', K);
                % end
                iatoc=toc(iatic);
                % if mod(iY,10) == 1
                if iX == ngX-1 || mod(iX,10) == 1
                    % fprintf(1,'%f sec remaining\n',iatoc.*(iY-1));
                    fprintf(1,'%f sec remaining\n',iatoc.*(iX-1));
                end
            end
            KNN = permute(KNN, [1,3,2]);
            KNND = permute(KNND, [1,3,2]);
            AEG=[];
            for iY=ngY:-1:1
            for iX = ngX:-1:1
                ssi=(iX-1)*ngY+iY;
                AEG(ssi,:) = mean(phiTraining(KNN(:,iY,iX),:));
            end
            end
            apsModel.apsGrid = reshape(AEG,ngY,ngX,nD);
            % apsModel will add the reference phase back on;
            AE = apsModel.interpolate(dy(:),dx(:),pscLLE(:,3),true);
            AE = AE.*conj(apsModel.referencePointPhase);

%         end
        
        phiTraining=normz(phiTraining.*conj(AE));
        [cq, q] = OI.Functions.invert_height( ...
            normz(phiTraining), ...
            kFactors, ...
            600, ...
            200 ...
        );
        disp('cq')
        mean(cq)
        phiTraining=phiTraining.*exp(1i.*kFactors.*q);
        ts = timeSeries-timeSeries(1);
        tsp = ts*4*pi/(365.25.*0.055);
        [Cv, v]=OI.Functions.invert_velocity(phiTraining, tsp, 0.1, 500);

        disp('Cv')
        mean(Cv)

        phi1 = phi.*exp(1i.*kFactors.*q).*exp(1i.*tsp.*v).*conj(phi(masi,:)).*conj(AE);
        apsModel.virtualMasterImage_working = mean(phi1,2);
        phi1 = normz(phi1.*conj(apsModel.virtualMasterImage_working));
        phi1 = normz(phi1.*AE);


        % fit elevation dependent aps
        eRamp = [];
        for ii = size(phi1,2):-1:1
            cost = @(x) -abs(exp(1i*x.*pscLLE(:,3)') * phi1(:,ii));
            eRamp(ii) = fminsearch(cost,0);
        end

        apsModel.elevationToPhase = eRamp;
        phi1=phi1.*exp(1i.*eRamp.*(pscLLE(:,3)-pscLLE(masi,3)));
        apsModel.referenceElevation = pscLLE(masi,3);

        
        latAxis = linspace(min(pscLLE(:,1)),max(pscLLE(:,1)),ngY);
        lonAxis = linspace(min(pscLLE(:,2)),max(pscLLE(:,2)),ngX);
        [lonGrid, latGrid]=meshgrid(lonAxis,latAxis);

        
        % get weights for each grid point
        ae=zeros(size(latGrid,1),size(latGrid,2),nD);

        for ia=size(latGrid,1):-1:1
            iatic=tic;
            for ir = size(lonGrid,2):-1:1
%                 if FEW_SAMPLES
%                     lat = latGrid(ia,ir);
%                     lon = lonGrid(ia,ir);
% 
%                     [dy1, dx1]=OI.Functions.haversineXY(pscLLE(:,1:2), [lat,lon]);
%                     dd = hypot(dx1,dy1);
%                     tt = (1-sill).*exp(-dd./decay);
%                     tt = tt ./ sum(tt);
% 
%                     a=tt.*phi1;
%                 else
                    dd = KNND(ia,ir,:);
                    tt = (1-sill).*exp(-dd(:)./decay);
                    tt = tt ./ sum(tt);
                    a=tt.*phi1(KNN(ia,ir,:),:);
%                 end
                acm = a'*a;
                acm=acm./acm(1);
                pp=OI.Functions.phase_triangulation(acm); % note this is conj
                offset = sum(a)*pp;
                ae(ia,ir,:) = normz(conj(pp).*offset);
                
            end
            iatoc=toc(iatic);
            if mod(ia,10) == 1
                fprintf(1,'%f sec remaining\n',iatoc.*(ia-1));
            end
        end

        ae1=normz(ae);
        apsModel.latGrid = latGrid;
        apsModel.lonGrid = lonGrid;
        apsModel.apsGrid = ae1;
        apsModel.overwrite = this.isOverwriting;

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

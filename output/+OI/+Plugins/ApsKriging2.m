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
        pscSample = engine.load( OI.Data.PscSample().configure('METHOD','PscSampling_4GBmax','BLOCK','ALL','STACK', this.STACK, 'POLARISATION','VV') );

        pscLLE = pscSample.sampleLLE;
        phi = pscSample.samplePhase;

        normz = @(x) x./abs(x);

        % reference point:
        [~, masi]=max(pscSample.sampleStability);

        % phase to use:
        p2=phi.*conj(phi(masi,:));
        p3=normz(p2.*conj(mean(p2,2)));

        phiTraining = p3;

        C0 = abs(mean(p3,2));

        apsModel.reference = phi(masi,:);
        apsModel.referenceInd = masi;
        apsModel.phi = phi;
        apsModel.vm0 = mean(p2,2);
        apsModel.C0 = C0;

        F = @(c) min(12*pi,(1-c.^2)./c.^2);

        % get the distance from the reference point
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

        apsModel.variogram = struct('sill',sill,'decay',decay);

        % Initial estimate:
        D = sqrt((dx-dx').^2+(dy-dy').^2);
        T = (1-sill).*exp(-D./decay);

        TT=T.*sqrt(F(C0)).*sqrt(F(C0))';

        L=numel(C0);
        pTT=pinv([TT ones(L,1); ones(1,L) 0]);


        W = pTT*[T.*F(C0); ones(1,L)];
        W(end,:)=[];
        W=W./sum(W,2);
        AE = normz(W'*phiTraining);
        phi0=normz(phiTraining.*conj(AE));
        [cq, q] = OI.Functions.invert_height( ...
        normz(phi0), ...
        kFactors, ...
        600, ...
        200 ...
        );
        disp('cq')
        mean(cq)
        phi0=phi0.*exp(1i.*kFactors.*q);
        ts = timeSeries-timeSeries(1);
        tsp = ts*4*pi/(365.25.*0.055);
        [Cv, v]=OI.Functions.invert_velocity(phi0, tsp, 0.1, 500);

        disp('Cv')
        mean(Cv)

        phi1 = phi.*exp(1i.*kFactors.*q).*exp(1i.*tsp.*v).*conj(phi(masi,:)).*conj(AE);
        apsModel.vm1 = mean(phi1,2);
        phi1 = normz(phi1.*conj(apsModel.vm1));
        phi1 = phi1.*AE;

        eRamp = [];
        for ii = nDays:-1:1
            cost = @(x) -abs(exp(1i*x.*pscLLE(:,3)') * phi1(:,ii));
            eRamp(ii) = fminsearch(cost,0);
        end

        apsModel.eRamp = eRamp;
        phi1=phi1.*exp(1i.*eRamp.*(pscLLE(:,3)-pscLLE(masi,3)));
        apsModel.referenceElevation = pscLLE(masi,3);

        % Grid spacing
        gSpace = 100;
        ngX = ceil((max(dx)-min(dx))/gSpace);
        ngY = ceil((max(dy)-min(dy))/gSpace);

        latAxis = linspace(min(pscLLE(:,1)),max(pscLLE(:,1)),ngY);
        lonAxis = linspace(min(pscLLE(:,2)),max(pscLLE(:,2)),ngX);
        [lonGrid, latGrid]=meshgrid(lonAxis,latAxis);

        % get weights for each grid point
        ae=zeros(size(latGrid,1),size(latGrid,2),nD);

        for ia=size(latGrid,1):-1:1
            iatic=tic;
            for ir = size(lonGrid,2):-1:1
                
                lat = latGrid(ia,ir);
                lon = lonGrid(ia,ir);

                [dy1, dx1]=OI.Functions.haversineXY(pscLLE(:,1:2), [lat,lon]);
                dd = hypot(dx1,dy1);
                tt = (1-sill).*exp(-dd./decay);
                tt = tt ./ sum(tt);
                
                a=tt.*phi1;
                acm = a'*a;
                acm=acm./acm(1);
                pp=OI.Functions.phase_triangulation(acm); % note this is conj
                offset = sum(a)*pp;
                ae(ia,ir,:) = normz(conj(pp).*offset);
                
            end
            iatoc=toc(iatic);
            fprintf(1,'%f sec remaining\n',iatoc.*(ia-1));
        end

        ae1=normz(ae);
        apsModel.latGrid = latGrid;
        apsModel.lonGrid = lonGrid;
        apsModel.values = ae1;

        engine.save(apsModel)
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

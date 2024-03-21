
this.STACK = 1;
stackInd = this.STACK;

pscSample = engine.load( OI.Data.PscSample().configure('METHOD','PscSampling_4GBmax','BLOCK','ALL','STACK', this.STACK, 'POLARISATION','VV') );

pscAz = pscSample.sampleAz;
pscRg = pscSample.sampleRg;
pscLLE = pscSample.sampleLLE;
pscAS = pscSample.sampleStability;
phi = pscSample.samplePhase;

nSamples = numel(pscAz);

normz = @(x) x./abs(x);
dm = @(x) normz(x.*conj(mean(x,2)));

% reference point:
[mas, masi]=max(pscAS);

% phase to use:
p1=phi;
p2=phi.*conj(phi(masi,:));
p3=dm(p2);

phiTraining = p3;

C0 = abs(mean(p3,2));

apsModel.stack(stackInd).reference = phi(masi,:);
apsModel.stack(stackInd).referenceInd = masi;
apsModel.stack(stackInd).phi = phi;
apsModel.stack(stackInd).vm0 = mean(p2,2);
apsModel.stack(stackInd).C0 = C0;

F = @(c) min(12*pi,(1-c.^2)./c.^2);

% get the distance from the reference point
[dy, dx]=OI.Functions.haversineXY(pscLLE(:,1:2), pscLLE(masi,1:2));
dd = hypot(dx,dy);
[sdd, sddi]=sort(dd);

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

apsModel.stack(stackInd).variogram = struct('sill',sill,'decay',decay);

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
apsModel.stack(stackInd).vm1 = mean(phi1,2);
phi1 = normz(phi1.*conj(apsModel.stack(stackInd).vm1));
phi1 = phi1.*AE;

eRamp = [];
for ii = nDays:-1:1
    cost = @(x) -abs(exp(1i*x.*pscLLE(:,3)') * phi1(:,ii));
    eRamp(ii) = fminsearch(cost,0);
end

apsModel.stack(stackInd).eRamp = eRamp;
phi1=phi1.*exp(1i.*eRamp.*(pscLLE(:,3)-pscLLE(masi,3)));
apsModel.stack(stackInd).referenceElevation = pscLLE(masi,3);

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
apsModel.stack(stackInd).latGrid = latGrid;
apsModel.stack(stackInd).lonGrid = lonGrid;
apsModel.stack(stackInd).values = ae1;

pscApsEst = [];
for jj = nD:-1:1
pscApsEst(:,jj) = interp2(lonGrid,latGrid,ae1(:,:,jj),pscLLE(:,2),pscLLE(:,1));
end
dEle = pscLLE(:,3)-apsModel.stack(stackInd).referenceElevation;
pscApsEst = pscApsEst.*exp(-1i.*apsModel.stack(stackInd).eRamp.*dEle);
pscApsEst = pscApsEst.*apsModel.stack(stackInd).reference;
disp('C for psc after aps')
mean(abs(mean(normz(phi.*conj(pscApsEst)),2)))

phi2=normz(phi.*conj(pscApsEst));
[cq, q] = OI.Functions.invert_height( ...
normz(phi2), ...
kFactors, ...
600, ...
200 ...
);
disp('Cq end')
mean(cq)
[Cv, v]=OI.Functions.invert_velocity(phi2, tsp, 0.1, 500);
disp('Cv end')
mean(Cv)

save(['apsModel_' num2str(stackInd)],'apsModel');